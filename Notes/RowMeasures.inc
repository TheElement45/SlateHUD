; ===== Row 1 =====
[MeasureInput1]
Measure=Plugin
Plugin=InputText
X=((42+#CardShiftX#)*#UiScale#)
Y=((58+#CardShiftY#)*#UiScale#)
W=(172*#UiScale#)
H=(18*#UiScale#)
FontFace=#fontName#
FontSize=#textSize#
FontColor=#ColorPrimary#
SolidColor=#ColorInputFill#
AntiAlias=1
FocusDismiss=1
Command1=[!SetVariable NewText """ $UserInput$ """][!EnableMeasure MeasureCommit1][!UpdateMeasure MeasureCommit1][!DisableMeasure MeasureCommit1]

[MeasureCommit1]
Measure=String
String=#NewText#
DynamicVariables=1
UpdateDivider=-1
Disabled=1
RegExpSubstitute=1
Substitute='^\s+|\s+$':"",'"':"'"
IfMatch=^\s*$
IfMatchMode=1
IfMatchAction=[!CommandMeasure MeasureNotes "Save(1)"]
IfNotMatchAction=[!CommandMeasure MeasureNotes "Save(1)"]

[MeasureNote1]
Measure=String
String=#NoteDisplay1#
DynamicVariables=1
UpdateDivider=-1
Group=NoteMeasures
IfMatch=^$
IfMatchMode=1
IfMatchAction=[!SetOption meterCheck1 Text "[\xE739]"][!SetOption meterCheck1 FontColor "#ColorCheckboxEmpty#"][!SetOption meterText1 FontColor "#ColorMuted#"][!SetOption meterText1 InlineSetting "None"][!SetOption meterText1 FontWeight "400"][!UpdateMeter meterCheck1][!UpdateMeter meterText1][!Redraw]
IfNotMatchAction=[!UpdateMeasure MeasureStatus1]

[MeasureStatus1]
Measure=Calc
Formula=#Status1#
DynamicVariables=1
UpdateDivider=-1
IfCondition=MeasureStatus1 = 1
IfConditionMode=1
IfTrueAction=[!SetOption meterCheck1 Text "[\xE73E]"][!SetOption meterCheck1 FontColor "#ColorAccent#"][!SetOption meterText1 FontColor "#ColorSecondary#"][!SetOption meterText1 InlineSetting "Strikethrough"][!SetOption meterText1 InlinePattern ".*"][!SetOption meterText1 FontWeight "400"][!UpdateMeter meterCheck1][!UpdateMeter meterText1][!Redraw]
IfFalseAction=[!SetOption meterCheck1 Text "[\xE739]"][!SetOption meterCheck1 FontColor "#ColorSecondary#"][!SetOption meterText1 FontColor "#colorText#"][!SetOption meterText1 InlineSetting "None"][!SetOption meterText1 FontWeight "600"][!UpdateMeter meterCheck1][!UpdateMeter meterText1][!Redraw]

; Checkbox click: an empty row opens the editor instead of toggling a status that has no text.
[MeasureInput2]
Measure=Plugin
Plugin=InputText
X=((42+#CardShiftX#)*#UiScale#)
Y=((80+#CardShiftY#)*#UiScale#)
W=(172*#UiScale#)
H=(18*#UiScale#)
FontFace=#fontName#
FontSize=#textSize#
FontColor=#ColorPrimary#
SolidColor=#ColorInputFill#
AntiAlias=1
FocusDismiss=1
Command1=[!SetVariable NewText """ $UserInput$ """][!EnableMeasure MeasureCommit2][!UpdateMeasure MeasureCommit2][!DisableMeasure MeasureCommit2]

[MeasureCommit2]
Measure=String
String=#NewText#
DynamicVariables=1
UpdateDivider=-1
Disabled=1
RegExpSubstitute=1
Substitute='^\s+|\s+$':"",'"':"'"
IfMatch=^\s*$
IfMatchMode=1
IfMatchAction=[!CommandMeasure MeasureNotes "Save(2)"]
IfNotMatchAction=[!CommandMeasure MeasureNotes "Save(2)"]

[MeasureNote2]
Measure=String
String=#NoteDisplay2#
DynamicVariables=1
UpdateDivider=-1
Group=NoteMeasures
IfMatch=^$
IfMatchMode=1
IfMatchAction=[!SetOption meterCheck2 Text "[\xE739]"][!SetOption meterCheck2 FontColor "#ColorCheckboxEmpty#"][!SetOption meterText2 FontColor "#ColorMuted#"][!SetOption meterText2 InlineSetting "None"][!SetOption meterText2 FontWeight "400"][!UpdateMeter meterCheck2][!UpdateMeter meterText2][!Redraw]
IfNotMatchAction=[!UpdateMeasure MeasureStatus2]

[MeasureStatus2]
Measure=Calc
Formula=#Status2#
DynamicVariables=1
UpdateDivider=-1
IfCondition=MeasureStatus2 = 1
IfConditionMode=1
IfTrueAction=[!SetOption meterCheck2 Text "[\xE73E]"][!SetOption meterCheck2 FontColor "#ColorAccent#"][!SetOption meterText2 FontColor "#ColorSecondary#"][!SetOption meterText2 InlineSetting "Strikethrough"][!SetOption meterText2 InlinePattern ".*"][!SetOption meterText2 FontWeight "400"][!UpdateMeter meterCheck2][!UpdateMeter meterText2][!Redraw]
IfFalseAction=[!SetOption meterCheck2 Text "[\xE739]"][!SetOption meterCheck2 FontColor "#ColorSecondary#"][!SetOption meterText2 FontColor "#colorText#"][!SetOption meterText2 InlineSetting "None"][!SetOption meterText2 FontWeight "600"][!UpdateMeter meterCheck2][!UpdateMeter meterText2][!Redraw]

; Checkbox click: an empty row opens the editor instead of toggling a status that has no text.
[MeasureInput3]
Measure=Plugin
Plugin=InputText
X=((42+#CardShiftX#)*#UiScale#)
Y=((102+#CardShiftY#)*#UiScale#)
W=(172*#UiScale#)
H=(18*#UiScale#)
FontFace=#fontName#
FontSize=#textSize#
FontColor=#ColorPrimary#
SolidColor=#ColorInputFill#
AntiAlias=1
FocusDismiss=1
Command1=[!SetVariable NewText """ $UserInput$ """][!EnableMeasure MeasureCommit3][!UpdateMeasure MeasureCommit3][!DisableMeasure MeasureCommit3]

[MeasureCommit3]
Measure=String
String=#NewText#
DynamicVariables=1
UpdateDivider=-1
Disabled=1
RegExpSubstitute=1
Substitute='^\s+|\s+$':"",'"':"'"
IfMatch=^\s*$
IfMatchMode=1
IfMatchAction=[!CommandMeasure MeasureNotes "Save(3)"]
IfNotMatchAction=[!CommandMeasure MeasureNotes "Save(3)"]

[MeasureNote3]
Measure=String
String=#NoteDisplay3#
DynamicVariables=1
UpdateDivider=-1
Group=NoteMeasures
IfMatch=^$
IfMatchMode=1
IfMatchAction=[!SetOption meterCheck3 Text "[\xE739]"][!SetOption meterCheck3 FontColor "#ColorCheckboxEmpty#"][!SetOption meterText3 FontColor "#ColorMuted#"][!SetOption meterText3 InlineSetting "None"][!SetOption meterText3 FontWeight "400"][!UpdateMeter meterCheck3][!UpdateMeter meterText3][!Redraw]
IfNotMatchAction=[!UpdateMeasure MeasureStatus3]

[MeasureStatus3]
Measure=Calc
Formula=#Status3#
DynamicVariables=1
UpdateDivider=-1
IfCondition=MeasureStatus3 = 1
IfConditionMode=1
IfTrueAction=[!SetOption meterCheck3 Text "[\xE73E]"][!SetOption meterCheck3 FontColor "#ColorAccent#"][!SetOption meterText3 FontColor "#ColorSecondary#"][!SetOption meterText3 InlineSetting "Strikethrough"][!SetOption meterText3 InlinePattern ".*"][!SetOption meterText3 FontWeight "400"][!UpdateMeter meterCheck3][!UpdateMeter meterText3][!Redraw]
IfFalseAction=[!SetOption meterCheck3 Text "[\xE739]"][!SetOption meterCheck3 FontColor "#ColorSecondary#"][!SetOption meterText3 FontColor "#colorText#"][!SetOption meterText3 InlineSetting "None"][!SetOption meterText3 FontWeight "600"][!UpdateMeter meterCheck3][!UpdateMeter meterText3][!Redraw]

; Checkbox click: an empty row opens the editor instead of toggling a status that has no text.
[MeasureInput4]
Measure=Plugin
Plugin=InputText
X=((42+#CardShiftX#)*#UiScale#)
Y=((124+#CardShiftY#)*#UiScale#)
W=(172*#UiScale#)
H=(18*#UiScale#)
FontFace=#fontName#
FontSize=#textSize#
FontColor=#ColorPrimary#
SolidColor=#ColorInputFill#
AntiAlias=1
FocusDismiss=1
Command1=[!SetVariable NewText """ $UserInput$ """][!EnableMeasure MeasureCommit4][!UpdateMeasure MeasureCommit4][!DisableMeasure MeasureCommit4]

[MeasureCommit4]
Measure=String
String=#NewText#
DynamicVariables=1
UpdateDivider=-1
Disabled=1
RegExpSubstitute=1
Substitute='^\s+|\s+$':"",'"':"'"
IfMatch=^\s*$
IfMatchMode=1
IfMatchAction=[!CommandMeasure MeasureNotes "Save(4)"]
IfNotMatchAction=[!CommandMeasure MeasureNotes "Save(4)"]

[MeasureNote4]
Measure=String
String=#NoteDisplay4#
DynamicVariables=1
UpdateDivider=-1
Group=NoteMeasures
IfMatch=^$
IfMatchMode=1
IfMatchAction=[!SetOption meterCheck4 Text "[\xE739]"][!SetOption meterCheck4 FontColor "#ColorCheckboxEmpty#"][!SetOption meterText4 FontColor "#ColorMuted#"][!SetOption meterText4 InlineSetting "None"][!SetOption meterText4 FontWeight "400"][!UpdateMeter meterCheck4][!UpdateMeter meterText4][!Redraw]
IfNotMatchAction=[!UpdateMeasure MeasureStatus4]

[MeasureStatus4]
Measure=Calc
Formula=#Status4#
DynamicVariables=1
UpdateDivider=-1
IfCondition=MeasureStatus4 = 1
IfConditionMode=1
IfTrueAction=[!SetOption meterCheck4 Text "[\xE73E]"][!SetOption meterCheck4 FontColor "#ColorAccent#"][!SetOption meterText4 FontColor "#ColorSecondary#"][!SetOption meterText4 InlineSetting "Strikethrough"][!SetOption meterText4 InlinePattern ".*"][!SetOption meterText4 FontWeight "400"][!UpdateMeter meterCheck4][!UpdateMeter meterText4][!Redraw]
IfFalseAction=[!SetOption meterCheck4 Text "[\xE739]"][!SetOption meterCheck4 FontColor "#ColorSecondary#"][!SetOption meterText4 FontColor "#colorText#"][!SetOption meterText4 InlineSetting "None"][!SetOption meterText4 FontWeight "600"][!UpdateMeter meterCheck4][!UpdateMeter meterText4][!Redraw]

; Checkbox click: an empty row opens the editor instead of toggling a status that has no text.
[MeasureInput5]
Measure=Plugin
Plugin=InputText
X=((42+#CardShiftX#)*#UiScale#)
Y=((146+#CardShiftY#)*#UiScale#)
W=(172*#UiScale#)
H=(18*#UiScale#)
FontFace=#fontName#
FontSize=#textSize#
FontColor=#ColorPrimary#
SolidColor=#ColorInputFill#
AntiAlias=1
FocusDismiss=1
Command1=[!SetVariable NewText """ $UserInput$ """][!EnableMeasure MeasureCommit5][!UpdateMeasure MeasureCommit5][!DisableMeasure MeasureCommit5]

[MeasureCommit5]
Measure=String
String=#NewText#
DynamicVariables=1
UpdateDivider=-1
Disabled=1
RegExpSubstitute=1
Substitute='^\s+|\s+$':"",'"':"'"
IfMatch=^\s*$
IfMatchMode=1
IfMatchAction=[!CommandMeasure MeasureNotes "Save(5)"]
IfNotMatchAction=[!CommandMeasure MeasureNotes "Save(5)"]

[MeasureNote5]
Measure=String
String=#NoteDisplay5#
DynamicVariables=1
UpdateDivider=-1
Group=NoteMeasures
IfMatch=^$
IfMatchMode=1
IfMatchAction=[!SetOption meterCheck5 Text "[\xE739]"][!SetOption meterCheck5 FontColor "#ColorCheckboxEmpty#"][!SetOption meterText5 FontColor "#ColorMuted#"][!SetOption meterText5 InlineSetting "None"][!SetOption meterText5 FontWeight "400"][!UpdateMeter meterCheck5][!UpdateMeter meterText5][!Redraw]
IfNotMatchAction=[!UpdateMeasure MeasureStatus5]

[MeasureStatus5]
Measure=Calc
Formula=#Status5#
DynamicVariables=1
UpdateDivider=-1
IfCondition=MeasureStatus5 = 1
IfConditionMode=1
IfTrueAction=[!SetOption meterCheck5 Text "[\xE73E]"][!SetOption meterCheck5 FontColor "#ColorAccent#"][!SetOption meterText5 FontColor "#ColorSecondary#"][!SetOption meterText5 InlineSetting "Strikethrough"][!SetOption meterText5 InlinePattern ".*"][!SetOption meterText5 FontWeight "400"][!UpdateMeter meterCheck5][!UpdateMeter meterText5][!Redraw]
IfFalseAction=[!SetOption meterCheck5 Text "[\xE739]"][!SetOption meterCheck5 FontColor "#ColorSecondary#"][!SetOption meterText5 FontColor "#colorText#"][!SetOption meterText5 InlineSetting "None"][!SetOption meterText5 FontWeight "600"][!UpdateMeter meterCheck5][!UpdateMeter meterText5][!Redraw]
