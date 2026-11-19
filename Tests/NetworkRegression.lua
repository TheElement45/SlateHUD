-- No real requests or Rainmeter settings are changed; exercise callback sequences.
function RunNetworkTests(root)
    local function check(value, message) if not value then error(message, 2) end end
    local vars = {NetAutoScale = '1', ['@']=root..'/@Resources/', CURRENTPATH=root..'/Network/',
        colorText = 'normal', ColorWarn = 'warn', ColorCrit = 'critical',
        WarnPing = '80', CritPing = '150',
        NetIPv4PrimaryURL = 'https://ipv4.icanhazip.com', NetIPv4FallbackURL = 'https://4.ident.me',
        NetIPv6PrimaryURL = 'https://ipv6.icanhazip.com', NetIPv6FallbackURL = 'https://6.ident.me'}
    local values = {measureAdapterID = 'wifi-guid', measureLANIP = '192.0.2.10',
        measureConnectivityV4 = 1, measureConnectivityV6 = 1, measurePing = 0}
    local calls, options = {}, {}
    SKIN = {}
    function SKIN:GetVariable(name, fallback) return vars[name] or fallback end
    function SKIN:GetMeasure(name)
        return {GetStringValue = function() return tostring(values[name] or '') end,
            GetValue = function() return tonumber(values[name]) or 0 end}
    end
    function SKIN:Bang(command, name, option, value, path)
        calls[#calls + 1] = {command, name, option, value, path}
        if command == '!SetVariable' then vars[name] = option
        elseif command == '!SetOption' then
            options[name] = options[name] or {}; options[name][option] = value
        elseif command == '!CommandMeasure' and option == 'Reset' then values[name] = '' end
    end
    local function count(command, name, option, path)
        local found = 0
        for _, call in ipairs(calls) do
            if call[1] == command and (not name or call[2] == name) and (not option or call[3] == option) and
                (not path or call[5] == path) then
                found = found + 1
            end
        end
        return found
    end
    local clock = 10000
    local realTime = os.time
    os.time = function() return clock end
    dofile(root .. '/@Resources/Network.lua')
    Initialize()
    Update()
    check(count('!CommandMeasure') == 0, 'Initial identity triggered duplicate public requests')
    local function failBoth(family)
        LookupFailed(family)
        Update()
        LookupFailed(family)
    end

    -- Empty / malformed payloads must never reach the desktop or reveal tooltip.
    for _, address in ipairs({'', '999.1.2.3', '192.0.2.10<script>', '1.2.3', '1.2.3.4.5'}) do
        values.measureIPv4Lookup = address
        LookupFinished(4)
        check(vars.NetIPv4Text == 'Checking...' and values.measureIPv4Lookup == '', 'Bad IPv4 leaked during failover')
        Update()
        values.measureIPv4Lookup = address
        LookupFinished(4)
        check(vars.NetIPv4Text == 'Lookup failed', 'Invalid IPv4 published: ' .. address)
    end
    values.measureIPv4Lookup = '192.0.2.10\r\n'
    LookupFinished(4)
    check(vars.NetIPv4Text == '192.0.2.10', 'Valid IPv4 was not trimmed and published')
    check(options.measureIPv4Lookup.UpdateRate == '900', 'Successful lookup did not reset backoff')
    local lastSuccess = vars.NetIPv4Last
    for index, delay in ipairs({60, 120, 240, 480, 900, 900}) do
        local before = count('!CommandMeasure', 'measureIPv4Lookup', 'Update')
        LookupFailed(4)
        check(vars.NetIPv4Text == 'Checking...' and values.measureIPv4Lookup == '', 'Failover exposed cached IPv4')
        check(options.measureIPv4Lookup.URL == vars.NetIPv4FallbackURL, 'First failure did not select fallback')
        check(count('!CommandMeasure', 'measureIPv4Lookup', 'Update') == before, 'Failover ran inside worker callback')
        Update()
        check(count('!CommandMeasure', 'measureIPv4Lookup', 'Update') == before + 1, 'Fallback was not requested next update')
        LookupFailed(4)
        check(tonumber(options.measureIPv4Lookup.UpdateRate) == delay, 'Wrong retry delay at failure ' .. index)
        check(options.measureIPv4Lookup.URL == vars.NetIPv4PrimaryURL, 'Exhausted providers did not return to primary')
        Update()
        check(count('!CommandMeasure', 'measureIPv4Lookup', 'Update') == before + 1, 'Both failures caused a request loop')
        check(vars.NetIPv4Text == 'Lookup failed' and values.measureIPv4Lookup == '', 'Failed lookup exposed cached IPv4')
        check(vars.NetIPv4Last == lastSuccess, 'Failure changed the last-success timestamp')
    end
    for _, address in ipairs({'::', '::1', '2001:db8::1', '1:2:3:4:5:6:7:8', '::ffff:192.0.2.10'}) do
        values.measureIPv6Lookup = address
        LookupFinished(6)
        check(vars.NetIPv6State == 'Available' and vars.NetIPv6Text == address, 'Valid IPv6 rejected: ' .. address)
    end
    local lastV6 = vars.NetIPv6Last
    for _, address in ipairs({'', 'error: offline', '192.0.2.10', '1:2:3', '1::2::3', '1:::2',
        '12345::1', ':1::2', '1::2:', '1:2:3:4:5:6:7:8::', '::ffff:999.0.0.1'}) do
        values.measureIPv6Lookup = address
        LookupFinished(6)
        check(vars.NetIPv6State == 'Checking...' and values.measureIPv6Lookup == '', 'Bad IPv6 leaked during failover')
        Update()
        values.measureIPv6Lookup = address
        LookupFinished(6)
        check(vars.NetIPv6State == 'Lookup failed' and vars.NetIPv6Text == 'Lookup failed', 'Invalid IPv6 published: ' .. address)
    end
    check(vars.NetIPv6Last == lastV6, 'IPv6 failure changed last-success time')
    local v6Retry = options.measureIPv6Lookup.UpdateRate
    values.measureIPv4Lookup = '198.51.100.10'
    LookupFinished(4)
    check(vars.NetIPv4Text == '198.51.100.10' and options.measureIPv4Lookup.UpdateRate == '900', 'IPv4 failed to recover')
    check(options.measureIPv6Lookup.UpdateRate == v6Retry, 'IPv4 recovery changed independent IPv6 retry timing')
    print('PASS: IPv4/IPv6 validation, stale-result clearing, independent retry backoff and success timestamps')

    local requests = count('!CommandMeasure', nil, 'Update')
    values.measureAdapterID, values.measureLANIP = 'ethernet-guid', '198.51.100.10'
    Update()
    check(count('!CommandMeasure', nil, 'Update') == requests + 2, 'Adapter change did not refresh both families')
    check(vars.NetIPv4Text == 'Checking...' and vars.NetIPv6State == 'Checking...', 'Network change left old status visible')
    Update()
    check(count('!CommandMeasure', nil, 'Update') == requests + 2, 'Unchanged identity repeatedly refreshed')
    clock = clock + 5
    values.measureConnectivityV6 = -1
    Update()
    check(count('!CommandMeasure', nil, 'Update') == requests + 4, 'IPv6 connectivity change was missed')
    clock = clock + 5
    RefreshAll()
    local manualRequests = count('!CommandMeasure', nil, 'Update')
    RefreshAll()
    check(count('!CommandMeasure', nil, 'Update') == manualRequests, 'Double click caused duplicate request bursts')
    check(options.measurePing.UpdateRate == '1' and vars.NetPingText == 'Checking...', 'Refresh did not request a fresh ping')
    check(count('!UpdateMeasure', 'measureNetIn') == 0 and count('!UpdateMeasure', 'measureNetOut') == 0,
        'Refresh disturbed traffic sampling cadence')
    print('PASS: Adapter/connectivity changes, manual refresh, double-click suppression and traffic sampling cadence')

    for _, sample in ipairs({{0, '0 ms', 'normal'}, {79, '79 ms', 'normal'}, {80, '80 ms', 'warn'},
        {149, '149 ms', 'warn'}, {150, '150 ms', 'critical'}, {999, '999 ms', 'critical'},
        {2000, '2000 ms', 'critical'}, {2001, 'Timeout', 'critical'}, {-1, 'Timeout', 'critical'}}) do
        values.measurePing = sample[1]
        PingFinished()
        Update()
        check(vars.NetPingText == sample[2], 'Wrong ping display for ' .. sample[1])
        check(options.meterPingValue.FontColor == sample[3], 'Wrong ping severity for ' .. sample[1])
        check(options.measurePing.UpdateRate == '5', 'Fast ping rate was not restored')
    end
    clock = clock + 11
    Update()
    check(vars.NetPingText == 'Unavailable', 'Missing ping callback left a stale latency visible')
    values.measurePing = 25
    PingFinished()
    Update()
    check(vars.NetPingText == '25 ms', 'Ping did not recover after failure')
    check(options.Rainmeter and options.Rainmeter.ContextTitle20 == 'Toggle traffic history (Off)' and
        options.Rainmeter.ContextTitle21 == 'Toggle ping monitoring (Off)' and
        options.Rainmeter.ContextTitle22 == 'Switch traffic scale (Auto)',
        'Initial Network context menu titles missing live state')
    local userSettings = vars['@'] .. 'UserSettings.inc'
    ToggleScale()
    check(vars.NetAutoScale == '0' and vars.NetScaleText == 'Fixed', 'Fixed scale toggle failed')
    check(options.Rainmeter.ContextTitle22 == 'Switch traffic scale (Fixed)',
        'Fixed scale toggle did not update ContextTitle22')
    ToggleScale()
    check(vars.NetAutoScale == '1' and vars.NetScaleText == 'Auto', 'Automatic scale toggle failed')
    check(options.Rainmeter.ContextTitle22 == 'Switch traffic scale (Auto)',
        'Automatic scale toggle did not update ContextTitle22')
    check(count('!WriteKeyValue','Variables','NetAutoScale',userSettings)==2,'Scale choices were not persisted to UserSettings.inc')
    ToggleHistory(); check(count('!WriteKeyValue','Variables','NetHistory',userSettings)==1 and count('!Refresh')==1 and
        count('!SetVariable','NetHistory','1')==1,
        'History toggle did not persist to UserSettings.inc and refresh layout')
    TogglePing(); check(count('!WriteKeyValue','Variables','NetPingEnabled',userSettings)==1 and count('!Refresh')==2,
        'Ping toggle did not persist to UserSettings.inc and refresh Network')
    print('PASS: Ping checking/timeout/recovery, threshold boundaries, missing callbacks and scale toggles')
    values.measureConnectivityV4,values.measureConnectivityV6=-1,-1
    Update()
    failBoth(4);failBoth(6)
    check(vars.NetIPv4Text=='Offline' and vars.NetIPv6State=='Offline','Disconnected network was shown as lookup failure')
    values.measureConnectivityV4=1
    Update()
    failBoth(6)
    check(vars.NetIPv6State=='No IPv6','IPv4-only connection was shown as offline')
    failBoth(4)
    check(vars.NetIPv4Text=='Lookup failed','Public lookup failure implied an offline connection')
    print('PASS: Offline, IPv4-only and public lookup failure states remain distinct')

    -- Recovery keeps the working service; failures in one family cannot switch the other.
    Initialize()
    Update()
    local v6Before = count('!CommandMeasure', 'measureIPv6Lookup', 'Update')
    LookupFailed(4)
    Update()
    values.measureIPv4Lookup = '198.51.100.20\n'
    LookupFinished(4)
    check(vars.NetIPv4Text == '198.51.100.20' and options.measureIPv4Lookup.UpdateRate == '900', 'Fallback did not recover IPv4')
    check(options.measureIPv4Lookup.URL == vars.NetIPv4FallbackURL, 'Fallback success abandoned working service')
    check(count('!CommandMeasure', 'measureIPv6Lookup', 'Update') == v6Before, 'IPv4 failover requested IPv6')
    LookupFailed(4)
    check(options.measureIPv4Lookup.URL == vars.NetIPv4PrimaryURL, 'Failed fallback did not try primary')
    Update()
    LookupFailed(4)
    check(options.measureIPv4Lookup.UpdateRate == '60', 'Recovery did not reset backoff')
    LookupFailed(6)
    check(options.measureIPv6Lookup.URL == vars.NetIPv6FallbackURL, 'IPv6 fallback was not selected')
    Update()
    values.measureIPv6Lookup = '2001:db8::20\n'
    LookupFinished(6)
    check(vars.NetIPv6State == 'Available' and options.measureIPv6Lookup.UpdateRate == '900', 'IPv6 fallback did not recover')
    check(options.measureIPv6Lookup.URL == vars.NetIPv6FallbackURL, 'IPv6 fallback success abandoned working service')
    LookupFailed(4)
    clock = clock + 5
    RefreshAll()
    local afterRefresh = count('!CommandMeasure', nil, 'Update')
    Update()
    check(count('!CommandMeasure', nil, 'Update') == afterRefresh, 'Manual refresh left a queued fallback request')
    check(options.measureIPv4Lookup.URL == vars.NetIPv4PrimaryURL and options.measureIPv6Lookup.URL == vars.NetIPv6PrimaryURL,
        'Manual refresh did not restore both primary URLs')
    LookupFailed(4)
    values.measureAdapterID = 'new-guid'
    local beforeChange = count('!CommandMeasure', nil, 'Update')
    Update()
    check(count('!CommandMeasure', nil, 'Update') == beforeChange + 2, 'Network change also sent an obsolete fallback request')
    check(options.measureIPv4Lookup.URL == vars.NetIPv4PrimaryURL, 'Network change kept failed provider')
    print('PASS: Deferred provider failover, sticky recovery, independent families and refresh cancellation')
    os.time = realTime
end
