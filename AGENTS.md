# AGENTS.md — AI Agent Guide for SlateHUD

This guide provides architecture context, language/platform constraints, invariants, and verification workflows for AI coding agents working in this repository.

---

## 1. Project Overview & Technology Stack

**SlateHUD** is a modular desktop HUD dashboard suite for **Rainmeter** (Windows). It delivers real-time system/GPU telemetry, Windows SMTC media controls, network & storage monitoring, an audio spectrum visualizer, searchable app & game launchers, and a multi-page notes/checklist widget.

### Runtime & Tooling Layers
- **Rainmeter Skins (`.ini`, `.inc`)**: Declarative UI layout, meter styling, measure definitions, and bangs.
- **Lua 5.1 (`@Resources/*.lua`)**: Widget state, responsive layout planning, string sanitization, and atomic persistence.
- **C# 5 Background Helper (`@Resources/SlateHUDHelper.exe`)**: Built from source via `@Resources/build.ps1` (git-ignored on `main`; distributed in GitHub Releases) with Windows' built-in .NET Framework 4 `csc.exe` (`AnyCPU`) from **five source files** (`SlateHUDHelper.cs`, `MediaHelper.cs`, `ArtworkHelper.cs`, `TelemetryHelper.cs`, `DisplayProbe.cs`). Runs as a singleton daemon (`Local\SlateHUDHelper.Daemon`) publishing throttled atomic snapshots to both a 64 KiB seqlock shared-memory section (`Local\SlateHUDHelper.SharedState`) and `@Resources/Cache/`, serving async commands on `\\.\pipe\SlateHUDHelper.Pipe` (current-user ACL + bounded read timeout), and handling one-shot CLI commands (`ensure`, `daemon`, `initnotes`, `status`, `refresh`, `launchgame`, `prev|playpause|next|seek|nextplayer|lockplayer|resetplayer|refetchcover`). Syncs `@Resources\Plugins\SlateHUD.dll` into `%APPDATA%\Rainmeter\Plugins\SlateHUD.dll` (or `<RainmeterDirectory>\Plugins\SlateHUD.dll` in Portable Mode when `%APPDATA%\Rainmeter` is absent) when newer, and exits automatically within ~10s after `Rainmeter.exe` closes.
- **Thin Native x64 Rainmeter Plugin (`@Resources/Plugin/SlateHUD.cpp` → `@Resources/Plugins/SlateHUD.dll`)**: Built alongside the helper by `@Resources/build.ps1` using MSVC Build Tools (`cl.exe` x64, Windows SDK; git-ignored on `main` and skipped when `-SkipPlugin` is passed). Reads `Local\SlateHUDHelper.SharedState` (`Stream=Media|MediaHealth|Gpu|Monitors|HelperHealth`, with `FallbackPath` disk fallback) and dispatches non-blocking commands over `\\.\pipe\SlateHUDHelper.Pipe` (with `HelperPath` CLI fallback).
- **PowerShell 5.1 (`@Resources/*.ps1` + `@Resources/IconExport.cs`)**: App/game library scanning (`ScanApps.ps1`, `ScanGames.ps1`), game launching (`LaunchGame.ps1`), and helper compilation (`build.ps1`).
- **Python (test-only)**: **Never used for application runtime.** Exists solely to run offline Lua 5.1 regression tests via `Tests/WidgetRegression.py` (`lupa.lua51`). Do not introduce Python runtime dependencies.

---

## 2. Directory Structure & Key Files

```text
SlateHUD/
├── AGENTS.md                     # AI agent architecture guide & conventions (this file)
├── LICENSE                       # MIT license
├── README.md                     # Suite overview, installation, quick start & documentation index
├── SECURITY.md                   # Security policy, binary transparency & outbound network docs
├── .github/workflows/            # GitHub Actions CI (`ci.yml`) & release packaging (`release.yml`)
├── scripts/
│   └── PackageRelease.ps1        # Stages clean SlateHUD release ZIP and SHA256SUMS.txt
├── docs/                         # Detailed guides (widgets.md, architecture.md)
├── .gitattributes                # LF/CRLF handling; marks MediaUnicode.lua, .exe, .png, .ico binary
├── .gitignore                    # Ignores Cache/, UserSettings.inc, personal data & generated catalogs
├── NowPlaying.ini                # Windows SMTC media player card & audio output switcher
├── Apps/                         # Searchable 6-category application launcher
│   ├── Apps.ini
│   ├── README.md                 # Apps launcher setup, categorization & verification notes
│   ├── Shortcuts.csv             # Default shortcut order, labels, categories, favorites, secondary link
│   ├── Catalog.inc               # Generated local app catalog & meters (git-ignored)
│   ├── Preferences.txt           # Personal pin/order/hide/category overrides (git-ignored)
│   └── View.inc                  # Saved expanded category & per-category pages (git-ignored)
├── Games/                        # Steam, Epic, HoYoPlay, Desktop Games & standalone game hub
│   ├── Games.ini
│   ├── Tiles.inc                 # Reusable 4-column tile meter definitions
│   ├── Overrides.txt             # Manual match rules (title, category, exe/URI, args, cwd, HIDE)
│   ├── GameList.inc              # Generated data-only [Variables] catalog (git-ignored)
│   ├── Favorites.txt             # Personal pinned games (git-ignored)
│   ├── Preferences.txt           # Personal category/hide preferences (git-ignored)
│   ├── Recent.txt                # Recently launched game IDs (git-ignored)
│   └── View.inc                  # Saved active category & page state (git-ignored)
├── Notes/                        # 3-tab daily task & checklist widget
│   ├── Notes.ini
│   ├── Defaults.inc              # Baseline defaults and daily rollover hour (DailyResetHour=4)
│   ├── RowMeasures.inc           # InputText, Commit, Note, and Status measures for rows 1–5
│   ├── RowMeters.inc             # Row UI meters for rows 1–5
│   ├── Settings.inc              # Active tab state (git-ignored)
│   └── Data/                     # Page1..3.inc & Page1..3.inc.undo backups (git-ignored)
├── Visualizer/                   # 36-band audio spectrum visualizer (4 variants in same config)
│   ├── Visualizer.ini            # VisualMode=0: active animation (default 25 FPS / 40ms)
│   ├── Economy.ini               # VisualMode=2: battery mode (~15 FPS / 66ms; @Include=Visualizer.ini)
│   ├── Idle.ini                  # VisualMode=1: peak-only wake probe (250ms, no FFT bands)
│   ├── Suspended.ini             # VisualMode=3: fullscreen static card (zero AudioLevel measures)
│   └── Appearance.inc            # Shared static background, baseline gradient, and MeterPad
├── System/System.ini             # CPU (+ optional LHM temp), RAM, Pagefile, and NVML/LHM GPU telemetry + Layout host
├── Network/Network.ini           # Public IPv4/IPv6, LAN IP, optional ping, Auto/Fixed traffic bars
├── Disks/Disks.ini               # Drive usage (C:, D:, E:), volume labels & disk R/W throughput
├── Battery/Battery.ini           # Battery %, AC/charging state & time left (auto-hides on desktop)
├── @Resources/                   # Shared configs, themes, Lua/PS1/C# modules, binaries & cache
│   ├── Variables.inc             # Portable defaults, geometry metrics, thresholds & theme/blur wiring
│   ├── UserSettings.inc          # Local user overrides overlay (git-ignored; auto-seeded by helper/Lua)
│   ├── Styles.inc                # Shared card, typography, bar & separator styles
│   ├── Context.inc               # Shared suite context menu (slots 1–18) & DefaultDraggable=0
│   ├── ContextMenu.lua           # Dynamic suite (1–18+) & custom menu builder + ensureUserSettings
│   ├── Blur.inc                  # DWM Acrylic/Blur plugin measure (#BlurPlugin#: FrostBehind.dll default, FrostedGlass.dll fallback)
│   ├── Themes/                   # Default, Cyberpunk, NordFrost, TokyoNight, Monochrome, WindowsAccent
│   ├── SlateHUDHelper.cs         # Daemon entry, lifecycle, SnapshotPublisher, WriteFast, EnsureUserSettings
│   ├── MediaHelper.cs            # Bounded WinRT SMTC polling, session selection & control commands
│   ├── ArtworkHelper.cs          # Thread-safe cover cache, SHA-256 dedup & bounded TLS 1.2+ fallback
│   ├── TelemetryHelper.cs        # NVML GPU, Windows pagefile & optional LibreHardwareMonitor WMI/HTTP telemetry polling
│   ├── DisplayProbe.cs           # Physical monitor topology, roles, Rainmeter skins & fullscreen probe
│   ├── Plugin/SlateHUD.cpp       # Thin native x64 Rainmeter plugin (shared memory + pipe IPC)
│   ├── Plugins/SlateHUD.dll      # Compiled x64 bridge plugin (git-ignored; synced to Rainmeter Plugins)
│   ├── SlateHUDHelper.exe        # Compiled background helper executable (git-ignored)
│   ├── build.ps1                 # Atomic helper & native plugin build script (`-RestartHelper`, `-SkipPlugin`)
│   ├── IconExport.cs             # Shared Win32 icon extractor compiled by ScanApps & GameIcons
│   ├── MediaUnicode.lua          # UTF-16 LE BOM entry point delegating to Media.lua (marked binary)
│   ├── Media.lua                 # SMTC snapshot parser, media capabilities & seek logic
│   ├── Layout.lua                # Monitor routing, work-area scaling & suite skin positioning
│   ├── DisplayState.lua          # monitors.txt parser, role fallback & fullscreen stabilization
│   ├── HelperWatchdog.lua        # Restarts SlateHUDHelper.exe when helper-health.txt is missing/stale
│   ├── FileStore.lua             # Binary-safe atomic .tmp/.bak file write & recovery
│   ├── Notes.lua / NotesData.lua # Daily 4AM rollover, escaping, per-page undo & encoding-safe INI edit
│   ├── Apps.lua                  # 6-category launcher UI, favorites, search, viewport fit & hover hints
│   ├── GameHub.lua / GameHubData.lua / GameHubLayout.lua # Game Hub controller, data & layout
│   ├── System.lua / Network.lua / Disks.lua / Battery.lua / Visualizer.lua # Widget controllers
│   ├── ScanApps.ps1 / AppDiscovery.ps1     # App shortcut scanner & 6-category classifier
│   ├── ScanGames.ps1 / GameDiscovery.ps1 / GameIcons.ps1 / LaunchGame.ps1 # Game scanner & launcher
│   └── Cache/                    # Ephemeral snapshots, icons, locks & JSON caches (git-ignored)
└── Tests/                        # PowerShell, C#, and Python/lupa Lua 5.1 regression suites
    ├── Regression.ps1            # Compiles HelperRegression.cs, tests genre logic & calls GameScannerRegression
    ├── HelperRegression.cs       # Unit/IPC tests for SlateHUDHelper (needs unsandboxed Local\ events)
    ├── ThemeRegression.ps1       # Themes, Variables/UserSettings wiring, slots, MIT license & metrics
    ├── GameScannerRegression.ps1 # Fixture game discovery, exclusions, data-only GameList, locks & launch
    ├── AppDiscoveryRegression.ps1# App shortcut precedence, 6 categories, keys & sanitization
    ├── AppScanRegression.ps1     # Fixture ScanApps run, icon fallback, rollback & AppScan.lock
    ├── WidgetRegression.py       # Runs all Lua 5.1 suites using python + lupa (e.g. local Tests/.scratch-python312)
    ├── WidgetRegression.lua / AppsRegression.lua / NetworkRegression.lua / NotesRegression.lua / PolishRegression.lua
    └── .scratch-*/               # Local scratch Python 3.12 / lupa runtime & temp test dirs (git-ignored)
```

---

## 3. Strict Language, Encoding & Compatibility Rules

### A. Rainmeter Lua 5.1 & Testability
- Rainmeter embeds **Lua 5.1**. **Never use Lua 5.2+ features**: no bitwise operators (`&`, `|`, `~`), no integer division (`//`), and no `goto`. Use `math.floor()` for integer division.
- Lua measures run synchronously on Rainmeter's UI thread; never introduce blocking loops or network calls in Lua.
- Offline tests (`Tests/WidgetRegression.py`) invoke Lua scripts with mocked `SKIN` tables and sometimes call `Setup()`/`Update()` directly without `Initialize()`. Keep `SKIN` lookups defensive (`SKIN and SKIN.GetY`, etc.), resolve sibling modules via `debug.getinfo` fallback or `SKIN:GetVariable('@')`, and load helper modules lazily where appropriate.

### B. UTF-16 LE BOM Entry Point (`MediaUnicode.lua`)
- [`@Resources/MediaUnicode.lua`](@Resources/MediaUnicode.lua) **must stay UTF-16 LE with BOM** (and marked `binary` in [`.gitattributes`](.gitattributes)). Rainmeter uses the `ScriptFile` encoding to preserve Unicode strings across `!SetOption` / `!SetVariable` bangs; it dynamically executes UTF-8 [`@Resources/Media.lua`](@Resources/Media.lua) via `loadfile`/`setfenv`. Never convert `MediaUnicode.lua` to UTF-8 or strip its BOM.

### C. C# 5 Constraint (`.NET Framework 4` `csc.exe`)
- `SlateHUDHelper` (`@Resources/*.cs`) and [`@Resources/IconExport.cs`](@Resources/IconExport.cs) compile using the Windows-bundled `.NET Framework 4` `csc.exe` (`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`) or PowerShell `Add-Type`.
- **Write strict C# 5**: do **not** use C# 6+ syntax (`$"..."` string interpolation, `?.` null-conditional, expression-bodied members `=>`, pattern matching, tuple syntax, target-typed `new()`, `out var`).

### D. Windows PowerShell 5.1 Compatibility
- All `@Resources/*.ps1` and `Tests/*.ps1` scripts must work in built-in **Windows PowerShell 5.1** (`powershell.exe`). Avoid PowerShell 7-only syntax (`?:`, `??`, `&&`, `||`).

---

## 4. Architectural Invariants & Coding Conventions

### A. Configuration Separation (`Variables.inc` vs `UserSettings.inc`)
- [`@Resources/Variables.inc`](@Resources/Variables.inc) must remain **portable**: no `C:\Users\...` paths, no machine-specific `GamesFolder=D:\Games`, `GamesExcludedDrives=G:`, or hardcoded `BlurFile` paths. `AcrylicBlur` must be literal `Acrylic`, `Blur`, or `None`; `BlurFile` must be empty or `#@#Blur.inc`.
- **Include order in `Variables.inc` is strict**: scalar defaults come first, followed by `@IncludeLayoutState=#LayoutStateFile#` and `@IncludeUserSettings=#@#UserSettings.inc`, followed by derived formulas (`ActiveFrameW`, `ActiveFrameH`, `CardPadX`, `CardPadY`, `CardShiftX`, `CardShiftY`, `LayoutRowWidth`, `UiScale`, `textSize`, `titleSize`, `CardFill`, `ColorCoverFill`, `colorBar`, `colorAccent`, `@IncludeTheme`, `@IncludeBlur`).
- All runtime/menu `!WriteKeyValue` writes (scale, opacity, theme, blur, `BlurTightFrame`, display placement, `LayoutMode`, `UiAnimations`, `SysHistory`, `SysLhmEnabled`, `SysSensorProvider`, `NetAutoScale`, `NetHistory`, `NetPingEnabled`) **must write to `#@#UserSettings.inc`**, never to `#@#Variables.inc` or skin `.ini` files. Ensure `UserSettings.inc` exists with `[Variables]` first via `ContextMenu.ensureUserSettings(SKIN)` in Lua or `SlateHUDHelper.EnsureUserSettings` in C#.
- Theme files in `@Resources/Themes/` must define `[Variables]` with `ThemeName`, `ColorAccent`, `CardFill`, `CardStroke`, `BarBack`, `VisualizerGradient`, `ColorHistory2`, `ColorDivider`, `ColorPill`, `ColorSwitchFill`, `ColorInputFill`, `ColorCoverFill`, `ColorCoverNote`, and `ColorCheckboxEmpty`.

### B. Context Menu Slot Contract (`1–18` vs `19–25`)
- Rainmeter enforces a **25-slot limit** (`ContextTitle` / `ContextTitle2..25`).
- Slots **1–18** belong to the shared suite menu. [`@Resources/Context.inc`](@Resources/Context.inc) and `SUITE_ITEMS` in [`@Resources/ContextMenu.lua`](@Resources/ContextMenu.lua) **must stay strictly identical**.
- Skin-specific menu extensions (`System/System.ini` slots `19–23`, `Network/Network.ini` slots `19–22`, and `ContextMenu.openSuite(SKIN, extraItems)`) **must use slots 19–25**.
- Contextual item menus (`ContextMenu.openCustom(SKIN, items)`) write from slot `1` and clear the trailing slot (`N + 1`).
- `Context.inc` sets `DefaultDraggable=0` and `OnRefreshAction=[!Draggable 0]`. Skins defining their own `OnRefreshAction` must retain the leading `[!Draggable 0]`.

### C. Responsive Layout & Skin Metadata
- Shared card and frame metrics (`StatCardW`, `StatCardH`, `BatteryCardH`, `WideCardW`, `MediaCardH`, `VisualizerCardH`, `CardFrameW`, `CardFrameH`, `CardGap`, `IconRailW`, `AppMaxCardH`, `GameMaxCardH`, `GameNotesReserve`, `NotesGap`) live in `Variables.inc`. Both `LayoutRowWidth` / `UiScale` and [`@Resources/Layout.lua`](@Resources/Layout.lua) (`layoutMetrics()`) derive coordinates from them, and skin `.ini` files reference `#WideCardW#`, `#StatCardW#`, `#CardFrameW#`, etc. Never introduce unscaled or duplicated literal card dimensions.
- Every standalone skin `.ini` (`NowPlaying.ini`, `Apps/Apps.ini`, `Games/Games.ini`, `Notes/Notes.ini`, `System/System.ini`, `Network/Network.ini`, `Disks/Disks.ini`, `Battery/Battery.ini`, `Visualizer/Visualizer.ini`, `Visualizer/Idle.ini`, `Visualizer/Suspended.ini`) must define `License=MIT` under `[Metadata]` (`Visualizer/Economy.ini` inherits it via `@Include=Visualizer.ini`).

### D. Rainmeter Syntax Sanitization & Tooltip Policy
- Escape/sanitize all external or user-entered text (Notes tasks/titles, App names/labels, Game titles) before setting meter text, variables, or generating `.inc` files: flatten `\r\n\t`, replace `#`, `[`, `]` with fullwidth `＃`, `［`, `］` (or escape via `Convert-IniText` in `AppDiscovery.ps1`), and sanitize `"` (`Notes.lua` `cleanInput`/`Edit`). Never embed raw `#Var#` strings inside `InputText` `DefaultValue` bangs.
- `Apps`, `Games`, and `Notes` intentionally use an in-card hover hint footer instead of native Rainmeter popup tooltips (`ToolTipHidden=1`) to avoid stacked popups.

### E. Performance, Thread-Safety & Visualizer Suspension
- **Low Wakeup & Throttled I/O**: Keep `Apps` event-driven (`Update=-1`), `Notes` on `Update=30000`, and helper snapshots throttled via `SnapshotPublisher` (immediate publish on content change; 2s heartbeat for `monitors.txt` and `media-health.txt`, 5s for `helper-health.txt`, 2s GPU polling, 1s media/display polling).
- **Helper Bounds & Locks**: Keep WinRT SMTC async calls bounded (`1.5s`), artwork HTTP fetches TLS 1.2+ only with `4s` timeouts, and cover state transitions guarded by `artworkLock` + `artworkGeneration` (`ArtworkHelper.cs`).
- **Fullscreen Audio Suspension**: `Visualizer/Suspended.ini` (`VisualMode=3`) must contain **zero `AudioLevel` measures** so fullscreen suspension actually unloads audio capture; `Visualizer/Idle.ini` (`VisualMode=1`) uses peak detection only (no FFT bands).

### F. Atomic Persistence, Locks & Data-Only Game Catalog
- Lua runtime writes (`Notes` pages + `.undo`, `Display.inc`, `VisualizerMode.txt`, `Games` favorites/preferences/recent) must go through [`@Resources/FileStore.lua`](@Resources/FileStore.lua) (`.tmp` + `.bak` recovery). Notes page edits use [`@Resources/NotesData.lua`](@Resources/NotesData.lua) to preserve UTF-8/UTF-16 encoding and unrelated INI sections/comments.
- C# snapshots use `WriteFast` (`MoveFileEx` with `REPLACE_EXISTING | WRITE_THROUGH`).
- Scanners acquire exclusive locks (`@Resources/Cache/AppScan.lock`, `@Resources/Cache/game_scan.lock`) and publish atomically so interrupted/failed scans preserve the prior catalog and icon generation.
- `ScanGames.ps1` emits data-only `[Variables]` (`Game<N>*`, `Platform<N>*`, `Utility<N>*`, `GameLibraryRevision`) in `Games/GameList.inc`; keep legacy `[Meter...]` fallback intact in `GameHubData.lua` unless intentionally deprecating it.

### G. Git Hygiene & Privacy
Never commit compiled binaries, personal files, or generated runtime artifacts (all listed in [`.gitignore`](.gitignore)):
- `@Resources/SlateHUDHelper.exe`, `@Resources/Plugins/SlateHUD.dll`, `@Resources/Plugins/FrostBehind.dll`, `@Resources/Plugins/FrostedGlass.dll`
- `@Resources/Cache/`, `@Resources/UserSettings.inc`
- `Apps/Catalog.inc`, `Apps/Catalog.inc.bak`, `Apps/Preferences.txt`, `Apps/Preferences.txt.bak`, `Apps/View.inc`
- `Games/Favorites.txt`, `Games/Favorites.txt.bak`, `Games/GameList.inc`, `Games/GameList.inc.bak`, `Games/Preferences.txt`, `Games/Preferences.txt.bak`, `Games/Recent.txt`, `Games/Recent.txt.bak`, `Games/View.inc`
- `Notes/Settings.inc`, `Notes/Data/` (including `PageN.inc` and `PageN.inc.undo`)
- `Tests/.scratch-*/`, `dist/`, `*.rmskin`, `*.exe.bak`, `*.dll.bak`, `*.tmp`, `*.TMP`, `@Resources/SlateHUDHelper.review-*.exe`

---

## 5. Key Workflows & Commands

### Rebuilding `SlateHUDHelper.exe` & `SlateHUD.dll`
Always rebuild after editing any of the five helper `.cs` files (`SlateHUDHelper.cs`, `MediaHelper.cs`, `ArtworkHelper.cs`, `TelemetryHelper.cs`, `DisplayProbe.cs`) or `@Resources/Plugin/SlateHUD.cpp`; `build.ps1` compiles `@Resources\SlateHUDHelper.exe` and (with MSVC Build Tools x64 `cl.exe`, unless `-SkipPlugin` is passed) `@Resources\Plugins\SlateHUD.dll`, syncing to `%APPDATA%\Rainmeter\Plugins\SlateHUD.dll`:
```powershell
# Build atomically (leaves existing binary intact on compile error):
powershell -NoProfile -ExecutionPolicy Bypass -File "@Resources\build.ps1"

# Build, stop running helper, replace binary, and restart daemon:
powershell -NoProfile -ExecutionPolicy Bypass -File "@Resources\build.ps1" -RestartHelper

# Rebuild only SlateHUDHelper.exe when MSVC Build Tools are unavailable:
powershell -NoProfile -ExecutionPolicy Bypass -File "@Resources\build.ps1" -SkipPlugin
```

### Running Scanners Manually
```powershell
# Refresh app catalog & local icons:
powershell -NoProfile -ExecutionPolicy Bypass -File "@Resources\ScanApps.ps1"

# Refresh game library (pass -NoNetwork to skip SteamSpy/Store lookups):
powershell -NoProfile -ExecutionPolicy Bypass -File "@Resources\ScanGames.ps1"
```

### Regression & Test Suites
All test suites use isolated `.scratch-*` temp directories and mocks; they do not modify personal notes, installed catalogs, or live system settings.

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
#    Uses a 64-bit Python 3.12 interpreter + lupa in Tests/.scratch-lua-runtime (locally: Tests\.scratch-python312\python.exe).
python Tests\WidgetRegression.py
```
If setting up the Lua test dependency from scratch with a 64-bit Python 3.12 interpreter:
```powershell
python -m pip install --target Tests/.scratch-lua-runtime lupa
```

---

## 6. Verification & Documentation Checklist

1. **Synchronize docs** whenever changing variables, features, timers, or publication cadence:
   - Keep portable defaults in [`@Resources/Variables.inc`](@Resources/Variables.inc) (and machine-local overrides in `@Resources/UserSettings.inc`).
   - Update [`README.md`](README.md) and [`docs/`](docs/architecture.md) (including polling, wakeup, or snapshot timing notes in [`docs/architecture.md`](docs/architecture.md), widget guides in [`docs/widgets.md`](docs/widgets.md), and [`Apps/README.md`](Apps/README.md) for Apps changes).
2. **Keep tests aligned** with architectural changes (especially `ThemeRegression.ps1` when adding variables/skins/menu slots, `HelperRegression.cs` for helper changes, and the Lua suites in `Tests/` for widget logic).
3. **Final check**: Recompile `SlateHUDHelper.exe` if any helper `.cs` changed, run all affected PowerShell and Lua regression suites after the final edit, and verify `git status` contains no personal or cache artifacts.
