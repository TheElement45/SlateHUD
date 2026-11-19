-- Keep unavailable time estimates useful without inventing a remaining duration.
function DescribeBattery(percent, ac, status, seconds, formatted)
    if status == 0 then return '', 'Status', 'No battery', false end
    if ac == 1 then
        if percent == 100 then return 'Plugged in', 'Status', 'Fully charged', true end
        if status == 1 then return 'Plugged in', 'Status', 'Charging', true end
        return 'Plugged in', 'Status', 'Not charging', true
    end
    if ac == 0 then
        if seconds > 0 and seconds < 4294967295 and formatted ~= '' and formatted ~= 'Unknown' then
            return 'On battery', 'Time left', formatted, true
        end
        return 'On battery', 'Time left', 'No estimate', true
    end
    return 'Unavailable', 'Status', 'Power unknown', true
end

local visible, blurType
local options, fill, iconFill = {}, nil, nil
local function option(meter, key, value)
    local id = meter .. ':' .. key
    if options[id] == value then return end
    options[id] = value
    SKIN:Bang('!SetOption', meter, key, value)
end
local function syncBlur(show)
    if not SKIN or SKIN:GetVariable('BlurFile', '') == '' then return end
    if not SKIN.GetMeasure or not SKIN:GetMeasure('MeasureBlur') then return end
    local targetType = show and SKIN:GetVariable('AcrylicBlur', 'None') or 'None'
    if blurType == targetType then return end
    if blurType == nil and show then blurType = targetType; return end
    blurType = targetType
    SKIN:Bang('!SetOption', 'MeasureBlur', 'Type', targetType)
    SKIN:Bang('!UpdateMeasure', 'MeasureBlur')
end
function Update()
    local life = SKIN:GetMeasure('measureBattLife')
    local power, label, value, present = DescribeBattery(
        SKIN:GetMeasure('measureBattPct'):GetValue(),
        SKIN:GetMeasure('measureBattAC'):GetValue(),
        SKIN:GetMeasure('measureBattStatus'):GetValue(),
        life:GetValue(), life:GetStringValue())
    if visible ~= present then
        SKIN:Bang(present and '!ShowMeterGroup' or '!HideMeterGroup', 'BatteryUI')
        syncBlur(present)
        visible = present
    end
    option('meterValueBattAC', 'Text', power)
    option('meterLabelBattLife', 'Text', label)
    option('meterValueBattLife', 'Text', value)
    -- Low charge while connected is different from a critical discharge.
    local percent = SKIN:GetMeasure('measureBattPct'):GetValue()
    local valid = percent >= 0 and percent <= 100
    option('meterValueBattPct', 'Text', valid and string.format('%.0f%%', percent) or 'Unavailable')
    local nextFill = valid and tostring(percent) or '0'
    if fill ~= nextFill then
        fill = nextFill
        SKIN:Bang('!SetVariable', 'BatteryFillPct', fill)
    end
    option('meterBatteryIcon', 'ToolTipText', power .. ': ' .. value)
    local color = valid and '#colorText#' or '#ColorMuted#'
    if power == 'On battery' then
        if percent <= tonumber(SKIN:GetVariable('CritBatt', '15')) then color = '#ColorCrit#'
        elseif percent <= tonumber(SKIN:GetVariable('WarnBatt', '30')) then color = '#ColorWarn#' end
    end
    local barColor = color == '#colorText#' and '#colorBar#' or color
    option('meterValueBattPct', 'FontColor', color)
    option('meterBarBatt', 'BarColor', barColor)
    if iconFill ~= barColor then
        iconFill = barColor
        SKIN:Bang('!SetVariable', 'BatteryFillColor', iconFill)
    end
    return 0
end
