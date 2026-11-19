# Fixture-only scanner and launch tests: no registry discovery, network requests, or games are launched.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root '@Resources\ScanGames.ps1') -LibraryOnly
. (Join-Path $root '@Resources\LaunchGame.ps1') -LibraryOnly
$scratch = Join-Path $PSScriptRoot ('.scratch-scanner-' + [Guid]::NewGuid().ToString('N'))

function Assert-Game($condition, [string]$message) { if (-not $condition) { throw $message } }
function Write-Fixture([string]$path, [string]$text='') {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}
function Move-FixtureDirectory([string]$from, [string]$to) {
    foreach ($path in @($from,$to)) {
        Assert-Game ([IO.Path]::GetFullPath($path).StartsWith([IO.Path]::GetFullPath($scratch) + '\', [StringComparison]::OrdinalIgnoreCase)) 'Move outside fixture root'
    }
    [IO.Directory]::Move($from,$to)
}
function Start-Process {
    [CmdletBinding()]
    param([string]$FilePath, [string]$WorkingDirectory, [string]$ArgumentList)
    $script:launched = @{ Path=$FilePath; WorkingDirectory=$WorkingDirectory; Arguments=$ArgumentList }
}

try {
    foreach ($scriptName in @('ScanGames.ps1','LaunchGame.ps1')) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root ('@Resources\' + $scriptName)) -LibraryOnly
        Assert-Game ($LASTEXITCODE -eq 0) ('Windows PowerShell default-path initialization failed: ' + $scriptName)
    }
    $resources = Join-Path $scratch '@Resources'
    $gamesDir = Join-Path $scratch 'Games'
    $standalone = Join-Path $scratch 'Installed'
    $steam = Join-Path $scratch 'Steam'
    $hoyo = Join-Path $scratch 'HoYoPlay\games'
    foreach ($path in @($resources,$gamesDir,$standalone,$hoyo)) { [void][IO.Directory]::CreateDirectory($path) }
    Write-Fixture (Join-Path $steam 'steamapps\common\Example\readme.txt')
    $manifest = Join-Path $steam 'steamapps\appmanifest_123.acf'
    Write-Fixture $manifest '"AppState" { "appid" "123" "name" "Steam Example" "installdir" "Example" }'
    Write-Fixture (Join-Path $standalone 'Shortcut\readme.txt')
    Write-Fixture (Join-Path $standalone 'Hidden\Launcher.ini') 'not valid metadata'
    Write-Fixture (Join-Path $standalone 'Runner\Runner.exe')
    Write-Fixture (Join-Path $standalone 'Runner\Service.bat') 'sc.exe start ExampleService'
    Write-Fixture (Join-Path $hoyo 'Star Rail Games\AHelper.exe')
    Write-Fixture (Join-Path $hoyo 'Star Rail Games\StarRail.exe')
    $overrideFile = Join-Path $gamesDir 'Overrides.txt'
    Write-Fixture $overrideFile "Shortcut | Shortcut title | OTHER | example://play`nHidden | | HIDE |`nRunner | Runner | ACTION | | --profile `"My Profile`" | ."
    $envFixture = [PSCustomObject]@{ GamesRoot=$standalone; Warnings=@(); Platforms=@(); Sources=@(
        [PSCustomObject]@{Kind='steam';Path=$steam;Optional=$false},
        [PSCustomObject]@{Kind='standalone';Path=$standalone;Optional=$false},
        [PSCustomObject]@{Kind='hoyo';Path=$hoyo;Optional=$false}) }
    $catalogPath = Join-Path $resources 'Cache\game_library.json'
    $include = Join-Path $gamesDir 'GameList.inc'
    $statusPath = Join-Path $resources 'Cache\game_scan_status.txt'
    $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
    Assert-Game ($scan.Published -and $scan.Games.Count -eq 4) ('Initial fixture scan failed: ' + $scan.Summary)
    $shortcut = @($scan.Games | Where-Object Title -eq 'Shortcut title')[0]
    Assert-Game ($shortcut.Path -eq 'example://play') 'Override-only game not discovered'
    $runner = @($scan.Games | Where-Object Title -eq 'Runner')[0]
    Assert-Game ($runner.Path.EndsWith('\Runner.exe') -and $runner.Arguments -eq '--profile "My Profile"') 'Launch selection or override arguments wrong'
    Assert-Game ($runner.WorkingDirectory -eq (Join-Path $standalone 'Runner')) 'Relative working directory not resolved'
    Assert-Game (@($scan.Games | Where-Object Id -eq 'hoyo:starrail')[0].Path.EndsWith('\StarRail.exe')) 'HoYoPlay helper selected instead of known binary'
    $published = [IO.File]::ReadAllText($include)
    Assert-Game ($published -match 'GameId=steam:123') 'Generated library lost stable identity'
    Assert-Game ($published -notmatch '(?m)^\[Meter') 'GameList.inc should emit data-only [Variables] without [Meter...] sections'
    $iconManifest = Join-Path $resources 'Cache\GameIcons.inc'
    $iconText = [IO.File]::ReadAllText($iconManifest)
    Assert-Game ($iconText -match '(?m)^GameIconsteam123=.+\.png') 'Tile icon mapping lost stable identity'
    $fallbackIcon = Join-Path $resources 'Cache\GameIcons\fallback.png'
    $png = [IO.File]::ReadAllBytes($fallbackIcon)
    Assert-Game ($png.Length -gt 8 -and $png[0] -eq 137 -and $png[1] -eq 80) 'Unavailable icons have no valid PNG fallback'
    $lockedIcons = [IO.File]::Open($iconManifest,'Open','Read','Read')
    try {
        $iconScan = Invoke-GameScan $scratch $envFixture -NoNetwork
        Assert-Game $iconScan.Published 'Optional icon publication blocked the game library'
        Assert-Game ([IO.File]::ReadAllText($iconManifest) -eq $iconText) 'Failed icon update lost the previous mapping'
        Assert-Game (-not [IO.File]::Exists($iconManifest+'.tmp')) 'Failed icon publication leaked a temporary file'
    } finally { $lockedIcons.Dispose() }
    Write-Output 'PASS: Stable icon identities, PNG fallback, optional-cache rollback and temporary-file cleanup'
    $notInstalled = Join-Path $steam 'steamapps\appmanifest_456.acf'
    Write-Fixture $notInstalled '"AppState" { "appid" "456" "name" "Not installed" "installdir" "Missing" }'
    $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
    Assert-Game ($scan.Games.Count -eq 4) 'Stale Steam manifest was treated as installed'
    [IO.File]::Delete($notInstalled)
    $envFixture | Add-Member -NotePropertyName ExcludedRoots -NotePropertyValue @($steam) -Force
    $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
    Assert-Game ($scan.Published -and $scan.State -eq 'Success' -and $scan.Games.Count -eq 3) 'Excluded cached source still generated a warning or games'
    Assert-Game (@($scan.Sources | Where-Object Kind -eq 'steam').Count -eq 0) 'Excluded source resurrected from snapshot'
    Assert-Game (-not (Test-ExcludedGameSource ($steam + '-other') @($steam))) 'Source exclusion ignored path boundaries'
    $envFixture.ExcludedRoots = @()
    $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
    Assert-Game ($scan.Games.Count -eq 4) 'Removing an exclusion did not rediscover the source'
    Write-Output 'PASS: Source exclusions apply to saved/discovered libraries and allow rediscovery when removed'
    $first = $runner | Select-Object *
    $second = $runner | Select-Object *
    $second.Id = 'folder:' + ('a' * 64)
    $sameTitles = @(Merge-GameSources @() @([PSCustomObject]@{Source=$runner.Source;State='Success';Games=@($first,$second)}))
    Assert-Game ($sameTitles.Count -eq 2) 'Distinct installations were deduplicated by display title'
    Assert-Game ((ConvertTo-MeterText "Game [Edition] #1`n[Injected]") -notmatch '[\[\]#\r\n]') 'Title can inject Rainmeter options or references'
    Write-Output 'PASS: Override-only targets, hidden folders, arguments/cwd, known HoYoPlay binaries, generated IDs'

    # Deterministic fallback and uncertain matches; generic service scripts must not win.
    $ambiguous = Join-Path $scratch 'Ambiguous'
    Write-Fixture (Join-Path $ambiguous 'Zulu.exe')
    Write-Fixture (Join-Path $ambiguous 'Alpha.exe')
    Write-Fixture (Join-Path $ambiguous 'Service.bat') 'sc.exe start Whatever'
    $target = Find-GameTarget (Get-Item -LiteralPath $ambiguous) 'Unrelated'
    Assert-Game ($target.Path.EndsWith('\Alpha.exe') -and $target.Confidence -eq 'uncertain') 'Ambiguous target was not deterministic and marked uncertain'
    Write-Fixture (Join-Path $ambiguous 'HVG.bat') 'open help guide'
    Write-Fixture (Join-Path $ambiguous 'Launcher.ini') "Button.Launch=<APP_PATH>\HVG.bat`nButton.Launch=<APP_PATH>\Zulu.exe"
    $target = Find-GameTarget (Get-Item -LiteralPath $ambiguous) 'Unrelated'
    Assert-Game ($target.Path.EndsWith('\Zulu.exe') -and $target.Confidence -eq 'metadata') 'Explicit launcher metadata did not outrank guesses'

    # A new target retains the folder ID and previous launch path for favorite migration.
    Write-Fixture (Join-Path $standalone 'Runner\NewRunner.exe')
    Add-Content -LiteralPath $overrideFile -Value "`n" # Rewrite the existing rule, preserving argument quoting.
    Write-Fixture $overrideFile "Shortcut | Shortcut title | OTHER | example://play`nHidden | | HIDE |`nRunner | Runner | ACTION | NewRunner.exe | --profile `"My Profile`" | ."
    $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
    $updated = @($scan.Games | Where-Object Title -eq 'Runner')[0]
    Assert-Game ($updated.Id -eq $runner.Id -and $updated.Aliases -contains $runner.Path) 'Target change lost game ID or migration alias'
    $published = Get-Content -LiteralPath $include -Raw
    $revision = Get-GameLibraryRevision $published
    $snapshot = Get-Content -LiteralPath $catalogPath -Raw
    $staged = $snapshot | ConvertFrom-Json
    $staged.Revision = [Guid]::NewGuid().ToString('N')
    ($staged.Games | Where-Object Id -eq $updated.Id).Path = $runner.Path
    $staged.Games = @($staged.Games | Where-Object Id -ne 'steam:123')
    Write-Fixture $catalogPath ($staged | ConvertTo-Json -Depth 8)
    Start-CatalogGame $catalogPath $updated.Id -Revision $revision
    Assert-Game ($launched.Path -eq $updated.Path) 'Launch consumed an unpublished catalog'
    $script:launched = $null
    $stale = $false
    try { Start-CatalogGame $catalogPath $updated.Id -Revision $staged.Revision }
    catch { $stale = $_.Exception.Message -eq 'GAMEHUB:STALE' }
    Assert-Game ($stale -and -not $launched) 'Stale tile dispatched a target'
    Move-FixtureDirectory $steam ($steam + '.offline')
    try {
        $recovered = Invoke-GameScan $scratch $envFixture -NoNetwork
        $offline = $recovered.Games | Where-Object Id -eq 'steam:123'
        Assert-Game ($recovered.Published -and $offline -and -not $offline.Available) 'Rescan used the unpublished catalog as its baseline'
    } finally { Move-FixtureDirectory ($steam + '.offline') $steam }
    $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
    $script:launched = $null
    Start-CatalogGame $catalogPath $updated.Id
    Assert-Game ($launched.Path -eq $updated.Path -and $launched.Arguments -eq '--profile "My Profile"' -and $launched.WorkingDirectory -eq $updated.WorkingDirectory) 'Launcher did not preserve target/cwd/arguments'
    Start-CatalogGame $catalogPath $updated.Id -OpenFolder
    Assert-Game ($launched.Path -eq $updated.Folder -and -not $launched.Arguments) 'Open folder dispatched the game or its arguments'
    Start-CatalogGame $catalogPath $shortcut.Id
    Assert-Game ($launched.Path -eq 'example://play') 'Protocol launch failed'
    [IO.File]::Delete($catalogPath)
    Start-CatalogGame $catalogPath $updated.Id
    Assert-Game ($launched.Path -eq $updated.Path -and $launched.Arguments -eq $updated.Arguments -and $launched.WorkingDirectory -eq $updated.WorkingDirectory) 'Cache-free launch lost target/arguments/cwd'
    Start-CatalogGame $catalogPath $updated.Id -OpenFolder
    Assert-Game ($launched.Path -eq $updated.Folder) 'Cache-free folder action lost the installation location'
    $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
    Assert-Game ($scan.Published -and $scan.Games.Count -eq 4 -and @($scan.Games | Where-Object Id -eq $updated.Id)[0].Aliases -contains $runner.Path) 'Cache-free rescan lost library data'
    Write-Output 'PASS: Deterministic uncertain targets, metadata preference, stable IDs/aliases, launch arguments/cwd, cache-free recovery'

    # Disconnection preserves entries as unavailable; source removal after a successful read is real removal.
    Move-FixtureDirectory $steam ($steam + '.offline')
    $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
    Assert-Game ($scan.Published -and $scan.State -eq 'Warning' -and $scan.Games.Count -eq 4) 'Disconnected library erased entries'
    Assert-Game (-not @($scan.Games | Where-Object Id -eq 'steam:123')[0].Available) 'Disconnected game remained launchable'
    $blocked = $false
    try { Start-CatalogGame $catalogPath 'steam:123' } catch { $blocked = $true }
    Assert-Game $blocked 'Offline launch was not blocked'
    Move-FixtureDirectory ($steam + '.offline') $steam
    Write-Fixture (Join-Path $steam 'steamapps\appmanifest_999.acf') 'invalid manifest'
    $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
    Assert-Game ($scan.Games.Count -eq 4 -and -not @($scan.Games | Where-Object Id -eq 'steam:123')[0].Available) 'Malformed source published partial results'
    [IO.File]::Delete((Join-Path $steam 'steamapps\appmanifest_999.acf'))
    [IO.File]::Delete($manifest)
    $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
    Assert-Game ($scan.Published -and $scan.Games.Count -eq 3) 'Successful empty source did not remove missing games'
    Write-Output 'PASS: Missing drives, offline launch blocking, malformed sources, successful empty source reconciliation'

    $before = [IO.File]::ReadAllText($include)
    $catalogBefore = [IO.File]::ReadAllText($catalogPath)
    $statusBefore = [IO.File]::ReadAllText($statusPath)
    $lock = [IO.File]::Open((Join-Path $resources 'Cache\game_scan.lock'),'OpenOrCreate','ReadWrite','None')
    try {
        $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
        Assert-Game ($scan.State -eq 'Busy' -and [IO.File]::ReadAllText($statusPath) -eq $statusBefore) 'Concurrent scan modified scan state'
    } finally { $lock.Dispose() }
    $lockedInclude = [IO.File]::Open($include,'Open','Read','Read')
    try {
        $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
        Assert-Game (-not $scan.Published -and $scan.State -eq 'Failed') 'Locked include was reported as successful'
        Assert-Game ([IO.File]::ReadAllText($catalogPath) -eq $catalogBefore) 'Failed publication changed catalog'
        Assert-Game ([IO.File]::ReadAllText($include) -eq $before) 'Failed publication changed previous meters'
    } finally { $lockedInclude.Dispose() }
    Assert-Game (@(Get-ChildItem -LiteralPath $scratch -Filter '*.tmp' -Recurse).Count -eq 0) 'Temporary publication files leaked'
    Write-Fixture $catalogPath '{bad json'
    $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
    Assert-Game ($scan.State -eq 'Failed' -and [IO.File]::ReadAllText($include) -eq $before) 'Corrupt snapshot overwrote library'
    Write-Fixture $catalogPath $catalogBefore
    Write-Fixture $overrideFile 'Runner | Runner | INVALID |'
    $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
    Assert-Game ($scan.State -eq 'Failed' -and [IO.File]::ReadAllText($include) -eq $before) 'Invalid override overwrote library'
    Write-Output 'PASS: Concurrent scan lock, failed-write rollback, temporary-file cleanup, corrupt snapshot/override preservation'

    $legacyFile = Join-Path $scratch 'Legacy.inc'
    $legacyPath = Join-Path $standalone 'Runner\Runner.exe'
    Write-Fixture $legacyFile "[Variables]`nGameCardH=324`n[MeterAction1]`nText=[\x25B8] Runner`nLeftMouseUpAction=[`"$legacyPath`"]`n[MeterRPG1]`nText=[\x25B8] Steam Example`nLeftMouseUpAction=[`"steam://rungameid/123`"]"
    $legacy = @(Read-LegacyLibrary $legacyFile $standalone)
    Assert-Game ($legacy.Count -eq 2 -and @($legacy | Where-Object Title -eq 'Runner')[0].Id -eq $runner.Id) 'Legacy include migration lost folder identity'
    Assert-Game (@($legacy | Where-Object Id -eq 'steam:123').Count -eq 1) 'Legacy Steam ID migration failed'
    Write-Output 'PASS: Legacy generated-library identity migration'

    # Additional roots and Epic installs use the same source reconciliation and launch pipeline.
    $secondRoot = Join-Path $scratch 'Other Games'
    Write-Fixture (Join-Path $secondRoot 'Second\Second.exe')
    $configured = @(Get-ConfiguredGameRoots $standalone ($secondRoot + '|' + $standalone + '\'))
    Assert-Game ($configured.Count -eq 2) 'Additional roots were not parsed/deduplicated'
    Assert-Game (@(Get-ConfiguredGameRoots 'E:\' '')[0] -eq 'E:\') 'Drive root became a drive-relative path'
    $epicManifests = Join-Path $scratch 'Epic\Manifests'
    $epicInstall = Join-Path $scratch 'Epic\Installed'
    Write-Fixture (Join-Path $epicInstall 'EpicExample.exe')
    $epicManifest = Join-Path $epicManifests 'example.item'
    $epicItem = @{ DisplayName='Epic Example'; AppName='Example App'; CatalogNamespace='sandbox'; CatalogItemId='item';
        InstallLocation=$epicInstall; bIsApplication=$true; bIsIncompleteInstall=$false }
    Write-Fixture $epicManifest ($epicItem | ConvertTo-Json)
    $expansionEnv = [PSCustomObject]@{ GamesRoot=$standalone; Platforms=@(); Warnings=@(); ExcludedRoots=@(); Sources=@(
        [PSCustomObject]@{Kind='standalone';Path=$secondRoot;Optional=$false},
        [PSCustomObject]@{Kind='epic';Path=$epicManifests;Optional=$false}) }
    Write-Fixture $overrideFile ''
    $expanded = Invoke-GameScan $scratch $expansionEnv -NoNetwork
    $epicGame = @($expanded.Games | Where-Object Title -eq 'Epic Example')[0]
    Assert-Game ($expanded.Published -and $epicGame.Id -like 'epic:*') 'Epic manifest did not produce a stable game entry'
    Assert-Game ($epicGame.Path -eq 'com.epicgames.launcher://apps/sandbox%3Aitem%3AExample%20App?action=launch&silent=true') 'Epic launch identity was not encoded correctly'
    Assert-Game (@($expanded.Games | Where-Object Title -eq 'Second').Count -eq 1) 'Additional standalone root was not scanned'
    Start-CatalogGame $catalogPath $epicGame.Id
    Assert-Game ($launched.Path -eq $epicGame.Path) 'Epic game was not launched through its platform URI'
    $epicItem.bIsIncompleteInstall = $true
    Write-Fixture $epicManifest ($epicItem | ConvertTo-Json)
    $expanded = Invoke-GameScan $scratch $expansionEnv -NoNetwork
    Assert-Game (@($expanded.Games | Where-Object Id -eq $epicGame.Id).Count -eq 0) 'Incomplete Epic install was included'
    $epicItem.bIsIncompleteInstall = $false
    Write-Fixture $epicManifest ($epicItem | ConvertTo-Json)
    $expanded = Invoke-GameScan $scratch $expansionEnv -NoNetwork
    Write-Fixture $epicManifest '{bad json'
    $expanded = Invoke-GameScan $scratch $expansionEnv -NoNetwork
    Assert-Game (@($expanded.Games | Where-Object Id -eq $epicGame.Id).Count -eq 1 -and
        -not @($expanded.Games | Where-Object Id -eq $epicGame.Id)[0].Available) 'Malformed Epic source erased or kept launching cached games'
    # Restore the original fixture snapshot for the final publication/deadline assertion.
    Write-Fixture $catalogPath $catalogBefore
    Write-Fixture $include $before
    Write-Output 'PASS: Multiple game roots, Epic manifest IDs/URIs, incomplete installs and malformed-source preservation'

    # Desktop\Games discovery (.lnk/.url, deduplication against Steam/standalone, overrides/hiding, launch, icons)
    Write-Fixture $manifest '"AppState" { "appid" "123" "name" "Steam Example" "installdir" "Example" }'
    $desktopGames = Join-Path $scratch 'Desktop\Games'
    $externalGames = Join-Path $scratch 'ExternalGames\SpaceGame'
    $externalExe = Join-Path $externalGames 'SpaceGame.exe'
    Write-Fixture $externalExe
    [void][IO.Directory]::CreateDirectory($desktopGames)

    function New-TestShortcut([string]$lnkPath, [string]$target, [string]$workDir='', [string]$arguments='') {
        $wsh = New-Object -ComObject WScript.Shell
        $lnk = $wsh.CreateShortcut($lnkPath)
        $lnk.TargetPath = $target
        if ($workDir) { $lnk.WorkingDirectory = $workDir }
        if ($arguments) { $lnk.Arguments = $arguments }
        $lnk.Save()
    }

    $spaceLnk = Join-Path $desktopGames 'SpaceGame.lnk'
    New-TestShortcut $spaceLnk $externalExe $externalGames

    $steamUrl = Join-Path $desktopGames 'Steam Example.url'
    Write-Fixture $steamUrl "[InternetShortcut]`r`nURL=steam://rungameid/123"

    $uncatalogedUrl = Join-Path $desktopGames 'Uncataloged Steam.url'
    Write-Fixture $uncatalogedUrl "[InternetShortcut]`r`nURL=steam://rungameid/777"

    $runnerLnk = Join-Path $desktopGames 'Runner.lnk'
    Write-Fixture (Join-Path $standalone 'Runner\Launcher.ini') 'Button.Launch=<APP_PATH>\NewRunner.exe'
    New-TestShortcut $runnerLnk (Join-Path $standalone 'Runner\Runner.exe') (Join-Path $standalone 'Runner')
    $matchingLnk = Join-Path $desktopGames 'Runner exact.lnk'
    New-TestShortcut $matchingLnk $updated.Path (Join-Path $standalone 'Runner')
    $profileLnk = Join-Path $desktopGames 'Runner profile.lnk'
    New-TestShortcut $profileLnk $updated.Path (Join-Path $standalone 'Runner') '--profile Alternate'
    Write-Fixture (Join-Path $externalGames 'Runner.exe')
    New-TestShortcut (Join-Path $desktopGames 'Runner (external).lnk') (Join-Path $externalGames 'Runner.exe')
    Write-Fixture (Join-Path $desktopGames 'Epic Example.url') "[InternetShortcut]`r`nURL=com.epicgames.launcher://apps/sandbox%3Aitem%3AExample%20App?action=launch&silent=true"
    Write-Fixture (Join-Path $desktopGames 'Epic Shortcut Only.url') "[InternetShortcut]`r`nURL=com.epicgames.launcher://apps/namespace%3Aitem%3AShortcut?action=launch&silent=true"
    Write-Fixture (Join-Path $standalone 'Simple Plan\Simple Plan.exe')

    $customExe = Join-Path $scratch 'Custom\Custom.exe'
    Write-Fixture $customExe
    $customLnk = Join-Path $desktopGames 'MyCustomGame.lnk'
    New-TestShortcut $customLnk $customExe
    $hiddenLnk = Join-Path $desktopGames 'SecretGame.lnk'
    New-TestShortcut $hiddenLnk $customExe
    $brokenLnk = Join-Path $desktopGames 'BrokenGame.lnk'
    New-TestShortcut $brokenLnk (Join-Path $scratch 'MissingFolder\Missing.exe')

    $steamPlatformLnk = Join-Path $desktopGames 'Steam.lnk'
    New-TestShortcut $steamPlatformLnk (Join-Path $steam 'Steam.exe') $steam

    $epicPlatformLnk = Join-Path $desktopGames 'Epic Games Launcher.lnk'
    New-TestShortcut $epicPlatformLnk (Join-Path $scratch 'Epic\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe')

    $hoyoPlatformLnk = Join-Path $desktopGames 'HoYoPlay.lnk'
    New-TestShortcut $hoyoPlatformLnk (Join-Path $standalone 'HoYoPlay\launcher.exe')

    $xxmiPlatformLnk = Join-Path $desktopGames 'XXMI Launcher.lnk'
    New-TestShortcut $xxmiPlatformLnk (Join-Path $scratch 'XXMI\XXMI Launcher.exe')

    Write-Fixture $overrideFile "MyCustomGame | Renamed RPG | RPG |`nSecretGame | | HIDE |"
    Write-Fixture $epicManifest ($epicItem | ConvertTo-Json)

    $desktopEnv = [PSCustomObject]@{
        GamesRoot = $standalone
        Warnings = @()
        Platforms = @(
            [PSCustomObject]@{ Title='Steam'; Path='steam://open/main' },
            [PSCustomObject]@{ Title='Epic Games'; Path='com.epicgames.launcher://' },
            [PSCustomObject]@{ Title='HoYoPlay'; Path=(Join-Path $standalone 'HoYoPlay\launcher.exe') },
            [PSCustomObject]@{ Title='XXMI Launcher'; Path=(Join-Path $scratch 'XXMI\XXMI Launcher.exe') }
        )
        ExcludedRoots = @()
        Sources = @(
            [PSCustomObject]@{ Kind='steam'; Path=$steam; Optional=$false },
            [PSCustomObject]@{ Kind='standalone'; Path=$standalone; Optional=$false },
            [PSCustomObject]@{ Kind='hoyo'; Path=$hoyo; Optional=$false },
            [PSCustomObject]@{ Kind='epic'; Path=$epicManifests; Optional=$false },
            [PSCustomObject]@{ Kind='desktop'; Path=$desktopGames; Optional=$true }
        )
    }

    $desktopScan = Invoke-GameScan $scratch $desktopEnv -NoNetwork
    # Real-world duplicate shapes: launcher metadata plus a renamed shortcut, and Epic-only Fortnite.
    $aceFolder = Join-Path $standalone 'Ace Fixture'
    Write-Fixture (Join-Path $aceFolder 'Launcher.exe')
    Write-Fixture (Join-Path $aceFolder 'Play.bat')
    Write-Fixture (Join-Path $aceFolder 'Launcher.ini') 'Button.Launch=<APP_PATH>\Play.bat'
    New-TestShortcut (Join-Path $desktopGames 'Ace Fixture.lnk') (Join-Path $aceFolder 'Launcher.exe') ($aceFolder + '\')
    Add-Content -LiteralPath $overrideFile -Value "`nAce Fixture | Ace Display | ACTION |"
    Write-Fixture (Join-Path $standalone 'Fortnite\FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe')
    Write-Fixture (Join-Path $desktopGames 'Fortnite.url') "[InternetShortcut]`nURL=com.epicgames.launcher://apps/fn%3Aitem%3AFortnite?action=launch&silent=true"
    $fixtureIcon=Join-Path $aceFolder 'icon.ico'
    $iconStream=[IO.File]::Create($fixtureIcon)
    try { [Drawing.SystemIcons]::Information.Save($iconStream) } finally { $iconStream.Dispose() }
    Add-Content -LiteralPath (Join-Path $desktopGames 'Fortnite.url') -Value "`nIconFile=$fixtureIcon"
    Write-Fixture (Join-Path $desktopGames 'Removed Steam.url') "[InternetShortcut]`nURL=steam://rungameid/9999`nIconFile=$scratch\Removed\game.exe"
    # A moved icon must not override an authoritative installed Steam record.
    Add-Content -LiteralPath $steamUrl -Value "`nIconFile=$scratch\OldLocation\game.exe"
    $desktopScan = Invoke-GameScan $scratch $desktopEnv -NoNetwork
    $ace = @($desktopScan.Games | Where-Object Title -eq 'Ace Display')
    Assert-Game (@($desktopScan.Games | Where-Object Id -eq 'steam:9999').Count -eq 0) 'Deleted Steam game survived through a leftover shortcut'
    Assert-Game ($ace.Count -eq 1 -and $ace[0].Path -eq (Join-Path $aceFolder 'Play.bat')) 'Metadata launcher and renamed shortcut duplicated'
    $fortnite = @($desktopScan.Games | Where-Object Title -eq 'Fortnite')
    Assert-Game ($fortnite.Count -eq 1 -and $fortnite[0].Path -like 'com.epicgames.launcher://*' -and
        $fortnite[0].Folder -eq (Join-Path $standalone 'Fortnite')) 'Fortnite bypassed Epic or duplicated its installation'
    $iconMappings=[IO.File]::ReadAllText($iconManifest)
    foreach ($game in @($ace[0],$fortnite[0])) {
        $iconKey='GameIcon'+($game.Id -creplace '[^A-Za-z0-9]','')
        Assert-Game ($iconMappings -match ("(?m)^"+$iconKey+'=(.+)')) 'Game icon mapping missing'
        Assert-Game ($Matches[1].Trim() -notlike '*fallback.png') 'Local/merged shortcut artwork fell back to generic icon'
    }
    Start-CatalogGame $catalogPath $fortnite[0].Id
    Assert-Game ($launched.Path -eq $fortnite[0].Path) 'Fortnite dispatch did not use Epic'
    Assert-Game ($desktopScan.Published -and $desktopScan.State -eq 'Warning') 'Desktop scan failed or missed unavailable broken shortcut'

    # 1. External .lnk shortcut discovery, folder resolution, launch, and icon
    $space = @($desktopScan.Games | Where-Object Title -eq 'SpaceGame')[0]
    Assert-Game ($space -and $space.Id -like 'shortcut:*') 'External .lnk shortcut game was not discovered with shortcut ID'
    Assert-Game ($space.Path -eq $spaceLnk) 'Launch path was not the .lnk file'
    Assert-Game ($space.Folder -eq $externalGames) 'Folder was not resolved to target parent directory'
    Assert-Game ($space.Available) 'Valid shortcut was marked unavailable'

    $script:launched = $null
    Start-CatalogGame $catalogPath $space.Id
    Assert-Game ($launched.Path -eq $spaceLnk -and -not $launched.WorkingDirectory) 'Shortcut launch did not preserve target path'
    Start-CatalogGame $catalogPath $space.Id -OpenFolder
    Assert-Game ($launched.Path -eq $externalGames) 'OpenFolder on shortcut game did not open the target directory'

    $iconText = [IO.File]::ReadAllText($iconManifest)
    $cleanSpaceId = 'GameIcon' + ($space.Id -creplace '[^A-Za-z0-9]','')
    Assert-Game ($iconText -match "(?m)^$cleanSpaceId=.+\.png") 'Tile icon mapping was not generated for shortcut game'

    # 2. .url steam shortcut deduplication against existing steam game
    Assert-Game (@($desktopScan.Games | Where-Object Title -eq 'Steam Example').Count -eq 1) 'Duplicate tile created for installed Steam game'
    $steamGame = @($desktopScan.Games | Where-Object Id -eq 'steam:123')[0]
    Assert-Game ($steamGame.Aliases -contains $steamUrl) 'Shortcut path was not merged into Steam game aliases'
    Assert-Game ($steamGame.Confidence -ne 'shortcut') 'Steam library installation was overridden by shortcut confidence'

    # 3. Uncataloged .url steam shortcut discovery
    $steam777 = @($desktopScan.Games | Where-Object Id -eq 'steam:777')[0]
    Assert-Game ($steam777 -and $steam777.Path -eq 'steam://rungameid/777' -and $steam777.Available) 'Uncataloged Steam game was not discovered from .url'

    # 4. Merge only matching launch behavior and keep similarly named installs.
    Assert-Game (@($desktopScan.Games | Where-Object Title -eq 'Runner').Count -eq 3) 'Distinct targets with the same title were merged'
    $runnerGame = $desktopScan.Games | Where-Object Id -eq $updated.Id
    Assert-Game ($runnerGame.Aliases -contains $matchingLnk -and $runnerGame.Aliases -notcontains $runnerLnk) 'Standalone merge ignored executable identity'
    Assert-Game (@($desktopScan.Games | Where-Object Path -eq $profileLnk).Count -eq 1) 'Shortcut launch arguments were lost through deduplication'
    $epicEntries = @($desktopScan.Games | Where-Object Title -eq 'Epic Example')
    Assert-Game ($epicEntries.Count -eq 1 -and $epicEntries[0].Id -eq $epicGame.Id -and
        $epicEntries[0].Aliases -contains (Join-Path $desktopGames 'Epic Example.url')) 'Epic shortcut did not merge by platform identity'
    Assert-Game (@($desktopScan.Games | Where-Object Title -eq 'Epic Shortcut Only').Count -eq 1) 'Uncataloged Epic game URL was filtered out'
    $fixtureJson = (Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json).Games
    $fixtureInclude = @(Read-GeneratedGames $include)
    Assert-Game (($fixtureJson | Where-Object Title -eq 'Simple Plan').Category -eq 'OTHER') 'Substring category false positive'
    foreach ($game in $fixtureJson) {
        Assert-Game (($fixtureInclude | Where-Object Id -eq $game.Id).Category -eq $game.Category) 'Published category disagrees with JSON'
    }

    # 5. Overrides.txt renaming, category, and hiding
    $renamed = @($desktopScan.Games | Where-Object Title -eq 'Renamed RPG')[0]
    Assert-Game ($renamed -and $renamed.Category -eq 'RPG') 'Override renaming or category on shortcut failed'
    Assert-Game (@($desktopScan.Games | Where-Object Title -match 'SecretGame').Count -eq 0) 'Shortcut with HIDE override was not hidden'

    # 6. Broken shortcut marks game unavailable
    $broken = @($desktopScan.Games | Where-Object Title -eq 'BrokenGame')[0]
    Assert-Game ($broken -and -not $broken.Available) 'Broken shortcut was not marked unavailable'
    $launchFailed = $false
    try { Start-CatalogGame $catalogPath $broken.Id } catch { $launchFailed = $true }
    Assert-Game $launchFailed 'Broken shortcut launch was not blocked'

    # 7. Platform shortcuts in Desktop\Games are excluded from $scan.Games and do not duplicate Platforms
    Assert-Game (@($desktopScan.Games | Where-Object Title -eq 'Epic Games Launcher').Count -eq 0) 'Epic Games Launcher shortcut was not excluded from games'
    Assert-Game (@($desktopScan.Games | Where-Object Title -eq 'HoYoPlay').Count -eq 0) 'HoYoPlay launcher shortcut was not excluded from games'
    Assert-Game (@($desktopScan.Games | Where-Object Title -eq 'XXMI Launcher').Count -eq 0) 'XXMI Launcher shortcut was not excluded from games'
    $steamMatches = @($desktopScan.Games | Where-Object { $_.Title -eq 'Steam' -and $_.Confidence -eq 'shortcut' })
    Assert-Game ($steamMatches.Count -eq 0) 'Steam launcher shortcut appeared in games list'

    # 8. Verify Get-ScanEnvironment discovers Desktop\Games source and applies UserSettings.inc overlay
    $varsInc = Join-Path $resources 'Variables.inc'
    $userInc = Join-Path $resources 'UserSettings.inc'
    Write-Fixture $varsInc "GamesFolder=$standalone`r`nGamesFolders=`r`nGamesExcludedDrives=`r`n"
    $scannedEnv = Get-ScanEnvironment $resources
    Assert-Game (@($scannedEnv.Sources | Where-Object Kind -eq 'desktop').Count -eq 1) 'Get-ScanEnvironment did not register desktop source'
    $overrideGames = Join-Path $scratch 'OverrideGames'
    [void][IO.Directory]::CreateDirectory($overrideGames)
    Write-Fixture $userInc "[Variables]`r`nGamesFolder=$overrideGames`r`nGamesExcludedDrives=Z:`r`n"
    $overlaidEnv = Get-ScanEnvironment $resources
    Assert-Game ($overlaidEnv.GamesRoot -eq $overrideGames) 'UserSettings.inc did not override GamesFolder'
    Assert-Game ($overlaidEnv.ExcludedRoots -contains 'Z:\') 'UserSettings.inc did not override GamesExcludedDrives'
    Remove-Item -LiteralPath $userInc -Force

    Write-Output 'PASS: Desktop\Games .lnk/.url discovery, deduplication against Steam/standalone, overrides/hiding, launch, icons'

    # Restore the original fixture snapshot for the final publication/deadline assertion.
    Write-Fixture $catalogPath $catalogBefore
    Write-Fixture $include $before

    # A cooperative time-budget failure must never publish a partial discovery result.
    $assertTime = (Get-Item Function:Assert-ScanTime).ScriptBlock
    function Assert-ScanTime { throw 'Simulated scan deadline' }
    try {
        Write-Fixture $overrideFile ''
        $scan = Invoke-GameScan $scratch $envFixture -NoNetwork
        Assert-Game ($scan.State -eq 'Failed' -and [IO.File]::ReadAllText($include) -eq $before) 'Time-budget failure replaced the library'
    } finally { Set-Item Function:Assert-ScanTime $assertTime }
    Write-Output 'PASS: Stale manifest filtering, distinct-install IDs, escaped titles, deadline preservation'
}
finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    if ([IO.Path]::GetDirectoryName($resolved).Equals([IO.Path]::GetFullPath($PSScriptRoot),[StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved) -like '.scratch-scanner-*' -and [IO.Directory]::Exists($resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
