-- WebParser handles periodic requests; failures back off independently per family.
local failures, identity, pingReady, pingStarted, lastRefresh
local providers, selected, attempted, pending
local pingEnabled, ctxMenu
local scriptDir = type(debug) == 'table' and debug.getinfo and (debug.getinfo(1, 'S').source:match('^@?(.*[/\\])') or '') or ''

local function set(name, value)
    SKIN:Bang('!SetVariable', name, tostring(value))
end

local function render()
    SKIN:Bang('!UpdateMeasureGroup', 'NetworkDisplay')
    SKIN:Bang('!UpdateMeterGroup', 'NetworkUI')
    SKIN:Bang('!Redraw')
end

local function lookup(family)
    return family == 4 and 'measureIPv4Lookup' or 'measureIPv6Lookup'
end

local function networkIdentity()
    return table.concat({
        SKIN:GetMeasure('measureAdapterID'):GetStringValue(),
        SKIN:GetMeasure('measureLANIP'):GetStringValue(),
        tostring(SKIN:GetMeasure('measureConnectivityV4'):GetValue()),
        tostring(SKIN:GetMeasure('measureConnectivityV6'):GetValue())
    }, '|')
end

local function validIPv4(address)
    local a, b, c, d = address:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
    if not a then return false end
    for _, part in ipairs({a, b, c, d}) do
        if #part > 3 or tonumber(part) > 255 then return false end
    end
    return true
end

local function validIPv6(address)
    if not address:find(':', 1, true) or address:find('[^%x:.]') then return false end
    -- An embedded IPv4 suffix occupies two 16-bit groups.
    if address:find('.', 1, true) then
        local prefix, suffix = address:match('^(.*:)([^:]+)$')
        if not prefix or not validIPv4(suffix) then return false end
        address = prefix .. '0:0'
    end
    local compression = address:find('::', 1, true)
    if address:find(':::', 1, true) then return false end
    if address:sub(1, 1) == ':' and address:sub(1, 2) ~= '::' then return false end
    if address:sub(-1) == ':' and address:sub(-2) ~= '::' then return false end
    if compression and address:find('::', compression + 2, true) then return false end
    if not compression and (address:sub(1, 1) == ':' or address:sub(-1) == ':') then return false end
    local count = 0
    for group in address:gmatch('[^:]+') do
        if #group > 4 then return false end
        count = count + 1
    end
    return (compression and count < 8) or (not compression and count == 8)
end

local function contextMenu()
    if not ctxMenu then
        local base = scriptDir ~= '' and scriptDir or SKIN:GetVariable('@', '')
        ctxMenu = dofile(base .. 'ContextMenu.lua')
    end
    return ctxMenu
end

local function syncContextMenu()
    contextMenu().syncSuite(SKIN)
    local hist = SKIN:GetVariable('NetHistory', '0') == '1' and 'On' or 'Off'
    local ping = SKIN:GetVariable('NetPingEnabled', '0') == '1' and 'On' or 'Off'
    local scaleMode = SKIN:GetVariable('NetAutoScale', '1') == '1' and 'Auto' or 'Fixed'
    SKIN:Bang('!SetOption', 'Rainmeter', 'ContextTitle20', 'Toggle traffic history (' .. hist .. ')')
    SKIN:Bang('!SetOption', 'Rainmeter', 'ContextTitle21', 'Toggle ping monitoring (' .. ping .. ')')
    SKIN:Bang('!SetOption', 'Rainmeter', 'ContextTitle22', 'Switch traffic scale (' .. scaleMode .. ')')
end

function Initialize()
    failures = {[4] = 0, [6] = 0}
    providers, selected, attempted, pending = {}, {}, {}, {}
    for _, family in ipairs({4, 6}) do
        providers[family] = {
            SKIN:GetVariable('NetIPv' .. family .. 'PrimaryURL'),
            SKIN:GetVariable('NetIPv' .. family .. 'FallbackURL')
        }
        selected[family], attempted[family] = 1, 0
    end
    identity, pingReady, lastRefresh = nil, false, nil
    pingEnabled = SKIN:GetVariable('NetPingEnabled', '1') == '1'
    pingStarted = pingEnabled and os.time() or nil
    set('NetScaleText', SKIN:GetVariable('NetAutoScale', '1') == '1' and 'Auto' or 'Fixed')
    syncContextMenu()
end

function LookupFailed(family)
    attempted[family] = attempted[family] + 1
    selected[family] = selected[family] % #providers[family] + 1
    SKIN:Bang('!SetOption', lookup(family), 'URL', providers[family][selected[family]])
    SKIN:Bang('!CommandMeasure', lookup(family), 'Reset')
    local v4 = SKIN:GetMeasure('measureConnectivityV4'):GetValue()
    local v6 = SKIN:GetMeasure('measureConnectivityV6'):GetValue()
    local label = v4 < 0 and v6 < 0 and 'Offline' or 'Lookup failed'
    if family == 6 and v6 < 0 and v4 >= 0 then label = 'No IPv6' end
    if attempted[family] < #providers[family] then
        -- Defer until the next script update, after WebParser's worker exits.
        -- Do not spend a backoff step until both services have failed.
        pending[family] = true
        label = 'Checking...'
    else
        pending[family], attempted[family] = nil, 0
        failures[family] = math.min(failures[family] + 1, 5)
        local retry = math.min(60 * 2 ^ (failures[family] - 1), 900)
        SKIN:Bang('!SetOption', lookup(family), 'UpdateRate', tostring(retry))
    end
    set('NetIPv' .. family .. 'Text', label)
    if family == 6 then set('NetIPv6State', label) end
    render()
end

function LookupFinished(family)
    local address = SKIN:GetMeasure(lookup(family)):GetStringValue():match('^%s*(.-)%s*$')
    if not (family == 4 and validIPv4(address) or family == 6 and validIPv6(address)) then
        LookupFailed(family)
        return
    end
    failures[family], attempted[family], pending[family] = 0, 0, nil
    -- Keep the working provider for periodic checks until it fails or is refreshed.
    SKIN:Bang('!SetOption', lookup(family), 'UpdateRate', '900')
    set('NetIPv' .. family .. 'Text', address)
    set('NetIPv' .. family .. 'Last', os.date('%Y-%m-%d %H:%M:%S'))
    if family == 6 then set('NetIPv6State', 'Available') end
    render()
end

function PingFinished()
    if not pingEnabled then return end
    -- Read on the next skin update, after the plugin has published its result.
    pingReady = true
end

function RefreshAll(networkChanged)
    local now = os.time()
    -- Suppress double-click request bursts, but always follow a changed network.
    if not networkChanged and lastRefresh and now - lastRefresh < 2 then return end
    lastRefresh = now
    SKIN:Bang('!UpdateMeasureGroup', 'NetworkIdentity')
    identity = networkIdentity()
    for _, family in ipairs({4, 6}) do
        failures[family], selected[family], attempted[family], pending[family] = 0, 1, 0, nil
        set('NetIPv' .. family .. 'Text', 'Checking...')
        SKIN:Bang('!SetOption', lookup(family), 'URL', providers[family][1])
        SKIN:Bang('!SetOption', lookup(family), 'UpdateRate', '900')
        SKIN:Bang('!CommandMeasure', lookup(family), 'Reset')
        SKIN:Bang('!UpdateMeasure', lookup(family))
        SKIN:Bang('!CommandMeasure', lookup(family), 'Update')
    end
    set('NetIPv6State', 'Checking...')
    if pingEnabled then
        set('NetPingText', 'Checking...')
        SKIN:Bang('!SetOption', 'meterPingValue', 'FontColor', SKIN:GetVariable('colorText'))
        pingReady, pingStarted = false, now
        -- Ping has no force-update command. A temporary one-tick rate makes the next
        -- idle plugin update reset its counter; the following tick starts a request.
        SKIN:Bang('!SetOption', 'measurePing', 'UpdateRate', '1')
        SKIN:Bang('!UpdateMeasure', 'measurePing')
    end
    render()
end

local function userSettingsPath()
    return contextMenu().ensureUserSettings(SKIN)
end

function ToggleScale()
    local automatic = SKIN:GetVariable('NetAutoScale', '1') ~= '1'
    local value = automatic and '1' or '0'
    SKIN:Bang('!WriteKeyValue','Variables','NetAutoScale',value,userSettingsPath())
    set('NetAutoScale', value)
    set('NetScaleText', automatic and 'Auto' or 'Fixed')
    syncContextMenu()
    -- Leave the traffic measures on their one-second cadence.
    render()
end

function ToggleHistory()
    local value = SKIN:GetVariable('NetHistory','0') == '1' and '0' or '1'
    SKIN:Bang('!WriteKeyValue','Variables','NetHistory',value,userSettingsPath())
    SKIN:Bang('!SetVariable','NetHistory',value,SKIN:GetVariable('ROOTCONFIG','SlateHUD')..'\\System')
    SKIN:Bang('!Refresh')
end

function TogglePing()
    local value = SKIN:GetVariable('NetPingEnabled','0') == '1' and '0' or '1'
    SKIN:Bang('!WriteKeyValue','Variables','NetPingEnabled',value,userSettingsPath())
    SKIN:Bang('!Refresh')
end

function Update()
    local function ceiling(name)
        local measure = SKIN:GetMeasure(name)
        local value = measure and measure.GetMaxValue and measure:GetMaxValue() or 0
        if value >= 1048576 then return string.format('%.1f MB/s', value / 1048576) end
        return string.format('%.1f kB/s', value / 1024)
    end
    set('NetScaleCeilings', 'Down ' .. ceiling('measureNetIn') .. ' / Up ' .. ceiling('measureNetOut'))
    local current = networkIdentity()
    if identity and current ~= identity then RefreshAll(true) end
    identity = current
    for _, family in ipairs({4, 6}) do
        if pending[family] then
            pending[family] = nil
            -- Apply the dynamic URL before forcing the next request.
            SKIN:Bang('!UpdateMeasure', lookup(family))
            SKIN:Bang('!CommandMeasure', lookup(family), 'Update')
        end
    end
    if pingEnabled and pingReady then
        local value = SKIN:GetMeasure('measurePing'):GetValue()
        local color = 'colorText'
        if value < 0 or value >= 2001 then
            set('NetPingText', 'Timeout')
            color = 'ColorCrit'
        else
            set('NetPingText', string.format('%.0f ms', value))
            if value >= tonumber(SKIN:GetVariable('CritPing', '150')) then color = 'ColorCrit'
            elseif value >= tonumber(SKIN:GetVariable('WarnPing', '80')) then color = 'ColorWarn' end
        end
        SKIN:Bang('!SetOption', 'meterPingValue', 'FontColor', SKIN:GetVariable(color))
        SKIN:Bang('!SetOption', 'measurePing', 'UpdateRate', '5')
        pingReady, pingStarted = false, os.time()
    elseif pingStarted and os.time() - pingStarted >= 10 then
        -- DNS/plugin failures may not execute FinishAction.
        set('NetPingText', 'Unavailable')
        SKIN:Bang('!SetOption', 'meterPingValue', 'FontColor', SKIN:GetVariable('ColorCrit'))
        SKIN:Bang('!SetOption', 'measurePing', 'UpdateRate', '5')
        pingStarted = nil
    end
    return 0
end
