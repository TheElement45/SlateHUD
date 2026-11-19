$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $PSScriptRoot ('.scratch-app-scan-' + [Guid]::NewGuid().ToString('N'))
function Assert-Scan($value,[string]$message) { if (-not $value) { throw $message } }
try {
    $resources = Join-Path $scratch '@Resources'
    $apps = Join-Path $scratch 'Apps'
    $links = Join-Path $resources 'Links'
    foreach ($folder in $resources,$apps,$links) { [IO.Directory]::CreateDirectory($folder) | Out-Null }
    Copy-Item -LiteralPath (Join-Path $root '@Resources\ScanApps.ps1') -Destination $resources
    Copy-Item -LiteralPath (Join-Path $root '@Resources\IconExport.cs') -Destination $resources
    $discovery = [IO.File]::ReadAllText((Join-Path $root '@Resources\AppDiscovery.ps1'))
    # Only fixture shortcuts can enter this scanner process. No real desktop data
    # or live catalog is read or changed by these failure scenarios.
    $fixtureIndex = @'

function Get-AppShortcutIndex {
    param([string[]]$Folders)
    return @{
        Good = (Join-Path $PSScriptRoot 'Links\Good.url')
        Missing = (Join-Path $PSScriptRoot 'Links\Missing.url')
        Bad = (Join-Path $PSScriptRoot 'Links\Bad#Name.url')
    }
}
'@
    [IO.File]::WriteAllText((Join-Path $resources 'AppDiscovery.ps1'),$discovery + $fixtureIndex,[Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $links 'Good.url'),"[InternetShortcut]`r`nURL=https://example.invalid`r`nIconFile=$env:WINDIR\System32\shell32.dll`r`nIconIndex=3`r`n")
    $csv = Join-Path $apps 'Shortcuts.csv'
    [IO.File]::WriteAllText($csv,"Shortcut,Label,Category,Favorite,Secondary`r`nGood,Good app,Utilities,1,`r`nMissing,Missing icon,Utilities,0,`r`n")
    $catalog = Join-Path $apps 'Catalog.inc'
    [IO.File]::WriteAllText($catalog,'previous successful catalog')
    $scanner = Join-Path $resources 'ScanApps.ps1'
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $result = & $powershell -NoProfile -ExecutionPolicy Bypass -File $scanner
    Assert-Scan ($LASTEXITCODE -eq 0 -and ($result -join ' ').Contains('APPS:PUBLISHED 2 WARNINGS 1')) 'One unavailable icon blocked the scan or lacked a warning'
    $published = [IO.File]::ReadAllText($catalog)
    Assert-Scan ($published.Contains('AppCount=2') -and $published.Contains('AppScanWarnings=1')) 'Published catalog omitted the fallback app'
    Assert-Scan ([IO.File]::ReadAllText($catalog + '.bak') -eq 'previous successful catalog') 'Previous catalog was not retained'
    $iconRoot = Join-Path $resources 'Cache\AppIcons'
    $icons = @(Get-ChildItem -LiteralPath $iconRoot -Recurse -File)
    Assert-Scan ($icons.Count -eq 2) 'Fallback PNG or normal icon is missing'
    $hashes = @{}
    foreach ($icon in $icons) { $hashes[$icon.FullName] = (Get-FileHash -LiteralPath $icon.FullName).Hash }

    Add-Content -LiteralPath $csv -Value 'Bad,Bad path,Utilities,0,'
    $result = & $powershell -NoProfile -ExecutionPolicy Bypass -File $scanner
    Assert-Scan ($LASTEXITCODE -ne 0 -and ($result -join ' ').Contains('APPS:FAILED')) 'Invalid launch path did not fail safely'
    Assert-Scan ([IO.File]::ReadAllText($catalog) -eq $published) 'Failed refresh changed the active catalog'
    foreach ($path in $hashes.Keys) { Assert-Scan ((Get-FileHash -LiteralPath $path).Hash -eq $hashes[$path]) 'Failed refresh overwrote a live icon' }
    Assert-Scan (@(Get-ChildItem -LiteralPath $iconRoot -Directory).Count -eq 1) 'Failed scan left a partial icon generation'

    $lock = [IO.File]::Open((Join-Path $resources 'Cache\AppScan.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $result = & $powershell -NoProfile -ExecutionPolicy Bypass -File $scanner
        Assert-Scan ($LASTEXITCODE -ne 0 -and ($result -join ' ').Contains('APPS:FAILED')) 'Concurrent scanner bypassed the publication lock'
    } finally { $lock.Dispose() }
    Assert-Scan ([IO.File]::ReadAllText($catalog) -eq $published) 'Concurrent scanner changed the catalog'
    Write-Output 'PASS: Fallback icon publication, previous-catalog backup, failed-scan icon/catalog rollback, partial-generation cleanup and exclusive scan lock'
} finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    $testRoot = [IO.Path]::GetFullPath($PSScriptRoot)
    if ([IO.Path]::GetDirectoryName($resolved) -eq $testRoot -and [IO.Path]::GetFileName($resolved) -like '.scratch-app-scan-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
