; --- ROW 1 ---
[meterCheck1]
Meter=String
X=((24+#CardShiftX#)*#UiScale#)
Y=((58+#CardShiftY#)*#UiScale#)
FontFace=#iconFont#
FontSize=(9*#UiScale#)
AntiAlias=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
LeftMouseUpAction=[!CommandMeasure MeasureNotes "Toggle(1)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(1)"]
MouseOverAction=[!SetOption meterHint Text "Click: toggle done | Right-click: task options"][!UpdateMeter meterHint][!Redraw]
W=(18*#UiScale#)
H=(20*#UiScale#)

[meterText1]
Meter=String
X=((42+#CardShiftX#)*#UiScale#)
Y=((58+#CardShiftY#)*#UiScale#)
W=(172*#UiScale#)
H=(18*#UiScale#)
FontFace=#fontName#
FontSize=#textSize#
StringEffect=Shadow
FontEffectColor=0,0,0,80
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
Text=#NoteDisplay1#
LeftMouseUpAction=[!CommandMeasure MeasureNotes "Edit(1)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(1)"]
; The hint line shows the full note (the row itself is clipped when the note is long).
MouseOverAction=[!SetOption meterText1 FontColor "#ColorAccent#"][!UpdateMeter meterText1][!CommandMeasure MeasureNotes "Hover(1)"]
MouseLeaveAction=[!UpdateMeasure MeasureNote1][!UpdateMeter meterText1][!Redraw]

; --- ROW 2 ---
[meterCheck2]
Meter=String
X=((24+#CardShiftX#)*#UiScale#)
Y=((80+#CardShiftY#)*#UiScale#)
FontFace=#iconFont#
FontSize=(9*#UiScale#)
AntiAlias=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
LeftMouseUpAction=[!CommandMeasure MeasureNotes "Toggle(2)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(2)"]
MouseOverAction=[!SetOption meterHint Text "Click: toggle done | Right-click: task options"][!UpdateMeter meterHint][!Redraw]
W=(18*#UiScale#)
H=(20*#UiScale#)

[meterText2]
Meter=String
X=((42+#CardShiftX#)*#UiScale#)
Y=((80+#CardShiftY#)*#UiScale#)
W=(172*#UiScale#)
H=(18*#UiScale#)
FontFace=#fontName#
FontSize=#textSize#
StringEffect=Shadow
FontEffectColor=0,0,0,80
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
Text=#NoteDisplay2#
LeftMouseUpAction=[!CommandMeasure MeasureNotes "Edit(2)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(2)"]
; The hint line shows the full note (the row itself is clipped when the note is long).
MouseOverAction=[!SetOption meterText2 FontColor "#ColorAccent#"][!UpdateMeter meterText2][!CommandMeasure MeasureNotes "Hover(2)"]
MouseLeaveAction=[!UpdateMeasure MeasureNote2][!UpdateMeter meterText2][!Redraw]

; --- ROW 3 ---
[meterCheck3]
Meter=String
X=((24+#CardShiftX#)*#UiScale#)
Y=((102+#CardShiftY#)*#UiScale#)
FontFace=#iconFont#
FontSize=(9*#UiScale#)
AntiAlias=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
LeftMouseUpAction=[!CommandMeasure MeasureNotes "Toggle(3)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(3)"]
MouseOverAction=[!SetOption meterHint Text "Click: toggle done | Right-click: task options"][!UpdateMeter meterHint][!Redraw]
W=(18*#UiScale#)
H=(20*#UiScale#)

[meterText3]
Meter=String
X=((42+#CardShiftX#)*#UiScale#)
Y=((102+#CardShiftY#)*#UiScale#)
W=(172*#UiScale#)
H=(18*#UiScale#)
FontFace=#fontName#
FontSize=#textSize#
StringEffect=Shadow
FontEffectColor=0,0,0,80
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
Text=#NoteDisplay3#
LeftMouseUpAction=[!CommandMeasure MeasureNotes "Edit(3)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(3)"]
; The hint line shows the full note (the row itself is clipped when the note is long).
MouseOverAction=[!SetOption meterText3 FontColor "#ColorAccent#"][!UpdateMeter meterText3][!CommandMeasure MeasureNotes "Hover(3)"]
MouseLeaveAction=[!UpdateMeasure MeasureNote3][!UpdateMeter meterText3][!Redraw]

; --- ROW 4 ---
[meterCheck4]
Meter=String
X=((24+#CardShiftX#)*#UiScale#)
Y=((124+#CardShiftY#)*#UiScale#)
FontFace=#iconFont#
FontSize=(9*#UiScale#)
AntiAlias=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
LeftMouseUpAction=[!CommandMeasure MeasureNotes "Toggle(4)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(4)"]
MouseOverAction=[!SetOption meterHint Text "Click: toggle done | Right-click: task options"][!UpdateMeter meterHint][!Redraw]
W=(18*#UiScale#)
H=(20*#UiScale#)

[meterText4]
Meter=String
X=((42+#CardShiftX#)*#UiScale#)
Y=((124+#CardShiftY#)*#UiScale#)
W=(172*#UiScale#)
H=(18*#UiScale#)
FontFace=#fontName#
FontSize=#textSize#
StringEffect=Shadow
FontEffectColor=0,0,0,80
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
Text=#NoteDisplay4#
LeftMouseUpAction=[!CommandMeasure MeasureNotes "Edit(4)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(4)"]
; The hint line shows the full note (the row itself is clipped when the note is long).
MouseOverAction=[!SetOption meterText4 FontColor "#ColorAccent#"][!UpdateMeter meterText4][!CommandMeasure MeasureNotes "Hover(4)"]
MouseLeaveAction=[!UpdateMeasure MeasureNote4][!UpdateMeter meterText4][!Redraw]

; --- ROW 5 ---
[meterCheck5]
Meter=String
X=((24+#CardShiftX#)*#UiScale#)
Y=((146+#CardShiftY#)*#UiScale#)
FontFace=#iconFont#
FontSize=(9*#UiScale#)
AntiAlias=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
LeftMouseUpAction=[!CommandMeasure MeasureNotes "Toggle(5)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(5)"]
MouseOverAction=[!SetOption meterHint Text "Click: toggle done | Right-click: task options"][!UpdateMeter meterHint][!Redraw]
W=(18*#UiScale#)
H=(20*#UiScale#)

[meterText5]
Meter=String
X=((42+#CardShiftX#)*#UiScale#)
Y=((146+#CardShiftY#)*#UiScale#)
W=(172*#UiScale#)
H=(18*#UiScale#)
FontFace=#fontName#
FontSize=#textSize#
StringEffect=Shadow
FontEffectColor=0,0,0,80
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
Text=#NoteDisplay5#
LeftMouseUpAction=[!CommandMeasure MeasureNotes "Edit(5)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(5)"]
; The hint line shows the full note (the row itself is clipped when the note is long).
MouseOverAction=[!SetOption meterText5 FontColor "#ColorAccent#"][!UpdateMeter meterText5][!CommandMeasure MeasureNotes "Hover(5)"]
MouseLeaveAction=[!UpdateMeasure MeasureNote5][!UpdateMeter meterText5][!Redraw]

; Daily repeat indicators share the existing row height.
[meterDaily1]
Meter=String
X=((198+#CardShiftX#)*#UiScale#)
Y=((58+#CardShiftY#)*#UiScale#)
W=(18*#UiScale#)
H=(20*#UiScale#)
FontFace=#iconFont#
FontSize=(9*#UiScale#)
FontColor=#ColorAccent#
AntiAlias=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
Hidden=1
Text="[\xE8EE]"
LeftMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(1)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(1)"]
MouseOverAction=[!SetOption meterHint Text "Daily: resets at #DailyResetHour#:00 local time. Click for options."][!UpdateMeter meterHint][!Redraw]

[meterDaily2]
Meter=String
X=((198+#CardShiftX#)*#UiScale#)
Y=((80+#CardShiftY#)*#UiScale#)
W=(18*#UiScale#)
H=(20*#UiScale#)
FontFace=#iconFont#
FontSize=(9*#UiScale#)
FontColor=#ColorAccent#
AntiAlias=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
Hidden=1
Text="[\xE8EE]"
LeftMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(2)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(2)"]
MouseOverAction=[!SetOption meterHint Text "Daily: resets at #DailyResetHour#:00 local time. Click for options."][!UpdateMeter meterHint][!Redraw]

[meterDaily3]
Meter=String
X=((198+#CardShiftX#)*#UiScale#)
Y=((102+#CardShiftY#)*#UiScale#)
W=(18*#UiScale#)
H=(20*#UiScale#)
FontFace=#iconFont#
FontSize=(9*#UiScale#)
FontColor=#ColorAccent#
AntiAlias=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
Hidden=1
Text="[\xE8EE]"
LeftMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(3)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(3)"]
MouseOverAction=[!SetOption meterHint Text "Daily: resets at #DailyResetHour#:00 local time. Click for options."][!UpdateMeter meterHint][!Redraw]

[meterDaily4]
Meter=String
X=((198+#CardShiftX#)*#UiScale#)
Y=((124+#CardShiftY#)*#UiScale#)
W=(18*#UiScale#)
H=(20*#UiScale#)
FontFace=#iconFont#
FontSize=(9*#UiScale#)
FontColor=#ColorAccent#
AntiAlias=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
Hidden=1
Text="[\xE8EE]"
LeftMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(4)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(4)"]
MouseOverAction=[!SetOption meterHint Text "Daily: resets at #DailyResetHour#:00 local time. Click for options."][!UpdateMeter meterHint][!Redraw]

[meterDaily5]
Meter=String
X=((198+#CardShiftX#)*#UiScale#)
Y=((146+#CardShiftY#)*#UiScale#)
W=(18*#UiScale#)
H=(20*#UiScale#)
FontFace=#iconFont#
FontSize=(9*#UiScale#)
FontColor=#ColorAccent#
AntiAlias=1
SolidColor=0,0,0,1
MouseActionCursor=1
DynamicVariables=1
Hidden=1
Text="[\xE8EE]"
LeftMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(5)"]
RightMouseUpAction=[!CommandMeasure MeasureNotes "OpenMenu(5)"]
MouseOverAction=[!SetOption meterHint Text "Daily: resets at #DailyResetHour#:00 local time. Click for options."][!UpdateMeter meterHint][!Redraw]
