# SlateHUD Architecture, Performance & Verification

This document details SlateHUD's background daemon, update/throttling architecture, architectural invariants, known scope limits, and automated/live verification workflows.

---

## ⚡ Background Helper (`SlateHUDHelper.exe`)

Instead of spawning `nvidia-smi.exe` and a media process every second, `NowPlaying.ini` and `System.ini` share one lightweight C# 5 daemon compiled with Windows' built-in `.NET Framework 4` `csc.exe` from five source files ([`SlateHUDHelper.cs`](../@Resources/SlateHUDHelper.cs), [`MediaHelper.cs`](../@Resources/MediaHelper.cs), [`ArtworkHelper.cs`](../@Resources/ArtworkHelper.cs), [`TelemetryHelper.cs`](../@Resources/TelemetryHelper.cs), [`DisplayProbe.cs`](../@Resources/DisplayProbe.cs)):

- **Startup & Watchdog:** `NowPlaying` and `System` run [`@Resources/HelperWatchdog.lua`](../@Resources/HelperWatchdog.lua) on load and every 5 seconds. It invokes `SlateHUDHelper.exe ensure` only when `helper-health.txt` is missing, invalid, or >15 seconds old (with at least 15 seconds between recovery attempts per skin). A named mutex (`Local\SlateHUDHelper.Daemon`) enforces a single running daemon.
- **Automatic Exit:** Exits automatically within ~10 seconds after `Rainmeter.exe` closes (`rainmeterMisses >= 2` checked every 5 ticks).
- **One-Shot Commands, Pipe & Fast Game Launcher:** Media clicks (`prev`, `playpause`, `next`, `seek <pct>`, `nextplayer`, `lockplayer`, `resetplayer`, `refetchcover`) dispatch asynchronously through the running daemon's named-pipe server (`\\.\pipe\SlateHUDHelper.Pipe`) via `SlateHUD.dll` (falling back to one-shot `SlateHUDHelper.exe` CLI execution over the pipe or direct WinRT execution up to 10s). `Games.ini` invokes `SlateHUDHelper.exe launchgame "<id>" "<revision>" <launch|folder>` directly from `Games\GameList.inc` (with `Cache\game_library.json` fallback) instead of cold-starting PowerShell per launch (`LaunchGame.ps1` stays available for standalone PowerShell tests). `Notes` invokes `SlateHUDHelper.exe initnotes` on load to seed missing personal files safely, and daemon startup syncs `@Resources\Plugins\SlateHUD.dll` into `%APPDATA%\Rainmeter\Plugins\SlateHUD.dll` (or `<RainmeterDirectory>\Plugins\SlateHUD.dll` in Portable Mode when `%APPDATA%\Rainmeter` is absent) when newer.
- **Widget Demand Gating:** Media polling stops when `NowPlaying` is unloaded; NVML polling and its handle close when `System` is unloaded. Hidden-but-loaded skins retain active sampling so showing them incurs zero startup lag.
- **Rebuilding:** After editing any helper `.cs` file or `@Resources/Plugin/SlateHUD.cpp`, rebuild atomically (leaves existing binaries intact on compile errors). Visual Studio Build Tools x64 (`cl.exe`) is required to build `SlateHUD.dll`; pass `-SkipPlugin` to rebuild only `SlateHUDHelper.exe`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "@Resources\build.ps1" -RestartHelper
```

### Snapshot Streams (Shared Memory + `@Resources/Cache/`)

`SnapshotPublisher` writes every snapshot to a 64 KiB lock-free seqlock memory-mapped section (`Local\SlateHUDHelper.SharedState`, 5 slots: `media.txt`, `media-health.txt`, `gpu.txt`, `monitors.txt`, `helper-health.txt`) for zero-disk reads via [`@Resources/Plugin/SlateHUD.cpp`](../@Resources/Plugin/SlateHUD.cpp) (`@Resources/Plugins/SlateHUD.dll`), while mirroring each update atomically to `@Resources/Cache/*.txt` via `WriteFast` (`MoveFileEx` with `REPLACE_EXISTING | WRITE_THROUGH`) for fallback and offline tests:

- **`media.txt` & `cover_<hash>.png`:** Polls Windows `GlobalSystemMediaTransportControlsSessionManager` (prioritizing Pear Desktop / YouTube Music unless locked/selected in `media_player.txt`) every 1 second and writes only when content changes. Artwork reads on track/session/property events, retries every 2 seconds for the first 10 seconds, then falls back to 30-second checks. All cover state is synchronized under `artworkLock` + a generation counter (`artworkGeneration`), while disk/WinRT/network I/O stays outside the lock so track changes or manual refreshes (`Local\SlateHUDHelper.CoverRefresh` + `Local\SlateHUDHelper.MediaWake`) never commit stale covers. Online lookup uses TLS 1.2+ with 4-second async HTTP timeouts (16 MiB cap), checks up to five candidates, and requires normalized title and artist equality. SHA-256 deduplication avoids rewriting identical covers; cleanup keeps the active cover, 8 newest files, and images under 5 minutes old.
- **`gpu.txt`:** Queries `nvml.dll` in-process every 2 seconds for GPU utilization, VRAM used/total, temperature (°C), power draw (W), and fan speed, plus Windows `psapi.dll` pagefile usage (`PAGEFILE=used,total`). When `SysLhmEnabled=1` or `SysSensorProvider=lhm`, also polls running `LibreHardwareMonitor` (`root\LibreHardwareMonitor` WMI or bounded `500 ms` loopback HTTP JSON, with 30-second backoff when stopped) and appends validated `CPUTEMP=` and `LHMGPU=` lines. Each snapshot includes a Unix timestamp; missing, malformed, or >10-second-old data displays `Unavailable` instead of `0`. NVML initialization retries every 30 seconds after failure, and unsupported optional sensors remain `Unavailable`.
- **`media-health.txt` & `monitors.txt` (`SnapshotPublisher`):** Shared publisher emits **immediately on content changes**, maintains a **2-second heartbeat** while unchanged, retries failed writes on the next poll, restores deleted snapshot files automatically, and forces republication on clock rollback. Each async WinRT media call is bounded to 1.5 seconds with cancellation. Display topology/identities cache until `DisplaySettingsChanged` or a 30-second fallback, while window geometry and fullscreen occupancy poll every 1 second independently of media queries, using `GetActiveRainmeterPid()` to discard exited Rainmeter handles immediately.
- **`helper-health.txt` & `WindowsAccent.inc`:** `helper-health.txt` publishes daemon liveness every 5 seconds; `SyncWindowsAccent` reads Windows personalization accent (`Explorer\Accent\AccentColorMenu` → `DWM\AccentColor` → `DWM\ColorizationColor`), clamps luminance (`L ∈ [0.24, 0.68]`), derives surface/chart palette tokens for [`WindowsAccent.inc`](../@Resources/Themes/WindowsAccent.inc), and refreshes `SlateHUD` on live `UserPreferenceChanged` / 5-second checks when `CurrentTheme=WindowsAccent`.

---

## 📊 Performance & Update Architecture

### Skin Update Cadences & UI Throttling
- **Apps (`Update=-1`):** Strictly event-driven (renders only on user clicks, scrolling, or scan completion).
- **Notes (`Update=30000`):** Runs periodic rollover checks every 30 seconds (2 wakeups/min instead of 60/min), while initialization and user edits execute immediately. Daily resets occur within up to 30 seconds after `DailyResetHour`.
- **Now Playing (`Update=1000`):** Reads `media.txt` and `media-health.txt` once per tick via [`@Resources/MediaUnicode.lua`](../@Resources/MediaUnicode.lua) (UTF-16 LE BOM boundary delegating to [`@Resources/Media.lua`](../@Resources/Media.lua)), reading from `SlateHUD.dll` shared-memory bridge measures (`MeasureMediaBridge`, `MeasureMediaHealthBridge`) first with `io.open` fallback, parsing with a delimiter-based parser (`||`) that preserves empty fields and single pipe characters without regex fallbacks, and dispatching controls asynchronously via `\\.\pipe\SlateHUDHelper.Pipe` with `RunCommand` fallback; unchanged snapshots skip UI bangs.
- **System, Disks & Battery:** `System` (`Update=1000` CPU, `UpdateDivider=2` RAM/Pagefile, 2s GPU snapshot via `MeasureGpuBridge`, 1s monitor topology via `MeasureMonitorsBridge`, 5s helper heartbeat via `MeasureHealthBridge`) and `Battery` (`Update=2000`) memoize option/variable writes in Lua so unchanged text and severity colors never reissue `!SetOption`. `Disks` reads volume labels and free capacity every 5 seconds (`UpdateDivider=5`) with 1s combined disk R/W counters.
- **Network:** Checks adapter identity and connectivity every 5 seconds (`UpdateDivider=5`) while traffic bars sample at 1 second.
- **Games (`Update=1000`):** Reads data-only `[Variables]` records from `Games\GameList.inc` (`Game<N>*`, `Platform<N>*`, `Utility<N>*`), eliminating per-game meter creation and per-render `!HideMeter` loops (legacy `[Meter...]` files remain supported on read).
- **Event-Driven Micro-Animations (`UpdateDivider=-1`):** `NowPlaying`, `Apps`, and `Games` include opt-in `ActionTimer` measures (`UiAnimations=1`, bypassed on battery when `UiAnimationsBatterySaver=1`) that stop automatically after completion (~150–450 ms) so `Apps` stays `Update=-1` with zero continuous idle timer ticks.
- **Ghost-Blur Suppression:** When `BlurFile` is active, [`@Resources/Battery.lua`](../@Resources/Battery.lua) and [`@Resources/Visualizer.lua`](../@Resources/Visualizer.lua) dynamically set `[MeasureBlur]` `Type=None` while `Battery` is hidden on desktops or `Visualizer` hides its background under `VisualizerHideIdle=1`.
- **Visualizer (4-variant switching within the same config):**
  - [`Visualizer.ini`](../Visualizer/Visualizer.ini): Active AC animation (`VisualizerUpdate=40` ms = 25 fps, 17.5% fewer updates than 33 ms / ~30.3 fps; set `33` for ~30 fps or `50` for 20 fps in `UserSettings.inc`).
  - [`Economy.ini`](../Visualizer/Economy.ini): Reduced battery animation (`VisualizerBatteryUpdate=66` ms ≈ 15 fps). Power checks track the configured interval to stay near once per second.
  - [`Idle.ini`](../Visualizer/Idle.ini): Peak-only wake probe every `250 ms` after 2 seconds of silence, zero FFT bands, sharing static appearance in [`Appearance.inc`](../Visualizer/Appearance.inc) with a 25%-alpha theme gradient.
  - [`Suspended.ini`](../Visualizer/Suspended.ini): Static fullscreen card containing **zero `AudioLevel` measures** so audio capture actually releases during fullscreen use.

---

## 🛡️ Key Architectural Invariants

1. **Configuration Separation:** [`@Resources/Variables.inc`](../@Resources/Variables.inc) holds portable defaults only (no user-specific paths or drive assumptions), loads `@Resources\Cache\Display.inc` and `@Resources\UserSettings.inc` before derived formulas (`LayoutRowWidth`, `UiScale`, `CardFill`, `@IncludeTheme`, `@IncludeBlur`), and all runtime `!WriteKeyValue` writes target `#@#UserSettings.inc` (auto-seeded via `EnsureUserSettings` in C# or `ContextMenu.ensureUserSettings` in Lua).
2. **25-Slot Context Menu Contract:** Slots `1–18` belong to the shared suite menu and must match identically between [`@Resources/Context.inc`](../@Resources/Context.inc) and [`@Resources/ContextMenu.lua`](../@Resources/ContextMenu.lua); skin extensions (`System.ini` `19–23`, `Network.ini` `19–22`, and `ContextMenu.openSuite`) use slots `19–25`; `ContextMenu.openCustom` writes from slot `1` and clears slot `N + 1`.
3. **Rainmeter Syntax & Encoding Safety:** User/external strings (`Notes`, `Apps`, `Games`) strip `\r\n\t`, replace `#`, `[`, `]` with fullwidth `＃`, `［`, `］`, sanitize `"`, and avoid raw `#Var#` strings in `InputText` `DefaultValue` bangs. `MediaUnicode.lua` remains UTF-16 LE with BOM (`binary` in `.gitattributes`).
4. **Atomic Persistence & Locks:** Runtime Lua writes (`Notes` + `.undo`, `Display.inc`, `VisualizerMode.txt`, `Games` favorites/preferences/recent) use [`@Resources/FileStore.lua`](../@Resources/FileStore.lua) (`.tmp` + `.bak` recovery) and [`@Resources/NotesData.lua`](../@Resources/NotesData.lua) (preserving UTF-8/UTF-16 encoding and unrelated sections). Scanners serialize via exclusive file locks (`AppScan.lock`, `game_scan.lock`) and retain prior catalogs/icon generations on failure.
5. **Skin Metadata & Layout Metrics:** Every standalone skin `.ini` specifies `License=MIT` under `[Metadata]` (`Economy.ini` inherits via `@Include=Visualizer.ini`), and all card/padding dimensions derive from shared variables in `Variables.inc`.

---

## 📋 Known Scope & Limitations

- **Implemented plugin & helper capabilities:** `FrostBehind` tight-framed DWM blur, opt-in `ActionTimer` micro-animations, `LibreHardwareMonitor` CPU temp & AMD/Intel GPU telemetry in `SlateHUDHelper.exe`, and the thin native `SlateHUD.dll` shared-memory/pipe + `launchgame` bridge are implemented and integrated.
- **Intentionally out of scope / deferred:** Game-running process badges, cross-page Notes transfers / >5 tasks per page / multi-step undo / weekly recurrence, per-drive disk activity and collapsing missing drive rows, manual network adapter selection, battery charge/discharge history graphs, and a standalone settings GUI panel.

---

## 🧪 Regression Checks & Live Verification

After rebuilding `SlateHUDHelper.exe` and `Plugins\SlateHUD.dll` (`@Resources\build.ps1 -RestartHelper`, which requires MSVC Build Tools x64 `cl.exe` for `SlateHUD.dll` unless `-SkipPlugin` is passed), restart Rainmeter or refresh the `SlateHUD` group. Performance comparisons should measure both `Rainmeter.exe` and `SlateHUDHelper.exe` across silence, playback, paused playback, and fullscreen separately.

### Automated Test Suites

All test suites use isolated fixtures and mocked Rainmeter APIs; they never alter personal notes, live catalogs, or system settings.

```powershell
# 1. Theme palettes, Variables/UserSettings wiring, context slots, MIT metadata & layout metrics:
powershell -NoProfile -ExecutionPolicy Bypass -File "Tests\ThemeRegression.ps1"

# 2. App shortcut discovery, 6 categories, stable keys & Rainmeter syntax escaping:
powershell -NoProfile -ExecutionPolicy Bypass -File "Tests\AppDiscoveryRegression.ps1"

# 3. Game scanner fixtures, drive exclusions, overrides, data-only GameList.inc, locks & mocked launches:
powershell -NoProfile -ExecutionPolicy Bypass -File "Tests\GameScannerRegression.ps1"

# 4. Full helper + Steam metadata classifier + GameScannerRegression (compiles HelperRegression.exe):
#    Note: Named Local\ EventWaitHandle IPC tests require running outside a restricted sandbox.
powershell -NoProfile -ExecutionPolicy Bypass -File "Tests\Regression.ps1"

# 5. End-to-end fixture app scan, fallback icon export, rollback & AppScan.lock:
#    Note: Extracts from %WINDIR%\System32\shell32.dll and may require running outside a restricted sandbox.
powershell -NoProfile -ExecutionPolicy Bypass -File "Tests\AppScanRegression.ps1"

# 6. Offline Lua 5.1 controller tests (Widget, Network, Apps, Polish, Notes):
python Tests\WidgetRegression.py
```

If setting up the Lua 5.1 runner from scratch, use a **64-bit Python 3.12** interpreter matching the `lupa` Lua 5.1 extension (bare `python` on Windows may hit the WindowsApps alias or a mismatched architecture):

```powershell
python -m pip install --target Tests/.scratch-lua-runtime lupa
```

Suite coverage:
- [`Tests/Regression.ps1`](../Tests/Regression.ps1) / [`Tests/HelperRegression.cs`](../Tests/HelperRegression.cs): Helper command parsing, SMTC formatting, `Local\SlateHUDHelper.SharedState` seqlock IPC, `\\.\pipe\SlateHUDHelper.Pipe` command dispatch, `LaunchCatalogGame`, native `SlateHUD.dll` x64 exports, LHM telemetry parsing, Steam metadata classifier, and `GameScannerRegression.ps1`.
- [`Tests/GameScannerRegression.ps1`](../Tests/GameScannerRegression.ps1): Fixture discovery, drive exclusions, multiple roots, Epic manifests/URIs, override-only targets, launcher selection, stable IDs, disconnected sources, malformed manifests, cache-free recovery, write rollback, scan locking, launch arguments, and working directories (no real launches or network requests).
- [`Tests/WidgetRegression.lua`](../Tests/WidgetRegression.lua): Favorite migration and interrupted-save recovery, offline pins, hover hints, single open category, remembered pages, four-column tiles, compact favorites, monitor-height changes, Notes docking, and battery states.
- [`Tests/NetworkRegression.lua`](../Tests/NetworkRegression.lua): IPv4/IPv6 validation, clearing failed results, independent retry backoff and recovery, last-success timestamps, adapter/connectivity changes, refresh-click debounce, ping threshold boundaries and missing callbacks, and scaling toggles.
- [`Tests/PolishRegression.lua`](../Tests/PolishRegression.lua): GPU validity/staleness, plugin bridge stream reading (`MeasureGpuBridge`, `MeasureMediaBridge`, `MeasureMediaHealthBridge`), monitor layout geometry (`LayoutRowWidth`, custom metrics, `UserSettings.inc` seeding), per-page undo/redo and interrupted saves, media capabilities and seek bounds, and visualizer silence/battery transitions.
- [`Tests/NotesRegression.lua`](../Tests/NotesRegression.lua): 4:00 AM rollover boundary, inactive pages, missed-day catch-up, backward clock changes, daily opt-in/out, recurring cleanup, same-day/cross-day undo, failed-save blocking, interrupted-write recovery, and UTF-8/UTF-16 Unicode edits.
- [`Tests/AppsRegression.lua`](../Tests/AppsRegression.lua): Six-category layout and saved overrides, bounded favorites, search, remembered pages, profile/menu actions, simulated rapid hover transitions, failed-save rollback, and sub-314px viewport-constrained monitor fit. See [`Apps/README.md`](../Apps/README.md#verification) for `AppDiscoveryRegression.ps1` and `AppScanRegression.ps1`.

### Live Desktop Verification Status

Automated fixtures mock Rainmeter APIs and do **not** claim live FPS, CPU, RAM, or real desktop interaction validation:

- **Verified live in Rainmeter:** Manual **Auto / External / Laptop** placement, ignoring ordinary maximized windows, moving the suite to the laptop after ~2 seconds on borderless fullscreen while activating `Visualizer\Suspended.ini`, returning to external + `Idle.ini` after window exit, 1s display / 2s GPU sampling cadence without catalog rescans, and isolated Game Hub category override/reset/favorite survival across rescans.
- **Pending live desktop verification:** Repeatable game-benchmark FPS / 1% low frame-time comparisons (widgets off vs. Auto + fullscreen profile, measuring both `Rainmeter.exe` and `SlateHUDHelper.exe`), exclusive-fullscreen games, mixed-DPI and display unplug/reconnect transitions, sleep/resume, and visual/interactive inspection across silence, playback, paused playback, and fullscreen states (`FrostBehind` tight-framed DWM blur, opt-in `ActionTimer` hover/seek/volume micro-animations, optional `LibreHardwareMonitor` CPU temp & AMD/Intel GPU sensors, `SlateHUD.dll` shared-memory/pipe media bridge + `launchgame`, `Notes` inline `InputText`, and context menus).
