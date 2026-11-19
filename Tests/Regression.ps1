# Run with Windows PowerShell or PowerShell 7. Test data stays in an isolated folder under Tests.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $PSScriptRoot ('.scratch-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null

function Assert-True($condition, [string]$message) {
    if (-not $condition) { throw $message }
}

try {
    $fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
    $winmd = Join-Path $env:WINDIR 'System32\WinMetadata'
    $testExe = Join-Path $scratch 'HelperRegression.exe'
    & "$fw\csc.exe" /nologo /target:exe /platform:anycpu /debug+ /optimize- /main:HelperRegression `
        "/out:$testExe" "/r:$fw\System.Runtime.WindowsRuntime.dll" "/r:$fw\System.Runtime.dll" `
        "/r:$fw\System.Runtime.InteropServices.WindowsRuntime.dll" `
        "/r:$fw\System.Management.dll" `
        "/r:$fw\System.Web.Extensions.dll" `
        "/r:$winmd\Windows.Foundation.winmd" "/r:$winmd\Windows.Media.winmd" "/r:$winmd\Windows.Storage.winmd" `
        (Join-Path $root '@Resources\SlateHUDHelper.cs') (Join-Path $root '@Resources\MediaHelper.cs') `
        (Join-Path $root '@Resources\ArtworkHelper.cs') (Join-Path $root '@Resources\TelemetryHelper.cs') `
        (Join-Path $root '@Resources\DisplayProbe.cs') (Join-Path $PSScriptRoot 'HelperRegression.cs')
    Assert-True ($LASTEXITCODE -eq 0) 'Helper test compilation failed'
    & $testExe $scratch
    Assert-True ($LASTEXITCODE -eq 0) 'Helper regression failed'

    $tokens = $null
    $parseErrors = $null
    $scanner = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root '@Resources\ScanGames.ps1'), [ref]$tokens, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) 'Scanner syntax errors'
    # Load only classification functions; never scan drives, call real endpoints, or write GameList.inc.
    foreach ($functionName in @('Resolve-GameMetadataCategory','Get-SteamCategory')) {
        $lookup = $scanner.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $true)
        . ([ScriptBlock]::Create($lookup.Extent.Text))
    }

    function Invoke-RestMethod {
        [CmdletBinding()]
        param([string]$Uri, [int]$TimeoutSec)
        $script:requests++
        if ($script:lookupMode -eq 'Offline') { throw 'Simulated timeout' }
        if ($Uri -like '*steamspy.com*') {
            if ($script:lookupMode -eq 'MixedStore') { throw 'Simulated SteamSpy outage' }
            if ($script:lookupMode -eq 'Mixed') { return ('{"tags":{"Shooter":10,"RPG":100}}' | ConvertFrom-Json) }
            if ($script:lookupMode -eq 'StoreOnly') { throw 'Simulated SteamSpy outage' }
            if ($script:lookupMode -eq 'Action') { return ('{"tags":{"Shooter":100}}' | ConvertFrom-Json) }
            return ('{"tags":{"Puzzle":100}}' | ConvertFrom-Json)
        }
        if ($script:lookupMode -eq 'Partial') { throw 'Simulated Store outage' }
        if ($script:lookupMode -eq 'MixedStore') { return ('{"123":{"success":true,"data":{"genres":[{"description":"Action"},{"description":"RPG"}]}}}' | ConvertFrom-Json) }
        if ($script:lookupMode -eq 'Invalid') { return ('{"123":{"success":false}}' | ConvertFrom-Json) }
        if ($script:lookupMode -eq 'StoreOnly') { return ('{"123":{"success":true,"data":{"genres":[{"description":"RPG"}]}}}' | ConvertFrom-Json) }
        return ('{"123":{"success":true,"data":{"genres":[{"description":"Casual"}]}}}' | ConvertFrom-Json)
    }

    $lookupDeadline = (Get-Date).AddMinutes(1)
    $genreCache = @{}
    $scanNoNetwork = $false
    $signals = @([pscustomobject]@{Name='Shooter';Weight=10}, [pscustomobject]@{Name='RPG';Weight=100})
    Assert-True ((Resolve-GameMetadataCategory @([pscustomobject]@{Name='Anime';Weight=100},[pscustomobject]@{Name='Gacha';Weight=100})) -eq '') 'Visual style or monetization assigned a genre'
    Assert-True ((Resolve-GameMetadataCategory @([pscustomobject]@{Name='Adventure';Weight=100})) -eq 'RPG') 'Adventure did not map to RPG & Adventure'
    Assert-True ((Resolve-GameMetadataCategory $signals) -eq 'RPG') 'Weak shooter tag beat the dominant RPG signal'
    [array]::Reverse($signals)
    Assert-True ((Resolve-GameMetadataCategory $signals) -eq 'RPG') 'Property order changed classification'
    $signals = @([pscustomobject]@{Name='RPG';Weight=10}, [pscustomobject]@{Name='Action';Weight=100})
    Assert-True ((Resolve-GameMetadataCategory $signals) -eq 'ACTION') 'Strong Action tag was ignored'
    $signals = @(1..8 | ForEach-Object { [pscustomobject]@{Name="Unknown$_";Weight=1} })
    $signals += [pscustomobject]@{Name='Strategy';Weight=100}
    Assert-True ((Resolve-GameMetadataCategory $signals) -eq 'STRATEGY') 'Strong signal beyond the first eight tags was ignored'
    $signals = @('Action','Simulation','RPG' | ForEach-Object { [pscustomobject]@{Name=$_;Weight=1} })
    Assert-True ((Resolve-GameMetadataCategory $signals) -eq 'RPG') 'Equal-weight category tie changed'
    $signals = @('Action','Simulation' | ForEach-Object { [pscustomobject]@{Name=$_;Weight=1} })
    Assert-True ((Resolve-GameMetadataCategory $signals) -eq 'STRATEGY') 'Strategy/Action tie changed'
    $signals = @([pscustomobject]@{Name='RPG';Weight=100}, [pscustomobject]@{Name='Shooter';Weight=60}, [pscustomobject]@{Name='FPS';Weight=60})
    Assert-True ((Resolve-GameMetadataCategory $signals) -eq 'RPG') 'Overlapping tags double-counted votes'
    $signals = @('bad','NaN','Infinity','-1','0' | ForEach-Object { [pscustomobject]@{Name='RPG';Weight=$_} })
    $signals += [pscustomobject]@{Name='Not RPG';Weight=100}
    Assert-True ((Resolve-GameMetadataCategory $signals) -eq '') 'Invalid weights or partial tag names classified'
    $lookupMode = 'Mixed'
    Assert-True ((Get-SteamCategory '123') -eq 'RPG' -and $genreCache['123'].Source -eq 'SteamSpy') 'Weighted lookup or provenance failed'
    $genreCache.Clear()
    $lookupMode = 'MixedStore'
    Assert-True ((Get-SteamCategory '123') -eq 'RPG' -and $genreCache['123'].Source -eq 'SteamStore') 'Mixed genre Store fallback disagreed'
    $genreCache['123'].Version = 2
    $lookupMode = 'Action'
    Assert-True ((Get-SteamCategory '123') -eq 'ACTION' -and $genreCache['123'].Version -eq 3) 'Unexpired old classifier cache was not refreshed'
    $genreCache.Clear()
    Write-Output 'PASS: Weighted genres, deterministic ties, tag order, invalid signals, provider fallback and classifier migration'
    $genreCacheDirty = $false
    $requests = 0
    $lookupMode = 'Offline'
    Assert-True ((Get-SteamCategory '123') -eq '') 'Offline lookup returned a category'
    Assert-True (-not $genreCache.ContainsKey('123')) 'Timeout cached permanently'
    $lookupMode = 'Action'
    Assert-True ((Get-SteamCategory '123') -eq 'ACTION') 'Offline lookup did not recover'
    $before = $requests
    Assert-True ((Get-SteamCategory '123') -eq 'ACTION' -and $requests -eq $before) 'Positive cache missed'

    $genreCache['123'] = 'ACTION'
    $lookupMode = 'Offline'
    Assert-True ((Get-SteamCategory '123') -eq 'ACTION') 'Outage discarded a legacy positive category'
    $scanNoNetwork = $true
    $before = $requests
    Assert-True ((Get-SteamCategory '123') -eq 'ACTION' -and $requests -eq $before) 'Offline mode did not use the last known category'
    $scanNoNetwork = $false
    $lookupMode = 'StoreOnly'
    Assert-True ((Get-SteamCategory '123') -eq 'RPG' -and $genreCache['123'].Version -eq 3) 'Legacy positive category was not refreshed'
    $genreCache['123'].ExpiresUtc = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
    $lookupMode = 'Offline'
    Assert-True ((Get-SteamCategory '123') -eq 'RPG') 'Expired positive category was lost during an outage'
    $lookupMode = 'Action'
    Assert-True ((Get-SteamCategory '123') -eq 'ACTION') 'Expired positive category did not refresh'

    $genreCache['123'] = 'OTHER'
    Assert-True ((Get-SteamCategory '123') -eq 'ACTION') 'Legacy OTHER was not retried'
    $genreCache.Clear()
    $lookupMode = 'Partial'
    Assert-True ((Get-SteamCategory '123') -eq '') 'Partial lookup returned unexpected category'
    Assert-True (-not $genreCache.ContainsKey('123')) 'Partial outage was cached'
    $lookupMode = 'Invalid'
    $null = Get-SteamCategory '123'
    Assert-True (-not $genreCache.ContainsKey('123')) 'Invalid Store response was cached'
    $lookupMode = 'StoreOnly'
    Assert-True ((Get-SteamCategory '123') -eq 'RPG') 'Store fallback failed'

    $genreCache.Clear()
    $lookupMode = 'Unknown'
    $null = Get-SteamCategory '123'
    Assert-True ($genreCache['123'].Category -eq 'OTHER') 'Successful unknown category not cached'
    # Exercise the object shape produced by saving and reloading the JSON cache.
    $saved = $genreCache | ConvertTo-Json | ConvertFrom-Json
    $genreCache['123'] = $saved.'123'
    $before = $requests
    $null = Get-SteamCategory '123'
    Assert-True ($requests -eq $before) 'Unexpired OTHER cache missed'
    $genreCache['123'].ExpiresUtc = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
    $lookupMode = 'Action'
    Assert-True ((Get-SteamCategory '123') -eq 'ACTION') 'Expired OTHER was not retried'
    $genreCache.Clear()
    $lookupDeadline = (Get-Date).AddSeconds(-1)
    $before = $requests
    $null = Get-SteamCategory '123'
    Assert-True ($requests -eq $before -and $genreCache.Count -eq 0) 'Expired scan budget attempted a lookup'
    Write-Output 'PASS: Genre outages, recovery, legacy cache migration, expiry, deadline, Store fallback'

    # Use a separate scope so fixture mocks cannot affect the helper/genre checks above.
    & (Join-Path $PSScriptRoot 'GameScannerRegression.ps1')
}
finally {
    # Only remove the exact, resolved temporary directory created by this invocation.
    $resolved = [IO.Path]::GetFullPath($scratch)
    $testRoot = [IO.Path]::GetFullPath($PSScriptRoot)
    if ([IO.Path]::GetDirectoryName($resolved).Equals($testRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved) -like '.scratch-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
