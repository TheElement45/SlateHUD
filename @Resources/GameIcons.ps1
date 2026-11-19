# Local icon cache for the Game Hub tiles. This never changes game targets.

function Write-GameIcons([string]$SuiteRoot) {
    Add-Type -AssemblyName System.Drawing
    if (-not ('IconExport' -as [type])) {
        $iconCs = Join-Path $PSScriptRoot 'IconExport.cs'
        if (-not [IO.File]::Exists($iconCs)) { $iconCs = Join-Path $SuiteRoot '@Resources\IconExport.cs' }
        Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition ([IO.File]::ReadAllText($iconCs))
    }
    $cache = Join-Path $SuiteRoot '@Resources\Cache'
    $icons = Join-Path $cache 'GameIcons'
    [void][IO.Directory]::CreateDirectory($icons)
    $fallback = Join-Path $icons 'fallback.png'
    if (-not [IO.File]::Exists($fallback)) { [IconExport]::Fallback($fallback) }
    $records = [Collections.Generic.List[object]]::new()
    $gameVars = @{}
    $platformVars = @{}
    $utilityVars = @{}
    $record = $null
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $SuiteRoot 'Games\GameList.inc'))) {
        if ($line -match '^\[(.+)\]$') {
            if ($record) { $records.Add($record) }
            $record = if ($Matches[1] -match '^Meter(?:RPG|Action|Strategy|Other|Platforms|Utilities)\d+$') { @{} } else { $null }
        } elseif ($null -ne $record -and $line -match '^; GameAlias=(.*)$') {
            $record['_Aliases'] = @($record['_Aliases']) + @($Matches[1])
        } elseif ($null -ne $record -and $line -match '^([^=]+)=(.*)$') {
            $record[$Matches[1]] = $Matches[2]
        } elseif ($null -eq $record) {
            if ($line -match '^Game(\d+)(Title|GameId|GamePath|GameFolder|GameAvailable)=(.*)$') {
                $idx = [int]$Matches[1]
                if (-not $gameVars.ContainsKey($idx)) { $gameVars[$idx] = @{ _Aliases=@() } }
                $field = if ($Matches[2] -eq 'Title') { 'Text' } else { $Matches[2] }
                $gameVars[$idx][$field] = $Matches[3]
            } elseif ($line -match '^; Game(\d+)GameAlias=(.*)$') {
                $idx = [int]$Matches[1]
                if (-not $gameVars.ContainsKey($idx)) { $gameVars[$idx] = @{ _Aliases=@() } }
                $gameVars[$idx]['_Aliases'] = @($gameVars[$idx]['_Aliases']) + @($Matches[2])
            } elseif ($line -match '^Platform(\d+)(Title|Action)=(.*)$') {
                $idx = [int]$Matches[1]
                if (-not $platformVars.ContainsKey($idx)) { $platformVars[$idx] = @{} }
                $field = if ($Matches[2] -eq 'Title') { 'Text' } else { 'LeftMouseUpAction' }
                $platformVars[$idx][$field] = $Matches[3]
            } elseif ($line -match '^Utility(\d+)(Title|Action)=(.*)$') {
                $idx = [int]$Matches[1]
                if (-not $utilityVars.ContainsKey($idx)) { $utilityVars[$idx] = @{} }
                $field = if ($Matches[2] -eq 'Title') { 'Text' } else { 'LeftMouseUpAction' }
                $utilityVars[$idx][$field] = $Matches[3]
            }
        }
    }
    if ($record) { $records.Add($record) }
    foreach ($idx in @($gameVars.Keys | Sort-Object)) { $records.Add($gameVars[$idx]) }
    foreach ($idx in @($platformVars.Keys | Sort-Object)) { $records.Add($platformVars[$idx]) }
    foreach ($idx in @($utilityVars.Keys | Sort-Object)) { $records.Add($utilityVars[$idx]) }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('; Generated local icons, keyed by stable game identity. No network artwork.')
    $sha = [Security.Cryptography.SHA256]::Create()
    $shell = $null
    $shellApp = $null
    try {
        foreach ($item in $records) {
            $title = $item.Text -replace '^\[\\x25B8\]\s*',''
            $target = $item.GamePath
            if (-not $target -and $item.LeftMouseUpAction -match '^\["(.*)"\]$') { $target = $Matches[1] }
            $identity = if ($item.GameId) { $item.GameId } else { $title }
            # Legacy game rows use the same identity migration as the Lua controller.
            if (-not $item.GameId -and $item.ContainsKey('GameAvailable')) {
                $identity = if ($target -match '^steam://rungameid/(\d+)$') { 'steam:'+$Matches[1] } else { 'legacy:'+$target.ToLowerInvariant() }
            }
            $key = 'GameIcon' + ($identity -creplace '[^A-Za-z0-9]','')
            $source = ''; $index = 0; $shortcutPath = ''
            if ($target -and [IO.Path]::GetExtension($target) -eq '.lnk' -and [IO.File]::Exists($target)) {
                $shortcutPath = $target
                if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
                if (-not $shellApp) { $shellApp = New-Object -ComObject Shell.Application }
                try {
                    $lnk = $shell.CreateShortcut($target)
                    if ($lnk.IconLocation -match '^(.*),(-?\d+)$') {
                        $source = [Environment]::ExpandEnvironmentVariables($Matches[1].Trim('"'))
                        $index = [int]$Matches[2]
                    }
                    if (-not $source) { $source = [Environment]::ExpandEnvironmentVariables([string]$lnk.TargetPath) }
                    if (-not $source) {
                        $dir = [IO.Path]::GetDirectoryName($target)
                        $fn = [IO.Path]::GetFileName($target)
                        $ns = $shellApp.NameSpace($dir)
                        if ($ns) {
                            $fItem = $ns.ParseName($fn)
                            if ($fItem) {
                                $appId = [string]$fItem.ExtendedProperty('System.Link.TargetParsingPath')
                                if ($appId -match '^[\w.]+![\w.]+$') { $source = 'shell:AppsFolder\' + $appId }
                            }
                        }
                    }
                } catch { }
            } elseif ($target -and [IO.Path]::GetExtension($target) -eq '.url' -and [IO.File]::Exists($target)) {
                $shortcutPath = $target
                try {
                    $urlText = Get-Content -LiteralPath $target -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                    if ($urlText -match '(?m)^IconFile=(.+)') { $source = $Matches[1].Trim() }
                    if ($urlText -match '(?m)^IconIndex=(-?\d+)') { $index = [int]$Matches[1] }
                    if (-not $source -and $urlText -match '(?m)^URL=steam://rungameid/(\d+)') {
                        $appId = $Matches[1]
                        foreach ($registryRoot in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
                            $installed = Get-ItemProperty -LiteralPath ($registryRoot+'\Steam App '+$appId) -ErrorAction SilentlyContinue
                            if ($installed.DisplayIcon) { $source = $installed.DisplayIcon; break }
                        }
                    }
                } catch { }
            } elseif ($target -match '^steam://rungameid/(\d+)$') {
                $appId = $Matches[1]
                foreach ($registryRoot in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
                    $installed = Get-ItemProperty -LiteralPath ($registryRoot+'\Steam App '+$appId) -ErrorAction SilentlyContinue
                    if ($installed.DisplayIcon) { $source = $installed.DisplayIcon; break }
                }
            } elseif ($target -and [IO.File]::Exists($target)) { $source = $target }
            if (-not $source) {
                switch ($title) {
                    'Steam' {
                        $source = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamExe
                        if (-not $source) { $source = 'C:\Program Files (x86)\Steam\steam.exe' }
                    }
                    'Epic Games' {
                        $source = 'C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe'
                        if (-not [IO.File]::Exists($source)) { $source = 'C:\Program Files\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe' }
                    }
                    'Discord' {
                        $discord = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Discord\app-*\Discord.exe') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
                        if ($discord) { $source = $discord.FullName }
                    }
                    'Open Games Folder' { $source = Join-Path $env:WINDIR 'System32\shell32.dll'; $index = 3 }
                }
            }
            if ($source -match '^(.*),(-?\d+)$') { $source = $Matches[1]; $index = [int]$Matches[2] }
            $source = [Environment]::ExpandEnvironmentVariables(([string]$source).Trim('"'))
            # Launch scripts and protocol URLs are not artwork sources. Retain
            # shortcut icon metadata after merging a shortcut into its installation.
            if ([IO.Path]::GetExtension($source) -in @('.bat','.cmd')) { $source = '' }
            if (-not $source -or -not [IO.File]::Exists($source)) {
                foreach ($alias in @($item['_Aliases'])) {
                    if (-not $alias -or -not [IO.File]::Exists($alias)) { continue }
                    $iconSource=''; $iconIndex=0
                    if ([IO.Path]::GetExtension($alias) -eq '.url') {
                        $text = [IO.File]::ReadAllText($alias)
                        if ($text -match '(?m)^IconFile=(.+)') { $iconSource=$Matches[1].Trim() }
                        if ($text -match '(?m)^IconIndex=(-?\d+)') { $iconIndex=[int]$Matches[1] }
                    } elseif ([IO.Path]::GetExtension($alias) -eq '.lnk') {
                        if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
                        $link = $shell.CreateShortcut($alias)
                        if ($link.IconLocation -match '^(.*),(-?\d+)$') { $iconSource=$Matches[1]; $iconIndex=[int]$Matches[2] }
                    }
                    $iconSource=[Environment]::ExpandEnvironmentVariables($iconSource.Trim('"'))
                    if ($iconSource -and [IO.File]::Exists($iconSource)) { $source=$iconSource; $index=$iconIndex; break }
                }
            }
            if ((-not $source -or -not [IO.File]::Exists($source)) -and $item.GameFolder) {
                $localIcon=Join-Path $item.GameFolder 'icon.ico'
                if ([IO.File]::Exists($localIcon)) { $source=$localIcon; $index=0 }
            }
            if ((-not $source -or -not [IO.File]::Exists($source)) -and $item.GameFolder -and [IO.Directory]::Exists($item.GameFolder)) {
                # Steam may have no uninstall icon after a library move. Reading an
                # installed executable's icon does not change the Steam launch URI.
                $executable = Get-ChildItem -LiteralPath $item.GameFolder -Filter '*.exe' -File -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch '(?i)setup|unins|crash|redist|updat|report|helper|CEF|UnityCrash|launcher' } |
                    Sort-Object Length -Descending | Select-Object -First 1
                if ($executable) { $source = $executable.FullName; $index = 0 }
            }
            $output = $fallback
            $canExtract = ($source -and [IO.File]::Exists($source)) -or
                          ($source -and $source.StartsWith('shell:AppsFolder\', [StringComparison]::OrdinalIgnoreCase)) -or
                          ($shortcutPath -and [IO.File]::Exists($shortcutPath))
            if ($canExtract) {
                $stamp = 0
                if ($source -and [IO.File]::Exists($source)) { $stamp = ([IO.File]::GetLastWriteTimeUtc($source)).Ticks }
                elseif ($shortcutPath -and [IO.File]::Exists($shortcutPath)) { $stamp = ([IO.File]::GetLastWriteTimeUtc($shortcutPath)).Ticks }
                $hashKey = if ($shortcutPath) { "$shortcutPath|$source|$index|$stamp" } else { "$source|$index|$stamp" }
                $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($hashKey))).Replace('-','').ToLowerInvariant()
                $candidate = Join-Path $icons ($hash+'.png')
                try {
                    if ([IO.File]::Exists($candidate)) { $output = $candidate }
                    else {
                        $temporary = $candidate+'.tmp'
                        if ([IconExport]::Save($shortcutPath,$source,$index,$temporary)) {
                            [IO.File]::Move($temporary,$candidate); $output = $candidate
                        }
                    }
                } catch { } # A missing icon must never prevent scanning or launching.
                finally { if ([IO.File]::Exists($candidate+'.tmp')) { [IO.File]::Delete($candidate+'.tmp') } }
            }
            $lines.Add($key+'='+$output)
        }
    } finally { $sha.Dispose() }
    $manifest = Join-Path $cache 'GameIcons.inc'
    $temporaryManifest = $manifest+'.tmp'
    try {
        [IO.File]::WriteAllText($temporaryManifest,($lines -join "`r`n"),[Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($manifest)) { [IO.File]::Replace($temporaryManifest,$manifest,$manifest+'.bak') }
        else { [IO.File]::Move($temporaryManifest,$manifest) }
    } finally { if ([IO.File]::Exists($temporaryManifest)) { [IO.File]::Delete($temporaryManifest) } }
}
