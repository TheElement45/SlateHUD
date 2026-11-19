; ==============================================================================
; SlateHUD shared variables - edit THIS file to re-theme every skin.
; Loaded with: @Include=#@#Variables.inc  (inside each skin's [Variables])
; ==============================================================================
[Variables]
; --- Fonts ---
fontName=Segoe UI
iconFont=Segoe Fluent Icons
; Preferred size is preserved when displays change. UiScale is the fitted size.
PreferredUiScale=1.125
; Automatic compact size for laptop displays or work areas narrower than 1700 pixels.
; Kept separate so reconnecting the external display restores PreferredUiScale.
LaptopUiScale=0.95
; Legacy fallback when the helper cannot read the desktop. 0 = primary.
LayoutMonitor=0
; auto moves to the laptop during external fullscreen use.
LayoutPlacement=auto
; Optional display identities from Cache/monitors.txt for setups with multiple external displays.
LayoutExternalId=
LayoutLaptopId=
LayoutMode=0
; Runtime width is shared by all skins; Layout.lua updates it on display changes.
LayoutWorkWidth=#PWORKAREAWIDTH#
LayoutIsLaptop=0
LayoutStateFile=#@#Cache/Display.inc

; --- Active Theme & Visual Effects ---
CurrentTheme=Default
AcrylicBlur=None
BlurFile=
BlurPlugin=FrostBehind
BlurCorner=Round
BlurTightFrame=0
UiAnimations=0
UiAnimationsBatterySaver=1

; --- Colors (R,G,B,A) ---
ColorAccent=235,170,0,255
ColorPrimary=255,255,255,255
ColorSecondary=255,255,255,195
ColorMuted=255,255,255,130
colorText=255,255,255,235

; --- Card look (lower the last number of CardFill for MORE transparency) ---
; Change presets from any card's right-click menu.
CardOpacity=180
CardStroke=255,255,255,30
CardRadius=10
BarBack=255,255,255,22
ColorHistory2=130,170,255,230
ColorDivider=255,255,255,20
ColorPill=255,255,255,7
ColorSwitchFill=255,255,255,14
ColorInputFill=25,25,32
ColorCoverNote=255,255,255,60
ColorCheckboxEmpty=255,255,255,65

; --- Card & layout geometry (logical pixels before UiScale) ---
StatCardW=222
StatCardH=168
BatteryCardH=110
WideCardW=320
MediaCardH=140
VisualizerCardH=44
CardFrameW=16
CardFrameH=24
CardGap=8
IconRailW=80

; --- Drives monitored by Disks widget (override in UserSettings.inc) ---
disk1=C:
disk2=D:
disk3=E:

; --- Network (see README.md: Network Widget) ---
; 1 = show ping latency to pingHost, 0 = hidden (toggle via Network right-click menu)
NetPingEnabled=0
; WAN IPv4 shown on the desktop: measureIPMasked = hidden (hover to reveal), measureIP = always visible
NetIPDisplay=measureIPMasked
; 1 = bars scale to observed peak traffic; 0 = use the fixed limits below.
; Click Auto / Fixed on the Network card to toggle and save the mode.
NetAutoScale=1
; Fixed-mode speed-bar limits in bytes/sec (set for a 1 Gbps plan).
; Used when NetAutoScale=0; a limit of 0 keeps that direction auto-scaled in either mode.
; Examples: 100 Mbps = 12500000, 300 Mbps = 37500000, 1 Gbps = 125000000
maxDownload=125000000
maxUpload=125000000

; --- Warning colors & thresholds ---
ColorWarn=255,190,40,255
ColorCrit=255,75,75,255
WarnUsage=80
CritUsage=95
WarnTemp=75
CritTemp=85
WarnMem=80
CritMem=92
WarnDisk=85
CritDisk=95
; Decimal GB remaining (1 GB = 1,000,000,000 bytes). 0 disables a threshold.
WarnDiskFreeGB=20
CritDiskFreeGB=5
WarnPing=80
CritPing=150

; --- Adaptive display layout ---
; LayoutMonitor and LayoutMode are set above, before the fitted-size formula.
; LayoutMode 0 = fit one top row, 1 = shelf wrapping at the preferred size.
; Logical gap below Game Hub. Coordinates and card geometry scale with UiScale.
NotesGap=24

; --- Battery thresholds (percent remaining; LOW values are bad) ---
WarnBatt=30
CritBatt=15

; --- Paths shared by Games.ini and ScanGames.ps1 (override in UserSettings.inc) ---
; Folder holding standalone games (and the HoYoPlay folder).
; Example override in UserSettings.inc: GamesFolder=D:\Games
GamesFolder=C:\Games
; Optional additional standalone roots, separated by | (example: E:\Games|F:\Games).
GamesFolders=
; Cloud / virtual drives excluded from discovery, including saved Steam sources. Comma separated.
; Example override in UserSettings.inc: GamesExcludedDrives=G:
GamesExcludedDrives=
; Game Hub and Apps icon grid limits: maximum card heights and room kept below Game Hub for Notes.
GameMaxCardH=480
AppMaxCardH=540
GameNotesReserve=260
; Show the Recent category (up to four successful launches from this widget).
GameShowRecent=1
; Optional extra launcher shown in the Game Hub platform list (leave empty or missing to hide it).
; Example override in UserSettings.inc: XXMILauncher=D:\Application\XXMI\Resources\Bin\XXMI Launcher.exe
XXMILauncher=

; Clicking the idle music title opens this app (an executable path or URI).
MusicApp=%LOCALAPPDATA%\Programs\youtube-music\YouTube Music.exe
MusicAppName=YouTube Music

; Disk activity ceiling in bytes/sec (1 GiB/s). Capacity tooltips keep used/total.
DiskActivityMax=1073741824
; Optional network and system history strips (0=compact, 1=show).
NetHistory=0
SysHistory=0
; System sensor provider: auto (NVML primary + LibreHardwareMonitor fallback/CPU temp), nvml, or lhm.
SysSensorProvider=auto
SysLhmEnabled=0
LhmSource=auto
LhmEndpoint=http://127.0.0.1:8085/data.json
; Frame intervals in milliseconds: 40=25 fps, 33=30 fps, 50=20 fps.
; Battery defaults to about 15 fps; idle retains 4 wake checks/sec.
VisualizerUpdate=40
VisualizerBatteryUpdate=66
VisualizerBatterySaver=1
VisualizerHideIdle=0
VisualizerSensitivity=45
VisualizerAttack=15
VisualizerDecay=130
; Idle baseline uses this theme gradient at 25% of each stop's alpha.
VisualizerGradient=270 | 255,220,95,255 ; 0.0 | 240,175,15,255 ; 0.55 | 215,110,10,220 ; 1.0


; --- Runtime Display State & User Overrides (git-ignored) ---
@IncludeLayoutState=#LayoutStateFile#
@IncludeUserSettings=#@#UserSettings.inc

; --- Derived Formulas & Active Theme Palette ---
ActiveFrameW=(#BlurTightFrame#=1 ? 0 : #CardFrameW#)
ActiveFrameH=(#BlurTightFrame#=1 ? 0 : #CardFrameH#)
CardPadX=(#BlurTightFrame#=1 ? 0 : Floor(#CardFrameW#/2))
CardPadY=(#BlurTightFrame#=1 ? 0 : (#CardFrameH#-Floor(#CardFrameW#/2)))
CardShiftX=(#CardPadX#-Floor(#CardFrameW#/2))
CardShiftY=(#CardPadY#-(#CardFrameH#-Floor(#CardFrameW#/2)))
; Logical row width covers two wide cards, three stat cards, six gaps, and the icon rail (1514 at defaults).
LayoutRowWidth=(((#WideCardW#+#CardFrameW#)*2)+((#StatCardW#+#CardFrameW#)*3)+(#CardGap#*6)+#IconRailW#)
; Leave two pixels for integer window rounding. Mode 1 keeps manual shelf wrapping.
UiScale=(#LayoutMode#=1 ? #PreferredUiScale# : Min(Min(#PreferredUiScale#,((#LayoutIsLaptop#=1) || (#LayoutWorkWidth#<1700) ? #LaptopUiScale# : #PreferredUiScale#)),Max(0.75,Floor(((#LayoutWorkWidth#-2)/#LayoutRowWidth#)*1000)/1000)))
textSize=(8*#UiScale#)
titleSize=(10*#UiScale#)
CardFill=14,14,18,#CardOpacity#
ColorCoverFill=35,35,42,#CardOpacity#
colorBar=#ColorAccent#
colorAccent=#ColorAccent#
@IncludeTheme=#@#Themes\#CurrentTheme#.inc
@IncludeBlur=#BlurFile#
