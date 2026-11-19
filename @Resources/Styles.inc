; ==============================================================================
; SlateHUD shared styles - loaded with: @Include2=#@#Styles.inc
; ==============================================================================

[styleCard]
Shape=Rectangle 0,0,(#StatCardW#*#UiScale#),(#StatCardH#*#UiScale#),(#CardRadius#*#UiScale#)| Fill Color #CardFill# | StrokeWidth 1 | Stroke Color #CardStroke#

[styleTitle]
MouseActionCursor=1
StringAlign=Center
StringCase=Upper
StringStyle=Bold
StringEffect=Shadow
FontEffectColor=0,0,0,90
FontColor=#ColorPrimary#
FontFace=#fontName#
FontSize=#titleSize#
AntiAlias=1
ClipString=1

[styleLeftText]
StringAlign=Left
StringCase=None
StringStyle=Normal
FontWeight=500
StringEffect=Shadow
FontEffectColor=0,0,0,80
FontColor=#ColorSecondary#
FontFace=#fontName#
FontSize=#textSize#
AntiAlias=1
ClipString=1

[styleRightText]
StringAlign=Right
StringCase=None
StringStyle=Bold
StringEffect=Shadow
FontEffectColor=0,0,0,80
FontColor=#colorText#
FontFace=#fontName#
FontSize=#textSize#
AntiAlias=1
ClipString=1

[styleBar]
BarColor=#colorBar#
BarOrientation=HORIZONTAL
SolidColor=#BarBack#

[styleSeperator]
SolidColor=#ColorDivider#
