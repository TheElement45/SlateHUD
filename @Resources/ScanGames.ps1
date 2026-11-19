# GameHub scanner: bounded discovery, source snapshots, and generated Rainmeter meters.
[CmdletBinding()]
param([switch]$LibraryOnly, [switch]$NoNetwork, [string]$RootDirectory = '')

if (-not $RootDirectory) { $RootDirectory = Split-Path -Parent $PSScriptRoot }

. (Join-Path $PSScriptRoot 'GameDiscovery.ps1')
. (Join-Path $PSScriptRoot 'GameIcons.ps1')

function Resolve-GameMetadataCategory($signals) {
    # Use the strongest signal per bucket, so overlapping synonyms do not add votes.
    # Store genres have equal weight; ties use the same priority for both providers.
    $scores = @{ RPG=0.0; STRATEGY=0.0; ACTION=0.0 }
    foreach ($signal in $signals) {
        $weight = 0.0
        if (-not [double]::TryParse([string]$signal.Weight, [ref]$weight) -or
            [double]::IsNaN($weight) -or [double]::IsInfinity($weight) -or $weight -le 0) { continue }
        $name = ([string]$signal.Name).Trim()
        $category = switch -Regex ($name) {
            '^(Adventure|JRPG|RPG|Action RPG|MMORPG|Party-Based RPG|CRPG|Visual Novel)$' { 'RPG'; break }
            '^(Strategy|Grand Strategy|4X|RTS|Turn-Based Strategy|Colony Sim|City Builder|Management|Base Building|Simulation|Wargame)$' { 'STRATEGY'; break }
            '^(Action|FPS|Shooter|Hero Shooter|Tactical Shooter|Third-Person Shooter|Combat Flight|Flight|Battle Royale|Arena Shooter|Hack and Slash|Fighting)$' { 'ACTION'; break }
        }
        if ($category -and $weight -gt $scores[$category]) { $scores[$category] = $weight }
    }
    $winner = ''; $best = 0.0
    foreach ($category in @('RPG','STRATEGY','ACTION')) {
        if ($scores[$category] -gt $best) { $winner = $category; $best = $scores[$category] }
    }
    return $winner
}

function Get-SteamCategory([string]$appId) {
    if (-not $appId) { return "" }
    $classifierVersion = 3
    $cached = $genreCache[$appId]
    $cachedCategory = if ($cached -is [string]) { $cached } else { $cached.Category }
    $lastKnown = if ($cachedCategory -in @('RPG', 'ACTION', 'STRATEGY')) { $cachedCategory } else { '' }
    $now = [DateTimeOffset]::UtcNow
    $expires = [DateTimeOffset]::MinValue
    if ($cached.Version -eq $classifierVersion -and
        [DateTimeOffset]::TryParse([string]$cached.ExpiresUtc, [ref]$expires) -and $expires -gt $now) {
        return $lastKnown
    }
    if ($scanNoNetwork -or (Get-Date) -gt $lookupDeadline) { return $lastKnown }

    $cat = ""
    $categorySource = ''
    $spySucceeded = $false
    $storeSucceeded = $false
    # 1. Try SteamSpy API first (fast community tags)
    try {
        $spy = Invoke-RestMethod -Uri "https://steamspy.com/api.php?request=appdetails&appid=$appId" -TimeoutSec 2 -ErrorAction Stop
        if ($spy -and $spy.tags -and $spy.tags.PSObject.Properties) {
            $spySucceeded = $true
            $signals = @($spy.tags.PSObject.Properties | ForEach-Object { [PSCustomObject]@{ Name=$_.Name; Weight=$_.Value } })
            $cat = Resolve-GameMetadataCategory $signals
            if ($cat) { $categorySource = 'SteamSpy' }
        }
    } catch {}

    # 2. Fallback to official Steam Store API genres
    if (-not $cat -and (Get-Date) -lt $lookupDeadline) {
        try {
            $store = Invoke-RestMethod -Uri "https://store.steampowered.com/api/appdetails?appids=$appId&filters=genres" -TimeoutSec 2 -ErrorAction Stop
            $data = $store.$appId.data
            if ($store.$appId.success -eq $true -and $data -and $null -ne $data.genres) {
                $storeSucceeded = $true
                $signals = @($data.genres | ForEach-Object { [PSCustomObject]@{ Name=$_.description; Weight=1 } })
                $cat = Resolve-GameMetadataCategory $signals
                if ($cat) { $categorySource = 'SteamStore' }
            }
        } catch {}
    }

    if ($cat -or ($spySucceeded -and $storeSucceeded)) {
        $genreCache[$appId] = [PSCustomObject]@{
            Version = $classifierVersion
            Category = if ($cat) { $cat } else { 'OTHER' }
            Source = if ($cat) { $categorySource } else { 'SteamSpy+SteamStore' }
            ExpiresUtc = $now.AddDays($(if ($cat) { 30 } else { 1 })).ToString('o')
        }
        $script:genreCacheDirty = $true
        return $cat
    }
    return $lastKnown
}


function ConvertTo-MeterText([string]$text) {
    # Escape Rainmeter variable / section syntax, retaining the original title in the catalog.
    return $text.Replace('[','［').Replace(']','］').Replace('#','＃').Replace('$','＄').Replace("`r",' ').Replace("`n",' ')
}

function Resolve-GameCategory($game) {
    if ($game.Category) { return $game.Category }
    if ($game.Title -match '\b(Wuthering Waves|Honkai|Zenless Zone Zero|Arknights Endfield|Witcher|Skyrim|Genshin Impact|Cyberpunk 2077|Elden Ring|Persona \d|Final Fantasy|Dragon Age|Dragon Quest|RPG|Tales of|Umamusume|Blue Archive|Nikke|Atelier|Granblue Fantasy)\b') { return 'RPG' }
    if ($game.Title -match '\b(Counter-Strike|Delta Force|Call of Duty|Far Cry|Ace Combat|Battlefield|Apex Legends|Valorant|Overwatch|Doom|Halo|Sniper|Shooter|FPS|Armored Core|Fortnite|PUBG|Rainbow Six|Marvel Rivals|Helldivers)\b') { return 'ACTION' }
    if ($game.Title -match '\b(Hearts of Iron|Stellaris|RimWorld|Civilization|Total War|Cities\s*:?\s+Skylines|SimCity|The Sims|Simulator|inZOI|Crusader Kings|Europa Universalis|Age of Empires|Age of Mythology|Factorio|Satisfactory|Frostpunk|Manor Lords|Strategy)\b') { return 'STRATEGY' }
    return 'OTHER'
}

function Write-GameInclude($games, $platforms, [string]$targetInc, [string]$revision) {
    $catMap = @{ RPG='RPG'; ACTION='Action'; STRATEGY='Strategy'; OTHER='Other' }
    $orderedGames = @($games | Sort-Object @{ Expression={
        switch ($_.Category) { 'RPG' { 0 } 'ACTION' { 1 } 'STRATEGY' { 2 } default { 3 } }
    } }, Title, Id)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('; Auto-generated by @Resources\ScanGames.ps1 - edit Games\Overrides.txt to customize')
    $lines.Add('[Variables]')
    $lines.Add('GameCardH=348')
    $lines.Add("GameLibraryRevision=$revision")
    $lines.Add("GameEntryCount=$($orderedGames.Count)")

    $index = 1
    foreach ($item in $orderedGames) {
        $prefix = "Game$index"
        $catKey = if ($catMap.ContainsKey($item.Category)) { $catMap[$item.Category] } else { 'Other' }
        $title = ConvertTo-MeterText $item.Title
        $lines.Add("${prefix}Category=$catKey")
        $lines.Add("${prefix}Title=$title")
        $lines.Add("${prefix}GameId=$($item.Id)")
        $lines.Add("${prefix}GamePath=$($item.Path)")
        $lines.Add("${prefix}GameSource=$($item.Source)")
        $lines.Add("${prefix}GameFolder=$($item.Folder)")
        $lines.Add("${prefix}GameArguments=$($item.Arguments)")
        $lines.Add("${prefix}GameWorkingDirectory=$($item.WorkingDirectory)")
        $lines.Add("${prefix}GameAvailable=$([int][bool]$item.Available)")
        $lines.Add("${prefix}GameConfidence=$($item.Confidence)")
        foreach ($alias in $item.Aliases) { $lines.Add("; ${prefix}GameAlias=$alias") }
        $index++
    }

    $lines.Add("PlatformCount=$($platforms.Count)")
    $pIndex = 1
    foreach ($platform in $platforms) {
        $pTitle = ConvertTo-MeterText $platform.Title
        $lines.Add("Platform${pIndex}Title=$pTitle")
        $lines.Add("Platform${pIndex}Action=[`"$($platform.Path)`"]")
        $pIndex++
    }

    $utilItems = @(
        [PSCustomObject]@{ Title = 'Discord'; Path = '#pathDiscord#' }
        [PSCustomObject]@{ Title = 'Open Games Folder'; Path = '#pathGamesFolder#' }
    )
    $lines.Add("UtilityCount=$($utilItems.Count)")
    $uIndex = 1
    foreach ($util in $utilItems) {
        $lines.Add("Utility${uIndex}Title=$(ConvertTo-MeterText $util.Title)")
        $lines.Add("Utility${uIndex}Action=[`"$($util.Path)`"]")
        $uIndex++
    }

    Write-AtomicText $targetInc ($lines -join "`r`n")
}

function Assert-ScanTime {
    if ([DateTime]::UtcNow -gt $scanDeadline) { throw 'Scan time limit reached; previous library retained.' }
}

function Get-ScanEnvironment([string]$resources) {
    function Test-OptionalPath([string]$path) {
        if (Test-ExcludedGameSource $path $excluded) { return $false }
        try { return Test-Path -LiteralPath $path -ErrorAction Stop } catch { return $false }
    }
    $settings = @{}
    foreach ($configName in @('Variables.inc', 'UserSettings.inc')) {
        $configPath = Join-Path $resources $configName
        if ($configName -eq 'UserSettings.inc' -and -not (Test-Path -LiteralPath $configPath -PathType Leaf)) { continue }
        foreach ($line in Get-Content -LiteralPath $configPath -Encoding UTF8 -ErrorAction Stop) {
            if ($line -match '^\s*([^;=\[]+?)\s*=\s*(.*?)\s*$') {
                $settings[$matches[1]] = [Environment]::ExpandEnvironmentVariables($matches[2].Trim('"'))
            }
        }
    }
    $gamesRoot = $settings.GamesFolder
    if (-not $gamesRoot) { $gamesRoot = 'C:\Games' }
    $gameRoots = @(Get-ConfiguredGameRoots $gamesRoot $settings.GamesFolders)
    $excluded = @($settings.GamesExcludedDrives -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object {
        if ($_ -notmatch '^[a-zA-Z]:?$') { throw "Invalid GamesExcludedDrives entry: $_" }
        $_.Substring(0,1).ToUpperInvariant() + ':\'
    })
    $sources = [Collections.Generic.List[object]]::new()
    $libs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $warnings = [Collections.Generic.List[string]]::new()
    $steam = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { $steam = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name InstallPath -ErrorAction SilentlyContinue).InstallPath }
    if ($steam -and -not (Test-ExcludedGameSource $steam $excluded)) {
        [void]$libs.Add($steam)
        try {
            foreach ($line in Get-Content -LiteralPath (Join-Path $steam 'steamapps\libraryfolders.vdf') -Encoding UTF8 -ErrorAction Stop) {
                if ($line -match '"path"\s+"([^"]+)"') { [void]$libs.Add($matches[1].Replace('\\','\')) }
            }
        } catch { $warnings.Add('Steam library configuration could not be read.') }
    }
    foreach ($path in @('C:\Program Files (x86)\Steam','C:\SteamLibrary','D:\SteamLibrary','E:\SteamLibrary')) {
        if (-not (Test-ExcludedGameSource $path $excluded) -and (Test-OptionalPath $path)) { [void]$libs.Add($path) }
    }
    foreach ($path in $libs) {
        if (-not (Test-ExcludedGameSource $path $excluded)) { $sources.Add([PSCustomObject]@{ Kind='steam'; Path=$path; Optional=$false }) }
    }
    foreach ($path in $gameRoots) { $sources.Add([PSCustomObject]@{ Kind='standalone'; Path=$path; Optional=$false }) }
    $hoyoRoots = @(@($gameRoots | ForEach-Object { Join-Path $_ 'HoYoPlay\games' }) + @('C:\Program Files\HoYoPlay\games') | Select-Object -Unique)
    foreach ($path in $hoyoRoots) {
        $sources.Add([PSCustomObject]@{ Kind='hoyo'; Path=$path; Optional=$true })
    }
    $sources.Add([PSCustomObject]@{ Kind='epic'; Path=(Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'); Optional=$true })
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop -and $env:USERPROFILE) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
    $desktopGames = if ($desktop) { Join-Path $desktop 'Games' } else { '' }
    if ($desktopGames -and -not (Test-ExcludedGameSource $desktopGames $excluded)) {
        $sources.Add([PSCustomObject]@{ Kind='desktop'; Path=$desktopGames; Optional=$true })
    }
    $platforms = [Collections.Generic.List[object]]::new()
    if ($libs.Count -or ($desktopGames -and (Test-OptionalPath (Join-Path $desktopGames 'Steam.lnk')))) {
        $platforms.Add([PSCustomObject]@{ Title='Steam'; Path='steam://open/main' })
    }
    if ((Test-OptionalPath 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Epic Games Launcher.lnk') -or
        (Test-OptionalPath 'C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe') -or
        ($desktopGames -and ((Test-OptionalPath (Join-Path $desktopGames 'Epic Games Launcher.lnk')) -or (Test-OptionalPath (Join-Path $desktopGames 'Epic Games.lnk'))))) {
        $platforms.Add([PSCustomObject]@{ Title='Epic Games'; Path='com.epicgames.launcher://' })
    }
    $hoyoDefault = Join-Path $gamesRoot 'HoYoPlay\launcher.exe'
    $hoyoLnk = if ($desktopGames) { Join-Path $desktopGames 'HoYoPlay.lnk' } else { '' }
    if (Test-OptionalPath $hoyoDefault) {
        $platforms.Add([PSCustomObject]@{ Title='HoYoPlay'; Path=$hoyoDefault })
    } elseif ($hoyoLnk -and (Test-OptionalPath $hoyoLnk)) {
        $platforms.Add([PSCustomObject]@{ Title='HoYoPlay'; Path=$hoyoLnk })
    }
    $xxmiPath = $settings.XXMILauncher
    $xxmiLnk = if ($desktopGames) { Join-Path $desktopGames 'XXMI Launcher.lnk' } else { '' }
    if ($xxmiPath -and (Test-OptionalPath $xxmiPath)) {
        $platforms.Add([PSCustomObject]@{ Title='XXMI Launcher'; Path=$xxmiPath })
    } elseif ($xxmiLnk -and (Test-OptionalPath $xxmiLnk)) {
        $platforms.Add([PSCustomObject]@{ Title='XXMI Launcher'; Path=$xxmiLnk })
    }
    return [PSCustomObject]@{ Sources=$sources.ToArray(); Platforms=$platforms.ToArray(); Warnings=$warnings.ToArray(); GamesRoot=$gamesRoot; ExcludedRoots=$excluded }
}

function Read-LegacyLibrary([string]$path, [string]$gamesRoot) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    # New includes also carry enough data to recover after the runtime cache is cleared.
    Read-GeneratedGames $path
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
    foreach ($match in [regex]::Matches($text, '(?ms)^\[Meter(RPG|Action|Strategy|Other)\d+\]\r?\n(.*?)(?=^\[|\z)')) {
        $body = $match.Groups[2].Value
        $title = if ($body -match '(?m)^Text=\[\\x25B8\] (.+)\r?$') { $matches[1].TrimEnd("`r") } else { '' }
        $target = if ($body -match '(?m)^LeftMouseUpAction=\["(.+)"\]\r?$') { $matches[1] } else { '' }
        if (-not $target -or -not $title) { continue }
        $kind = 'standalone'
        $source = Get-SourceId $kind $gamesRoot
        $folder = Split-Path -Parent $target
        if ($target -match '^steam://rungameid/(\d+)$') { $id = 'steam:' + $matches[1]; $source = 'steam:legacy'; $folder = '' }
        else {
            $hoyoRoot = Join-Path $gamesRoot 'HoYoPlay\games'
            if ($target.StartsWith($hoyoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $relative = $target.Substring($hoyoRoot.Length + 1).Split('\')[0]
                $folder = Join-Path $hoyoRoot $relative
                $info = Get-HoyoInfo $relative
                $id = if ($info) { $info.Id } else { Get-GameId 'folder' $folder }
                $source = Get-SourceId 'hoyo' $hoyoRoot
            } elseif ($target.StartsWith($gamesRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $relative = $target.Substring($gamesRoot.TrimEnd('\').Length + 1).Split('\')[0]
                $folder = Join-Path $gamesRoot $relative
                $id = Get-GameId 'folder' $folder
            } else { $id = Get-GameId 'legacy' $target; $source = 'legacy' }
        }
        [PSCustomObject]@{ Id=$id; Title=$title; Path=$target; Source=$source; Folder=$folder;
            Category=$match.Groups[1].Value.ToUpperInvariant(); WorkingDirectory=$folder; Arguments='';
            Confidence='legacy'; Available=$false; Aliases=@() }
    }
}

function Write-ScanStatus([string]$path, [string]$state, [string]$summary, [string]$detail, [string]$lastSuccess) {
    $detail = $detail.Replace("`r",' ').Replace("`n",' ')
    Write-AtomicText $path "State=$state`nSummary=$summary`nDetail=$detail`nLastSuccess=$lastSuccess`n"
}

function Invoke-GameScan([string]$RootDirectory, $Environment=$null, [switch]$NoNetwork) {
    $ErrorActionPreference = 'Stop'
    $resDir = Join-Path $RootDirectory '@Resources'
    $skinDir = Join-Path $RootDirectory 'Games'
    $cacheDir = Join-Path $resDir 'Cache'
    [void][IO.Directory]::CreateDirectory($cacheDir)
    $catalogFile = Join-Path $cacheDir 'game_library.json'
    $statusFile = Join-Path $cacheDir 'game_scan_status.txt'
    $targetInc = Join-Path $skinDir 'GameList.inc'
    $lock = $null
    try { $lock = [IO.File]::Open((Join-Path $cacheDir 'game_scan.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch {
        $cause = $_.Exception.GetBaseException()
        if (($cause.HResult -band 65535) -in @(32,33)) {
            return [PSCustomObject]@{ State='Busy'; Summary='Another scan is already running.' }
        }
        return [PSCustomObject]@{ State='Failed'; Summary=('Could not open scan lock: ' + $cause.Message); Published=$false }
    }
    $lastSuccess = ''
    try {
        $scanDeadline = [DateTime]::UtcNow.AddSeconds(70)
        $lookupDeadline = (Get-Date).AddSeconds(40)
        $scanNoNetwork = [bool]$NoNetwork
        $genreCacheFile = Join-Path $cacheDir 'steam_genres.json'
        $genreCache = @{}
        $script:genreCacheDirty = $false
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if (Test-Path -LiteralPath $genreCacheFile) {
            try {
                $obj = Get-Content -LiteralPath $genreCacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($prop in $obj.PSObject.Properties) { $genreCache[$prop.Name] = $prop.Value }
            } catch { } # Genre data is optional and may be rebuilt.
        }
        $old = $null
        if (Test-Path -LiteralPath $catalogFile) {
            $old = Get-Content -LiteralPath $catalogFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($old.Version -ne 1 -or $null -eq $old.Games -or $null -eq $old.Sources) { throw 'Saved game library is invalid; restore it or move it aside before rescanning.' }
            $published = if (Test-Path -LiteralPath $targetInc) { Get-Content -LiteralPath $targetInc -Raw -Encoding UTF8 }
            if ([string]$old.Revision -cne (Get-GameLibraryRevision $published)) { $old = $null }
            else { $lastSuccess = [string]$old.LastSuccess }
        }
        Write-ScanStatus $statusFile 'Running' 'Scanning installed games...' '' $lastSuccess
        if (-not $Environment) { $Environment = Get-ScanEnvironment $resDir }
        $previous = if ($old) { @($old.Games) } else { @(Read-LegacyLibrary $targetInc $Environment.GamesRoot) }
        $overrides = @(Read-GameOverrides (Join-Path $skinDir 'Overrides.txt'))
        $specs = @{}
        foreach ($spec in $Environment.Sources) { $specs[(Get-SourceId $spec.Kind $spec.Path)] = $spec }
        # Keep disconnected Steam libraries in the scan set even if the VDF no longer exposes them.
        foreach ($source in $old.Sources) {
            if ($source.Kind -eq 'steam' -and -not $specs.ContainsKey($source.Source)) {
                $specs[$source.Source] = [PSCustomObject]@{ Kind='steam'; Path=$source.Path; Optional=$false }
            }
        }
        foreach ($game in $previous) {
            if ($game.Source -like 'steam:*' -and $game.Source -ne 'steam:legacy' -and -not $specs.ContainsKey($game.Source)) {
                $specs[$game.Source] = [PSCustomObject]@{ Kind='steam'; Path=$game.Source.Substring(6); Optional=$false }
            }
        }
        $results = [Collections.Generic.List[object]]::new()
        $warnings = [Collections.Generic.List[string]]::new()
        foreach ($warning in $Environment.Warnings) { $warnings.Add($warning) }
        foreach ($source in @($specs.Keys | Sort-Object)) {
            Assert-ScanTime
            $spec = $specs[$source]
            # Apply exclusions here as well so cached sources cannot resurrect a cloud drive.
            if (Test-ExcludedGameSource $spec.Path $Environment.ExcludedRoots) { continue }
            $hadSource = @($previous | Where-Object Source -eq $source).Count -gt 0 -or @($old.Sources | Where-Object Source -eq $source).Count -gt 0
            $items = @(); $state = 'Success'; $detail = ''
            try {
                if (-not (Test-Path -LiteralPath $spec.Path -PathType Container -ErrorAction Stop)) {
                    if ($spec.Optional -and -not $hadSource) { continue }
                    $state = 'Unavailable'; $detail = 'Folder unavailable: ' + $spec.Path
                } else {
                    $items = @(switch ($spec.Kind) {
                        'steam' { Find-SteamGames $spec.Path $source }
                        'epic' { Find-EpicGames $spec.Path $source $Environment.ExcludedRoots }
                        'desktop' { @(Find-ShortcutGames $spec.Path $source $Environment.Platforms) + @(Find-FolderGames $spec.Path $source 'standalone') }
                        default { Find-FolderGames $spec.Path $source $spec.Kind }
                    })
                }
            } catch { $state = 'Failed'; $detail = $spec.Path + ': ' + $_.Exception.Message; $items = @() }
            if ($state -ne 'Success') { $warnings.Add($detail) }
            $results.Add([PSCustomObject]@{ Source=$source; Kind=$spec.Kind; Path=$spec.Path; State=$state; Detail=$detail; Games=$items })
        }
        # Bootstrap older generated lists conservatively when their source cannot be mapped or read.
        $steamFailed = @($results | Where-Object { $_.Kind -eq 'steam' -and $_.State -ne 'Success' }).Count -gt 0
        if (-not @($results | Where-Object Kind -eq 'steam').Count -and @($previous | Where-Object Source -eq 'steam:legacy').Count) {
            $steamFailed = $true
            $warnings.Add('Previous Steam library could not be located; entries retained as unavailable.')
        }
        foreach ($legacySource in @('steam:legacy','legacy')) {
            if (@($previous | Where-Object Source -eq $legacySource).Count -and
                (($legacySource -eq 'steam:legacy' -and $steamFailed) -or ($legacySource -eq 'legacy' -and $warnings.Count))) {
                $results.Add([PSCustomObject]@{ Source=$legacySource; Kind='legacy'; Path=''; State='Unavailable'; Detail=''; Games=@() })
            }
        }
        $games = @(Merge-GameSources $previous $results $Environment.Platforms | Where-Object {
            -not $_.Folder -or -not (Test-ExcludedGameSource $_.Folder $Environment.ExcludedRoots)
        } | Sort-Object Title,Id)
        foreach ($game in $games) { $game.Category = Resolve-GameCategory $game }
        $now = Get-Date -Format 'yyyy-MM-dd HH:mm'
        if (-not $warnings.Count) { $lastSuccess = $now }
        $revision = [Guid]::NewGuid().ToString('N')
        $catalog = [PSCustomObject]@{ Version=1; Revision=$revision; Updated=$now; LastSuccess=$lastSuccess; Games=$games;
            Sources=@($results | Select-Object Source,Kind,Path,State,Detail) }
        Assert-ScanTime
        $catalogText = $catalog | ConvertTo-Json -Depth 8
        # The catalog is published first; the include is published only after complete rendering.
        # Roll back the catalog if rendering/publication fails, leaving the previous meters usable.
        $oldCatalogText = if ([IO.File]::Exists($catalogFile)) { [IO.File]::ReadAllText($catalogFile) } else { $null }
        Write-AtomicText $catalogFile $catalogText
        try { Write-GameInclude $games $Environment.Platforms $targetInc $revision }
        catch {
            if ($null -ne $oldCatalogText) { Write-AtomicText $catalogFile $oldCatalogText }
            else { [IO.File]::Delete($catalogFile) }
            throw
        }
        # Icons are an optional local presentation cache; library publication is independent.
        try { Write-GameIcons $RootDirectory } catch { }
        if ($script:genreCacheDirty) {
            try { Write-AtomicText $genreCacheFile ($genreCache | ConvertTo-Json -Depth 5) } catch { $warnings.Add('Genre cache could not be saved.') }
        }
        $available = @($games | Where-Object Available).Count
        $offline = $games.Count - $available
        $uncertain = @($games | Where-Object { $_.Available -and $_.Confidence -eq 'uncertain' }).Count
        $state = if ($warnings.Count -or $offline -or $uncertain) { 'Warning' } else { 'Success' }
        $summary = "$available games - updated $now"
        if ($offline) { $summary = "$available games / $offline unavailable" }
        if ($warnings.Count) { $summary = "$available games - scan warnings" }
        $details = @($warnings)
        if ($uncertain) { $details += "$uncertain launch target(s) need review in Overrides.txt." }
        Write-ScanStatus $statusFile $state $summary ($details -join ' | ') $lastSuccess
        return [PSCustomObject]@{ State=$state; Summary=$summary; Games=$games; Sources=$catalog.Sources; Published=$true }
    } catch {
        $message = $_.Exception.Message
        try { Write-ScanStatus $statusFile 'Failed' 'Scan failed - library retained' $message $lastSuccess } catch { }
        return [PSCustomObject]@{ State='Failed'; Summary=$message; Published=$false }
    } finally { $lock.Dispose() }
}

if (-not $LibraryOnly) {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $result = Invoke-GameScan -RootDirectory $RootDirectory -NoNetwork:$NoNetwork
    if ($result.Published) { Write-Output 'GAMEHUB:PUBLISHED' }
    elseif ($result.State -eq 'Busy') { Write-Output 'GAMEHUB:BUSY' }
    else { Write-Output ('GAMEHUB:FAILED ' + $result.Summary); exit 1 }
}
