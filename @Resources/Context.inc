; Shared menu entries, included inside each skin's [Rainmeter] section.
[Rainmeter]
; Lock new skins and reapply the lock whenever a skin loads or refreshes.
; Skins with their own OnRefreshAction must keep its leading !Draggable 0.
DefaultDraggable=0
OnRefreshAction=[!Draggable 0]
ContextTitle=Size: Compact
ContextAction=[!WriteKeyValue Variables PreferredUiScale 1 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
ContextTitle2=Size: Readable
ContextAction2=[!WriteKeyValue Variables PreferredUiScale 1.125 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
ContextTitle3=Background: Dark
ContextAction3=[!WriteKeyValue Variables CardOpacity 180 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
ContextTitle4=Background: Translucent
ContextAction4=[!WriteKeyValue Variables CardOpacity 110 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
ContextTitle5=Background: Frosted Glass
ContextAction5=[!WriteKeyValue Variables CardOpacity 85 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
ContextTitle6=Display: Auto
ContextAction6=[!WriteKeyValue Variables LayoutPlacement auto "#@#UserSettings.inc"][!SetVariable LayoutPlacement auto "#ROOTCONFIG#\System"][!UpdateMeasure MeasureLayout "#ROOTCONFIG#\System"]
ContextTitle7=Display: External
ContextAction7=[!WriteKeyValue Variables LayoutPlacement external "#@#UserSettings.inc"][!SetVariable LayoutPlacement external "#ROOTCONFIG#\System"][!UpdateMeasure MeasureLayout "#ROOTCONFIG#\System"]
ContextTitle8=Display: Laptop
ContextAction8=[!WriteKeyValue Variables LayoutPlacement laptop "#@#UserSettings.inc"][!SetVariable LayoutPlacement laptop "#ROOTCONFIG#\System"][!UpdateMeasure MeasureLayout "#ROOTCONFIG#\System"]
ContextTitle9=---
ContextAction9=[]
ContextTitle10=Theme: Amber (Default)
ContextAction10=[!WriteKeyValue Variables CurrentTheme "Default" "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
ContextTitle11=Theme: Cyberpunk
ContextAction11=[!WriteKeyValue Variables CurrentTheme "Cyberpunk" "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
ContextTitle12=Theme: Nord Frost
ContextAction12=[!WriteKeyValue Variables CurrentTheme "NordFrost" "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
ContextTitle13=Theme: Tokyo Night
ContextAction13=[!WriteKeyValue Variables CurrentTheme "TokyoNight" "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
ContextTitle14=Theme: Monochrome Stealth
ContextAction14=[!WriteKeyValue Variables CurrentTheme "Monochrome" "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
ContextTitle15=Theme: Windows Accent Sync
ContextAction15=[!WriteKeyValue Variables CurrentTheme "WindowsAccent" "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
ContextTitle16=---
ContextAction16=[]
ContextTitle17=Blur: DWM Acrylic
ContextAction17=[!WriteKeyValue Variables AcrylicBlur Acrylic "#@#UserSettings.inc"][!WriteKeyValue Variables BlurFile "#*@*#Blur.inc" "#@#UserSettings.inc"][!WriteKeyValue Variables BlurTightFrame 1 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
ContextTitle18=Blur: Off
ContextAction18=[!WriteKeyValue Variables AcrylicBlur None "#@#UserSettings.inc"][!WriteKeyValue Variables BlurFile "" "#@#UserSettings.inc"][!WriteKeyValue Variables BlurTightFrame 0 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]
