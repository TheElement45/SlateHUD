[StyleGameTile]
SolidColor=0,0,0,1
DynamicVariables=1
MouseActionCursor=1
Hidden=1

[StyleGameLabel]
FontFace=#fontName#
FontSize=(8.5*#UiScale#)
FontColor=#ColorSecondary#
StringEffect=Shadow
FontEffectColor=0,0,0,80
AntiAlias=1
StringAlign=Center
ClipString=1
DynamicVariables=1
Hidden=1

[GameTile1Hit]
Meter=Image
MeterStyle=StyleGameTile
W=(70*#UiScale#)
H=(70*#UiScale#)
Group=GameTile1
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(1)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(1)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(1)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(1)"]

[GameTile1Icon]
Meter=Image
MeterStyle=StyleGameTile
W=(32*#UiScale#)
H=(32*#UiScale#)
PreserveAspectRatio=1
Group=GameTile1
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(1)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(1)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(1)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(1)"]

[GameTile1Initial]
Meter=String
MeterStyle=StyleGameLabel
FontSize=(13*#UiScale#)
FontColor=#ColorAccent#
SolidColor=#ColorPill#
W=(32*#UiScale#)
H=(32*#UiScale#)
Group=GameTile1
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(1)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(1)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(1)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(1)"]

[GameTile1Label]
Meter=String
MeterStyle=StyleGameLabel
W=(70*#UiScale#)
H=(16*#UiScale#)
Group=GameTile1
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(1)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(1)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(1)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(1)"]

[GameTile2Hit]
Meter=Image
MeterStyle=StyleGameTile
W=(70*#UiScale#)
H=(70*#UiScale#)
Group=GameTile2
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(2)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(2)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(2)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(2)"]

[GameTile2Icon]
Meter=Image
MeterStyle=StyleGameTile
W=(32*#UiScale#)
H=(32*#UiScale#)
PreserveAspectRatio=1
Group=GameTile2
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(2)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(2)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(2)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(2)"]

[GameTile2Initial]
Meter=String
MeterStyle=StyleGameLabel
FontSize=(13*#UiScale#)
FontColor=#ColorAccent#
SolidColor=#ColorPill#
W=(32*#UiScale#)
H=(32*#UiScale#)
Group=GameTile2
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(2)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(2)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(2)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(2)"]

[GameTile2Label]
Meter=String
MeterStyle=StyleGameLabel
W=(70*#UiScale#)
H=(16*#UiScale#)
Group=GameTile2
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(2)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(2)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(2)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(2)"]

[GameTile3Hit]
Meter=Image
MeterStyle=StyleGameTile
W=(70*#UiScale#)
H=(70*#UiScale#)
Group=GameTile3
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(3)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(3)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(3)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(3)"]

[GameTile3Icon]
Meter=Image
MeterStyle=StyleGameTile
W=(32*#UiScale#)
H=(32*#UiScale#)
PreserveAspectRatio=1
Group=GameTile3
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(3)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(3)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(3)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(3)"]

[GameTile3Initial]
Meter=String
MeterStyle=StyleGameLabel
FontSize=(13*#UiScale#)
FontColor=#ColorAccent#
SolidColor=#ColorPill#
W=(32*#UiScale#)
H=(32*#UiScale#)
Group=GameTile3
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(3)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(3)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(3)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(3)"]

[GameTile3Label]
Meter=String
MeterStyle=StyleGameLabel
W=(70*#UiScale#)
H=(16*#UiScale#)
Group=GameTile3
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(3)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(3)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(3)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(3)"]

[GameTile4Hit]
Meter=Image
MeterStyle=StyleGameTile
W=(70*#UiScale#)
H=(70*#UiScale#)
Group=GameTile4
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(4)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(4)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(4)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(4)"]

[GameTile4Icon]
Meter=Image
MeterStyle=StyleGameTile
W=(32*#UiScale#)
H=(32*#UiScale#)
PreserveAspectRatio=1
Group=GameTile4
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(4)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(4)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(4)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(4)"]

[GameTile4Initial]
Meter=String
MeterStyle=StyleGameLabel
FontSize=(13*#UiScale#)
FontColor=#ColorAccent#
SolidColor=#ColorPill#
W=(32*#UiScale#)
H=(32*#UiScale#)
Group=GameTile4
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(4)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(4)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(4)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(4)"]

[GameTile4Label]
Meter=String
MeterStyle=StyleGameLabel
W=(70*#UiScale#)
H=(16*#UiScale#)
Group=GameTile4
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(4)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(4)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(4)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(4)"]

[GameTile5Hit]
Meter=Image
MeterStyle=StyleGameTile
W=(70*#UiScale#)
H=(70*#UiScale#)
Group=GameTile5
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(5)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(5)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(5)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(5)"]

[GameTile5Icon]
Meter=Image
MeterStyle=StyleGameTile
W=(32*#UiScale#)
H=(32*#UiScale#)
PreserveAspectRatio=1
Group=GameTile5
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(5)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(5)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(5)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(5)"]

[GameTile5Initial]
Meter=String
MeterStyle=StyleGameLabel
FontSize=(13*#UiScale#)
FontColor=#ColorAccent#
SolidColor=#ColorPill#
W=(32*#UiScale#)
H=(32*#UiScale#)
Group=GameTile5
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(5)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(5)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(5)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(5)"]

[GameTile5Label]
Meter=String
MeterStyle=StyleGameLabel
W=(70*#UiScale#)
H=(16*#UiScale#)
Group=GameTile5
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(5)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(5)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(5)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(5)"]

[GameTile6Hit]
Meter=Image
MeterStyle=StyleGameTile
W=(70*#UiScale#)
H=(70*#UiScale#)
Group=GameTile6
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(6)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(6)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(6)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(6)"]

[GameTile6Icon]
Meter=Image
MeterStyle=StyleGameTile
W=(32*#UiScale#)
H=(32*#UiScale#)
PreserveAspectRatio=1
Group=GameTile6
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(6)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(6)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(6)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(6)"]

[GameTile6Initial]
Meter=String
MeterStyle=StyleGameLabel
FontSize=(13*#UiScale#)
FontColor=#ColorAccent#
SolidColor=#ColorPill#
W=(32*#UiScale#)
H=(32*#UiScale#)
Group=GameTile6
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(6)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(6)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(6)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(6)"]

[GameTile6Label]
Meter=String
MeterStyle=StyleGameLabel
W=(70*#UiScale#)
H=(16*#UiScale#)
Group=GameTile6
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(6)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(6)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(6)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(6)"]

[GameTile7Hit]
Meter=Image
MeterStyle=StyleGameTile
W=(70*#UiScale#)
H=(70*#UiScale#)
Group=GameTile7
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(7)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(7)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(7)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(7)"]

[GameTile7Icon]
Meter=Image
MeterStyle=StyleGameTile
W=(32*#UiScale#)
H=(32*#UiScale#)
PreserveAspectRatio=1
Group=GameTile7
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(7)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(7)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(7)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(7)"]

[GameTile7Initial]
Meter=String
MeterStyle=StyleGameLabel
FontSize=(13*#UiScale#)
FontColor=#ColorAccent#
SolidColor=#ColorPill#
W=(32*#UiScale#)
H=(32*#UiScale#)
Group=GameTile7
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(7)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(7)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(7)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(7)"]

[GameTile7Label]
Meter=String
MeterStyle=StyleGameLabel
W=(70*#UiScale#)
H=(16*#UiScale#)
Group=GameTile7
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(7)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(7)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(7)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(7)"]

[GameTile8Hit]
Meter=Image
MeterStyle=StyleGameTile
W=(70*#UiScale#)
H=(70*#UiScale#)
Group=GameTile8
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(8)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(8)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(8)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(8)"]

[GameTile8Icon]
Meter=Image
MeterStyle=StyleGameTile
W=(32*#UiScale#)
H=(32*#UiScale#)
PreserveAspectRatio=1
Group=GameTile8
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(8)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(8)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(8)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(8)"]

[GameTile8Initial]
Meter=String
MeterStyle=StyleGameLabel
FontSize=(13*#UiScale#)
FontColor=#ColorAccent#
SolidColor=#ColorPill#
W=(32*#UiScale#)
H=(32*#UiScale#)
Group=GameTile8
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(8)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(8)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(8)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(8)"]

[GameTile8Label]
Meter=String
MeterStyle=StyleGameLabel
W=(70*#UiScale#)
H=(16*#UiScale#)
Group=GameTile8
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(8)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(8)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(8)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(8)"]

[GameTile9Hit]
Meter=Image
MeterStyle=StyleGameTile
W=(70*#UiScale#)
H=(70*#UiScale#)
Group=GameTile9
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(9)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(9)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(9)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(9)"]

[GameTile9Icon]
Meter=Image
MeterStyle=StyleGameTile
W=(32*#UiScale#)
H=(32*#UiScale#)
PreserveAspectRatio=1
Group=GameTile9
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(9)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(9)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(9)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(9)"]

[GameTile9Initial]
Meter=String
MeterStyle=StyleGameLabel
FontSize=(13*#UiScale#)
FontColor=#ColorAccent#
SolidColor=#ColorPill#
W=(32*#UiScale#)
H=(32*#UiScale#)
Group=GameTile9
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(9)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(9)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(9)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(9)"]

[GameTile9Label]
Meter=String
MeterStyle=StyleGameLabel
W=(70*#UiScale#)
H=(16*#UiScale#)
Group=GameTile9
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(9)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(9)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(9)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(9)"]

[GameTile10Hit]
Meter=Image
MeterStyle=StyleGameTile
W=(70*#UiScale#)
H=(70*#UiScale#)
Group=GameTile10
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(10)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(10)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(10)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(10)"]

[GameTile10Icon]
Meter=Image
MeterStyle=StyleGameTile
W=(32*#UiScale#)
H=(32*#UiScale#)
PreserveAspectRatio=1
Group=GameTile10
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(10)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(10)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(10)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(10)"]

[GameTile10Initial]
Meter=String
MeterStyle=StyleGameLabel
FontSize=(13*#UiScale#)
FontColor=#ColorAccent#
SolidColor=#ColorPill#
W=(32*#UiScale#)
H=(32*#UiScale#)
Group=GameTile10
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(10)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(10)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(10)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(10)"]

[GameTile10Label]
Meter=String
MeterStyle=StyleGameLabel
W=(70*#UiScale#)
H=(16*#UiScale#)
Group=GameTile10
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(10)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(10)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(10)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(10)"]

[GameTile11Hit]
Meter=Image
MeterStyle=StyleGameTile
W=(70*#UiScale#)
H=(70*#UiScale#)
Group=GameTile11
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(11)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(11)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(11)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(11)"]

[GameTile11Icon]
Meter=Image
MeterStyle=StyleGameTile
W=(32*#UiScale#)
H=(32*#UiScale#)
PreserveAspectRatio=1
Group=GameTile11
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(11)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(11)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(11)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(11)"]

[GameTile11Initial]
Meter=String
MeterStyle=StyleGameLabel
FontSize=(13*#UiScale#)
FontColor=#ColorAccent#
SolidColor=#ColorPill#
W=(32*#UiScale#)
H=(32*#UiScale#)
Group=GameTile11
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(11)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(11)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(11)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(11)"]

[GameTile11Label]
Meter=String
MeterStyle=StyleGameLabel
W=(70*#UiScale#)
H=(16*#UiScale#)
Group=GameTile11
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(11)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(11)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(11)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(11)"]

[GameTile12Hit]
Meter=Image
MeterStyle=StyleGameTile
W=(70*#UiScale#)
H=(70*#UiScale#)
Group=GameTile12
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(12)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(12)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(12)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(12)"]

[GameTile12Icon]
Meter=Image
MeterStyle=StyleGameTile
W=(32*#UiScale#)
H=(32*#UiScale#)
PreserveAspectRatio=1
Group=GameTile12
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(12)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(12)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(12)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(12)"]

[GameTile12Initial]
Meter=String
MeterStyle=StyleGameLabel
FontSize=(13*#UiScale#)
FontColor=#ColorAccent#
SolidColor=#ColorPill#
W=(32*#UiScale#)
H=(32*#UiScale#)
Group=GameTile12
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(12)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(12)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(12)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(12)"]

[GameTile12Label]
Meter=String
MeterStyle=StyleGameLabel
W=(70*#UiScale#)
H=(16*#UiScale#)
Group=GameTile12
Y=((88+#CardShiftY#)*#UiScale#)
LeftMouseUpAction=[!CommandMeasure MeasureGameHub "LaunchTile(12)"]
RightMouseUpAction=[!CommandMeasure MeasureGameHub "OpenTileMenu(12)"]
MouseOverAction=[!CommandMeasure MeasureGameHub "HoverTile(12)"]
MouseLeaveAction=[!CommandMeasure MeasureGameHub "LeaveTile(12)"]
