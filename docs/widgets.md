# SlateHUD Widget & Customization Guide

This guide covers configuration, interactive controls, multi-monitor adaptive layout, and troubleshooting across all SlateHUD widgets.

---

## 🎨 Theme, Blur & Threshold Customization

All skins share [`@Resources/Variables.inc`](../@Resources/Variables.inc). Personal overrides (selected theme, layout mode, scale, blur preset, network ping toggle, and machine-specific paths) are stored in git-ignored `@Resources\UserSettings.inc` (auto-seeded by `SlateHUDHelper.exe` and included after defaults in `Variables.inc`), keeping `Variables.inc` portable. Refresh the SlateHUD skins after manual edits.

Every card's right-click context menu provides quick presets for:
- **Themes:** Amber (Default), Cyberpunk, Nord Frost, Tokyo Night, Monochrome Stealth, and Windows Accent Sync (dynamically synced from Windows personalization via `@Resources\Cache\WindowsAccent.inc`).
- **Effects & Opacity:** Toggle DWM Acrylic blur (`Blur: DWM Acrylic` / `Blur: Off`, automatically adjusting `BlurTightFrame`), Dark (`180`), Translucent (`110`), and Frosted Glass (`85`) presets. Right-click **System** for **Toggle UI animations** (`UiAnimations`).
- **Size:** Compact (`PreferredUiScale=1`) and Readable (`PreferredUiScale=1.125`).
- **Display Target:** Auto, External, or Laptop placement.

### Shared Configuration Variables (`@Resources/Variables.inc`)

| Variable | Default | Description |
| :--- | :--- | :--- |
| `CurrentTheme` | `Default` | Active theme preset from `@Resources\Themes\` (`Default`, `Cyberpunk`, `NordFrost`, `TokyoNight`, `Monochrome`, `WindowsAccent`) |
| `AcrylicBlur` | `None` | DWM background blur mode (`Acrylic`, `Blur`, or `None`); uses optional unbundled `FrostBehind.dll` (or legacy `FrostedGlass.dll`) via [`@Resources/Blur.inc`](../@Resources/Blur.inc). Place the 64-bit `.dll` in `%APPDATA%\Rainmeter\Plugins\` (or `<RainmeterDirectory>\Plugins\` for portable installs) |
| `BlurPlugin` / `BlurCorner` | `FrostBehind` / `Round` | Plugin name and corner mode (`Round`, `RoundSmall`, `DoNotRound`) passed to `[MeasureBlur]` in [`@Resources/Blur.inc`](../@Resources/Blur.inc); Windows 11 supports native `Round` DWM corners, while Windows 10 falls back to rectangular blur |
| `BlurTightFrame` | `0` | Collapses transparent snap margins (`1` = tight framing when `Blur: DWM Acrylic` is enabled, `0` = standard `8,16` snap margins) while [`@Resources/Layout.lua`](../@Resources/Layout.lua) compensates window coordinates |
| `UiAnimations` / `UiAnimationsBatterySaver` | `0` / `1` | Opt-in event-driven `ActionTimer` hover/seek/volume micro-animations in `Apps`, `Games`, and `NowPlaying`, auto-bypassed on battery via `PowerPlugin` when `UiAnimationsBatterySaver=1` |
| `fontName` | `Segoe UI` | Primary UI font across all cards |
| `iconFont` | `Segoe Fluent Icons` | Font used for media, battery, and volume icons |
| `ColorAccent` | `235,170,0,255` | Highlight/accent color (bars, hover states, category headers; overridden by theme presets) |
| `ColorHistory2` / `ColorDivider` / `ColorPill` / `ColorInputFill` / `ColorCoverFill` | Portable defaults | Secondary chart line, divider hairlines, control pills, `InputText` backgrounds, and `NowPlaying` cover placeholder (overridden by theme presets; `WindowsAccent` clamps accent luminance and auto-refreshes live on accent changes) |
| `PreferredUiScale` | `1.125` | Preferred external-monitor size; use `1` for Compact. Automatic layout also applies the laptop cap and fits the top row beside the desktop icon rail |
| `LaptopUiScale` | `0.95` | Compact size cap on laptop displays or below 1700 logical pixels of work-area width; external displays restore `PreferredUiScale` |
| `UiScale` | Calculated | Effective size shared by text, cards, shapes, inputs, and click targets (derived from `LayoutRowWidth`) |
| `CardOpacity` | `180` | Background alpha (`180` Dark, `110` Translucent, `85` Frosted Glass) |
| `CardFill` | `14,14,18,#CardOpacity#` | Card background RGBA |
| `CardStroke` | `255,255,255,30` | 1px rounded card border color |
| `CardRadius` | `10` | Corner radius (px) for all cards |
| `VisualizerUpdate` | `40` | Visualizer frame interval on AC in ms (`40` = 25 fps, `33` = 30 fps, `50` = 20 fps) |
| `VisualizerBatteryUpdate` | `66` | Visualizer frame interval on battery in ms (`66` ≈ 15 fps) |
| `VisualizerBatterySaver` | `1` | Switches visualizer to `Economy.ini` (~15 fps) while on battery (`0` disables) |
| `VisualizerHideIdle` | `0` | Hides the idle/paused visualizer card when silent (`1` hides, `0` shows baseline) |
| `NetIPDisplay` | `measureIPMasked` | `measureIPMasked` (`•••.•••.•••.42`, reveal on hover) or `measureIP` (always visible) |
| `NetAutoScale` | `1` | Automatically scale traffic bars to observed peak traffic (`0` uses fixed limits below) |
| `maxDownload` / `maxUpload` | `125000000` | Fixed-mode bar ceilings in bytes/sec (`125000000` = 1 Gbps); `0` keeps that direction auto-scaled even in Fixed mode |
| `NetPingEnabled` | `0` | Toggles periodic ping monitoring on the Network card (`0` or `1`; saved in `UserSettings.inc`) |
| `NetHistory` / `SysHistory` | `0` / `0` | Compact 2-series history strips for Network traffic and System CPU/GPU load (`1` shows, `0` hides) |
| `SysSensorProvider` / `SysLhmEnabled` | `auto` / `0` | System GPU/CPU telemetry source (`auto` = NVML GPU + optional LHM CPU temp/GPU fallback, `nvml`, or `lhm`). Enabling `SysLhmEnabled=1` or `lhm` polls running LibreHardwareMonitor for CPU temp and AMD/Intel/fallback GPU telemetry |
| `LhmSource` / `LhmEndpoint` | `auto` / `http://127.0.0.1:8085/data.json` | LHM transport (`auto`, `wmi` via `root\LibreHardwareMonitor`, or `http`) and validated loopback endpoint (`127.0.0.1` / `localhost` only) |
| `ColorWarn` / `ColorCrit` | Amber / Red | Colors applied automatically when metrics cross warning/critical thresholds |
| `WarnUsage` / `CritUsage` | `80` / `95` | CPU & GPU usage warning thresholds (%) |
| `WarnTemp` / `CritTemp` | `75` / `85` | CPU (when LHM temp active) & GPU temperature warning thresholds (°C) |
| `WarnMem` / `CritMem` | `80` / `92` | VRAM, RAM, and pagefile usage warning thresholds (%) |
| `WarnDisk` / `CritDisk` | `85` / `95` | Disk space used warning thresholds (%) |
| `WarnDiskFreeGB` / `CritDiskFreeGB` | `20` / `5` | Decimal GB remaining thresholds on Disks (`1 GB = 1,000,000,000 bytes`; `0` disables). The stronger of percentage and free-space severity applies |
| `WarnPing` / `CritPing` | `80` / `150` | Ping latency warning thresholds (ms) |
| `WarnBatt` / `CritBatt` | `30` / `15` | Battery charge warning thresholds (%, low is bad while discharging) |
| `disk1` / `disk2` / `disk3` | `C:` / `D:` / `E:` | Drive letters monitored by the Disks card |
| `LayoutPlacement` / `LayoutMode` | `auto` / `0` | Monitor routing (`auto`, `external`, `laptop`) and layout mode (`0` = fit one top row, `1` = manual shelf wrapping at `PreferredUiScale`) |
| `GamesFolder` | `C:\Games` | Portable default folder scanned for standalone games (override locally in `UserSettings.inc`, e.g. `D:\Games`, which also holds `HoYoPlay\`) |
| `GamesFolders` | Empty | Additional standalone folders separated by `\|` (primary `GamesFolder` remains included; duplicates removed) |
| `GamesExcludedDrives` | Empty | Comma-separated drive letters excluded from discovered and remembered sources (e.g. `GamesExcludedDrives=G:` in `UserSettings.inc`) |
| `GameMaxCardH` | `480` | Preferred maximum Game Hub card height in pixels; longer libraries use pages |
| `GameNotesReserve` | `260` | Space reserved below Game Hub when calculating its screen-aware height limit, in addition to `NotesGap` |
| `AppMaxCardH` | `540` | Maximum expanded Apps launcher card height before viewport fitting clamps rows and reclaims the favorites shelf |
| `NotesGap` | `24` | Gap in pixels below Game Hub; Notes tracks Game Hub's actual position and height |
| `GameShowRecent` | `1` | Shows the Recent category in Game Hub (up to 4 launches from this widget; `0` hides it) |
| `StatCardW` / `StatCardH` / `BatteryCardH` / `WideCardW` / `MediaCardH` / `VisualizerCardH` / `CardFrameW` / `CardFrameH` / `CardGap` / `IconRailW` | `222` / `168` / `110` / `320` / `140` / `44` / `16` / `24` / `8` / `80` | Shared logical card geometry metrics used across skins and [`@Resources/Layout.lua`](../@Resources/Layout.lua) |
| `MusicApp` / `MusicAppName` | YouTube Music executable / `YouTube Music` | App path or URI and display name used by the idle music shortcut |
| `XXMILauncher` | Empty | Optional extra launcher path (set locally in `UserSettings.inc`; hidden in Game Hub when empty or missing) |

---

## 📱 Apps Launcher

See the dedicated [Apps launcher guide](../Apps/README.md) for setup, categorization rules, CSV configuration, removing shortcuts, saved state, and recovery.

Summary of [`Apps/Apps.ini`](../Apps/Apps.ini):
- Shares the left sidebar below `NowPlaying` and `Visualizer` with room for one desktop icon column; unloading `SlateHUD\Apps` restores the previous layout.
- Displays up to eight favorites above six expandable categories (`Communication`, `Development`, `Creative`, `Utilities`, `System`, `Productivity`). On vertically constrained screens, [`@Resources/Apps.lua`](../@Resources/Apps.lua) clamps `pageSize` (4 vs. 8 items) and reclaims the favorites shelf while a category is open so the card never clips below the work area.
- Right-click any app to **Pin/Unpin**, move favorites left/right, recategorize, **Hide app** (and view **Show hidden apps** from the card menu), or **Open shortcut location**. Entries configured with a `Secondary` shortcut in [`Apps/Shortcuts.csv`](../Apps/Shortcuts.csv) also show a secondary-profile action in the tile menu and beside their icon.
- Hover details share an in-card footer (`ToolTipHidden=1`) instead of native popup tooltips.
- Generate the initial catalog on a fresh checkout before loading:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "@Resources\ScanApps.ps1"
```

---

## 🌐 Network Widget

[`Network/Network.ini`](../Network/Network.ini) displays public IPv4, active adapter LAN IP, public IPv6 availability, optional ping latency, and upload/download traffic. [`@Resources/Network.lua`](../@Resources/Network.lua) validates responses, clears failed results, and manages backoff retries and display states.

### Configuration and Applying Changes
- Default `NetIPDisplay`, `NetAutoScale`, `maxDownload`, and `maxUpload` values live in [`@Resources/Variables.inc`](../@Resources/Variables.inc); set overrides in `@Resources\UserSettings.inc` and **Refresh skin** after manual edits. Clicking the **NETWORK** title refreshes readings only.
- `NetIPDisplay=measureIPMasked` hides the first three IPv4 octets until hovered; `measureIP` keeps the full address visible. IPv6 displays `Available` and reveals the full address on hover. Hovering the LAN label or value shows the complete adapter alias and LAN IP.
- `NetAutoScale=1` scales each traffic bar to observed peak traffic. Click **Auto / Fixed**, a traffic label/bar, or **Switch Auto / Fixed scale** in the context menu to save the mode. Fixed limits use bytes/sec (`12500000` = 100 Mbps, `125000000` = 1 Gbps; `0` keeps that direction auto-scaled).
- Right-click Network for **Toggle traffic history** (`NetHistory`) and **Toggle ping monitoring** (`NetPingEnabled`). When enabled, ping checks `pingHost=1.1.1.1` every 5 seconds with a 2-second timeout (`WarnPing=80`, `CritPing=150` ms).

### Refresh and Recovery
- Click **NETWORK**, the **WAN IPv4 value**, the **IPv6 value**, or the **ping value** to refresh LAN details, public addresses, and ping together (rapid repeat clicks within 2 seconds are ignored). Hover the title or public-address values for separate IPv4/IPv6 last-success times (`Never` until first lookup after load).
- Public IPv4 and IPv6 use family-specific `icanhazip` endpoints (`ipv4.icanhazip.com` / `ipv6.icanhazip.com`) with `ident.me` fallbacks (`4.ident.me` / `6.ident.me`). A failed or malformed lookup clears the cached value (including IPv4 hover reveal) and tries the fallback on the next update; if both fail, that family backs off at roughly **1, 2, 4, 8, then 15 minutes** (staying at 15 minutes until recovery). Manual refresh or network change resets both families to primary and clears backoff.
- Adapter identity, LAN IP, and Windows IPv4/IPv6 connectivity are checked every 5 seconds; changes refresh public lookups and ping automatically.

| Display | Meaning |
| :--- | :--- |
| `Checking...` | Initial lookup or explicit refresh awaiting a result |
| IPv6 `Available` | Latest public IPv6 lookup succeeded |
| Public address `Lookup failed` | Request failed or returned an invalid address; automatic retries continue |
| Public address `Offline` | Windows reports neither IPv4 nor IPv6 internet connectivity |
| IPv6 `No IPv6` | Windows reports no IPv6 internet route while IPv4 remains connected |
| Ping `Timeout` | Probe failed to return a reply |
| Ping `Unavailable` | No completion result arrived for 10 seconds; later results restore latency |

---

## 🎮 Game Hub & Custom Overrides

### Setup and Scanning
1. Set `GamesFolder` in `@Resources\UserSettings.inc` (portable default `C:\Games` in [`@Resources/Variables.inc`](../@Resources/Variables.inc)) to your primary standalone games folder. Optionally add extra roots in `GamesFolders`, separated by `|`. Shortcuts placed in `Desktop\Games` are also discovered.
2. Review `GamesExcludedDrives` (portable default is empty in `Variables.inc`). Exclude cloud/virtual drives such as `G:` in `@Resources\UserSettings.inc` so scans skip them.
3. Load or refresh [`Games/Games.ini`](../Games/Games.ini), then click **SCAN** to discover games. Scanning is manual; refreshing the widget alone reloads the saved list.

| Source | Discovery | Default launch method |
| :--- | :--- | :--- |
| Steam | Registry, `libraryfolders.vdf`, and `appmanifest_*.acf`; install folder must exist | Steam game URI |
| Epic Games | Installed manifests under `%ProgramData%\Epic\EpicGamesLauncher\Data\Manifests`; incomplete installs skipped | Epic launcher URI |
| HoYoPlay | `HoYoPlay\games` beneath each configured root, plus `C:\Program Files\HoYoPlay\games` | Recognized game executable, otherwise target selection |
| Standalone | Immediate game folders inside `GamesFolder` / `GamesFolders` with bounded target search | Override, launcher metadata, recognized script, or scored executable |
| Desktop Games | Direct `.lnk` / `.url` shortcuts (and game subfolders) inside `Desktop\Games` | Shortcut launch directly, or resolved executable / URI |

Example `@Resources\UserSettings.inc` snippet for `D:`, `E:`, `F:` while excluding `G:`:

```ini
GamesFolder=D:\Games
GamesFolders=E:\Games|F:\Games
GamesExcludedDrives=G:
```

Exclusions apply to remembered sources as well (preventing stale `G:\SteamLibrary` probes from reappearing). Steam's configuration is never modified. The `GAME HUB` title and `Open Games Folder` open only the primary `GamesFolder`.

### Customizing Games (`Games/Overrides.txt`)
Add customization rules in [`Games/Overrides.txt`](../Games/Overrides.txt), then click **SCAN** (`Games\GameList.inc` is regenerated on every scan):

```text
# Format: MatchFolderOrTitle | DisplayTitle | Category | CustomExeOrURI | Arguments | WorkingDirectory
# Categories: RPG, ACTION, STRATEGY, OTHER, HIDE

ACE COMBAT 8 - WINGS OF THEVE | ACE COMBAT 8 | ACTION |
Call of Duty - Modern Warfare 4 | Call of Duty: MW | ACTION |
SomeRedistFolder | | HIDE |
My Game | My Game | ACTION | launcher.exe | --profile "Player One" | .
```

- Rules use case-insensitive substring matching against folder or title; first match wins (no wildcards). Invalid categories or >6 fields fail the scan and keep the previous list.
- Relative executable/working-directory paths resolve against the game folder; omitted working directories default to the executable's folder.
- Hide rules and explicit targets apply before recursive discovery, letting a folder use a custom URI/executable even when automatic detection finds no target. Local launches and folder opens run directly through `SlateHUDHelper.exe launchgame` (checking availability and passing saved arguments and working directory without `powershell.exe` startup delay); [`@Resources/LaunchGame.ps1`](../@Resources/LaunchGame.ps1) is retained as a standalone PowerShell utility and regression harness.

### Layout and Saved Preferences
- Four-column icon grid; click a category button to expand one group at a time. Category selection and per-category pages persist in `Games\View.inc`.
- Up to four favorites appear above categories (right-click a tile to pin/unpin or reorder); pinned games are removed from their regular category to avoid duplicates, and offline favorites remain dimmed and unpinnable.
- Use **< / >** or mouse wheel to page (4 or 8 tiles; final page preserves layout height). `SEARCH` filters titles and category names without scanning (click **x** or right-click to clear; favorites remain accessible).
- `GameShowRecent=1` adds a Recent category for up to four launches dispatched from this widget.
- Icons are extracted locally via [`@Resources/IconExport.cs`](../@Resources/IconExport.cs) and Steam's registered icon files into `@Resources\Cache\GameIcons.inc`; missing icons fall back to a generic icon or initials.
- `GameMaxCardH` sets the preferred height cap while reserving `GameNotesReserve` + `NotesGap` below; short screens switch to one tile row and fold favorites into a category button. Notes docks dynamically to Game Hub's position and right edge.
- Favorites use stable IDs in `Games\Favorites.txt` with automatic migration from legacy path pins and atomic `.tmp`/`.bak` recovery.

### Scan Results, Merging & Recovery
- Each scan saves per-source snapshots in `@Resources\Cache\game_library.json` (missing/unreadable sources keep prior entries as unavailable; healthy sources prune removed games). Steam uses app IDs, Epic uses platform identity, supported HoYoPlay titles use fixed IDs, and standalone games use their install folder.
- **Merging rules:** Desktop shortcuts merge only on matching platform ID or an unambiguous exact executable target with agreeing launch arguments and working directory (no title-only merging across distinct installs). Detected Fortnite shipping executables route through Epic Games Launcher and merge by launcher identity. Steam desktop shortcuts pointing to missing executable icon targets on an online drive are excluded when no installed Steam record exists and Steam sources succeeded. Merged entries keep shortcut artwork; script launchers support local `icon.ico`, and icon search checks up to 4 levels deep.
- **Authoritative published catalog:** `Games\GameList.inc` uses a data-only `[Variables]` format (`Game<N>*`, `Platform<N>*`, `Utility<N>*`, `GameLibraryRevision`) shared by both `Games.ini` tiles and `LaunchGame.ps1`. Clicking a stale-revision tile reloads the list and prompts re-selection. Clearing the cache leaves `GameList.inc` usable until the next scan rebuilds `game_library.json`.
- Hover **SCAN** or the subtitle for warnings and last-success time (`@Resources\Cache\game_scan_status.txt`). Overlapping scans are blocked by `@Resources\Cache\game_scan.lock` (70s discovery budget, 90s Rainmeter timeout; interrupted scans keep the current catalog).

| Symptom | Action |
| :--- | :--- |
| Drive or library unavailable | Reconnect or restore read access, then click SCAN |
| Cloud drive appears in scan warnings | Add its drive letter to `GamesExcludedDrives` in `UserSettings.inc` and rescan |
| Wrong executable or uncertain target | Set `CustomExeOrURI` (and optional args/cwd) in `Overrides.txt`, then rescan |
| Four favorite slots occupied by missing games | Right-click offline tiles to unpin them |
| Runtime cache was cleared | Existing shortcuts use `GameList.inc` metadata; click SCAN to rebuild JSON history |
| Saved library JSON is corrupt | Back up/move `game_library.json` aside and rescan (corrupt files are never silently discarded) |
| Scan was interrupted | Wait for the prior process to stop, then click SCAN again |
| Reset category selection and pages | Move `Games\View.inc` aside and refresh the skin |

- **Category & Steam Genre Policy:** Categories resolve in strict order: `Overrides.txt` > platform metadata/defaults > curated franchise and word/phrase-boundary title rules (preventing substring false positives like matching `Sim` inside `Simple Plan`) > **Other Games**. Right-click choices in `Preferences.txt` override defaults on display. SteamSpy/Steam Store lookups share a ~40s budget per scan, match complete tag names scored by strongest single tag vote (Steam Store genres have equal weight; ties prefer RPG > Strategy > Action; Anime/Gacha alone do not assign a genre), record provider + classifier version, refresh after 30 days (24 hours for confirmed unknowns), and retain last-known categories if offline or failed.

---

## 🖱️ Interactive Shortcuts

- **Now Playing:**
  - **Next player / Next audio:** Cycle active media session or audio output device. Middle-click **Next player** to lock/unlock the player; right-click **Next player** to restore automatic playing-session priority.
  - **Idle Title / Subtitle:** Click `Nothing playing` or `Click to open YouTube Music` to launch `MusicApp`. Middle-click track title while active to cycle sessions.
  - **Progress Bar:** Left-click anywhere on the bar to seek (when supported by SMTC capabilities).
  - **Album art:** Middle-click to trigger thumbnail + online artwork refresh.
  - **Prev / Play-Pause / Next:** Control active media session (or open `MusicApp` when idle).
  - **Speaker / Volume %:** Scroll anywhere on the card (±2%), left-click to mute, middle-click to cycle output devices.
- **Disks:** Click **`DISKS`** to open `This PC`; click **`C:\`**, **`D:\`**, or **`E:\`** labels to open drives in Explorer (missing drives show `Not present` and disable click actions).
- **Network:** Click **`NETWORK`**, public-address values, or ping value to refresh; hover WAN IPv4 to reveal full address; hover IPv6 or LAN label/value for full details; click **`Auto` / `Fixed`**, Upload/Download labels, or traffic bars to toggle scaling. Right-click card actions display live states for **Toggle traffic history (`On`/`Off`)**, **Toggle ping monitoring (`On`/`Off`)**, and **Switch Auto / Fixed scale (`Auto`/`Fixed`)**.
- **System:** Left-click **`SYSTEM`** for Task Manager; middle-click to toggle fitted-row / shelf layout; right-click to realign; right-click card actions display live states for **Toggle CPU / GPU history (`On`/`Off`)**, **Toggle UI animations (`On`/`Off`)**, **Toggle LHM sensors (`On`/`Off`)**, and **Cycle GPU sensor priority (`Auto` / `LHM` / `NVML`)**.
- **Notes:**
  - **Initialization & Resilience:** On load, the helper seeds missing personal page files and tab settings (`Notes\Data\PageN.inc` and `Notes\Settings.inc`) before enabling left-click editing, keeping right-click `SuiteMenu()` usable while loading. If initialization fails, `FailReady()` keeps mouse actions enabled and turns the footer hint into a click-to-retry prompt.
  - **Click Note Text / Checkbox:** Click text to edit inline (Enter saves; empty clears and unchecks; `"` converts to `'`; `#`, `[`, `]` display safely as fullwidth characters). Click a checkbox to toggle completion (empty rows open the editor).
  - **Right-click Task / Checkbox:** **Move up** / **Move down** swaps rows within the active page (moving text, status, daily repeat, and reset date together), plus repeat and delete actions.
  - **Daily Tasks:** Repeat icon marks daily tasks; checkboxes reset automatically at **`DailyResetHour=4` (4:00 AM local PC time)** across all 3 pages (override `DailyResetHour` `0–23` in `Notes\Settings.inc` under `[Variables]`). Backward clock changes do not re-trigger resets.
  - **Tabs, Title, Trash & Undo:** Click tabs `1–3` to switch pages; click page title to rename inline (empty falls back to `Page N`); right-click title or click Notepad icon to edit the `.inc` file in Notepad; click Trash for footer confirmation (**COMPLETED** clears checked non-daily tasks, **ALL** clears everything, **CANCEL** aborts); click Undo for durable single-level per-page undo/redo (`Notes\Data\PageN.inc.undo`), preserved across tabs, refreshes, restarts, and daily rollovers (cross-day restores advance daily checkboxes to today, and failed `.undo` saves block mutations).
- **Battery:** Click **`BATTERY`** to open Windows battery settings; auto-hides on desktops without a battery. Distinguishes `Charging`, `Fully charged`, `Not charging`, discharging time remaining, and `No estimate`.
- **Game Hub:** Click **`GAME HUB`** or `Open Games Folder` to open `GamesFolder`; click **SCAN** to rescan; right-click tiles to pin/unpin, reorder favorites, open install folder, change/reset category, or hide/restore.

---

## 🖥️ Adaptive Display Layout

With both displays active in Windows **Extend** mode, keep the `System` skin loaded and choose **Display: Auto** from any card's context menu:
- Starts on the external display and moves all loaded widgets to the laptop once fullscreen occupancy stays stable for ~2 seconds; returns after fullscreen ends. **Display: External** and **Display: Laptop** pin the suite manually (unavailable targets fall back to an active display).
- During a full-screen Snipping Tool or `ScreenClippingHost` capture overlay, automatic placement publishes unknown occupancy and holds its current destination so screenshots do not bounce widgets between monitors.
- Ensure [Rainmeter Game mode](https://docs.rainmeter.net/manual/user-interface/manage/#TheGameModeTab) does not unload SlateHUD skins during fullscreen; even in manual placement modes, `Visualizer` switches to `Suspended.ini` while the external display is occupied and restores its prior active/battery/idle state afterward.
- `System` publishes the destination work area via `@Resources/Cache/Display.inc` (`LayoutRowWidth` and `UiScale` derive dynamically from shared card metrics in `Variables.inc`). Laptop displays or work areas `< 1700` px wide apply `LaptopUiScale=0.95`; `1920`-wide external work areas retain `PreferredUiScale=1.125`; ultra-narrow screens fall back to shelf wrapping at minimum scale `0.75`.
- For multi-external setups, copy target identities from `@Resources/Cache/monitors.txt` into `LayoutExternalId` / `LayoutLaptopId` in `UserSettings.inc` (`LayoutMonitor` acts as Rainmeter monitor-number fallback).
- Middle-click **SYSTEM** to toggle fitted rows vs. shelves; right-click **SYSTEM** to realign. Layout moves preserve hidden/unloaded skin state and defer geometry reloads on hidden skins until shown.

---

## 📐 Screen-Edge Snap Padding

Every skin includes a transparent margin controlled by `BlurTightFrame`: in default blur-off mode (`BlurTightFrame=0`), each card uses a `CardPadX=8`, `CardPadY=16` offset plus a 1×1 invisible `[MeterPad]` / `[meterPad]` scaled by `UiScale` so snapping against a monitor edge or adjacent skin keeps a clean gap. When DWM blur is enabled via **Blur: DWM Acrylic** (`BlurTightFrame=1`), internal snap margins collapse to `0` so blur hugs the card bounds (`CardRadius=10`, Windows 11 `BlurCorner=Round`) while [`@Resources/Layout.lua`](../@Resources/Layout.lua) shifts window positions to keep visible card spacing identical. Adaptive layout adds an 8-logical-pixel outer margin and shelf gaps.
