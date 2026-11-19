local Display = {}

function Display.read(path, now)
    local text
    if SKIN and SKIN.GetMeasure and SKIN.GetVariable and
        SKIN:GetVariable('VisualMode', '0') ~= '3' and SKIN:GetVariable('MonitorSnapshotFile', '') == '' then
        local bridge = SKIN:GetMeasure('MeasureMonitorsBridge')
        local bridged = bridge and bridge.GetStringValue and bridge:GetStringValue() or ''
        if bridged ~= '' then text = bridged end
    end
    if not text then
        local file = io.open(path, 'r')
        if not file then return end
        text = file:read('*a')
        file:close()
    end
    local updated = tonumber(text:match('^UPDATED=(%d+)\r?\n'))
    now = now or os.time()
    if not updated or updated > now + 1 then return end

    local monitors, skins = {}, nil
    for line in text:gmatch('[^\r\n]+') do
        local id, role, primary, dpi, x, y, w, h, occupied =
            line:match('^(%x+)\t(%a+)\t([01])\t(%d+)\t(-?%d+)\t(-?%d+)\t(%d+)\t(%d+)\t([01?])$')
        if id and tonumber(w) > 0 and tonumber(h) > 0 then
            monitors[#monitors + 1] = {id=id, role=role, primary=primary=='1', dpi=tonumber(dpi),
                x=tonumber(x), y=tonumber(y), w=tonumber(w), h=tonumber(h), occupancy=occupied}
        elseif line == 'SKINS=1' then
            skins = {}
        elseif not line:match('^UPDATED=%d+$') then
            local config, visible = line:match('^SKIN\t([^\t]+)\t([01])$')
            if not skins or not config then return end
            skins[config:lower()] = visible == '1'
        end
    end
    if #monitors == 0 then return end
    table.sort(monitors, function(a, b)
        if a.primary ~= b.primary then return a.primary end
        return a.id < b.id
    end)
    if now - updated > 4 then return nil, nil, skins, monitors end
    return monitors, updated, skins
end

function Display.roles(monitors, externalId, laptopId)
    local external, laptop
    for _, monitor in ipairs(monitors) do
        if monitor.id == externalId then external = monitor end
        if monitor.id == laptopId then laptop = monitor end
    end
    for _, monitor in ipairs(monitors) do
        if not external and monitor.role == 'external' and monitor ~= laptop then external = monitor end
        if not laptop and monitor.role == 'laptop' and monitor ~= external then laptop = monitor end
    end
    if not external then
        for _, monitor in ipairs(monitors) do
            if monitor.role == 'unknown' and monitor ~= laptop then external = monitor; break end
        end
    end
    return external, laptop, monitors[1]
end

-- Require new samples spanning the delay. Re-reading the same file, including
-- after the helper stalls, must never settle a pending transition.
function Display.stabilize(state, external, updated)
    local value
    if updated then
        if not external then value = false
        elseif external.occupancy ~= '?' then value = external.occupancy == '1' end
    end
    local identity = external and external.id or ''
    if value == nil or value == state.active then
        state.pending, state.since = nil, nil
    elseif state.pending ~= value or state.identity ~= identity or updated < state.since or updated - state.last > 2 then
        state.pending, state.since = value, updated
    elseif updated - state.since >= 2 then
        state.active, state.pending = value, nil
    end
    state.last, state.identity = updated, identity
    return state.active
end

return Display
