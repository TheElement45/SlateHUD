local silentSince, switching, blurType
local display, store, checkedAt
local fullscreen = {}
local variants = {[0]='Visualizer.ini', [1]='Idle.ini', [2]='Economy.ini'}
local function mode() return tonumber(SKIN:GetVariable('VisualMode','0')) or 0 end
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
local function target()
    local battery = SKIN:GetMeasure('MeasureVisualPower'):GetValue() == 0
    return battery and SKIN:GetVariable('VisualizerBatterySaver','1') == '1' and 'Economy.ini' or 'Visualizer.ini'
end
local function switch(file)
    if switching then return end
    switching = true
    SKIN:Bang('!ActivateConfig',SKIN:GetVariable('ROOTCONFIG','SlateHUD') .. '\\Visualizer',file)
end
local function modePath(source)
    return SKIN:GetVariable('VisualizerModeFile',source .. 'Cache/VisualizerMode.txt')
end
function Setup()
    local source = SKIN:GetVariable('@')
    local saved = ''
    if source then
        store = store or dofile(source .. 'FileStore.lua')
        saved = store.recover(modePath(source)) or ''
        local prior, hideOn = saved:match('^(%d)\nHIDE=(.+)$')
        if hideOn and hideOn == (mode() == 3 and 'Suspended.ini' or variants[mode()]) then
            SKIN:Bang('!Hide')
            store.write(modePath(source), prior)
        end
    end
    if mode() == 3 then
        if saved:sub(1,1) == '1' and SKIN:GetVariable('VisualizerHideIdle','0') == '1' then
            SKIN:Bang('!HideMeter','MeterBackground')
            SKIN:Bang('!HideMeter','MeterSuspended')
            syncBlur(false)
        else
            syncBlur(true)
        end
        return
    end
    local idle = mode() == 1
    local gradient = SKIN:GetVariable('VisualizerGradient','')
    if gradient ~= '' then
        gradient = gradient:gsub('(%d+),(%d+),(%d+),(%d+)', function(r,g,b,a)
            return r .. ',' .. g .. ',' .. b .. ',' .. math.floor(tonumber(a)*0.25+0.5)
        end)
        SKIN:Bang('!SetOption','MeterStaticBaseline','Grad',gradient)
    end
    -- Idle.ini contains only a peak detector; there are no FFT bands to pause.
    if not idle then SKIN:Bang('!ShowMeter','MeterBars') end
    SKIN:Bang(idle and '!ShowMeter' or '!HideMeter','MeterStaticBaseline')
    if idle and SKIN:GetVariable('VisualizerHideIdle','0') == '1' then
        SKIN:Bang('!HideMeter','MeterBackground'); SKIN:Bang('!HideMeter','MeterStaticBaseline')
        syncBlur(false)
    else
        syncBlur(true)
    end
    SKIN:Bang('!UpdateMeter','*'); SKIN:Bang('!Redraw')
end

local function checkFullscreen(current)
    local now = os.time()
    local source = SKIN:GetVariable('@')
    if not source or checkedAt == now then return end
    checkedAt = now
    display = display or dofile(source .. 'DisplayState.lua')
    local monitors, updated, skins = display.read(SKIN:GetVariable('MonitorSnapshotFile',source .. 'Cache/monitors.txt'), now)
    local external = monitors and display.roles(monitors,
        SKIN:GetVariable('LayoutExternalId',''):upper(), SKIN:GetVariable('LayoutLaptopId',''):upper())
    if fullscreen.active == nil then fullscreen.active = current == 3 end
    local occupied = display.stabilize(fullscreen, external, updated)
    if occupied == (current == 3) then return end
    store = store or dofile(source .. 'FileStore.lua')
    local path = modePath(source)
    local hidden = skins and skins.visualizer == false
    if occupied then
        local marker = hidden and '\nHIDE=Suspended.ini' or ''
        if store.write(path, tostring(current)..marker) then switch('Suspended.ini') end
    else
        local prior = tonumber((store.recover(path) or ''):match('^(%d)')) or 1
        local file = variants[prior] or 'Idle.ini'
        if not hidden or store.write(path,tostring(prior)..'\nHIDE='..file) then switch(file) end
    end
end

function Update()
    local current = mode()
    checkFullscreen(current)
    if current == 3 or switching then return 0 end
    local peak = SKIN:GetMeasure('MeasureAudioPeak'):GetValue()
    if current == 1 then
        if peak >= 0.002 then switch(target()) end
    elseif peak < 0.002 then
        silentSince = silentSince or os.time()
        if os.time()-silentSince >= 2 then switch('Idle.ini') end
    else
        silentSince = nil
        local desired = target()
        if current == 2 and desired == 'Visualizer.ini' or current == 0 and desired == 'Economy.ini' then switch(desired) end
    end
    return 0
end
