local capabilities = {}
local active = false
local connected = false
local lastText, lastConnected
local options, variables, visibility = {}, {}, {}
local function option(meter, key, value)
    local id = meter .. ':' .. key
    if options[id] == value then return end
    options[id] = value
    SKIN:Bang('!SetOption', meter, key, value)
end
local function show(name, visible, group)
    visible = not not visible
    if visibility[name] == visible then return end
    visibility[name] = visible
    SKIN:Bang((visible and '!ShowMeter' or '!HideMeter') .. (group and 'Group' or ''), name)
end
function MediaConnected(text, now)
    local updated = tonumber(text:match('^UPDATED=(%d+)\r?\nCONNECTED=1%s*$'))
    return updated and updated <= now + 1 and now - updated <= 5
end
function ParseMedia(text)
    local fields, start = {}, 1
    while start <= #text do
        local ending = text:find('||',start,true)
        local field = text:sub(start,ending and ending-1 or #text)
        local key,value = field:match('^([A-Z]+)=(.*)$')
        if key then fields[key]=value end
        if not ending then break end
        start=ending+2
    end
    return fields
end
local function readStream(measureName, fileVar, defaultPath, mode)
    local customPath = SKIN and SKIN.GetVariable and SKIN:GetVariable(fileVar, '') or ''
    if customPath == '' and SKIN and SKIN.GetMeasure then
        local bridge = SKIN:GetMeasure(measureName)
        local bridged = bridge and bridge.GetStringValue and bridge:GetStringValue() or ''
        if bridged ~= '' then return bridged end
    end
    local path = customPath ~= '' and customPath or defaultPath
    local file = io.open(path, mode or 'r')
    local content = file and file:read('*a') or ''
    if file then file:close() end
    return content
end
function Update()
    local source = SKIN:GetVariable('@')
    local heartbeat = readStream('MeasureMediaHealthBridge', 'MediaHealthFile', source .. 'Cache/media-health.txt', 'r')
    connected = MediaConnected(heartbeat, os.time())
    local text = readStream('MeasureMediaBridge', 'MediaStatusFile', source .. 'Cache/media.txt', 'rb')
    if text == lastText and connected == lastConnected then return 0 end
    lastText, lastConnected = text, connected
    local fields = connected and ParseMedia(text) or {}
    local state = tonumber(fields.STATE) or 0
    local player = fields.PLAYER
    active = player and player ~= '' or state > 0
    local playerName = player
    if player and player:lower() == 'com.github.th-ch.youtube-music' then
        playerName = 'YouTube Music'
    end
    local title = fields.TITLE or ''
    if title == '' or title == 'No Track Playing' then title='Nothing playing' end
    local artist = fields.ARTIST or ''
    if artist == '' or artist == 'Unknown Artist' then artist='Play music in any app' end
    if not connected then
        title, artist = 'Media helper offline', 'Waiting for a connection'
    end
    local cover = fields.COVER or ''
    local image = cover ~= '' and io.open(cover,'rb')
    if image then image:close() else cover='' end
    for name,value in pairs({MediaTitle=title,MediaArtist=artist,MediaPosition=fields.POS or '00:00',
        MediaDuration=fields.DUR or '00:00',MediaProgress=tostring(math.max(0,math.min(100,tonumber(fields.PROG) or 0))),
        MediaCover=cover,MediaSession=playerName and playerName~='' and playerName or (connected and 'None' or 'Offline'),
        MediaStateIcon=state==1 and '[\\xE769]' or '[\\xE768]'}) do
        if variables[name] ~= value then
            variables[name] = value
            SKIN:Bang('!SetVariable',name,value)
        end
    end
    show('MeterAlbumArt', cover ~= '')
    capabilities = {}
    local names = {'prev', 'playpause', 'next', 'seek'}
    local index = 1
    for value in (fields.CAPS or '0,0,0,0'):gmatch('%d') do
        if index > 4 then break end
        capabilities[names[index]] = value == '1'; index = index + 1
    end
    local timeline = active and (fields.DUR or '00:00') ~= '00:00'
    show('MediaTimeline', timeline, true)
    option('MeterTrackTitle', 'Y', timeline and '((27+#CardShiftY#)*#UiScale#)' or '((36+#CardShiftY#)*#UiScale#)')
    option('MeterArtistName', 'Y', timeline and '((47+#CardShiftY#)*#UiScale#)' or '((58+#CardShiftY#)*#UiScale#)')
    for command, meter in pairs({prev='MeterPrevButton',playpause='MeterPlayPauseButton',next='MeterNextButton'}) do
        local available = connected and (active and capabilities[command] or command == 'playpause' and not active)
        local color = available and (command == 'playpause' and '#ColorAccent#' or '#ColorPrimary#') or '#ColorMuted#'
        option(meter, 'FontColor', color)
        option(meter, 'MouseActionCursor', available and '1' or '0')
        option(meter, 'ToolTipText', not available and 'Not supported by this player' or
            command == 'playpause' and (active and 'Play / Pause' or 'Open music app') or command == 'prev' and 'Previous track' or 'Next track')
        local hoverColor = command == 'playpause' and '#ColorPrimary#' or '#ColorAccent#'
        option(meter, 'MouseOverAction', available and
            '[!SetOption ' .. meter .. ' FontColor "' .. hoverColor .. '"][!UpdateMeter ' .. meter .. '][!Redraw]' or '')
    end
    option('MeterNextPlayer', 'MouseActionCursor', connected and '1' or '0')
    option('MeterNextPlayer', 'FontColor', connected and '#ColorSecondary#' or '#ColorMuted#')
    option('MeterNextPlayer', 'ToolTipText', 'Left-click: switch player | Middle-click: lock player | Right-click: automatic player#CRLF#Current: [MeasureSession]')
    option('MeterSeekTarget', 'MouseActionCursor', capabilities.seek and '1' or '0')
    option('MeterProgressBar', 'BarColor', capabilities.seek and '#ColorAccent#' or '#ColorMuted#')
    return 0
end
local function canAnimate()
    if not SKIN or SKIN:GetVariable('UiAnimations', '0') ~= '1' then return false end
    if SKIN:GetVariable('UiAnimationsBatterySaver', '1') == '1' and SKIN.GetMeasure then
        local power = SKIN:GetMeasure('MeasureAnimPower')
        if power and power.GetValue then
            SKIN:Bang('!UpdateMeasure', 'MeasureAnimPower')
            if power:GetValue() == 0 then return false end
        end
    end
    return true
end
function RestoreProgress()
    options['MeterProgressBar:BarColor'] = nil
    option('MeterProgressBar', 'BarColor', capabilities.seek and '#ColorAccent#' or '#ColorMuted#')
    SKIN:Bang('!UpdateMeter', 'MeterProgressBar')
    SKIN:Bang('!Redraw')
end
function FlashVolume()
    if not canAnimate() then return end
    SKIN:Bang('!CommandMeasure', 'MeasureUiAnim', 'Stop 2')
    SKIN:Bang('!CommandMeasure', 'MeasureUiAnim', 'Execute 2')
end
function RestoreControls()
    -- Hover actions change colors outside this script's cache.
    for _, meter in ipairs({'MeterPrevButton','MeterPlayPauseButton','MeterNextButton'}) do
        options[meter .. ':FontColor'] = nil
    end
    lastText = nil
    Update()
end
function Control(command, percent)
    if not connected then return end
    if command == 'playpause' and not active then
        SKIN:Bang('!EnableMeasure', 'MeasureOpenMusic'); SKIN:Bang('!UpdateMeasure', 'MeasureOpenMusic'); SKIN:Bang('!DisableMeasure', 'MeasureOpenMusic')
        return
    end
    if command ~= 'nextplayer' and command ~= 'resetplayer' and command ~= 'lockplayer' and command ~= 'refetchcover' and (not active or not capabilities[command]) then return end
    local parameter = command
    if command == 'seek' then
        parameter = 'seek ' .. math.max(0, math.min(100, tonumber(percent) or 0))
        if canAnimate() then
            SKIN:Bang('!CommandMeasure', 'MeasureUiAnim', 'Stop 1')
            SKIN:Bang('!CommandMeasure', 'MeasureUiAnim', 'Execute 1')
        end
    end
    if SKIN and SKIN.GetMeasure and SKIN:GetVariable('MediaStatusFile', '') == '' then
        local bridge = SKIN:GetMeasure('MeasureMediaBridge')
        if bridge and bridge.GetStringValue and bridge:GetStringValue() ~= '' then
            SKIN:Bang('!CommandMeasure', 'MeasureMediaBridge', parameter)
            return
        end
    end
    SKIN:Bang('!SetOption', 'MeasureSMTCCmd', 'Parameter', parameter)
    SKIN:Bang('!UpdateMeasure', 'MeasureSMTCCmd'); SKIN:Bang('!CommandMeasure', 'MeasureSMTCCmd', 'Run')
end
function FinishControl(pipeOutput)
    local output = pipeOutput
    if not output or output == '' then
        local measure = SKIN.GetMeasure and SKIN:GetMeasure('MeasureSMTCCmd')
        output = measure and measure.GetStringValue and measure:GetStringValue() or ''
    end
    if output:find('MEDIA:ERROR', 1, true) then
        local message = output:match('MEDIA:ERROR%s*(.-)%s*$')
        if not message or message == '' then message = 'Media command failed' end
        variables.MediaSession = 'Command failed'
        SKIN:Bang('!SetVariable', 'MediaSession', 'Command failed')
        option('MeterNextPlayer', 'FontColor', '#ColorCrit#')
        option('MeterNextPlayer', 'ToolTipText', message)
        SKIN:Bang('!UpdateMeasureGroup', 'SMTC')
        SKIN:Bang('!UpdateMeter', '*')
        SKIN:Bang('!Redraw')
        return
    end
    Update()
    SKIN:Bang('!UpdateMeasureGroup', 'SMTC')
    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
end
