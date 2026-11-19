local M = {}

local SUITE_ITEMS = {
    {'Size: Compact', '[!WriteKeyValue Variables PreferredUiScale 1 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'},
    {'Size: Readable', '[!WriteKeyValue Variables PreferredUiScale 1.125 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'},
    {'Background: Dark', '[!WriteKeyValue Variables CardOpacity 180 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'},
    {'Background: Translucent', '[!WriteKeyValue Variables CardOpacity 110 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'},
    {'Background: Frosted Glass', '[!WriteKeyValue Variables CardOpacity 85 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'},
    {'Display: Auto', '[!WriteKeyValue Variables LayoutPlacement auto "#@#UserSettings.inc"][!SetVariable LayoutPlacement auto "#ROOTCONFIG#\\System"][!UpdateMeasure MeasureLayout "#ROOTCONFIG#\\System"]'},
    {'Display: External', '[!WriteKeyValue Variables LayoutPlacement external "#@#UserSettings.inc"][!SetVariable LayoutPlacement external "#ROOTCONFIG#\\System"][!UpdateMeasure MeasureLayout "#ROOTCONFIG#\\System"]'},
    {'Display: Laptop', '[!WriteKeyValue Variables LayoutPlacement laptop "#@#UserSettings.inc"][!SetVariable LayoutPlacement laptop "#ROOTCONFIG#\\System"][!UpdateMeasure MeasureLayout "#ROOTCONFIG#\\System"]'},
    {'---', '[]'},
    {'Theme: Amber (Default)', '[!WriteKeyValue Variables CurrentTheme "Default" "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'},
    {'Theme: Cyberpunk', '[!WriteKeyValue Variables CurrentTheme "Cyberpunk" "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'},
    {'Theme: Nord Frost', '[!WriteKeyValue Variables CurrentTheme "NordFrost" "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'},
    {'Theme: Tokyo Night', '[!WriteKeyValue Variables CurrentTheme "TokyoNight" "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'},
    {'Theme: Monochrome Stealth', '[!WriteKeyValue Variables CurrentTheme "Monochrome" "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'},
    {'Theme: Windows Accent Sync', '[!WriteKeyValue Variables CurrentTheme "WindowsAccent" "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'},
    {'---', '[]'},
    {'Blur: DWM Acrylic', '[!WriteKeyValue Variables AcrylicBlur Acrylic "#@#UserSettings.inc"][!WriteKeyValue Variables BlurFile "#*@*#Blur.inc" "#@#UserSettings.inc"][!WriteKeyValue Variables BlurTightFrame 1 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'},
    {'Blur: Off', '[!WriteKeyValue Variables AcrylicBlur None "#@#UserSettings.inc"][!WriteKeyValue Variables BlurFile "" "#@#UserSettings.inc"][!WriteKeyValue Variables BlurTightFrame 0 "#@#UserSettings.inc"][!Delay 100][!RefreshGroup SlateHUD]'}
}

local function ensureUserSettings(skin)
    local base = skin:GetVariable('@', '')
    if not base or base == '' then return '' end
    local path = base .. 'UserSettings.inc'
    local existing = io.open(path, 'rb')
    if existing then
        existing:close()
        return path
    end
    local created = io.open(path, 'wb')
    if created then
        created:write('; Local user overrides (git-ignored). Values written here override Variables.inc.\r\n[Variables]\r\n')
        created:close()
    end
    return path
end

local function slotSuffix(slot)
    return slot == 1 and '' or tostring(slot)
end

function M.applySlot(skin, slot, title, action)
    local suffix = slotSuffix(slot)
    skin:Bang('!SetOption', 'Rainmeter', 'ContextTitle' .. suffix, title or '')
    if action ~= nil then
        skin:Bang('!SetOption', 'Rainmeter', 'ContextAction' .. suffix, action)
    end
end

local function isSlotActive(skin, slot)
    if not skin or not skin.GetVariable then return false end
    if slot == 1 then return tonumber(skin:GetVariable('PreferredUiScale', '')) == 1
    elseif slot == 2 then return tonumber(skin:GetVariable('PreferredUiScale', '')) == 1.125
    elseif slot == 3 then return tonumber(skin:GetVariable('CardOpacity', '')) == 180
    elseif slot == 4 then return tonumber(skin:GetVariable('CardOpacity', '')) == 110
    elseif slot == 5 then return tonumber(skin:GetVariable('CardOpacity', '')) == 85
    elseif slot == 6 then return (skin:GetVariable('LayoutPlacement', '') or ''):lower() == 'auto'
    elseif slot == 7 then return (skin:GetVariable('LayoutPlacement', '') or ''):lower() == 'external'
    elseif slot == 8 then return (skin:GetVariable('LayoutPlacement', '') or ''):lower() == 'laptop'
    elseif slot == 10 then return skin:GetVariable('CurrentTheme', '') == 'Default'
    elseif slot == 11 then return skin:GetVariable('CurrentTheme', '') == 'Cyberpunk'
    elseif slot == 12 then return skin:GetVariable('CurrentTheme', '') == 'NordFrost'
    elseif slot == 13 then return skin:GetVariable('CurrentTheme', '') == 'TokyoNight'
    elseif slot == 14 then return skin:GetVariable('CurrentTheme', '') == 'Monochrome'
    elseif slot == 15 then return skin:GetVariable('CurrentTheme', '') == 'WindowsAccent'
    elseif slot == 17 then
        local b = (skin:GetVariable('AcrylicBlur', '') or ''):lower()
        return b == 'acrylic' or b == 'blur'
    elseif slot == 18 then
        return (skin:GetVariable('AcrylicBlur', '') or ''):lower() == 'none'
    end
    return false
end

function M.slotTitle(skin, slot, baseTitle)
    local title = baseTitle or (SUITE_ITEMS[slot] and SUITE_ITEMS[slot][1]) or ''
    if isSlotActive(skin, slot) then return '* ' .. title end
    return title
end

function M.syncSuite(skin, optionFn)
    for slot = 1, #SUITE_ITEMS do
        local item = SUITE_ITEMS[slot]
        local title = M.slotTitle(skin, slot, item[1])
        if optionFn then
            optionFn('Rainmeter', 'ContextTitle' .. slotSuffix(slot), title)
        else
            M.applySlot(skin, slot, title)
        end
    end
end

function M.openSuite(skin, extraItems)
    ensureUserSettings(skin)
    local slot = 1
    for i = 1, #SUITE_ITEMS do
        local item = SUITE_ITEMS[i]
        M.applySlot(skin, slot, M.slotTitle(skin, slot, item[1]), item[2])
        slot = slot + 1
    end
    if extraItems and #extraItems > 0 then
        M.applySlot(skin, slot, '---', '[]')
        slot = slot + 1
        for i = 1, #extraItems do
            local item = extraItems[i]
            M.applySlot(skin, slot, item[1], item[2])
            slot = slot + 1
        end
    end
    M.applySlot(skin, slot, '')
    skin:Bang('!SkinMenu')
end

function M.openCustom(skin, items)
    local slot = 1
    if items then
        for i = 1, #items do
            local item = items[i]
            M.applySlot(skin, slot, item[1], item[2])
            slot = slot + 1
        end
    end
    M.applySlot(skin, slot, '')
    skin:Bang('!SkinCustomMenu')
end

M.ensureUserSettings = ensureUserSettings
M.suiteItems = SUITE_ITEMS
return M
