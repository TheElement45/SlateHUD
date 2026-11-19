# Discovery helpers are side-effect free until explicitly invoked by ScanGames.ps1.
function Get-GameId([string]$kind, [string]$value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($value.TrimEnd('\').ToLowerInvariant())) }
    finally { $sha.Dispose() }
    return $kind + ':' + ([BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant())
}

function Get-SourceId([string]$kind, [string]$path) {
    return $kind + ':' + [IO.Path]::GetFullPath($path).TrimEnd('\').ToLowerInvariant()
}

function Test-ExcludedGameSource([string]$path, $excludedRoots) {
    $full = [IO.Path]::GetFullPath($path).TrimEnd('\')
    foreach ($root in $excludedRoots) {
        $excluded = [IO.Path]::GetFullPath($root).TrimEnd('\')
        if ($full.Equals($excluded, [StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($excluded + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-ConfiguredGameRoots([string]$primary, [string]$additional) {
    @(@($primary) + @($additional -split '\|' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim().Trim('"') }) |
        ForEach-Object {
            $full = [IO.Path]::GetFullPath($_)
            if ($full.Length -gt 3) { $full.TrimEnd('\') } else { $full }
        } | Select-Object -Unique)
}

function Get-HoyoInfo([string]$name) {
    switch -Wildcard ($name) {
        '*Star Rail*' { return @{ Title='Honkai: Star Rail'; Id='hoyo:starrail'; Exe='StarRail.exe' } }
        '*Zenless*' { return @{ Title='Zenless Zone Zero'; Id='hoyo:zenless'; Exe='ZenlessZoneZero.exe' } }
        '*Genshin*' { return @{ Title='Genshin Impact'; Id='hoyo:genshin'; Exe='GenshinImpact.exe' } }
        '*Honkai 3*' { return @{ Title='Honkai Impact 3rd'; Id='hoyo:honkai3'; Exe='BH3.exe' } }
    }
    return $null
}

function Read-GameOverrides([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop) {
        if (-not $line.Trim() -or $line.Trim().StartsWith('#')) { continue }
        $parts = $line -split '\|'
        if ($parts.Count -gt 6) { throw "Too many override fields: $line" }
        $fields = @('', '', '', '', '', '')
        for ($i = 0; $i -lt $parts.Count; $i++) { $fields[$i] = $parts[$i].Trim() }
        if (-not $fields[0]) { throw 'Override match cannot be empty.' }
        if ($fields[2] -and $fields[2].ToUpperInvariant() -notin @('RPG','ACTION','STRATEGY','OTHER','HIDE')) {
            throw "Unknown override category: $($fields[2])"
        }
        [PSCustomObject]@{ Match=$fields[0]; Title=$fields[1]; Category=$fields[2].ToUpperInvariant();
            Path=$fields[3]; Arguments=$fields[4]; WorkingDirectory=$fields[5] }
    }
}

function Apply-Override([string]$rawName, [string]$defaultTitle, [string]$defaultPath) {
    $result = [PSCustomObject]@{ Title=$defaultTitle; Path=$defaultPath; Category=''; Arguments=''; WorkingDirectory='' }
    foreach ($ov in $overrides) {
        if (($rawName -and $rawName.IndexOf($ov.Match, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or
            ($defaultTitle -and $defaultTitle.IndexOf($ov.Match, [StringComparison]::OrdinalIgnoreCase) -ge 0)) {
            foreach ($key in @('Title','Path','Category','Arguments','WorkingDirectory')) {
                if ($ov.$key) { $result.$key = $ov.$key }
            }
            break
        }
    }
    return $result
}

function Test-GameUri([string]$path) { return $path -match '^[a-zA-Z][a-zA-Z0-9+.-]*://' }

function Get-GameLibraryRevision([string]$text) {
    if ($text -cmatch '(?m)^GameLibraryRevision=([a-f0-9]{32})\r?$') { return $Matches[1] }
    return ''
}

function Read-GeneratedGames([string]$path, [string]$text) {
    if ($null -eq $text -or $text -eq '') {
        if (-not (Test-Path -LiteralPath $path)) { return }
        $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
    }
    $indexed = @{}
    foreach ($line in $text -split '\r?\n') {
        if ($line -match '^Game(\d+)(Category|Title|GameId|GamePath|GameSource|GameFolder|GameArguments|GameWorkingDirectory|GameAvailable|GameConfidence)=(.*)$') {
            $idx = [int]$matches[1]
            if (-not $indexed.ContainsKey($idx)) { $indexed[$idx] = @{ Aliases=[Collections.Generic.List[string]]::new() } }
            $indexed[$idx][$matches[2]] = $matches[3]
        } elseif ($line -match '^; Game(\d+)GameAlias=(.+)$') {
            $idx = [int]$matches[1]
            if (-not $indexed.ContainsKey($idx)) { $indexed[$idx] = @{ Aliases=[Collections.Generic.List[string]]::new() } }
            $indexed[$idx].Aliases.Add($matches[2])
        }
    }
    foreach ($idx in @($indexed.Keys | Sort-Object)) {
        $v = $indexed[$idx]
        if (-not $v.GameId -or -not $v.GamePath -or -not $v.GameSource) { continue }
        [PSCustomObject]@{ Id=$v.GameId; Title=$v.Title; Path=$v.GamePath; Source=$v.GameSource; Folder=$v.GameFolder;
            Category=([string]$v.Category).ToUpperInvariant(); Arguments=$v.GameArguments; WorkingDirectory=$v.GameWorkingDirectory;
            Confidence=$v.GameConfidence; Available=($v.GameAvailable -eq '1'); Aliases=$v.Aliases.ToArray() }
    }
    foreach ($match in [regex]::Matches($text, '(?ms)^\[Meter(RPG|Action|Strategy|Other)\d+\]\r?\n(.*?)(?=^\[|\z)')) {
        $values = @{}
        foreach ($line in $match.Groups[2].Value -split '\r?\n') {
            if ($line -match '^([^=]+)=(.*)$') { $values[$matches[1]] = $matches[2] }
        }
        if (-not $values.GameId -or -not $values.GamePath -or -not $values.GameSource) { continue }
        $aliases = @([regex]::Matches($match.Groups[2].Value, '(?m)^; GameAlias=(.+)\r?$') | ForEach-Object { $_.Groups[1].Value.TrimEnd("`r") })
        [PSCustomObject]@{ Id=$values.GameId; Title=($values.Text -replace '^\[\\x25B8\]\s*',''); Path=$values.GamePath;
            Source=$values.GameSource; Folder=$values.GameFolder; Category=$match.Groups[1].Value.ToUpperInvariant();
            Arguments=$values.GameArguments; WorkingDirectory=$values.GameWorkingDirectory;
            Confidence=$values.GameConfidence; Available=($values.GameAvailable -eq '1'); Aliases=$aliases }
    }
}

function New-GameRecord($rule, [string]$id, [string]$source, [string]$folder, [string]$confidence) {
    $isUri = Test-GameUri $rule.Path
    $path = $rule.Path
    if (-not $isUri) {
        $path = [Environment]::ExpandEnvironmentVariables($path)
        if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $folder $path }
        $path = [IO.Path]::GetFullPath($path)
    }
    $workDir = $rule.WorkingDirectory
    if ($workDir) {
        $workDir = [Environment]::ExpandEnvironmentVariables($workDir)
        if (-not [IO.Path]::IsPathRooted($workDir)) { $workDir = Join-Path $folder $workDir }
        $workDir = [IO.Path]::GetFullPath($workDir)
    } elseif (-not $isUri) { $workDir = Split-Path -Parent $path }
    $available = $isUri -or (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction Stop)
    if ($workDir -and -not (Test-Path -LiteralPath $workDir -PathType Container -ErrorAction Stop)) { $available = $false }
    [PSCustomObject]@{ Id=$id; Title=$rule.Title; Path=$path; Category=$rule.Category; Source=$source;
        Folder=$folder; Arguments=$rule.Arguments; WorkingDirectory=$workDir; Confidence=$confidence;
        Available=[bool]$available; Aliases=@() }
}

function Find-GameTarget([IO.DirectoryInfo]$folder, [string]$title, [string]$knownExe='') {
    # Explicit launcher metadata outranks guesses. No script content is used as a play signal.
    $metadata = Join-Path $folder.FullName 'Launcher.ini'
    if (Test-Path -LiteralPath $metadata) {
        foreach ($line in Get-Content -LiteralPath $metadata -ErrorAction Stop) {
            if ($line -match '(?i)^\s*Button\.Launch=<APP_PATH>\\(.+?)\s*$') {
                $target = Join-Path $folder.FullName $matches[1].Trim('"')
                $name = [IO.Path]::GetFileName($target)
                if ($name -match '(?i)^(HVG|VBS)\.|install|setup|unins|guide|verify|redist|language|updater') { continue }
                if ($name -notmatch '(?i)\.exe$|^(!start[^\\]*|play|launch|start)\.(bat|cmd)$') { continue }
                if (Test-Path -LiteralPath $target -PathType Leaf) { return @{ Path=$target; Confidence='metadata' } }
            }
        }
    }
    $exes = @(Get-ChildItem -LiteralPath $folder.FullName -Filter '*.exe' -File -Recurse -Depth 4 -ErrorAction Stop |
        Where-Object {
            $_.Name -notmatch '(?i)unins\d*|uninstall|setup|installer|wizard|QuickSFV|Verify|Crash|Dump|EasyAntiCheat|CODSecure|CODBroker|downloader|updater|patcher|vc_redist|dxwebsetup|DotNet|UE4Prereq|Language|Changer|Benchmark|Server|Config|ErrorReporter|^7za|^scc\.exe$|^redMod' -and
            $_.FullName -notmatch '(?i)[\\/](tools|CrashReporter|_CommonRedist|redist)[\\/]'
        })
    if ($knownExe) {
        $known = @($exes | Where-Object Name -eq $knownExe | Sort-Object FullName)
        if ($known.Count) { return @{ Path=$known[0].FullName; Confidence='known' } }
    }
    # Recognizable play scripts are supported, but generic setup/service scripts are ignored.
    $scripts = @(Get-ChildItem -LiteralPath $folder.FullName -Filter '*.bat' -File -Recurse -Depth 1 -ErrorAction Stop |
        Where-Object { $_.Name -match '(?i)^(!start[^\\]*|play|launch|start)\.bat$' -and
            $_.Name -notmatch '(?i)verify|install|setup|language|redist' } | Sort-Object FullName)
    if ($scripts.Count -eq 1) { return @{ Path=$scripts[0].FullName; Confidence='script' } }
    $normalizedTitle = ($title -replace '[^\p{L}\p{Nd}]','').ToLowerInvariant()
    $scored = @($exes | ForEach-Object {
        $score = [Math]::Min(50, [Math]::Floor($_.Length / 1MB))
        $normalizedName = ($_.BaseName -replace '[^\p{L}\p{Nd}]','').ToLowerInvariant()
        if ($normalizedTitle.Length -ge 4 -and $normalizedName.Length -ge 4 -and
            ($normalizedName.Contains($normalizedTitle) -or $normalizedTitle.Contains($normalizedName))) { $score += 500 }
        if ($_.Name -match '(?i)^start_protected_game\.exe$') { $score += 650 }
        if ($_.Name -match '(?i)^(Game|Launcher|Start)\.exe$') { $score += 200 }
        if (Test-Path -LiteralPath (Join-Path $_.DirectoryName ($_.BaseName + '_Data'))) { $score += 300 }
        if ($_.Name -match '(?i)-Win64-Shipping\.exe$') { $score += 100 }
        if ($_.DirectoryName -eq $folder.FullName) { $score += 50 }
        [PSCustomObject]@{ Path=$_.FullName; Score=$score }
    } | Sort-Object @{Expression='Score';Descending=$true}, @{Expression='Path';Descending=$false})
    if ($scored.Count) {
        $confidence = 'heuristic'
        if ($scored[0].Score -lt 200 -or ($scored.Count -gt 1 -and $scored[0].Score - $scored[1].Score -lt 50)) { $confidence = 'uncertain' }
        return @{ Path=$scored[0].Path; Confidence=$confidence }
    }
    return $null
}

function Find-FolderGames([string]$path, [string]$source, [string]$kind) {
    $folders = @(Get-ChildItem -LiteralPath $path -Directory -ErrorAction Stop | Sort-Object FullName)
    foreach ($folder in $folders) {
        Assert-ScanTime
        if ($folder.Name -match '(?i)^(HoYoPlay|\$Recycle\.Bin|System Volume Information|SteamLibrary)$') { continue }
        $info = if ($kind -eq 'hoyo') { Get-HoyoInfo $folder.Name } else { $null }
        $title = $folder.Name -replace '(?i)\s*-\s*GOG\b.*', ''
        $title = ($title -replace '(?i)\s*[\(\[].*?[\)\]]','').Trim()
        if ($info) { $title = $info.Title }
        $rule = Apply-Override $folder.Name $title ''
        if ($rule.Category -eq 'HIDE') { continue }
        $confidence = 'override'
        if (-not $rule.Path) {
            $known = if ($info) { $info.Exe } else { '' }
            $target = Find-GameTarget $folder $title $known
            if (-not $target) { continue }
            $rule.Path = $target.Path
            $confidence = $target.Confidence
        }
        $id = if ($info) { $info.Id } else { Get-GameId 'folder' $folder.FullName }
        if (-not $rule.Category -and $kind -eq 'hoyo') { $rule.Category = 'RPG' }
        if (-not $rule.Category) {
            $appIdFiles = @(Get-ChildItem -LiteralPath $folder.FullName -Filter 'steam_appid.txt' -File -Recurse -Depth 4 -ErrorAction Stop | Sort-Object FullName)
            if ($appIdFiles.Count) {
                $appId = (Get-Content -LiteralPath $appIdFiles[0].FullName -Raw -ErrorAction Stop).Trim()
                if ($appId -match '^\d+$') { $rule.Category = Get-SteamCategory $appId }
            }
        }
        New-GameRecord $rule $id $source $folder.FullName $confidence
    }
}

function Test-IsPlatformShortcut([string]$title, [string]$targetPath, [string]$url, $platforms) {
    if ($targetPath) {
        $targetName = [IO.Path]::GetFileName($targetPath)
        if ($targetName -match '(?i)^(steam|epicgameslauncher)\.exe$') { return $true }
        if ($targetPath -match '(?i)[\\/]HoYoPlay[\\/]launcher\.exe$') { return $true }
        if ($targetName -match '(?i)^xxmi(\s*launcher)?\.exe$' -or $targetPath -match '(?i)[\\/]xxmi.*launcher\.exe$') { return $true }
    }
    if ($url) {
        if ($url -match '^(steam://open/main/?|com\.epicgames\.launcher:///?)$') { return $true }
    }
    if ($platforms) {
        foreach ($p in $platforms) {
            if ($p.Path) {
                if ($url -and $url.Equals($p.Path, [StringComparison]::OrdinalIgnoreCase)) { return $true }
                if ($targetPath -and -not (Test-GameUri $p.Path)) {
                    try {
                        if ([IO.Path]::GetFullPath($targetPath).Equals([IO.Path]::GetFullPath($p.Path), [StringComparison]::OrdinalIgnoreCase)) {
                            return $true
                        }
                    } catch { }
                }
            }
            if ($p.Title) {
                $pNorm = ($p.Title -replace '[^\p{L}\p{Nd}]','').ToLowerInvariant()
                $pNormTrim = ($p.Title -replace '(?i)\s*launcher\s*$','' -replace '[^\p{L}\p{Nd}]','').ToLowerInvariant()
                $tNorm = ($title -replace '[^\p{L}\p{Nd}]','').ToLowerInvariant()
                $tNormTrim = ($title -replace '(?i)\s*launcher\s*$','' -replace '[^\p{L}\p{Nd}]','').ToLowerInvariant()
                if ($tNorm -and ($tNorm -eq $pNorm -or $tNormTrim -eq $pNorm -or $tNorm -eq $pNormTrim -or ($pNormTrim -and $tNormTrim -eq $pNormTrim))) {
                    return $true
                }
            }
        }
    }
    $cleanNorm = ($title -replace '(?i)\s*launcher\s*$','' -replace '[^\p{L}\p{Nd}]','').ToLowerInvariant()
    if ($cleanNorm -in @('steam', 'epicgames', 'hoyoplay', 'xxmi')) { return $true }
    return $false
}

function Find-ShortcutGames([string]$path, [string]$source, $platforms=$null) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { return }
    $shell = $null
    $files = @(Get-ChildItem -LiteralPath $path -File -ErrorAction Stop |
        Where-Object { $_.Extension -in @('.lnk', '.url') } | Sort-Object FullName)
    foreach ($file in $files) {
        Assert-ScanTime
        if ($file.BaseName -match '(?i)^(unins\d*|uninstall|setup|installer|wizard|readme|help|manual|website|register|config|settings|diagnostic|crash\s*reporter)\b') { continue }
        $title = $file.BaseName -replace '(?i)\s*-\s*GOG\b.*', ''
        $title = ($title -replace '(?i)\s*[\(\[].*?[\)\]]','').Trim()
        if (-not $title) { $title = $file.BaseName.Trim() }

        if ($file.Extension -eq '.url') {
            $urlText = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
            $url = if ($urlText -match '(?m)^URL=(.+?)\s*$') { $matches[1].Trim() } else { '' }
            $overrideCheck = Apply-Override $file.BaseName $title ''
            if ((-not $url -or $url -match '^(?i)https?://') -and -not $overrideCheck.Path) { continue }
            $appId = if ($url -match '^steam://rungameid/(\d+)$') { $Matches[1] }
            $epicGameUrl = $url -match '^com\.epicgames\.launcher://apps/([^?#]+)\?(?:[^#]*&)?action=launch(?:&|#|$)'
            $epicIdentity = if ($epicGameUrl) {
                $identity = [Uri]::UnescapeDataString($Matches[1])
                if ($identity -match '^[^:]+:[^:]+:[^:]+$') { $identity }
            }
            if (-not $appId -and -not $epicGameUrl -and -not $overrideCheck.Category -and
                (Test-IsPlatformShortcut $title '' $url $platforms)) { continue }
            if ($appId) {
                $clean = ($title -replace '(?i)The Elder Scrolls V:\s*','' -replace '(?i):\s*Pretty Derby','').Trim()
                $rule = Apply-Override $file.BaseName $clean "steam://rungameid/$appId"
                if ($rule.Category -eq 'HIDE') { continue }
                if (-not $rule.Category) { $rule.Category = Get-SteamCategory $appId }
                $id = "steam:$appId"
                if ($rule.Path -ne $url -or $rule.Arguments -or $rule.WorkingDirectory -or
                    $overrideCheck.Category -or $overrideCheck.Title -ne $title) { $id = Get-GameId 'shortcut' $file.FullName }
                $rec = New-GameRecord $rule $id $source $file.DirectoryName 'shortcut'
                $rec.Aliases = @($file.FullName)
                # A leftover Steam URL is not proof of an installed game. Only use
                # a missing local executable as evidence when its drive is online.
                $missingInstall = $false
                if (-not $overrideCheck.Path -and $urlText -match '(?m)^IconFile=(.+?)\s*$') {
                    $iconExe = [Environment]::ExpandEnvironmentVariables($Matches[1].Trim('"'))
                    if ([IO.Path]::IsPathRooted($iconExe) -and [IO.Path]::GetExtension($iconExe) -eq '.exe' -and
                        (Test-Path -LiteralPath ([IO.Path]::GetPathRoot($iconExe))) -and
                        -not (Test-Path -LiteralPath $iconExe -PathType Leaf)) { $missingInstall = $true }
                }
                $rec | Add-Member -NotePropertyName SteamInstallMissing -NotePropertyValue $missingInstall
                $rec
            } else {
                $defaultTarget = if (Test-GameUri $url) { $url } else { $file.FullName }
                $rule = Apply-Override $file.BaseName $title $defaultTarget
                if ($rule.Category -eq 'HIDE') { continue }
                $confidence = if ($rule.Path -ne $defaultTarget) { 'override' } else { 'shortcut' }
                $id = Get-GameId 'shortcut' $file.FullName
                if ($epicIdentity -and $confidence -eq 'shortcut' -and -not $rule.Arguments -and
                    -not $rule.WorkingDirectory -and -not $overrideCheck.Category -and $overrideCheck.Title -eq $title) {
                    $id = Get-GameId 'epic' $epicIdentity
                }
                $rec = New-GameRecord $rule $id $source $file.DirectoryName $confidence
                if ($rule.Path -ne $file.FullName) { $rec.Aliases = @($file.FullName) }
                $rec
            }
        } elseif ($file.Extension -eq '.lnk') {
            if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
            $lnk = $shell.CreateShortcut($file.FullName)
            $targetPath = [Environment]::ExpandEnvironmentVariables([string]$lnk.TargetPath)
            $workDir = [Environment]::ExpandEnvironmentVariables([string]$lnk.WorkingDirectory)
            $shortcutArguments = [string]$lnk.Arguments
            if ($targetPath -and ([IO.Path]::GetFileName($targetPath) -match '(?i)unins\d*|uninstall|setup|installer|wizard')) {
                $ov = Apply-Override $file.BaseName $title ''
                if (-not $ov.Path) { continue }
            }
            $overrideCheck = Apply-Override $file.BaseName $title ''
            if (-not $overrideCheck.Category -and (Test-IsPlatformShortcut $title $targetPath '' $platforms)) { continue }

            $hoyoInfo = Get-HoyoInfo $file.BaseName
            if (-not $hoyoInfo -and $targetPath) {
                $targetName = [IO.Path]::GetFileName($targetPath)
                if ($targetName -match '(?i)^(StarRail|ZenlessZoneZero|GenshinImpact|BH3)\.exe$') {
                    $hoyoInfo = switch -Regex ($targetName) {
                        '(?i)^StarRail\.exe$' { @{ Title='Honkai: Star Rail'; Id='hoyo:starrail'; Exe='StarRail.exe' } }
                        '(?i)^ZenlessZoneZero\.exe$' { @{ Title='Zenless Zone Zero'; Id='hoyo:zenless'; Exe='ZenlessZoneZero.exe' } }
                        '(?i)^GenshinImpact\.exe$' { @{ Title='Genshin Impact'; Id='hoyo:genshin'; Exe='GenshinImpact.exe' } }
                        '(?i)^BH3\.exe$' { @{ Title='Honkai Impact 3rd'; Id='hoyo:honkai3'; Exe='BH3.exe' } }
                    }
                }
            }
            if ($hoyoInfo) { $title = $hoyoInfo.Title }
            $rule = Apply-Override $file.BaseName $title $file.FullName
            if ($rule.Category -eq 'HIDE') { continue }
            if (-not $rule.Category -and $hoyoInfo) { $rule.Category = 'RPG' }
            $folder = $file.DirectoryName
            if ($targetPath -and [IO.Path]::IsPathRooted($targetPath)) {
                $targetParent = Split-Path -Parent $targetPath
                if ($targetParent -and (Test-Path -LiteralPath $targetParent -PathType Container)) {
                    $folder = $targetParent
                } elseif ($workDir -and (Test-Path -LiteralPath $workDir -PathType Container)) {
                    $folder = $workDir
                }
            } elseif ($workDir -and (Test-Path -LiteralPath $workDir -PathType Container)) {
                $folder = $workDir
            }
            if (-not $rule.Category -and $folder -ne $file.DirectoryName) {
                $appIdFiles = @(Get-ChildItem -LiteralPath $folder -Filter 'steam_appid.txt' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue | Sort-Object FullName)
                if ($appIdFiles.Count) {
                    $appId = (Get-Content -LiteralPath $appIdFiles[0].FullName -Raw -ErrorAction SilentlyContinue).Trim()
                    if ($appId -match '^\d+$') { $rule.Category = Get-SteamCategory $appId }
                }
            }
            $id = Get-GameId 'shortcut' $file.FullName
            $confidence = if ($rule.Path -ne $file.FullName) { 'override' } else { 'shortcut' }
            $record = New-GameRecord $rule $id $source $folder $confidence
            if ($rule.Path -eq $file.FullName) {
                if (-not $rule.WorkingDirectory) { $record.WorkingDirectory = '' }
                if ($targetPath -and [IO.Path]::IsPathRooted($targetPath) -and -not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                    $record.Available = $false
                }
            }
            $recAliases = [Collections.Generic.List[string]]::new()
            if ($targetPath) { $recAliases.Add($targetPath) }
            if ($rule.Path -ne $file.FullName) { $recAliases.Add($file.FullName) }
            $record.Aliases = $recAliases.ToArray()
            $record | Add-Member -NotePropertyName PresentationOverride -NotePropertyValue ([bool]($overrideCheck.Category -or $rule.Title -ne $title))
            if ($shortcutArguments -or
                ($workDir -and (-not $targetPath -or
                    [IO.Path]::GetFullPath($workDir).TrimEnd('\','/') -ne
                    [IO.Path]::GetFullPath((Split-Path -Parent $targetPath)).TrimEnd('\','/')))) {
                $record.Confidence = 'shortcut-custom'
            }
            $record
        }
    }
}

function Find-SteamGames([string]$library, [string]$source) {
    foreach ($manifest in Get-ChildItem -LiteralPath (Join-Path $library 'steamapps') -Filter 'appmanifest_*.acf' -File -ErrorAction Stop | Sort-Object FullName) {
        Assert-ScanTime
        $raw = [IO.File]::ReadAllText($manifest.FullName)
        $appId = if ($raw -match '"appid"\s+"(\d+)"') { $matches[1] } else { $null }
        $title = if ($raw -match '"name"\s+"([^"]+)"') { $matches[1] } else { $null }
        $install = if ($raw -match '"installdir"\s+"([^"]+)"') { $matches[1] } else { $null }
        if (-not $appId -or -not $title -or -not $install) { throw "Invalid Steam manifest: $($manifest.Name)" }
        if ($title -match '(?i)Wallpaper Engine|Common Redistributables|Dedicated Server|Steamworks|SteamVR|Proton|Soundtrack|Benchmark') { continue }
        $folder = Join-Path (Join-Path $library 'steamapps\common') $install
        if (-not (Test-Path -LiteralPath $folder -PathType Container -ErrorAction Stop)) { continue }
        $clean = ($title -replace '(?i)The Elder Scrolls V:\s*','' -replace '(?i):\s*Pretty Derby','').Trim()
        $rule = Apply-Override $title $clean "steam://rungameid/$appId"
        if ($rule.Category -eq 'HIDE') { continue }
        if (-not $rule.Category) { $rule.Category = Get-SteamCategory $appId }
        New-GameRecord $rule "steam:$appId" $source $folder 'platform'
    }
}

function Find-EpicGames([string]$manifests, [string]$source, $excludedRoots) {
    foreach ($file in Get-ChildItem -LiteralPath $manifests -Filter '*.item' -File -ErrorAction Stop | Sort-Object FullName) {
        Assert-ScanTime
        $item = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($item.bIsApplication -eq $false -or $item.bIsIncompleteInstall -eq $true) { continue }
        if (-not $item.DisplayName -or -not $item.InstallLocation -or -not $item.AppName -or
            -not $item.CatalogNamespace -or -not $item.CatalogItemId) { throw "Invalid Epic manifest: $($file.Name)" }
        $folder = [Environment]::ExpandEnvironmentVariables($item.InstallLocation)
        if (Test-ExcludedGameSource $folder $excludedRoots) { continue }
        if (-not (Test-Path -LiteralPath $folder -PathType Container -ErrorAction Stop)) { continue }
        $identity = $item.CatalogNamespace + ':' + $item.CatalogItemId + ':' + $item.AppName
        # Epic's protocol routes through its launcher, preserving its authentication / launch setup.
        $uri = 'com.epicgames.launcher://apps/' + [Uri]::EscapeDataString($identity) + '?action=launch&silent=true'
        $rule = Apply-Override $item.DisplayName $item.DisplayName $uri
        if ($rule.Category -eq 'HIDE') { continue }
        New-GameRecord $rule (Get-GameId 'epic' $identity) $source $folder 'platform'
    }
}

function Merge-GameSources($previous, $results, $platforms=$null) {
    $byId = @{}
    $allGames = [Collections.Generic.List[object]]::new()
    foreach ($result in $results) {
        $items = @($result.Games)
        if ($result.State -ne 'Success') {
            $items = @($previous | Where-Object Source -eq $result.Source | Where-Object {
                -not (Test-IsPlatformShortcut $_.Title $_.Path '' $platforms) -and
                -not (Test-IsPlatformShortcut $_.Title '' '' $platforms)
            } | ForEach-Object {
                $copy = $_ | Select-Object *
                $copy.Available = $false
                $copy
            })
        }
        foreach ($game in $items) { $allGames.Add($game) }
    }

    # Fortnite requires Epic authentication; its shipping executable is not a launch entry point.
    foreach ($game in $allGames) {
        if ($game.Source -like 'standalone:*' -and $game.Confidence -ne 'override' -and
            [IO.Path]::GetFileName($game.Path) -eq 'FortniteClient-Win64-Shipping.exe') {
            $epic = @($allGames | Where-Object {
                $_.Available -and $_.Path -match '^com\.epicgames\.launcher://apps/(?:[^?]*%3A|[^?]*:)?Fortnite\?'
            })
            $game.Aliases = @($game.Aliases) + @($game.Path, $game.Id)
            if ($epic.Count -eq 1) { $game.Path=$epic[0].Path; $game.Id=$epic[0].Id }
            else { $game.Path='com.epicgames.launcher://apps/Fortnite?action=launch&silent=true' }
            $game.Arguments=''; $game.WorkingDirectory=''; $game.Confidence='platform'
        }
    }
    $primaryGames = @($allGames | Where-Object { $_.Source -notlike 'desktop:*' })
    $desktopGames = @($allGames | Where-Object { $_.Source -like 'desktop:*' })

    foreach ($game in $primaryGames) {
        if (-not $byId.ContainsKey($game.Id) -or (-not $byId[$game.Id].Available -and $game.Available)) {
            $byId[$game.Id] = $game
        }
    }

    foreach ($game in $desktopGames) {
        if ($game.SteamInstallMissing -and -not $byId.ContainsKey($game.Id) -and
            -not @($results | Where-Object { $_.Source -like 'steam:*' -and $_.State -ne 'Success' }).Count) { continue }
        if ($byId.ContainsKey($game.Id)) {
            $existing = $byId[$game.Id]
            if (-not $existing.Available -and $game.Available) {
                $game.Aliases = @($game.Aliases) + @($existing.Path) + @($existing.Aliases)
                $byId[$game.Id] = $game
            } else {
                $existing.Aliases = @($existing.Aliases) + @($game.Path) + @($game.Aliases)
            }
            continue
        }

        $matchesByTarget = @()
        if ($game.Confidence -eq 'shortcut' -and $game.Path -like '*.lnk' -and
            -not $game.Arguments -and -not $game.WorkingDirectory) {
            $matchesByTarget = @($byId.Values | Where-Object {
                $_.Source -notlike 'desktop:*' -and $_.Available -and
                (-not $game.PresentationOverride -or ($_.Title -eq $game.Title -and $_.Category -eq $game.Category)) -and
                ($_.Path -in $game.Aliases -or
                    ($_.Confidence -eq 'metadata' -and $_.Folder -eq $game.Folder -and
                     $_.Title -eq $game.Title -and $_.Category -eq $game.Category -and
                     (Join-Path $_.Folder 'Launcher.exe') -in $game.Aliases)) -and -not $_.Arguments -and
                $_.WorkingDirectory -eq $game.Folder
            })
        }

        if ($matchesByTarget.Count -eq 1) {
            $match = $matchesByTarget[0]
            $match.Aliases = @($match.Aliases) + @($game.Path, $game.Id) + @($game.Aliases)
        } else {
            $byId[$game.Id] = $game
        }
    }

    foreach ($game in $byId.Values) {
        $old = @($previous | Where-Object Id -eq $game.Id)
        $aliases = @($game.Aliases) + @($old | ForEach-Object { $_.Path; $_.Aliases })
        $game.Aliases = @($aliases | Where-Object { $_ -and $_ -ne $game.Path } | Sort-Object -Unique)
        $game
    }
}

function Write-AtomicText([string]$path, [string]$text) {
    $temp = $path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp, $text, [Text.UTF8Encoding]::new($false))
        for ($attempt = 0; ; $attempt++) {
            try {
                if ([IO.File]::Exists($path)) { [IO.File]::Replace($temp, $path, [NullString]::Value) }
                else { [IO.File]::Move($temp, $path) }
                break
            } catch {
                # File watchers / virus scanners may briefly hold a handle without delete sharing.
                if ($attempt -ge 4 -or -not [IO.File]::Exists($temp)) { throw }
                Start-Sleep -Milliseconds 50
            }
        }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}
