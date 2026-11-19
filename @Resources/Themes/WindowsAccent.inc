; ==============================================================================
; Theme: Windows System Accent Sync
; Automatically synchronizes with Windows 10/11 Personalization Accent Color.
; ==============================================================================
[Variables]
ThemeName=Windows Accent Sync

; Default fallbacks in case Cache\WindowsAccent.inc has not yet been generated
WindowsAccentR=0
WindowsAccentG=136
WindowsAccentB=243
WindowsAccentColor=0,136,243,255
WindowsAccentStroke=76,172,247,58
WindowsAccentBarBack=153,207,250,32
WindowsAccentGradient=270 | 69,173,255,255 ; 0.0 | 0,136,243,255 ; 0.5 | 0,101,182,215 ; 1.0
WindowsAccentCardFill=12,15,21
WindowsAccentHistory2=135,160,245,235
WindowsAccentDivider=153,207,250,28
WindowsAccentPill=153,207,250,16
WindowsAccentSwitchFill=153,207,250,20
WindowsAccentInputFill=22,24,30
WindowsAccentCoverFill=26,29,37
WindowsAccentCoverNote=153,207,250,75
WindowsAccentCheckboxEmpty=153,207,250,75

; Load live Windows accent cached by SlateHUDHelper
@IncludeLiveAccent=#@#Cache\WindowsAccent.inc

ColorAccent=#WindowsAccentColor#
ColorPrimary=255,255,255,255
ColorSecondary=245,245,248,210
ColorMuted=255,255,255,160
colorText=250,250,252,240
colorBar=#ColorAccent#
colorAccent=#ColorAccent#

CardFill=#WindowsAccentCardFill#,#CardOpacity#
CardStroke=#WindowsAccentStroke#
BarBack=#WindowsAccentBarBack#
ColorHistory2=#WindowsAccentHistory2#
ColorDivider=#WindowsAccentDivider#
ColorPill=#WindowsAccentPill#
ColorSwitchFill=#WindowsAccentSwitchFill#
ColorInputFill=#WindowsAccentInputFill#
ColorCoverFill=#WindowsAccentCoverFill#,#CardOpacity#
ColorCoverNote=#WindowsAccentCoverNote#
ColorCheckboxEmpty=#WindowsAccentCheckboxEmpty#

VisualizerGradient=#WindowsAccentGradient#
