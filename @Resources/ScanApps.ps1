[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$suite = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'AppDiscovery.ps1')
$appsFolder = Join-Path $suite 'Apps'
$iconFolder = Join-Path $PSScriptRoot 'Cache\AppIcons'
[IO.Directory]::CreateDirectory($iconFolder) | Out-Null
Add-Type -AssemblyName System.Drawing
if (-not ('IconExport' -as [type])) {
    $iconCs = Join-Path $PSScriptRoot 'IconExport.cs'
    if (-not [IO.File]::Exists($iconCs)) { $iconCs = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '@Resources\IconExport.cs' }
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition ([IO.File]::ReadAllText($iconCs))
}

$scanLock = $null
$generation = $null
$published = $false
try {
    # Hold the lock through publication so two widgets / manual scans cannot race.
    $scanLock = [IO.File]::Open((Join-Path $PSScriptRoot 'Cache\AppScan.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $generation = Join-Path $iconFolder ([Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($generation) | Out-Null
    $output = Join-Path $appsFolder 'Catalog.inc'
    $previous = if (Test-Path -LiteralPath $output) { [IO.File]::ReadAllText($output) } else { '' }
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutFolder = Join-Path $desktop 'Apps'
    $null = Get-LaunchAction $shortcutFolder
    # The Apps folder takes precedence; desktop roots remain a configured fallback.
    $links = Get-AppShortcutIndex -Folders @([Environment]::GetFolderPath('CommonDesktopDirectory'),$desktop,$shortcutFolder)
    $configured = @(Import-Csv -LiteralPath (Join-Path $appsFolder 'Shortcuts.csv'))
    $rows = @(Get-AppRows -Links $links -ConfiguredRows $configured -DiscoveryFolder $shortcutFolder)
    $shell = New-Object -ComObject WScript.Shell
    $shellApp = New-Object -ComObject Shell.Application
    $records = @()
    $warnings = 0
    foreach ($row in $rows) {
        if (-not $links.ContainsKey($row.Shortcut)) { continue }
        if ($row.Category -notin (Get-AppCategories)) { throw 'Unknown app category in Shortcuts.csv.' }
        $path = $links[$row.Shortcut]
        $action = Get-LaunchAction $path
        $id = 'App{0:D2}' -f ($records.Count + 1)
        $icon = Join-Path $generation ($id + '.png')
        try {
            $source = ''; $iconIndex = 0
            if ([IO.Path]::GetExtension($path) -eq '.lnk') {
                $shortcut = $shell.CreateShortcut($path)
                if ($shortcut.IconLocation -match '^(.*),(-?\d+)$') {
                    $source = [Environment]::ExpandEnvironmentVariables($Matches[1].Trim('"'))
                    $iconIndex = [int]$Matches[2]
                }
                if (-not $source) { $source = $shortcut.TargetPath }
                if (-not $source) {
                    $item = $shellApp.NameSpace([IO.Path]::GetDirectoryName($path)).ParseName([IO.Path]::GetFileName($path))
                    $appId = [string]$item.ExtendedProperty('System.Link.TargetParsingPath')
                    if ($appId -match '^[\w.]+![\w.]+$') { $source = 'shell:AppsFolder\' + $appId }
                }
            } else {
                $urlText = Get-Content -LiteralPath $path -Raw
                if ($urlText -match '(?m)^IconFile=(.+)') { $source = $Matches[1].Trim() }
                if ($urlText -match '(?m)^IconIndex=(-?\d+)') { $iconIndex = [int]$Matches[1] }
            }
            if (-not [IconExport]::Save($path,$source,$iconIndex,$icon)) { throw 'Icon unavailable' }
        } catch {
            # A malformed shortcut or missing icon must not block other apps.
            [IconExport]::SaveFallback($icon)
            $warnings++
        }
        $secondary = ''
        if ($row.Secondary -and $links.ContainsKey($row.Secondary)) { $secondary = Get-LaunchAction $links[$row.Secondary] }
        $records += [pscustomobject]@{
            Id=$id; Key=(Get-AppShortcutKey $row.Shortcut); Name=(Convert-IniText $row.Shortcut)
            Label=(Convert-IniText $row.Label); Path=$path; Category=$row.Category
            Favorite=$row.Favorite; Icon=$icon; Action=$action; SecondaryAction=$secondary
        }
    }
    $text = New-AppCatalogText -Records $records -ShortcutFolder $shortcutFolder -Warnings $warnings
    $temporary = $output + '.tmp'
    [IO.File]::WriteAllText($temporary,$text,[Text.UTF8Encoding]::new($true))
    # Each catalog references its own completed icon generation. Failed refreshes
    # cannot overwrite icons used by the last successful catalog.
    if (Test-Path -LiteralPath $output) { [IO.File]::Replace($temporary,$output,$output+'.bak') }
    else { [IO.File]::Move($temporary,$output) }
    $published = $true

    # Keep the current catalog, its backup, and all young generations in case a
    # skin is still painting old icons. Only scanner-owned GUID directories qualify.
    $keep = @([IO.Path]::GetFileName($generation))
    foreach ($match in [regex]::Matches($previous,'[\\/]([a-f0-9]{32})[\\/]App\d+\.png')) { $keep += $match.Groups[1].Value }
    $resolvedIconRoot = [IO.Path]::GetFullPath($iconFolder).TrimEnd('\')
    try {
        foreach ($folder in Get-ChildItem -LiteralPath $iconFolder -Directory) {
            if ($folder.Name -notmatch '^[a-f0-9]{32}$' -or $folder.Name -in $keep -or $folder.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddMinutes(-5)) { continue }
            $candidate = [IO.Path]::GetFullPath($folder.FullName)
            if ([IO.Path]::GetDirectoryName($candidate) -eq $resolvedIconRoot -and -not ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Remove-Item -LiteralPath $candidate -Recurse -Force -ErrorAction Stop
            }
        }
    } catch { } # Cache cleanup must not turn a successful publication into a failure.
    Write-Output ('APPS:PUBLISHED ' + $records.Count + ' WARNINGS ' + $warnings)
} catch {
    Write-Output ('APPS:FAILED ' + $_.Exception.Message)
    exit 1
} finally {
    if ($scanLock) { $scanLock.Dispose() }
    if (-not $published -and $generation -and (Test-Path -LiteralPath $generation)) {
        $candidate = [IO.Path]::GetFullPath($generation)
        $resolvedIconRoot = [IO.Path]::GetFullPath($iconFolder).TrimEnd('\')
        if ([IO.Path]::GetDirectoryName($candidate) -eq $resolvedIconRoot -and [IO.Path]::GetFileName($candidate) -match '^[a-f0-9]{32}$') {
            Remove-Item -LiteralPath $candidate -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
