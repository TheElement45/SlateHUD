# Apps launcher

The Apps widget launches Windows shortcuts from a four-column grid. It shows up to eight favorites above six expandable categories and sits below the music visualizer. The shared layout keeps it aligned with the music card and fits it to laptop and external-monitor work areas.

## Setup

1. Create an `Apps` folder on your Windows desktop and put `.lnk` or `.url` shortcuts directly inside it. Nested folders are not scanned.
2. From the suite directory, generate the local app catalog:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "@Resources\ScanApps.ps1"
   ```

3. Load `SlateHUD\Apps\Apps.ini` in Rainmeter.

Click **REFRESH** after adding, moving, or removing shortcuts. After updating the skin's code, use Rainmeter's **Refresh skin** action to load the new files. Refreshing only the app catalog does not install applications or change their shortcuts.

Launches open the original shortcut, preserving its arguments, working directory, Store-app identity, or URL. The `Desktop\Apps` copy takes precedence when a configured shortcut also exists on your personal or public desktop. Configured entries can use either desktop as a fallback; automatic discovery adds only shortcuts directly inside `Desktop\Apps`.

## Everyday controls

| Control | Behavior |
| --- | --- |
| App tile | Left-click to launch; right-click for app actions. |
| Pin / Unpin | Keep up to eight apps visible above the category buttons. Unpin one before adding a ninth. |
| Move favorite left / right | Swap a favorite with its neighbor and save the order. |
| Hide app | Remove the app from favorites, categories, and normal search. Its shortcut stays in place. |
| Show hidden apps | Right-click the card and choose this item to browse hidden apps. Right-click a tile and choose **Restore app**. |
| Move to a category | Apply and save a personal category override immediately. |
| Open shortcut location | Open Explorer with the app's shortcut selected. |
| Secondary arrow (`▾`) | When a row defines an optional `Secondary` shortcut in `Shortcuts.csv`, open that secondary shortcut. The same action appears in the app's menu. |
| Search apps | Type part of a shortcut name or display label, then press Enter. Results include favorites and all categories. |
| Search **x** / right-click search | Clear the filter and restore the previous category and page. Escape dismisses an unfinished edit. |
| Category button | Expand that group, switch from another group, or collapse the active group. Counts exclude favorites. |
| **< / >** / mouse wheel | Browse up to eight category apps per page. The arrows stay in place on the final page. |
| Open Apps folder | Open the main shortcut folder. |

Each category remembers its page across skin refreshes. Only one category is expanded at a time. Favorites start in catalog order and use your saved order after you move them. Restoring a hidden favorite restores its pin when space is available.

App labels have room for two lines. Hover over a tile to read its full name and category in the footer. App and control hints share this one footer; native popup tooltips are disabled. Rapid hover transitions update highlighting without repositioning or rebuilding the app grid, and an older leave event cannot clear a newer tile's highlight.

## Categories and precedence

Categories appear in two columns and three rows:

| Category | Automatic name matches include |
| --- | --- |
| Communication | Brave, Edge, Chrome, Firefox, Discord, WhatsApp, Telegram, Slack, Zoom. |
| Development | Visual Studio Code, Git Bash, Eclipse, Antigravity, PyCharm, IntelliJ, Notepad++. |
| Creative | Resolve, OBS Studio, music and media players, Photoshop, Blender, Audacity, Wallpaper Engine, Peace. |
| Utilities | Shortcuts that do not match another category, including general download tools and launchers. |
| System | CrystalDiskInfo, WizTree, MSI Afterburner, Flydigi, NVIDIA App, Revo Uninstaller, Windhawk, Superposition, and other recognized hardware tools. |
| Productivity | Google Drive, Docs, Sheets, Slides, Gemini, PDFgear, and recognized office, notes, and task apps. |

Automatic matching uses case-insensitive keywords in the **shortcut name**. The rules are in [`AppDiscovery.ps1`](../@Resources/AppDiscovery.ps1). Category selection uses this precedence:

1. Your saved choice from the app's right-click menu.
2. An explicit `Category` in `Shortcuts.csv`.
3. Automatic name matching for a newly discovered shortcut, falling back to Utilities.

## CSV defaults

Edit [`Shortcuts.csv`](Shortcuts.csv), then click **REFRESH** to apply default labels, ordering, categories, and favorites.

| Column | Meaning |
| --- | --- |
| `Shortcut` | Shortcut filename without `.lnk` or `.url`. |
| `Label` | Display name below the icon; the shortcut name remains searchable. |
| `Category` | One of the six category names above. |
| `Favorite` | `1` for a default favorite, otherwise `0`. |
| `Secondary` | Optional secondary shortcut name (without its extension), e.g. a second browser profile. It stays attached to the primary app when that shortcut exists. |

For example:

```csv
Shortcut,Label,Category,Favorite,Secondary
Brave,Brave,Communication,1,Personal - Brave
Google Drive,Drive,Productivity,1,
CrystalDiskInfo,Disk Info,System,0,
```

Configured rows appear first in CSV order. Newly discovered shortcuts follow in name order. Missing configured shortcuts are skipped. Additional configured favorites beyond eight remain available in their categories.

Personal pin and category choices override the CSV defaults. To change an app's category after making a personal choice, use its menu again. To reset all personal choices, unload the Apps skin, remove both `Preferences.txt` and `Preferences.txt.bak` if present, then load the skin again.

## Hiding an app from the widget

Choose **Hide app** in its tile menu. To restore it, open **Show hidden apps** from the card menu and choose **Restore app** on the tile. The hidden list supports the same search and paging controls.

## Saved state and refresh recovery

| Local file | Purpose |
| --- | --- |
| `Catalog.inc` / `.bak` | Generated app metadata and meters; the backup retains the previous published catalog. |
| `Preferences.txt` / `.bak` | Personal pins, favorite order, category overrides, and hidden apps. Choices use a case-insensitive shortcut name hash. Moving a shortcut preserves its identity. Renaming it creates a new one. |
| `View.inc` | Expanded category and remembered page for each category. |
| `../@Resources/Cache/AppIcons/` | Extracted icons, grouped into completed scan generations. |
| `../@Resources/Cache/AppScan.lock` | Exclusive file handle prevents concurrent scan publication. |

These generated files and personal settings are ignored by Git. Keep custom defaults in the CSV and controller changes in [`Apps.lua`](../@Resources/Apps.lua); do not edit the generated catalog.

Icons are extracted locally. If one is unavailable, the scanner uses a generic icon and reports a warning while retaining the launch action. A scan builds a new icon generation before publishing its catalog, so a failed scan cannot overwrite the icons used by the previous successful catalog. Older unused generations are cleaned up while retaining the current catalog's icons, the backup catalog's icons, and recent generations.

The footer reports scan progress and failures. If **RETRY** appears, check the shortcut folder and CSV category names, then try again. Existing apps remain available after a failed refresh. If no shortcuts are found, the widget shows setup guidance.

If old overlapping popup windows remain after installing this update, refresh the Apps skin once to recreate its meters with native tooltips disabled.

## Verification

Run from the suite directory:

```powershell
python Tests\WidgetRegression.py
powershell -NoProfile -ExecutionPolicy Bypass -File Tests\AppDiscoveryRegression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File Tests\AppScanRegression.ps1
```

The Python runner requires `lupa`; its existing optional local setup is `python -m pip install --target Tests/.scratch-lua-runtime lupa`. Tests use Lua 5.1, matching Rainmeter's scripting language version.

Coverage includes six-category layout and persistence, favorites limits and failed-save rollback, search, stable and remembered pages, profile/menu actions, rapid hover transitions without popup or layout updates, supported monitor bounds, shortcut discovery, icon fallback, failed-scan rollback, and concurrent scan exclusion. Scanner failure tests use isolated fixture folders and leave the live catalog untouched.

Hover and layout checks use a mocked Rainmeter API. Live rendering, actual mouse behavior, and application launches require verification in Rainmeter.
