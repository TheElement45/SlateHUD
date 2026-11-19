-- Small INI editor for Notes. Preserve encoding, comments and unrelated sections;
-- callers publish the complete page with FileStore rather than separate key writes.
local Data = {}
local function utf8(n)
    if n < 128 then return string.char(n) end
    if n < 2048 then return string.char(192 + math.floor(n / 64), 128 + n % 64) end
    if n < 65536 then return string.char(224 + math.floor(n / 4096), 128 + math.floor(n / 64) % 64, 128 + n % 64) end
    return string.char(240 + math.floor(n / 262144), 128 + math.floor(n / 4096) % 64, 128 + math.floor(n / 64) % 64, 128 + n % 64)
end
local function decode(bytes)
    local bom = bytes:sub(1, 2)
    if bom ~= '\255\254' and bom ~= '\254\255' then
        if bytes:sub(1, 3) == '\239\187\191' then return bytes:sub(4), 'bom' end
        return bytes, 'plain'
    end
    local little, out, i = bom == '\255\254', {}, 3
    local function unit(at)
        local a, b = bytes:byte(at, at + 1)
        if not b then return nil end
        return little and a + b * 256 or a * 256 + b
    end
    while i <= #bytes do
        local n = unit(i); if not n then return nil end
        i = i + 2
        if n >= 55296 and n <= 56319 then
            local low = unit(i)
            if not low or low < 56320 or low > 57343 then return nil end
            n = 65536 + (n - 55296) * 1024 + low - 56320; i = i + 2
        elseif n >= 56320 and n <= 57343 then return nil end
        out[#out + 1] = utf8(n)
    end
    return table.concat(out), little and 'le' or 'be'
end
local function encode(text, encoding)
    if encoding == 'plain' then return text end
    if encoding == 'bom' then return '\239\187\191' .. text end
    local out, i = {encoding == 'le' and '\255\254' or '\254\255'}, 1
    local function unit(n)
        local a, b = n % 256, math.floor(n / 256)
        out[#out + 1] = encoding == 'le' and string.char(a, b) or string.char(b, a)
    end
    while i <= #text do
        local n, length = text:byte(i), 1
        if n >= 240 then n, length = n - 240, 4
        elseif n >= 224 then n, length = n - 224, 3
        elseif n >= 192 then n, length = n - 192, 2 end
        for j = 1, length - 1 do
            local b = text:byte(i + j)
            if not b or b < 128 or b > 191 then return nil end
            n = n * 64 + b - 128
        end
        if n > 1114111 then return nil end
        if n >= 65536 then n = n - 65536; unit(55296 + math.floor(n / 1024)); unit(56320 + n % 1024)
        else unit(n) end
        i = i + length
    end
    return table.concat(out)
end
function Data.parse(bytes)
    if not bytes then return nil end
    local text, encoding = decode(bytes)
    if not text then return nil end
    local doc = {lines = {}, values = {}, encoding = encoding, newline = text:find('\r\n', 1, true) and '\r\n' or '\n'}
    local position, active, found = 1, false, false
    while position <= #text do
        local stop = text:find('\n', position, true)
        local raw = text:sub(position, stop or #text)
        local body = raw:gsub('[\r\n]+$', '')
        local section = body:match('^%s*%[([^%]]+)%]%s*$')
        if section then active = section:lower() == 'variables'; found = found or active end
        local key, value = body:match('^%s*([^;=%s][^=]-)%s*=(.*)$')
        key = active and key and key:match('^(.-)%s*$'):lower() or nil
        doc.lines[#doc.lines + 1] = {raw = raw, key = key, active = active}
        if key and doc.values[key] == nil then doc.values[key] = value end
        position = stop and stop + 1 or #text + 1
    end
    return found and doc or nil
end
function Data.get(doc, key, default) return doc.values[key:lower()] or default end
function Data.patch(doc, changes)
    local pending, out = {}, {}
    for key, value in pairs(changes) do pending[key:lower()] = {key, tostring(value)} end
    local function appendPending()
        local keys = {}; for key in pairs(pending) do keys[#keys + 1] = key end; table.sort(keys)
        for _, key in ipairs(keys) do
            if #out > 0 and out[#out]:sub(-1) ~= '\n' then out[#out + 1] = doc.newline end
            out[#out + 1] = pending[key][1] .. '=' .. pending[key][2] .. doc.newline
        end
        pending = {}
    end
    local lastActive
    for i, line in ipairs(doc.lines) do if line.active then lastActive = i end end
    for i, line in ipairs(doc.lines) do
        local change
        if line.key then
            for key, value in pairs(changes) do if key:lower() == line.key then change = tostring(value); break end end
        end
        if change ~= nil then
            out[#out + 1] = line.raw:match('^([^=]*=)') .. change .. (line.raw:match('(\r?\n)$') or '')
            pending[line.key] = nil
        else out[#out + 1] = line.raw end
        if i == lastActive then appendPending() end
    end
    return encode(table.concat(out), doc.encoding)
end
-- Use a calendar day boundary, not a fixed 24-hour duration (DST safe).
function Data.day(hour)
    local now = os.date('*t')
    if now.hour < hour then now.day = now.day - 1 end
    now.hour, now.min, now.sec, now.isdst = 12, 0, 0, nil
    return os.date('%Y-%m-%d', os.time(now))
end
function Data.rollover(doc, day)
    local changes = {}
    for row = 1, 5 do
        if Data.get(doc, 'Daily' .. row, '0') == '1' and Data.get(doc, 'Note' .. row, '') ~= '' then
            local previous = Data.get(doc, 'DailyDay' .. row, '')
            if not previous:match('^%d%d%d%d%-%d%d%-%d%d$') then
                changes['DailyDay' .. row] = day -- first use preserves today's checkbox
            elseif previous < day then
                changes['Status' .. row], changes['DailyDay' .. row] = '0', day
            end
        end
    end
    return changes
end
return Data
