# Security Policy

## Supported Versions

| Version | Supported |
| :--- | :--- |
| 2.4.x | Yes |
| < 2.4.0 | No |

## Reporting a Vulnerability

Please report security issues privately using GitHub Security Advisories rather than opening a public issue:

- https://github.com/TheElement45/SlateHUD/security/advisories/new

Include reproduction steps, affected files or components, and any relevant Windows / Rainmeter version details.

---

## Transparency & Runtime Architecture

SlateHUD includes a local C# background helper (`@Resources\SlateHUDHelper.exe`) and a native x64 Rainmeter plugin (`@Resources\Plugins\SlateHUD.dll`) built from source in this repository.

### Local Binaries & Plugin Sync

- **Source-built releases:** Neither binary is tracked in `main`. GitHub Releases attach `SlateHUD-v<version>-win64.zip` and `SHA256SUMS.txt` built directly in GitHub Actions, and you can build both locally from source via `@Resources\build.ps1`.
- **Automatic plugin sync:** When `SlateHUDHelper.exe` starts (`ensure` / `daemon`), it copies `@Resources\Plugins\SlateHUD.dll` into `%APPDATA%\Rainmeter\Plugins\SlateHUD.dll` (or `<RainmeterDirectory>\Plugins\SlateHUD.dll` for portable installs) if the destination file is missing or outdated so Rainmeter can load `[Measure...Bridge]` measures.
- **Lifecycle:** `SlateHUDHelper.exe` enforces a single daemon instance (`Local\SlateHUDHelper.Daemon`) and exits automatically within ~10 seconds after `Rainmeter.exe` closes.

### Local IPC & Access Controls

- **Shared memory (`Local\SlateHUDHelper.SharedState`):** Session-scoped 64 KiB memory-mapped section containing read-only snapshots (`media`, `media-health`, `gpu`, `monitors`, `helper-health`).
- **Named pipe (`\\.\pipe\SlateHUDHelper.Pipe`):** Restricted with a current-user ACL (`PipeSecurity`) and bounded read timeouts; accepts only the fixed media control command allowlist (`ping`, `playpause`, `next`, `prev`, `seek`, `nextplayer`, `lockplayer`, `resetplayer`, `refetchcover`).
- **LibreHardwareMonitor telemetry (opt-in):** When `SysLhmEnabled=1` or `SysSensorProvider=lhm`, `SlateHUDHelper.exe` reads local WMI (`root\LibreHardwareMonitor`) or a loopback-only HTTP endpoint (`127.0.0.1` / `localhost`, redirects disabled). Non-loopback or credentialed URLs are rejected.

### Outbound Network Connections

SlateHUD makes outbound HTTPS requests only for the features listed below; no telemetry or analytics are sent anywhere:

| Feature | Endpoint(s) | Notes |
| :--- | :--- | :--- |
| Network WAN IPv4/IPv6 display | `https://ipv4.icanhazip.com`, `https://4.ident.me`, `https://ipv6.icanhazip.com`, `https://6.ident.me` | Plaintext public IP lookup (`Network\Network.ini`). IPv4 is masked (`•••.•••.•••.last_octet`) by default until hovered. |
| Network ping (disabled by default) | `1.1.1.1` (`pingHost`) | Runs only when `NetPingEnabled=1`. |
| Album artwork fallback | `https://itunes.apple.com/search?...` | TLS 1.2+ only with 4-second timeout and 16 MiB cap when SMTC provides no thumbnail or a browser reports a low-res/stale cover. |
| Steam genre classification | `https://steamspy.com/api.php`, `https://store.steampowered.com/api/appdetails` | Runs only when clicking **SCAN** in Game Hub (skip via `ScanGames.ps1 -NoNetwork`). |

### Rebuilding from Source

To compile `@Resources\SlateHUDHelper.exe` and `@Resources\Plugins\SlateHUD.dll` locally from audited source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "@Resources\build.ps1" -RestartHelper
```

Pass `-SkipPlugin` to rebuild only `SlateHUDHelper.exe` using Windows' built-in `.NET Framework 4` compiler if Visual Studio C++ Build Tools are not installed.
