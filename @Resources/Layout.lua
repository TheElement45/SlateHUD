-- Layout dimensions are logical pixels. Scaling applies to cards and targets,
-- while placement uses Rainmeter's desktop coordinates, including negative origins.
local last, cached, store, display, ctxMenu, lastBounds
local scriptDir = type(debug) == 'table' and debug.getinfo and (debug.getinfo(1, 'S').source:match('^@?(.*[/\\])') or '') or ''
local fullscreen = {}
local configs = {'Root','Disks','Network','System','Games','Visualizer','Apps','Battery','Notes'}
local function configPath(root, name)
    return name == 'Root' and root or root .. '\\' .. name
end
local function num(name, default)
    if not SKIN or not SKIN.GetVariable then return default end
    local value = SKIN:GetVariable(name, tostring(default))
    return tonumber(value) or (SKIN.ParseFormula and SKIN:ParseFormula(SKIN:ReplaceVariables(value))) or default
end
local function layoutMetrics()
    local statCardW = num('StatCardW', 222)
    local statCardH = num('StatCardH', 168)
    local batteryCardH = num('BatteryCardH', 110)
    local wideCardW = num('WideCardW', 320)
    local mediaCardH = num('MediaCardH', 140)
    local visualizerCardH = num('VisualizerCardH', 44)
    local frameW = num('CardFrameW', 16)
    local frameH = num('CardFrameH', 24)
    local tight = num('BlurTightFrame', 0) == 1
    local padX = num('CardPadX', tight and 0 or math.floor(frameW / 2))
    local padY = num('CardPadY', tight and 0 or (frameH - math.floor(frameW / 2)))
    local shiftX = math.floor(frameW / 2) - padX
    local shiftY = (frameH - math.floor(frameW / 2)) - padY
    local gap = num('CardGap', 8)
    local rail = num('IconRailW', 80)
    local statW = statCardW + frameW
    local statH = statCardH + frameH
    local wideW = wideCardW + frameW
    local batteryH = batteryCardH + frameH
    local mediaH = mediaCardH + frameH
    local visualizerH = visualizerCardH + frameH
    local visualizerOffset = mediaCardH + gap
    local appsOffset = visualizerOffset + visualizerH + gap
    local batteryOffset = statH + gap
    return {
        statCardW = statCardW, wideCardW = wideCardW,
        statW = statW, statH = statH, wideW = wideW,
        shiftX = shiftX, shiftY = shiftY, tight = tight,
        batteryOffset = batteryOffset, systemClusterH = batteryOffset + batteryH,
        mediaClusterH = mediaH + visualizerH, visualizerOffset = visualizerOffset,
        appsOffset = appsOffset, gap = gap, rail = rail,
        rowWidth = wideW * 2 + statW * 3 + gap * 4 + rail + gap * 2
    }
end
function FitScale(width, preferred, forceWrap, laptopScale, isLaptop)
    preferred = math.max(0.75, math.min(2, preferred))
    if forceWrap then return preferred end
    if isLaptop or width < 1700 then preferred = math.min(preferred,math.max(0.75,laptopScale or 0.95)) end
    return math.min(preferred, math.max(0.75, math.floor((width-2)/layoutMetrics().rowWidth*1000)/1000))
end
function PlanLayout(area, scale, forceWrap, history, laptopScale, sysHistory)
    local m = layoutMetrics()
    scale = FitScale(area.w, scale, forceWrap, laptopScale, area.role == 'laptop')
    local margin, gap = m.gap * scale, m.gap * scale
    local right = area.x + area.w - margin
    local gamesWidth = m.wideW * scale
    local shelfRight = right - gamesWidth - gap
    local cards = {
        {name='', w=m.wideW, h=m.mediaClusterH}, {name='Disks', w=m.statW, h=m.statH},
        {name='Network', w=m.statW, h=m.statH + (history and 40 or 0)},
        {name='System', w=m.statW, h=m.systemClusterH + (sysHistory and 40 or 0)}
    }
    local total = gamesWidth + gap
    for i, card in ipairs(cards) do total = total + card.w * scale + (i > 1 and gap or 0) end
    local wrap = forceWrap or total + 2 * margin > area.w
    local positions = {Games={x=right-gamesWidth,y=area.y+margin}}
    local x = wrap and area.x + margin or right - total
    local y, rowHeight = area.y + margin, 0
    for _, card in ipairs(cards) do
        if x + card.w * scale > shelfRight + 0.5 and x > area.x + margin + 1 then
            x, y, rowHeight = area.x + margin, y + rowHeight + gap, 0
        end
        positions[card.name] = {x=x, y=y}
        rowHeight = math.max(rowHeight, card.h * scale)
        x = x + card.w * scale + gap
    end
    if not wrap then
        -- Reserve one icon column and center the status cluster between sidebars.
        local spare = math.max(0,area.w-total-2*margin)
        positions[''].x = area.x+margin+math.min(m.rail*scale,spare)
        local clusterWidth = (m.statW*3+m.gap*2)*scale
        local corridorLeft = positions[''].x+m.wideW*scale
        local clusterX = corridorLeft+(positions.Games.x-corridorLeft-clusterWidth)/2
        for i,name in ipairs({'Disks','Network','System'}) do
            positions[name].x = clusterX+(i-1)*(m.statW+m.gap)*scale
        end
    end
    local media, system = positions[''], positions.System
    positions.Visualizer = {x=media.x, y=media.y+m.visualizerOffset*scale}
    -- Apps shares the music card's left edge, below the full visualizer footprint.
    -- In shelf mode start below all wrapped cards to keep expanded app groups clear.
    local appsY = media.y+m.appsOffset*scale
    if wrap then appsY = math.max(appsY,y+rowHeight+gap) end
    positions.Apps = {x=media.x, y=appsY}
    positions.Battery = {x=system.x, y=system.y+(m.batteryOffset + (sysHistory and 40 or 0))*scale}
    if m.shiftX ~= 0 or m.shiftY ~= 0 then
        local ox, oy = m.shiftX * scale, m.shiftY * scale
        for _, point in pairs(positions) do
            point.x = point.x + ox
            point.y = point.y + oy
        end
    end
    return positions, wrap, scale
end
local function rainmeterArea(monitor)
    local suffix = monitor > 0 and '@' .. monitor or ''
    local function value(name)
        return tonumber(SKIN:GetVariable(monitor > 0 and name .. suffix or 'P' .. name))
    end
    local x,y,w,h = value('WORKAREAX'),value('WORKAREAY'),value('WORKAREAWIDTH'),value('WORKAREAHEIGHT')
    if x and y and w and h and w > 0 and h > 0 then return {x=x,y=y,w=w,h=h} end
end

local function availableAt(x,y)
    local fallback, bestDistance
    for index = 0, 32 do
        local bounds = rainmeterArea(index)
        if bounds then
            if bounds.x == x and bounds.y == y then return bounds end
            local distance = math.abs(bounds.x - x) + math.abs(bounds.y - y)
            if math.abs(bounds.x - x) <= 64 and math.abs(bounds.y - y) <= 64 and
                (not bestDistance or distance < bestDistance) then
                fallback, bestDistance = bounds, distance
            end
        end
    end
    return fallback
end

local function area()
    local source = SKIN:GetVariable('@')
    display = display or dofile(source .. 'DisplayState.lua')
    local monitors, updated, skins, stale = display.read(SKIN:GetVariable('MonitorSnapshotFile',source .. 'Cache/monitors.txt'))
    if stale then
        -- Retain known display identities only for origins Rainmeter still
        -- reports as active. Manual placement can work during a helper restart.
        for _, monitor in ipairs(stale) do
            local bounds = availableAt(monitor.x,monitor.y)
            if bounds then
                monitors = monitors or {}
                monitor.x,monitor.y,monitor.w,monitor.h = bounds.x,bounds.y,bounds.w,bounds.h
                monitors[#monitors + 1] = monitor
            end
        end
    end
    local previousRole = SKIN:GetVariable('LayoutDisplayRole', '')
    if fullscreen.active == nil then fullscreen.active = previousRole == 'laptop' end
    if monitors then
        local external, laptop, primary = display.roles(monitors,
            SKIN:GetVariable('LayoutExternalId',''):upper(), SKIN:GetVariable('LayoutLaptopId',''):upper())
        local occupied = display.stabilize(fullscreen, external, updated)
        local mode = SKIN:GetVariable('LayoutPlacement','auto')
        local selected
        if mode == 'laptop' then selected = laptop or external
        elseif mode == 'external' then selected = external or laptop
        elseif occupied then selected = laptop or external
        else selected = external or laptop end
        selected = selected or primary
        -- The helper detects fullscreen in physical pixels. Rainmeter can see a
        -- smaller work area on a scaled monitor and clamps moves to that area.
        local bounds = availableAt(selected.x, selected.y)
        if bounds then selected.x, selected.y, selected.w, selected.h = bounds.x, bounds.y, bounds.w, bounds.h end
        return selected, skins
    end

    display.stabilize(fullscreen)
    -- The helper may be restarting. Preserve the last destination while
    -- Rainmeter still reports a live work area at its origin.
    local x = lastBounds and lastBounds.x or tonumber(SKIN:GetVariable('LayoutWorkX'))
    local y = lastBounds and lastBounds.y or tonumber(SKIN:GetVariable('LayoutWorkY'))
    if x and y then
        local bounds = availableAt(x,y)
        if bounds then
            bounds.id = lastBounds and lastBounds.id or SKIN:GetVariable('LayoutDisplayId', '')
            bounds.role = lastBounds and lastBounds.role or previousRole
            bounds.dpi = lastBounds and lastBounds.dpi or num('LayoutDisplayDpi', 100)
            return bounds, skins
        end
    end
    return rainmeterArea(math.max(0, math.floor(num('LayoutMonitor',0)))) or rainmeterArea(0) or
        {x=0,y=0,w=1920,h=1080}, skins
end

local function syncArea(bounds, skins, root)
    local source = SKIN:GetVariable('@')
    local path = SKIN:GetVariable('LayoutStateFile',source .. 'Cache/Display.inc')
    store = store or dofile(source .. 'FileStore.lua')
    cached = cached or store.recover(path) or ''
    local content = ('[Variables]\nLayoutWorkWidth=%d\nLayoutWorkHeight=%d\nLayoutWorkX=%d\nLayoutWorkY=%d\n' ..
        'LayoutDisplayId=%s\nLayoutDisplayRole=%s\nLayoutDisplayDpi=%d\nLayoutIsLaptop=%d\n'):format(
        bounds.w,bounds.h,bounds.x,bounds.y,bounds.id or '',bounds.role or '',bounds.dpi or 100,bounds.role == 'laptop' and 1 or 0)
    local changed = cached:gsub('LayoutRefreshPending=[^\n]*\n$', '') ~= content
    if not skins then
        if not changed then return true end
        if not store.write(path,content) then return false end
        cached = content
        SKIN:Bang('!RefreshGroup','SlateHUD')
        return false
    end

    -- Rainmeter refreshes reset runtime hiding. Defer the geometry reload
    -- for a hidden skin until it is shown again. Its window can still move.
    local oldPending, pending, refresh = {}, {}, {}
    for name in (cached:match('LayoutRefreshPending=([^\n]*)') or ''):gmatch('%a+') do oldPending[name] = true end
    for _, name in ipairs(configs) do
        local visible = skins[name:lower()]
        if changed or oldPending[name] then
            if visible == false then pending[#pending + 1] = name
            elseif visible then refresh[#refresh + 1] = name end
        end
    end
    if #pending > 0 then content = content .. 'LayoutRefreshPending=' .. table.concat(pending, ',') .. '\n' end
    if cached ~= content then
        if not store.write(path,content) then return false end
        cached = content
    end
    for _, name in ipairs(refresh) do SKIN:Bang('!Refresh', configPath(root,name)) end
    return not changed
end

local function apply(force)
    local bounds, skins = area()
    lastBounds = bounds
    local root = SKIN:GetVariable('ROOTCONFIG','SlateHUD')
    if not syncArea(bounds,skins,root) then return end
    local wrap, history, laptopScale = num('LayoutMode',0)==1, num('NetHistory',0)==1, num('LaptopUiScale',0.95)
    local sysHistory = num('SysHistory',0)==1
    local preferred = num('PreferredUiScale',num('UiScale',1))
    local loaded = {}
    if skins then
        for _, name in ipairs(configs) do if skins[name:lower()] ~= nil then loaded[#loaded + 1] = name end end
    end
    local signature = table.concat({cached,preferred,tostring(wrap),tostring(history),tostring(sysHistory),laptopScale,tostring(num('BlurTightFrame',0)),table.concat(loaded,',')},':')
    if not force and signature == last then return end
    last = signature
    local positions, _, scale = PlanLayout(bounds, preferred, wrap, history, laptopScale, sysHistory)
    for key, point in pairs(positions) do
        local name = key == '' and 'Root' or key
        if not skins or skins[name:lower()] ~= nil then
            SKIN:Bang('!Move', math.floor(point.x), math.floor(point.y), configPath(root,name))
        end
    end
    -- Notes can be loaded without Games. Place it in the right column first;
    -- an active Game Hub then docks it below its actual card.
    if not skins or skins.notes ~= nil then
        if not skins or not skins.games then
            local m = layoutMetrics()
            local notesX = positions.Games.x + (m.wideCardW - m.statCardW) * scale
            SKIN:Bang('!Move', math.floor(notesX), math.floor(positions.Games.y), root .. '\\Notes')
        end
        if not skins or skins.games then SKIN:Bang('!CommandMeasure','MeasureGameHub','PlaceNotes()',root .. '\\Games') end
    end
end
local function userSettingsPath()
    if not ctxMenu then
        local base = scriptDir ~= '' and scriptDir or SKIN:GetVariable('@', '')
        ctxMenu = dofile(base .. 'ContextMenu.lua')
    end
    return ctxMenu.ensureUserSettings(SKIN)
end
function Apply() apply(true) end
function Toggle()
    SKIN:Bang('!WriteKeyValue','Variables','LayoutMode',num('LayoutMode',0)==1 and '0' or '1',userSettingsPath())
    SKIN:Bang('!RefreshGroup','SlateHUD')
end
function Update()
    apply(false)
    return 0
end
