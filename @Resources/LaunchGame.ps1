[CmdletBinding()]
param([ValidatePattern('^(steam:[0-9]+|hoyo:[a-z0-9]+|(folder|epic|legacy|shortcut):[a-f0-9]{64})$')][string]$Id,
    [switch]$LibraryOnly, [string]$CatalogPath = '', [switch]$OpenFolder,
    [ValidatePattern('^(legacy|[a-f0-9]{32})?$')][string]$Revision = '')

if (-not $CatalogPath) { $CatalogPath = Join-Path $PSScriptRoot 'Cache\game_library.json' }
. (Join-Path $PSScriptRoot 'GameDiscovery.ps1')

function Start-CatalogGame([string]$CatalogPath, [string]$Id, [switch]$OpenFolder, [string]$Revision = '') {
    $ErrorActionPreference = 'Stop'
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $CatalogPath))
    $include = Join-Path $root 'Games\GameList.inc'
    $published = if (Test-Path -LiteralPath $include) { Get-Content -LiteralPath $include -Raw -Encoding UTF8 }
    $publishedRevision = Get-GameLibraryRevision $published
    $currentRevision = if ($publishedRevision) { $publishedRevision } else { 'legacy' }
    if ($Revision -and $Revision -cne $currentRevision) {
        throw [InvalidOperationException]::new('GAMEHUB:STALE')
    }
    if ($publishedRevision) {
        $games = @(Read-GeneratedGames $include $published)
    } elseif (Test-Path -LiteralPath $CatalogPath) {
        $catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        # A revisioned catalog paired with a legacy include has not been published.
        $games = if ($catalog.Revision) { @(Read-GeneratedGames $include $published) } else { @($catalog.Games) }
    } else {
        $games = @(Read-GeneratedGames $include $published)
    }
    $game = @($games | Where-Object Id -eq $Id | Select-Object -First 1)
    if (-not $game.Count) { throw 'Game unavailable. Scan to retry or correct its override.' }
    $game = $game[0]
    if ($OpenFolder) {
        if (-not $game.Folder) { throw 'No installation folder is recorded for this game.' }
        if (-not (Test-Path -LiteralPath $game.Folder -PathType Container)) { throw 'Installation folder is unavailable.' }
        Start-Process -FilePath $game.Folder -ErrorAction Stop
        return
    }
    if (-not $game.Available) { throw 'Game unavailable. Scan to retry or correct its override.' }
    if ($game.Folder -and -not (Test-Path -LiteralPath $game.Folder -PathType Container)) { throw 'Installation folder is unavailable.' }
    $parameters = @{ FilePath=$game.Path; ErrorAction='Stop' }
    if ($game.Path -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        if (-not (Test-Path -LiteralPath $game.Path -PathType Leaf)) { throw 'Launch target is missing. Scan or correct its override.' }
        if ($game.WorkingDirectory) {
            if (-not (Test-Path -LiteralPath $game.WorkingDirectory -PathType Container)) { throw 'Working directory is missing.' }
            $parameters.WorkingDirectory = $game.WorkingDirectory
        }
    }
    if ($game.Arguments) { $parameters.ArgumentList = $game.Arguments }
    # Start-Process returns after creation. Rainmeter never owns or waits for the game.
    Start-Process @parameters
}

if (-not $LibraryOnly) {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    try {
        Start-CatalogGame $CatalogPath $Id -OpenFolder:$OpenFolder -Revision $Revision
        if ($OpenFolder) { Write-Output 'GAMEHUB:FOLDER' } else { Write-Output 'GAMEHUB:LAUNCHED' }
    }
    catch {
        if ($_.Exception.Message -ceq 'GAMEHUB:STALE') { Write-Output 'GAMEHUB:STALE' }
        else { Write-Output ('GAMEHUB:FAILED ' + $_.Exception.Message) }
        exit 1
    }
}
