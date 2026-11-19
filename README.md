# SlateHUD Rainmeter Suite (v2.4)

[![CI](https://github.com/TheElement45/SlateHUD/actions/workflows/ci.yml/badge.svg)](https://github.com/TheElement45/SlateHUD/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/TheElement45/SlateHUD)](https://github.com/TheElement45/SlateHUD/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-blue)](#requirements)

A lightweight, translucent desktop HUD dashboard suite for **Rainmeter** (Windows) featuring real-time CPU/GPU/RAM telemetry, Windows SMTC media controls, network & storage monitoring, a 4-mode audio spectrum visualizer, searchable app & game launchers, and a multi-page notes/checklist widget.

---

## 📋 Requirements

- **OS:** Windows 11 (recommended) or Windows 10.
  - *Windows 10 icon font note:* SlateHUD defaults to `iconFont=Segoe Fluent Icons` (built into Windows 11). On Windows 10, either install the Segoe Fluent Icons font or set `iconFont=Segoe MDL2 Assets` in `@Resources\UserSettings.inc`.
- **Rainmeter:** 64-bit Rainmeter **4.5 or newer**.
- **Optional building from source:** Built-in Windows `.NET Framework 4` `csc.exe` (included with Windows) compiles `SlateHUDHelper.exe`; **Visual Studio Build Tools (MSVC x64 C++ tools)** are required to compile the native `SlateHUD.dll` plugin (or pass `-SkipPlugin` to `@Resources\build.ps1` to build only the C# helper).

---

## 📥 Installation

### Option A — Release ZIP (Recommended)
1. Download `SlateHUD-v2.4.0-win64.zip` and `SHA256SUMS.txt` from [GitHub Releases](https://github.com/TheElement45/SlateHUD/releases).
2. Optionally verify the checksum in PowerShell before extracting:
   ```powershell
   Get-FileHash .\SlateHUD-v2.4.0-win64.zip -Algorithm SHA256
   ```
   Compare the hash against `SHA256SUMS.txt`.
3. Extract the `SlateHUD\` folder into your Rainmeter skins folder:
   ```text
   %USERPROFILE%\Documents\Rainmeter\Skins\SlateHUD
   ```
4. Refresh all skins in Rainmeter (or click **Refresh all** in Manage Rainmeter). When `NowPlaying.ini` or `System\System.ini` loads, `SlateHUDHelper.exe` automatically copies `SlateHUD.dll` into `%APPDATA%\Rainmeter\Plugins\` (or `<RainmeterDirectory>\Plugins\` in Portable Mode).

### Option B — From Source
Prebuilt binaries (`SlateHUDHelper.exe` and `SlateHUD.dll`) are not committed to `main`. After cloning, build them locally before loading the skins:

```powershell
git clone https://github.com/TheElement45/SlateHUD.git "%USERPROFILE%\Documents\Rainmeter\Skins\SlateHUD"
cd "%USERPROFILE%\Documents\Rainmeter\Skins\SlateHUD"
powershell -NoProfile -ExecutionPolicy Bypass -File "@Resources\build.ps1"
```

If Visual Studio C++ Build Tools are not installed, pass `-SkipPlugin` to compile `SlateHUDHelper.exe` alone (Rainmeter skins fall back cleanly to reading `@Resources\Cache\*.txt` and invoking the helper CLI).

---

## 🚀 Quick Start

1. **Generate local catalogs on a fresh checkout** (git-ignored files stay local):
   - **Apps Launcher:** Put `.lnk` / `.url` shortcuts in `Desktop\Apps`, then run:
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File "@Resources\ScanApps.ps1"
     ```
   - **Game Hub:** Load `SlateHUD\Games\Games.ini`, set `GamesFolder` (and optionally `GamesFolders` / `GamesExcludedDrives`) in `@Resources\UserSettings.inc`, and click **SCAN**.
2. **Load skins in Rainmeter:** Load `NowPlaying.ini`, `System\System.ini`, `Network\Network.ini`, `Disks\Disks.ini`, `Battery\Battery.ini`, `Visualizer\Visualizer.ini`, `Apps\Apps.ini`, `Games\Games.ini`, and `Notes\Notes.ini` (all share `Group=SlateHUD`).
3. **Customize via right-click menu:** Every card shares a suite menu for **Size** (`Compact` / `Readable`), **Opacity** (`Dark` / `Translucent` / `Frosted Glass`), **Display Target** (`Auto` / `External` / `Laptop`), **Themes** (`Amber`, `Cyberpunk`, `Nord Frost`, `Tokyo Night`, `Monochrome Stealth`, `Windows Accent Sync`), and **Blur** (`DWM Acrylic` enables tight DWM framing and requires placing third-party 64-bit `FrostBehind.dll` — or `FrostedGlass.dll` if `BlurPlugin=FrostedGlass` — in `%APPDATA%\Rainmeter\Plugins\` or `<RainmeterDirectory>\Plugins\`). Right-click **System** for **Toggle UI animations**. All choices save to `@Resources\UserSettings.inc`.

---

## 🧩 Widgets Overview

| Skin | Role | Guide |
| :--- | :--- | :--- |
| [`NowPlaying.ini`](NowPlaying.ini) | Windows SMTC media player, seek bar, artwork, volume & output switcher | [Shortcuts & Media](docs/widgets.md#-interactive-shortcuts) |
| [`Visualizer/Visualizer.ini`](Visualizer/Visualizer.ini) | 36-band equalizer with AC, battery (`Economy.ini`), idle (`Idle.ini`), and fullscreen (`Suspended.ini`) modes | [Performance & Modes](docs/architecture.md#skin-update-cadences--ui-throttling) |
| [`Apps/Apps.ini`](Apps/Apps.ini) | Searchable 6-category launcher with 8 favorites, hide/restore, and optional secondary links | [Apps Guide](Apps/README.md) |
| [`Games/Games.ini`](Games/Games.ini) | Steam, Epic, HoYoPlay, standalone & Desktop Games launcher with overrides and recent history | [Game Hub](docs/widgets.md#-game-hub--custom-overrides) |
| [`Notes/Notes.ini`](Notes/Notes.ini) | 3-page checklist with inline editing, 4 AM daily reset, row reorder, and per-page undo | [Notes Shortcuts](docs/widgets.md#-interactive-shortcuts) |
| [`System/System.ini`](System/System.ini) | CPU (+ optional LibreHardwareMonitor temp), NVIDIA NVML / optional LHM GPU, VRAM, RAM, pagefile, history & display layout host | [Display Layout](docs/widgets.md#-adaptive-display-layout) |
| [`Network/Network.ini`](Network/Network.ini) | Public IPv4/IPv6, LAN adapter IP, optional ping, Auto/Fixed traffic bars & history | [Network Widget](docs/widgets.md#-network-widget) |
| [`Disks/Disks.ini`](Disks/Disks.ini) | Volume labels, decimal GB free space, percentage + GB warnings, combined R/W throughput | [Disks & Variables](docs/widgets.md#-theme-blur--threshold-customization) |
| [`Battery/Battery.ini`](Battery/Battery.ini) | Charge %, AC/not-charging state & remaining time (auto-hides on desktops) | [Battery Controls](docs/widgets.md#-interactive-shortcuts) |

---

## 📚 Documentation

* [**Widget & Customization Guide**](docs/widgets.md) — Shared variables (`Variables.inc` / `UserSettings.inc`), Network backoff/states, Game Hub overrides/merging/classification, full shortcut reference, adaptive multi-monitor routing, and snap padding.
* [**Architecture, Performance & Verification**](docs/architecture.md) — `SlateHUDHelper.exe` daemon & snapshot streams, update cadences, configuration/menu invariants, known scope limits, and automated/live test workflows.
* [**Apps Launcher Guide**](Apps/README.md) — Dedicated setup, CSV defaults, category precedence, and scan recovery for `Apps`.
* [**Security Policy**](SECURITY.md) — Helper/plugin IPC boundaries, outbound endpoints, and vulnerability reporting.

---

## 🔒 Security & Binaries

- All compiled binaries (`SlateHUDHelper.exe` and `SlateHUD.dll`) are built transparently in GitHub Actions for each release (with `SHA256SUMS.txt` published alongside the release ZIP) and can be rebuilt from source via `@Resources\build.ps1`.
- `SlateHUDHelper.exe` automatically copies `@Resources\Plugins\SlateHUD.dll` to `%APPDATA%\Rainmeter\Plugins\SlateHUD.dll` (or `<RainmeterDirectory>\Plugins\SlateHUD.dll` in Portable Mode) when newer.
- Outbound HTTPS connections are limited to explicit features (public IP lookup, optional ping when enabled, missing/browser album art fallback over TLS 1.2+, and Steam genre lookups during manual Game Hub scans). See [SECURITY.md](SECURITY.md) for the complete list and IPC details.

---

## 📁 Suite Structure

```text
SlateHUD/
├── README.md                     # Suite overview, installation, quick start & docs index
├── LICENSE                       # MIT license
├── SECURITY.md                   # Binary transparency, IPC controls & vulnerability reporting
├── AGENTS.md                     # AI agent architecture guide & repository conventions
├── .github/workflows/            # CI verification & release packaging workflows
├── scripts/
│   └── PackageRelease.ps1        # Stages clean release ZIP and SHA256SUMS.txt
├── docs/
│   ├── widgets.md                # Widget guides, shortcuts, variables & multi-monitor layout
│   └── architecture.md           # Background helper, update cadences, invariants & test suites
├── NowPlaying.ini                # Media player card (Windows SMTC + audio device control)
├── Disks/
│   └── Disks.ini                 # Storage usage (C:, D:, E:) & real-time Disk Read/Write
├── Network/
│   └── Network.ini               # Public/LAN addresses, ping, refresh controls, Auto/Fixed traffic bars
├── Battery/
│   └── Battery.ini               # Laptop battery %, power source, time left (hides itself on desktops)
├── System/
│   └── System.ini                # CPU, NVIDIA GPU (usage, temp, power), VRAM, RAM, Pagefile
├── Apps/
│   ├── Apps.ini                  # Searchable launcher, eight favorites, and six categories
│   ├── README.md                 # Apps setup, controls, categories, CSV, and recovery
│   ├── Shortcuts.csv             # Default shortcut order, labels, categories, and favorites
│   ├── Catalog.inc               # Generated local app metadata and meters (git-ignored)
│   ├── Preferences.txt           # Personal pin/category overrides (git-ignored)
│   └── View.inc                  # Saved expanded group and category pages (git-ignored)
├── Notes/
│   ├── Notes.ini                 # Multi-tab tasks & checklist with inline editing and undo
│   ├── Defaults.inc              # Fallback page title / empty notes
│   ├── Settings.inc              # Active page state (git-ignored)
│   └── Data/                     # Page1..3.inc & Page1..3.inc.undo backups (git-ignored)
├── Visualizer/
│   ├── Visualizer.ini            # 36-band equalizer (active AC animation, default 25 fps)
│   ├── Economy.ini               # Reduced animation on battery (~15 fps)
│   ├── Idle.ini                  # Low-frequency peak-only audio wake checks (250 ms)
│   ├── Suspended.ini             # Static fullscreen card with zero AudioLevel measures
│   └── Appearance.inc            # Shared static background, baseline gradient, and padding
├── Games/
│   ├── Games.ini                 # Game Hub header, styling, and layout container
│   ├── Overrides.txt             # Custom game rules (rename, recategorize, hide, custom exe)
│   ├── Favorites.txt             # Personal pinned games (git-ignored)
│   ├── View.inc                  # Active category and saved pages (git-ignored)
│   └── GameList.inc              # Data-only [Variables] catalog (written by ScanGames.ps1; git-ignored)
└── @Resources/
    ├── Variables.inc             # Portable suite defaults, layout metrics & theme/blur wiring
    ├── UserSettings.inc          # Local user overrides (git-ignored; auto-seeded by SlateHUDHelper.exe)
    ├── Styles.inc                # Shared card, typography, and bar styles
    ├── Blur.inc                  # Optional DWM Acrylic blur configuration (`FrostBehind` default; optional unbundled `.dll`)
    ├── Context.inc               # Shared 18-slot suite context menu & DefaultDraggable=0
    ├── ContextMenu.lua           # Dynamic suite (1–18) & item (1–N) menu builder
    ├── Themes/                   # Theme presets (Default, Cyberpunk, NordFrost, TokyoNight, etc.)
    ├── Plugin/
    │   └── SlateHUD.cpp          # Thin native x64 Rainmeter plugin bridge (shared memory + pipe IPC)
    ├── Plugins/
    │   └── SlateHUD.dll          # Built x64 bridge plugin (git-ignored; built by build.ps1 / Releases)
    ├── SlateHUDHelper.cs / .exe  # C# background daemon (`.exe` git-ignored; built by build.ps1 / Releases)
    ├── build.ps1                 # Atomic helper & native plugin build script (`-RestartHelper`, `-SkipPlugin`)
    ├── ScanApps.ps1 / AppDiscovery.ps1 / Apps.lua
    ├── ScanGames.ps1 / GameDiscovery.ps1 / GameIcons.ps1 / LaunchGame.ps1
    ├── GameHub.lua / GameHubData.lua / GameHubLayout.lua / IconExport.cs
    ├── Layout.lua / DisplayState.lua / HelperWatchdog.lua / FileStore.lua
    ├── MediaUnicode.lua / Media.lua / System.lua / Network.lua / Disks.lua / Battery.lua
    ├── Notes.lua / NotesData.lua / Visualizer.lua
    └── Cache/                    # Ephemeral runtime snapshots, icons, locks & JSON caches (git-ignored)
```

---

## 🤖 AI-Assisted Development

Portions of the codebase, documentation, and test suites in SlateHUD were developed and refined with AI coding assistants under human direction, review, and testing. Release binaries (`SlateHUDHelper.exe` and `SlateHUD.dll`) are built transparently in GitHub Actions and covered by the automated regression suites in [`Tests/`](Tests/) and [SECURITY.md](SECURITY.md).

---

## 🙏 Credits & License

- Built for [Rainmeter](https://www.rainmeter.net/).
- Optional DWM blur support via third-party `FrostBehind.dll` or `FrostedGlass.dll`.
- Optional extended CPU/GPU telemetry via [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) and NVIDIA NVML.
- Licensed under the [MIT License](LICENSE).
