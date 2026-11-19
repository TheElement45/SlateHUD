-- Only launch recovery when the daemon's independent heartbeat is stale.
local attemptedAt
function Check()
    local now = os.time()
    local customPath = SKIN:GetVariable('HelperHealthFile', '')
    local text = ''
    if customPath == '' and SKIN and SKIN.GetMeasure then
        local bridge = SKIN:GetMeasure('MeasureHealthBridge')
        text = bridge and bridge.GetStringValue and bridge:GetStringValue() or ''
    end
    if text == '' then
        local path = customPath ~= '' and customPath or (SKIN:GetVariable('@') .. 'Cache/helper-health.txt')
        local file = io.open(path, 'r')
        text = file and file:read('*a') or ''
        if file then file:close() end
    end
    local updated = tonumber(text:match('^UPDATED=(%d+)%s*$'))
    if updated and updated <= now + 1 and now - updated <= 15 then return end
    if attemptedAt and now >= attemptedAt and now - attemptedAt < 15 then return end
    attemptedAt = now
    SKIN:Bang('!CommandMeasure', 'MeasureHelper', 'Run')
end
function Update()
    Check()
    return 0
end
