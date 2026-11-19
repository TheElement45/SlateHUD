# Packages a clean, portable SlateHUD release archive and SHA256SUMS.txt.
[CmdletBinding()]
param(
    [string]$Version = '2.4.0',
    [string]$OutputDir = 'dist'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outPath = if ([IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $root $OutputDir }
$helperExe = Join-Path $root '@Resources\SlateHUDHelper.exe'
$pluginDll = Join-Path $root '@Resources\Plugins\SlateHUD.dll'

if (-not (Test-Path -LiteralPath $helperExe -PathType Leaf)) {
    throw "Missing compiled helper: $helperExe (run @Resources\build.ps1 first)."
}
if (-not (Test-Path -LiteralPath $pluginDll -PathType Leaf)) {
    throw "Missing compiled native plugin: $pluginDll (run @Resources\build.ps1 first)."
}

$cleanVersion = $Version.TrimStart('v', 'V')
if ([string]::IsNullOrWhiteSpace($cleanVersion) -or $cleanVersion -match '[\\/:*?"<>|\s]') {
    throw "Invalid release version: $Version"
}

[void][IO.Directory]::CreateDirectory($outPath)
$zipName = "SlateHUD-v$cleanVersion-win64.zip"
$zipPath = Join-Path $outPath $zipName
$sumsPath = Join-Path $outPath 'SHA256SUMS.txt'

$stageParent = Join-Path ([IO.Path]::GetTempPath()) ('slatehud-pkg-' + [Guid]::NewGuid().ToString('N'))
$stageRoot = Join-Path $stageParent 'SlateHUD'

function Copy-FilteredTree {
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [string]$RelativePrefix
    )
    [void][IO.Directory]::CreateDirectory($DestDir)

    foreach ($dir in Get-ChildItem -LiteralPath $SourceDir -Directory -Force) {
        $rel = if ($RelativePrefix) { "$RelativePrefix/$($dir.Name)" } else { $dir.Name }
        if ($rel -ieq '@Resources/Cache' -or
            $rel -ieq 'Notes/Data' -or
            $dir.Name -like '.tmp-plugin-*') {
            continue
        }
        Copy-FilteredTree -SourceDir $dir.FullName -DestDir (Join-Path $DestDir $dir.Name) -RelativePrefix $rel
    }

    foreach ($file in Get-ChildItem -LiteralPath $SourceDir -File -Force) {
        $rel = if ($RelativePrefix) { "$RelativePrefix/$($file.Name)" } else { $file.Name }
        if ($rel -ieq '@Resources/UserSettings.inc' -or
            $rel -ieq '@Resources/Plugins/FrostBehind.dll' -or
            $rel -ieq '@Resources/Plugins/FrostedGlass.dll' -or
            $rel -ieq 'Apps/Catalog.inc' -or
            $rel -ieq 'Apps/Catalog.inc.bak' -or
            $rel -ieq 'Apps/Preferences.txt' -or
            $rel -ieq 'Apps/Preferences.txt.bak' -or
            $rel -ieq 'Apps/View.inc' -or
            $rel -ieq 'Games/Favorites.txt' -or
            $rel -ieq 'Games/Favorites.txt.bak' -or
            $rel -ieq 'Games/GameList.inc' -or
            $rel -ieq 'Games/GameList.inc.bak' -or
            $rel -ieq 'Games/Preferences.txt' -or
            $rel -ieq 'Games/Preferences.txt.bak' -or
            $rel -ieq 'Games/Recent.txt' -or
            $rel -ieq 'Games/Recent.txt.bak' -or
            $rel -ieq 'Games/View.inc' -or
            $rel -ieq 'Notes/Settings.inc' -or
            $file.Name -like 'SlateHUDHelper.review-*.exe' -or
            $file.Name -ieq 'Thumbs.db' -or
            $file.Name -ieq 'desktop.ini' -or
            $file.Extension -in @('.tmp', '.bak', '.obj', '.lib', '.exp', '.pdb')) {
            continue
        }
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $DestDir $file.Name) -Force
    }
}

try {
    [void][IO.Directory]::CreateDirectory($stageRoot)

    foreach ($topFile in @('NowPlaying.ini', 'LICENSE', 'README.md', 'SECURITY.md')) {
        $src = Join-Path $root $topFile
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
            throw "Missing required release file: $src"
        }
        Copy-Item -LiteralPath $src -Destination (Join-Path $stageRoot $topFile) -Force
    }

    foreach ($folder in @('docs', 'Apps', 'Battery', 'Disks', 'Games', 'Network', 'Notes', 'System', 'Visualizer', '@Resources')) {
        $srcDir = Join-Path $root $folder
        if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) {
            throw "Missing required release directory: $srcDir"
        }
        Copy-FilteredTree -SourceDir $srcDir -DestDir (Join-Path $stageRoot $folder) -RelativePrefix $folder
    }

    if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory(
        $stageRoot,
        $zipPath,
        [IO.Compression.CompressionLevel]::Optimal,
        $true
    )

    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $helperHash = (Get-FileHash -LiteralPath $helperExe -Algorithm SHA256).Hash.ToLowerInvariant()
    $dllHash = (Get-FileHash -LiteralPath $pluginDll -Algorithm SHA256).Hash.ToLowerInvariant()

    $sumLines = @(
        "$zipHash  $zipName",
        "$helperHash  SlateHUD/@Resources/SlateHUDHelper.exe",
        "$dllHash  SlateHUD/@Resources/Plugins/SlateHUD.dll"
    )
    [IO.File]::WriteAllText($sumsPath, ($sumLines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))

    Write-Output "Packaged $zipPath"
    Write-Output "Checksums written to $sumsPath"
}
finally {
    if (Test-Path -LiteralPath $stageParent -PathType Container) {
        Remove-Item -LiteralPath $stageParent -Recurse -Force -ErrorAction SilentlyContinue
    }
}
