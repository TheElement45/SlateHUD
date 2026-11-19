$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) '@Resources\AppDiscovery.ps1')
$scratch = Join-Path $PSScriptRoot ('.scratch-app-discovery-' + [Guid]::NewGuid().ToString('N'))
function Assert-App($value,[string]$message) { if (-not $value) { throw $message } }
try {
    $desktop = Join-Path $scratch 'Desktop'
    $apps = Join-Path $desktop 'Apps'
    [IO.Directory]::CreateDirectory($apps) | Out-Null
    foreach ($name in 'Brave.lnk','Personal - Brave.lnk','Git Bash.lnk','Google Docs.lnk','Media Player Classic.lnk','Microsoft Edge.lnk','Sample.url','Ignore.exe') {
        [IO.File]::WriteAllText((Join-Path $apps $name),'test shortcut fixture')
    }
    foreach ($name in 'Unrelated.lnk','Git Bash.lnk') { [IO.File]::WriteAllText((Join-Path $desktop $name),'root fixture') }
    $links = Get-AppShortcutIndex -Folders @($desktop,$apps)
    Assert-App ($links['Git Bash'] -eq (Join-Path $apps 'Git Bash.lnk')) 'Apps folder did not take precedence'
    Assert-App (-not $links.ContainsKey('Ignore')) 'Executable was mistaken for a shortcut'
    $configured = @(
        [pscustomobject]@{Shortcut='Brave';Label='Browser';Category='Communication';Favorite='1';Secondary='Personal - Brave'},
        [pscustomobject]@{Shortcut='Google Docs';Label='Docs';Category='Development';Favorite='0';Secondary=''},
        [pscustomobject]@{Shortcut='Missing';Label='Missing';Category='Utilities';Favorite='0';Secondary=''}
    )
    $rows = @(Get-AppRows -Links $links -ConfiguredRows $configured -DiscoveryFolder $apps)
    Assert-App ($rows.Count -eq 6) 'Discovery count or duplicate exclusion failed'
    Assert-App ($rows[0].Label -eq 'Browser' -and $rows[0].Favorite -eq '1') 'Configured favorite/order changed'
    Assert-App ($rows[1].Label -eq 'Docs' -and $rows[1].Category -eq 'Development') 'Custom label/category ignored'
    Assert-App (@($rows | Where-Object Shortcut -eq 'Git Bash')[0].Category -eq 'Development') 'Git Bash classification failed'
    Assert-App (@($rows | Where-Object Shortcut -eq 'Media Player Classic')[0].Category -eq 'Creative') 'Media classification failed'
    Assert-App (@($rows | Where-Object Shortcut -eq 'Microsoft Edge')[0].Category -eq 'Communication') 'Browser classification failed'
    Assert-App (@($rows | Where-Object Shortcut -eq 'Sample')[0].Category -eq 'Utilities') 'Unknown shortcut fallback failed'
    Assert-App (@($rows | Where-Object Shortcut -in 'Personal - Brave','Missing','Unrelated').Count -eq 0) 'Profile, missing app, or unrelated desktop item was added'
    [IO.File]::WriteAllText((Join-Path $apps 'New App.lnk'),'added later')
    $links = Get-AppShortcutIndex -Folders @($desktop,$apps)
    $rows = @(Get-AppRows -Links $links -ConfiguredRows $configured -DiscoveryFolder $apps)
    Assert-App (@($rows | Where-Object Shortcut -eq 'New App').Count -eq 1) 'New shortcut was not discovered on refresh'
    Assert-App (@($rows | Where-Object Shortcut -eq 'New App')[0].Favorite -eq '0') 'New shortcut crowded the favorites grid'
    Assert-App (@(Get-AppCategories).Count -eq 6) 'Six-category validation list is incomplete'
    foreach ($name in 'CrystalDiskInfo','WizTree','MSI Afterburner','NVIDIA App','Revo Uninstaller','Windhawk','Superposition Benchmark') {
        Assert-App ((Get-AppCategory $name) -eq 'System') ('System classification failed: ' + $name)
    }
    foreach ($name in 'Google Docs','Google Sheets','Google Slides','Google Drive','Gemini','PDFgear') {
        Assert-App ((Get-AppCategory $name) -eq 'Productivity') ('Productivity classification failed: ' + $name)
    }
    $newOverrides = @(
        [pscustomobject]@{Shortcut='Git Bash';Label='System tool';Category='System';Favorite='0';Secondary=''},
        [pscustomobject]@{Shortcut='Google Docs';Label='Work';Category='Productivity';Favorite='0';Secondary=''}
    )
    $newRows = @(Get-AppRows -Links $links -ConfiguredRows $newOverrides -DiscoveryFolder $apps)
    Assert-App ($newRows[0].Category -eq 'System' -and $newRows[1].Category -eq 'Productivity') 'New configured categories were rejected or ignored'
    $stableKey = Get-AppShortcutKey 'New App'
    Assert-App ($stableKey -match '^[a-f0-9]{64}$') 'Shortcut preference key is not safe for persistence'
    Assert-App ($stableKey -eq (Get-AppShortcutKey 'NEW APP')) 'Preference key changed with shortcut casing'
    Assert-App ($stableKey -ne (Get-AppShortcutKey 'Another App')) 'Distinct apps share a preference key'
    $unsafe = Convert-IniText "Bad#ColorAccent#[Measure]`nLabel"
    Assert-App ($unsafe -notmatch '[#\[\]\r\n]') 'App label can become Rainmeter syntax'
    $rejected = $false
    try { $null = Get-LaunchAction 'C:\Apps\Bad#Name.lnk' } catch { $rejected = $true }
    Assert-App $rejected 'Unsupported launch path was accepted'
    $record = [pscustomobject]@{
        Id='App01';Key=$stableKey;Name='New App';Label='Long application name';Path='C:\Apps\New App.lnk'
        Category='Utilities';Favorite='0';SecondaryAction='["C:\Apps\Personal.lnk"]'
        Action=(Get-LaunchAction 'C:\Apps\New App.lnk');Icon='C:\Cache\generation\App01.png'
    }
    $catalog = New-AppCatalogText -Records @($record) -ShortcutFolder 'C:\Apps' -Warnings 1
    Assert-App ($catalog.Contains('App01Key=' + $stableKey)) 'Generated catalog lacks stable preference identity'
    Assert-App ($catalog.Contains('AppScanWarnings=1')) 'Fallback icon warnings were lost'
    Assert-App ($catalog.Contains('H=(28*#UiScale#)')) 'Two-line labels are not generated'
    Assert-App (([regex]::Matches($catalog,'RightMouseUpAction=\[!CommandMeasure MeasureApps "OpenMenu')).Count -eq 4) 'App hit areas do not share the native app menu'
    Assert-App ($catalog.Contains('[App01Profile]') -and $catalog.Contains('LaunchSecondary(')) 'Visible profile shortcut is missing'
    $skin = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'Apps\Apps.ini'))
    Assert-App ($skin -match '(?m)^ToolTipHidden=1\r?$') 'Native popup tooltips are still enabled for Apps'
    Assert-App ($skin -notmatch 'MouseLeaveAction=.*Render\(') 'A hover leave still triggers a full layout rebuild'
    $empty = New-AppCatalogText -Records @() -ShortcutFolder 'C:\Apps'
    Assert-App ($empty.Contains('AppCount=0')) 'Empty catalog cannot be published for setup guidance'
    Write-Output 'PASS: App discovery, overrides, stable identities, safe labels/actions, two-line labels, app menus, profile indicator and empty catalog'
} finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    $testRoot = [IO.Path]::GetFullPath($PSScriptRoot)
    if ([IO.Path]::GetDirectoryName($resolved) -eq $testRoot -and [IO.Path]::GetFileName($resolved) -like '.scratch-app-discovery-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
