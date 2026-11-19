# Theme and Accent Regression Test
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-True($cond, [string]$msg) {
    if (-not $cond) { throw "FAIL: $msg" }
}

$themes = @('Default', 'Cyberpunk', 'NordFrost', 'TokyoNight', 'Monochrome', 'WindowsAccent')
$requiredKeys = @('ThemeName', 'ColorAccent', 'CardFill', 'CardStroke', 'BarBack', 'VisualizerGradient',
    'ColorHistory2', 'ColorDivider', 'ColorPill', 'ColorSwitchFill', 'ColorInputFill', 'ColorCoverFill', 'ColorCoverNote', 'ColorCheckboxEmpty')

foreach ($theme in $themes) {
    $file = Join-Path $root "@Resources\Themes\$theme.inc"
    Assert-True (Test-Path $file) "Theme file missing: $file"
    $text = [IO.File]::ReadAllText($file)
    Assert-True ($text -match '\[Variables\]') "Theme $theme missing [Variables] section"
    foreach ($key in $requiredKeys) {
        Assert-True ($text -match "(?m)^$key=") "Theme $theme missing key $key"
    }
}
$monoText = [IO.File]::ReadAllText((Join-Path $root "@Resources\Themes\Monochrome.inc"))
Assert-True ($monoText -match '(?m)^ColorAccent=([^\r\n]+)' -and ($monoAccent = $Matches[1].Trim()) -ne '' -and
    $monoText -match '(?m)^ColorPrimary=([^\r\n]+)' -and $Matches[1].Trim() -ne $monoAccent) "Monochrome.inc must keep ColorAccent distinct from ColorPrimary"
Write-Output "PASS: All 6 themes defined with required palette keys"

# Test Variables.inc theme inclusion and default visual settings
$varFile = Join-Path $root "@Resources\Variables.inc"
$varText = [IO.File]::ReadAllText($varFile)
Assert-True ($varText -match 'CurrentTheme=') "Variables.inc missing CurrentTheme"
Assert-True ($varText -match '@IncludeTheme=#@#Themes\\#CurrentTheme#\.inc') "Variables.inc missing @IncludeTheme"
Assert-True ($varText -match '@IncludeUserSettings=#@#UserSettings\.inc') "Variables.inc missing @IncludeUserSettings"
$idxUser = $varText.IndexOf('@IncludeUserSettings=#@#UserSettings.inc')
foreach ($derivedKey in @('ActiveFrameW=', 'ActiveFrameH=', 'CardPadX=', 'CardPadY=', 'CardShiftX=', 'CardShiftY=', 'LayoutRowWidth=', 'UiScale=', 'CardFill=', 'ColorCoverFill=', '@IncludeTheme=', '@IncludeBlur=')) {
    $m = [regex]::Match($varText, "(?m)^" + [regex]::Escape($derivedKey))
    Assert-True ($idxUser -ge 0 -and $m.Success -and $m.Index -gt $idxUser) "Variables.inc must include UserSettings.inc before $derivedKey"
}
Assert-True ($varText -match '(?m)^UiScale=.*#LayoutRowWidth#' -and $varText -notmatch '(?m)^UiScale=.*\b1514\b') "Variables.inc UiScale must derive from #LayoutRowWidth# instead of hardcoded 1514"
Assert-True ($varText -notmatch '(?im)^[^;\r\n]*C:\\Users\\') "Variables.inc still contains user-specific C:\Users path"
Assert-True ($varText -notmatch '(?im)^GamesFolder=D:\\Games\r?$') "Variables.inc still hardcodes author GamesFolder=D:\Games"
Assert-True ($varText -notmatch '(?im)^GamesExcludedDrives=G:\r?$') "Variables.inc still hardcodes author GamesExcludedDrives=G:"
Assert-True ($varText -notmatch '(?im)^XXMILauncher=D:\\Application\\') "Variables.inc still hardcodes author XXMILauncher path"
Assert-True ($varText -match '(?m)^AcrylicBlur=(Acrylic|Blur|None)\r?$') "Variables.inc AcrylicBlur must be literal Acrylic, Blur, or None"
Assert-True ($varText -match '(?m)^BlurFile=([^\r\n]*)\r?$') "Variables.inc missing BlurFile"
$blurValue = $Matches[1].Trim()
Assert-True ($blurValue -eq '' -or $blurValue -eq '#@#Blur.inc') "Variables.inc BlurFile must be empty or #@#Blur.inc (got: $blurValue)"
Assert-True ($blurValue -notmatch '[\(\)]' -and $blurValue -notmatch '^[A-Za-z]:\\') "Variables.inc BlurFile must be unexpanded or empty (got: $blurValue)"
Assert-True ($varText -match '(?m)^CardOpacity=(\d+)\r?$') "Variables.inc CardOpacity invalid"
$cardOpacity = [int]$Matches[1]
Assert-True ($cardOpacity -ge 0 -and $cardOpacity -le 255) "Variables.inc CardOpacity out of 0..255 range: $cardOpacity"
foreach ($expectedLine in @(
    'CurrentTheme=Default',
    'disk1=C:',
    'disk2=D:',
    'disk3=E:',
    'NetPingEnabled=0',
    'BlurPlugin=FrostBehind',
    'BlurCorner=Round',
    'BlurTightFrame=0',
    'UiAnimations=0',
    'UiAnimationsBatterySaver=1',
    'SysSensorProvider=auto',
    'SysLhmEnabled=0',
    'LhmSource=auto',
    'LhmEndpoint=http://127.0.0.1:8085/data.json',
    'GamesFolder=C:\Games',
    'GamesExcludedDrives=',
    'XXMILauncher=',
    'StatCardW=222',
    'StatCardH=168',
    'BatteryCardH=110',
    'WideCardW=320',
    'MediaCardH=140',
    'VisualizerCardH=44',
    'CardFrameW=16',
    'CardFrameH=24',
    'CardGap=8',
    'IconRailW=80',
    'AppMaxCardH=540',
    'ColorHistory2=130,170,255,230',
    'ColorDivider=255,255,255,20',
    'ColorPill=255,255,255,7',
    'ColorSwitchFill=255,255,255,14',
    'ColorInputFill=25,25,32'
)) {
    Assert-True ($varText -match ("(?m)^" + [regex]::Escape($expectedLine) + "\r?$")) "Variables.inc missing expected default/geometry key: $expectedLine"
}
Write-Output "PASS: Variables.inc correctly wires CurrentTheme, UserSettings.inc overlay, portable defaults, layout metrics, AcrylicBlur, BlurFile, and CardOpacity"

# Test WindowsAccent.inc format (generate if absent on clean checkout)
$accentFile = Join-Path $root "@Resources\Cache\WindowsAccent.inc"
if (-not (Test-Path $accentFile)) {
    $helperExe = Join-Path $root "@Resources\SlateHUDHelper.exe"
    Assert-True (Test-Path $helperExe) "SlateHUDHelper.exe missing for WindowsAccent.inc generation (run @Resources\build.ps1 first)"
    & $helperExe ensure | Out-Null
}
Assert-True (Test-Path $accentFile) "Cache\WindowsAccent.inc missing"
$accentText = [IO.File]::ReadAllText($accentFile)
Assert-True ($accentText -match 'WindowsAccentColor=\d+,\d+,\d+,255') "WindowsAccentColor format invalid"
Assert-True ($accentText -match 'WindowsAccentGradient=270 \|') "WindowsAccentGradient format invalid"
foreach ($accKey in @('WindowsAccentR=', 'WindowsAccentG=', 'WindowsAccentB=', 'WindowsAccentStroke=', 'WindowsAccentBarBack=', 'WindowsAccentCardFill=', 'WindowsAccentHistory2=')) {
    Assert-True ($accentText -match "(?m)^$accKey") "Cache\WindowsAccent.inc missing key $accKey"
}
Write-Output "PASS: WindowsAccent.inc generated and correctly formatted"

# Test Context.inc and skin-specific context slot boundaries
$ctxFile = Join-Path $root "@Resources\Context.inc"
$ctxText = [IO.File]::ReadAllText($ctxFile)
Assert-True ($ctxText -match 'Theme: Cyberpunk') "Context.inc missing Cyberpunk option"
Assert-True ($ctxText -match 'Theme: Nord Frost') "Context.inc missing Nord Frost option"
Assert-True ($ctxText -match 'Theme: Tokyo Night') "Context.inc missing Tokyo Night option"
Assert-True ($ctxText -match 'Theme: Monochrome Stealth') "Context.inc missing Monochrome option"
Assert-True ($ctxText -match 'Theme: Windows Accent Sync') "Context.inc missing Windows Accent option"
$blurFile = Join-Path $root "@Resources\Blur.inc"
$blurText = [IO.File]::ReadAllText($blurFile)
Assert-True ($blurText -match '\[MeasureBlur\]' -and $blurText -match '(?m)^Plugin=#BlurPlugin#\r?$' -and
    $blurText -match '(?m)^Type=#AcrylicBlur#\r?$' -and $blurText -match '(?m)^Corner=#BlurCorner#\r?$') "Blur.inc must define [MeasureBlur] with #BlurPlugin#, #AcrylicBlur#, and #BlurCorner#"
$hwinfoFile = Join-Path $root "@Resources\HWiNFO.inc"
Assert-True (-not (Test-Path $hwinfoFile)) "Retired HWiNFO.inc must be removed"
$sysIniText = [IO.File]::ReadAllText((Join-Path $root "System\System.ini"))
Assert-True ($sysIniText -notmatch '@IncludeHWiNFO') "System.ini must not reference @IncludeHWiNFO"
Assert-True ($sysIniText -match 'Toggle LHM sensors' -and $sysIniText -match 'GPU sensor priority:') "System.ini missing LHM context menu actions"
Assert-True ($varText -notmatch '@IncludeHWiNFO|HWiNFOFile|HWiNFO') "Variables.inc must not retain retired HWiNFO keys"

Assert-True ($ctxText -match 'Blur: DWM Acrylic' -and $ctxText -match 'BlurTightFrame 1') "Context.inc missing explicit Acrylic + tight-frame preset"
Assert-True ($ctxText -match 'Blur: Off' -and $ctxText -match 'BlurTightFrame 0') "Context.inc missing explicit Blur Off preset"
Assert-True ($ctxText -notmatch 'Blur: Toggle DWM Acrylic') "Context.inc still has broken formula toggle"
Assert-True ($ctxText -match 'ContextTitle18=Blur: Off') "Context.inc suite menu must end at slot 18"
Assert-True ($ctxText -match '#@#UserSettings\.inc' -and $ctxText -notmatch '#@#Variables\.inc') "Context.inc must write overrides to UserSettings.inc, not Variables.inc"

$ctxMenuLua = [IO.File]::ReadAllText((Join-Path $root "@Resources\ContextMenu.lua"))
Assert-True ($ctxMenuLua -match "Blur: DWM Acrylic" -and $ctxMenuLua -match "Blur: Off" -and $ctxMenuLua -match "BlurTightFrame 1" -and $ctxMenuLua -match "BlurTightFrame 0") "ContextMenu.lua out of sync with Context.inc"
Assert-True ($ctxMenuLua -match '#@#UserSettings\.inc' -and $ctxMenuLua -notmatch '#@#Variables\.inc') "ContextMenu.lua must write overrides to UserSettings.inc, not Variables.inc"

foreach ($ctxMatch in [regex]::Matches($ctxText, '(?m)^ContextTitle(\d*)=([^\r\n]*)')) {
    $titleVal = $ctxMatch.Groups[2].Value
    if ($titleVal -ne '---') {
        Assert-True (($titleVal.Length + 2) -le 30) "Context.inc title exceeds Rainmeter 30-char limit with '* ' prefix: $titleVal"
    }
}
foreach ($skinRel in @("System\System.ini", "Network\Network.ini")) {
    $skinText = [IO.File]::ReadAllText((Join-Path $root $skinRel))
    foreach ($m in [regex]::Matches($skinText, '(?m)^ContextTitle(\d*)=([^\r\n]*)')) {
        $slot = if ($m.Groups[1].Value -eq '') { 1 } else { [int]$m.Groups[1].Value }
        $titleVal = $m.Groups[2].Value
        Assert-True ($slot -ge 19 -and $slot -le 25) "$skinRel ContextTitle$slot collides with Context.inc (1..18) or exceeds Rainmeter 25-slot limit"
        Assert-True ($titleVal.Length -le 30) "$skinRel ContextTitle$slot exceeds Rainmeter 30-char limit: $titleVal"
    }
}
$allSkinInis = @(
    "NowPlaying.ini",
    "Apps\Apps.ini",
    "Games\Games.ini",
    "Notes\Notes.ini",
    "System\System.ini",
    "Network\Network.ini",
    "Disks\Disks.ini",
    "Battery\Battery.ini",
    "Visualizer\Visualizer.ini",
    "Visualizer\Idle.ini",
    "Visualizer\Suspended.ini"
)
foreach ($skinRel in $allSkinInis) {
    $skinPath = Join-Path $root $skinRel
    Assert-True (Test-Path $skinPath) "Missing skin ini: $skinRel"
    $skinText = [IO.File]::ReadAllText($skinPath)
    Assert-True ($skinText -match '(?m)^License=MIT\r?$') "$skinRel missing License=MIT in [Metadata]"
}
$economyText = [IO.File]::ReadAllText((Join-Path $root "Visualizer\Economy.ini"))
Assert-True ($economyText -match '(?m)^@Include=Visualizer\.ini\r?$') "Visualizer\Economy.ini must inherit Visualizer.ini metadata"
$nowPlayingText = [IO.File]::ReadAllText((Join-Path $root "NowPlaying.ini"))
Assert-True ($nowPlayingText -match '#WideCardW#' -and $nowPlayingText -match '#MediaCardH#') "NowPlaying.ini must reference #WideCardW# and #MediaCardH#"
$appsIniText = [IO.File]::ReadAllText((Join-Path $root "Apps\Apps.ini"))
Assert-True ($appsIniText -match '#WideCardW#' -and $appsIniText -notmatch '\(320\*#UiScale#\)') "Apps\Apps.ini must reference #WideCardW#"
$gamesIniText = [IO.File]::ReadAllText((Join-Path $root "Games\Games.ini"))
Assert-True ($gamesIniText -match '(?m)^GameCardW=#WideCardW#\r?$') "Games\Games.ini GameCardW must reference #WideCardW#"
Assert-True ($gamesIniText -match '(?m)^Program="#@#SlateHUDHelper\.exe"\r?$' -and $gamesIniText -match '(?m)^Parameter=launchgame ') "Games\Games.ini [MeasureLaunch] must invoke SlateHUDHelper.exe launchgame"
Assert-True (Test-Path -LiteralPath (Join-Path $root "@Resources\Plugin\SlateHUD.cpp") -PathType Leaf) "Missing native plugin source @Resources\Plugin\SlateHUD.cpp"
Assert-True (Test-Path -LiteralPath (Join-Path $root "@Resources\Plugins\SlateHUD.dll") -PathType Leaf) "Missing built native plugin @Resources\Plugins\SlateHUD.dll (run @Resources\build.ps1 first)"
foreach ($bridgeCheck in @(
    @{ Rel = "NowPlaying.ini"; Sections = @("\[MeasureMediaBridge\]", "\[MeasureMediaHealthBridge\]", "\[MeasureHealthBridge\]") },
    @{ Rel = "System\System.ini"; Sections = @("\[MeasureGpuBridge\]", "\[MeasureMonitorsBridge\]", "\[MeasureHealthBridge\]") },
    @{ Rel = "Visualizer\Visualizer.ini"; Sections = @("\[MeasureMonitorsBridge\]") },
    @{ Rel = "Visualizer\Idle.ini"; Sections = @("\[MeasureMonitorsBridge\]") }
)) {
    $t = [IO.File]::ReadAllText((Join-Path $root $bridgeCheck.Rel))
    foreach ($sec in $bridgeCheck.Sections) {
        Assert-True ($t -match $sec) "$($bridgeCheck.Rel) missing $sec plugin bridge measure"
    }
}
$visIniText = [IO.File]::ReadAllText((Join-Path $root "Visualizer\Visualizer.ini"))
Assert-True ($visIniText -match '(?m)^CardW=#WideCardW#\r?$' -and $visIniText -match '(?m)^CardH=#VisualizerCardH#\r?$') "Visualizer\Visualizer.ini must reference #WideCardW# and #VisualizerCardH#"
$idleIniText = [IO.File]::ReadAllText((Join-Path $root "Visualizer\Idle.ini"))
Assert-True ($idleIniText -match '(?m)^CardW=#WideCardW#\r?$' -and $idleIniText -match '(?m)^CardH=#VisualizerCardH#\r?$') "Visualizer\Idle.ini must reference #WideCardW# and #VisualizerCardH#"
$suspendedIniText = [IO.File]::ReadAllText((Join-Path $root "Visualizer\Suspended.ini"))
Assert-True ($suspendedIniText -match '#WideCardW#' -and $suspendedIniText -match '#VisualizerCardH#' -and $suspendedIniText -notmatch '(?m)^Plugin=AudioLevel\r?$') "Visualizer\Suspended.ini must use shared card variables with zero AudioLevel measures"
$notesIniText = [IO.File]::ReadAllText((Join-Path $root "Notes\Notes.ini"))
Assert-True ($notesIniText -match '(?m)^NotesCardH=216\r?$' -and $notesIniText -match '#NotesCardH#' -and $notesIniText -match '#StatCardW#' -and $notesIniText -match '#ActiveFrameW#' -and $notesIniText -notmatch '\((216|238)\*#UiScale#\)') "Notes\Notes.ini must parameterize #NotesCardH#, #StatCardW#, and #ActiveFrameW#"
foreach ($padSkin in @("NowPlaying.ini", "Apps\Apps.ini", "Games\Games.ini", "Notes\Notes.ini", "System\System.ini", "Network\Network.ini", "Disks\Disks.ini", "Battery\Battery.ini", "Visualizer\Appearance.inc", "Visualizer\Suspended.ini")) {
    $padText = [IO.File]::ReadAllText((Join-Path $root $padSkin))
    Assert-True ($padText -match '#CardPadX#' -and $padText -match '#CardPadY#' -and $padText -match '#ActiveFrameW#' -and $padText -match '#ActiveFrameH#') "$padSkin must parameterize blur-tight card padding (#CardPadX#, #CardPadY#, #ActiveFrameW#, #ActiveFrameH#)"
    Assert-True ($padText -notmatch '(?m)^X=\(8\*#UiScale#\)\r?$') "$padSkin still hardcodes literal X=(8*#UiScale#)"
}
foreach ($animSkin in @("NowPlaying.ini", "Apps\Apps.ini", "Games\Games.ini")) {
    $animText = [IO.File]::ReadAllText((Join-Path $root $animSkin))
    Assert-True ($animText -match '(?m)^Plugin=ActionTimer\r?$' -and $animText -match '\[MeasureAnimPower\]') "$animSkin missing ActionTimer or MeasureAnimPower"
}
Write-Output "PASS: Context menu includes all themes, explicit Blur presets, collision-free slots, MIT skin metadata, and unified skin metrics"
