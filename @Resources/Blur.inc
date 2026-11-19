; ==============================================================================
; DWM Hardware Acrylic / Frosted Blur Measure
; Defaults to FrostBehind (Win10/11 + rounded corners via BlurCorner); set
; BlurPlugin=FrostedGlass in @Resources\UserSettings.inc for legacy fallback.
; Set AcrylicBlur=Acrylic, AcrylicBlur=Blur, or AcrylicBlur=None and
; BlurCorner=Round, RoundSmall, or None in @Resources\UserSettings.inc.
; When the chosen plugin DLL is present in Plugins\, Windows DWM renders
; native hardware acrylic blur behind the skin.
; ==============================================================================
[MeasureBlur]
Measure=Plugin
Plugin=#BlurPlugin#
Type=#AcrylicBlur#
Corner=#BlurCorner#
Border=None
UpdateDivider=-1
