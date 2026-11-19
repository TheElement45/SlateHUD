-- Timestamped GPU telemetry: absent, failed and stale samples never become zeros.
function ParseGpu(text, now)
    local stamp = tonumber(text:match('UPDATED=(%d+)'))
    if not stamp or now - stamp > 10 or stamp - now > 5 then return nil, 'Telemetry stale' end
    local line = text:match('^[^\r\n]+') or ''
    local _, commas = line:gsub(',', '')
    if commas ~= 5 then return nil, 'GPU unavailable' end
    local values = {}
    for value in line:gmatch('[^,]+') do
        local parsed = tonumber(value:match('^%s*(.-)%s*$'))
        if not parsed or parsed ~= parsed or math.abs(parsed) == math.huge then return nil, 'GPU unavailable' end
        values[#values + 1] = parsed
    end
    if #values ~= 6 or values[1] < 0 or values[1] > 100 or values[2] < 0 or
        values[3] <= 0 or values[2] > values[3] then return nil, 'GPU unavailable' end
    return values
end

function ParsePageFile(text, now)
    local stamp = tonumber(text:match('UPDATED=(%d+)'))
    if not stamp or now - stamp > 10 or stamp - now > 5 then return nil end
    local used, total = text:match('PAGEFILE=(%d+),(%d+)')
    used, total = tonumber(used), tonumber(total)
    if not used or not total or total < 0 or used < 0 or used > total then return nil end
    local pct = total > 0 and (used / total * 100) or 0
    return {used = used / 1073741824, total = total / 1073741824, pct = pct}
end

local options, variables, ctxMenu, lhmPendingUntil = {}, {}, nil, nil
local function trim(text) return tostring(text or ''):match('^%s*(.-)%s*$') end
local function isFinite(n) return type(n) == 'number' and n == n and math.abs(n) ~= math.huge end

local function hasFreshStamp(text, now)
    local stamp = tonumber((text or ''):match('UPDATED=(%d+)'))
    if not stamp or now - stamp > 10 or stamp - now > 5 then return nil end
    return stamp
end

function ParseCpuTemp(text, now)
    if not hasFreshStamp(text, now) then return nil end
    local raw = text:match('CPUTEMP=([^\r\n]+)')
    if not raw then return nil end
    local valStr, name = raw:match('^([^|]+)|(.*)$')
    local val = tonumber(trim(valStr))
    name = trim(name)
    if not isFinite(val) or val < -40 or val > 150 or name == '' then return nil end
    if name:lower():find('distance to tjmax', 1, true) then return nil end
    return val, name
end

function ParseLhmGpu(text, now)
    local stamp = hasFreshStamp(text, now)
    if not stamp then return nil, 'Telemetry stale' end
    local line = text:match('LHMGPU=([^\r\n]+)')
    if not line then return nil, 'LHM GPU unavailable' end
    local uStr, usedStr, totalStr, tempStr, powerStr, fanStr, fanUnitStr =
        line:match('^%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*(.-)%s*$')
    local usage = tonumber(uStr)
    if not isFinite(usage) or usage < 0 or usage > 100 then return nil, 'LHM GPU unavailable' end

    local usedMiB = tonumber(usedStr)
    local totalMiB = tonumber(totalStr)
    if isFinite(usedMiB) and isFinite(totalMiB) and usedMiB >= 0 and totalMiB > 0 and usedMiB <= totalMiB * 1.1 then
        usedMiB = math.min(usedMiB, totalMiB)
    else
        usedMiB, totalMiB = nil, nil
    end

    local tempC = tonumber(tempStr)
    if not isFinite(tempC) or tempC < -40 or tempC > 150 then tempC = -1 end

    local powerW = tonumber(powerStr)
    if not isFinite(powerW) or powerW < 0 or powerW > 2000 then powerW = -1 end

    local fanVal = tonumber(fanStr)
    local fan, fanUnit = nil, '%'
    if isFinite(fanVal) and fanVal >= 0 then
        fan = fanVal
        fanUnit = trim(fanUnitStr):upper() == 'RPM' and 'RPM' or '%'
    end

    return {
        usage = usage, usedMiB = usedMiB, totalMiB = totalMiB, tempC = tempC,
        powerW = powerW, fan = fan, fanUnit = fanUnit,
        age = math.max(0, now - stamp), provider = 'LHM'
    }
end
local scriptDir = type(debug) == 'table' and debug.getinfo and (debug.getinfo(1, 'S').source:match('^@?(.*[/\\])') or '') or ''
local function option(meter, key, value)
    local id = meter .. ':' .. key
    value = tostring(value)
    if options[id] == value then return end
    options[id] = value
    SKIN:Bang('!SetOption', meter, key, value)
end
local function variable(name, value)
    value = tostring(value)
    if variables[name] == value then return end
    variables[name] = value
    SKIN:Bang('!SetVariable', name, value)
end
local function severity(value, warn, critical)
    if value >= tonumber(SKIN:GetVariable(critical)) then return '#ColorCrit#' end
    if value >= tonumber(SKIN:GetVariable(warn)) then return '#ColorWarn#' end
    return '#colorText#'
end
local function maxSeverity(a, b)
    if a == '#ColorCrit#' or b == '#ColorCrit#' then return '#ColorCrit#' end
    if a == '#ColorWarn#' or b == '#ColorWarn#' then return '#ColorWarn#' end
    return a or b or '#colorText#'
end
local function applySeverity(meter, color)
    option('meterValue' .. meter, 'FontColor', color)
    option('meterBar' .. meter, 'BarColor', color == '#colorText#' and '#colorBar#' or color)
end

local function contextMenu()
    if not ctxMenu then
        local base = scriptDir ~= '' and scriptDir or SKIN:GetVariable('@', '')
        ctxMenu = dofile(base .. 'ContextMenu.lua')
    end
    return ctxMenu
end

local function userSettingsPath()
    return contextMenu().ensureUserSettings(SKIN)
end

function ToggleHistory()
    local value = SKIN:GetVariable('SysHistory', '0') == '1' and '0' or '1'
    SKIN:Bang('!WriteKeyValue', 'Variables', 'SysHistory', value, userSettingsPath())
    SKIN:Bang('!SetVariable', 'SysHistory', value)
    SKIN:Bang('!Refresh')
end

function ToggleAnimations()
    local value = SKIN:GetVariable('UiAnimations', '0') == '1' and '0' or '1'
    SKIN:Bang('!WriteKeyValue', 'Variables', 'UiAnimations', value, userSettingsPath())
    SKIN:Bang('!SetVariable', 'UiAnimations', value)
    SKIN:Bang('!RefreshGroup', 'SlateHUD')
end

function ToggleLhm()
    local value = trim(SKIN:GetVariable('SysLhmEnabled', '0')) == '1' and '0' or '1'
    SKIN:Bang('!WriteKeyValue', 'Variables', 'SysLhmEnabled', value, userSettingsPath())
    SKIN:Bang('!SetVariable', 'SysLhmEnabled', value)
    Update()
    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
end

local function applyGpu(data)
    local temp = data.tempC >= 0 and string.format(' (%.0f[\\x00B0]C)', data.tempC) or ''
    option('meterValueGPU', 'Text', string.format('%.0f%%', data.usage) .. temp)
    local color = severity(data.usage, 'WarnUsage', 'CritUsage')
    if data.tempC >= 0 then color = maxSeverity(color, severity(data.tempC, 'WarnTemp', 'CritTemp')) end
    applySeverity('GPU', color)
    local memory = 0
    if data.usedMiB and data.totalMiB and data.totalMiB > 0 then
        memory = data.usedMiB / data.totalMiB * 100
        option('meterValueVRAM', 'Text', string.format('%.1f / %.1f GB', data.usedMiB / 1024, data.totalMiB / 1024))
        option('meterValueVRAM', 'ToolTipText', string.format('%.0f%% dedicated GPU memory used', memory))
        applySeverity('VRAM', severity(memory, 'WarnMem', 'CritMem'))
    else
        option('meterValueVRAM', 'Text', 'Unavailable')
        option('meterValueVRAM', 'FontColor', '#ColorMuted#')
        option('meterValueVRAM', 'ToolTipText', 'GPU VRAM telemetry unavailable or unconfigured.')
        option('meterBarVRAM', 'BarColor', '#ColorMuted#')
    end
    local power = data.powerW >= 0 and string.format('%.0f W', data.powerW) or 'Unavailable'
    local fan = data.fan and (data.fanUnit == 'RPM' and string.format('%.0f RPM', data.fan) or string.format('%.0f%%', data.fan)) or 'Unavailable'
    local tooltip = data.provider == 'LHM'
        and ('Source: LibreHardwareMonitor#CRLF#GPU power: ' .. power .. '#CRLF#Fan: ' .. fan .. '#CRLF#Sample age: ' .. data.age .. ' s')
        or ('GPU power: ' .. power .. '#CRLF#Fan: ' .. fan .. '#CRLF#Sample age: ' .. data.age .. ' s')
    option('meterValueGPU', 'ToolTipText', tooltip)
    variable('GpuUsage', data.usage)
    variable('GpuMemoryPct', memory)
    option('meterHistory', 'MeasureName2', 'measureGPU')
    option('meterHistory', 'LineColor2', SKIN:GetVariable('ColorHistory2', '130,170,255,230'))
    option('meterHistoryLabel', 'Text', 'Recent load (CPU / GPU)')
end

local function updateContextMenu(provider)
    contextMenu().syncSuite(SKIN, option)
    local hist = SKIN:GetVariable('SysHistory', '0') == '1' and 'On' or 'Off'
    local anim = SKIN:GetVariable('UiAnimations', '0') == '1' and 'On' or 'Off'
    local lhm = trim(SKIN:GetVariable('SysLhmEnabled', '0')) == '1' and 'On' or 'Off'
    local provLabel = provider == 'lhm' and 'LHM' or (provider == 'nvml' and 'NVML' or 'Auto')
    option('Rainmeter', 'ContextTitle20', 'Toggle CPU/GPU history (' .. hist .. ')')
    option('Rainmeter', 'ContextTitle21', 'Toggle UI animations (' .. anim .. ')')
    option('Rainmeter', 'ContextTitle22', 'Toggle LHM sensors (' .. lhm .. ')')
    option('Rainmeter', 'ContextTitle23', 'GPU sensor priority: ' .. provLabel)
end

local function updateGpu(text, provider, lhmActive, now)
    local gpuData, reason = nil, nil
    if provider ~= 'lhm' then
        local nvml, nvmlReason = ParseGpu(text, now)
        if nvml then
            local age = math.max(0, now - (tonumber(text:match('UPDATED=(%d+)')) or now))
            gpuData = {
                usage = nvml[1], usedMiB = nvml[2], totalMiB = nvml[3],
                tempC = nvml[4], powerW = nvml[5],
                fan = nvml[6] >= 0 and nvml[6] or nil, fanUnit = '%',
                age = age, provider = 'NVML'
            }
        else
            reason = nvmlReason
        end
    end
    if not gpuData and lhmActive then
        local lhm, lhmReason = ParseLhmGpu(text, now)
        if lhm then gpuData = lhm
        elseif provider == 'lhm' or not reason then reason = lhmReason end
    end
    if gpuData then
        lhmPendingUntil = nil
        applyGpu(gpuData)
        return
    end
    if provider == 'lhm' and lhmPendingUntil and now <= lhmPendingUntil and ParseGpu(text, now) then
        for _, name in ipairs({'meterValueGPU', 'meterValueVRAM'}) do
            option(name, 'Text', 'Checking...')
            option(name, 'FontColor', '#ColorMuted#')
            option(name, 'ToolTipText', 'Waiting for LibreHardwareMonitor sample...')
        end
        return
    end
    lhmPendingUntil = nil
    local hint = (reason or 'GPU unavailable') .. (provider == 'lhm'
        and '. Enable LibreHardwareMonitor (WMI or HTTP server).'
        or '. The helper retries automatically.')
    for _, name in ipairs({'meterValueGPU', 'meterValueVRAM'}) do
        option(name, 'Text', 'Unavailable')
        option(name, 'FontColor', '#ColorMuted#')
        option(name, 'ToolTipText', hint)
    end
    for _, name in ipairs({'meterBarGPU', 'meterBarVRAM'}) do option(name, 'BarColor', '#ColorMuted#') end
    option('meterHistory', 'MeasureName2', '')
    option('meterHistory', 'LineColor2', '0,0,0,0')
    option('meterHistoryLabel', 'Text', 'Recent load (CPU / GPU unavailable)')
    variable('GpuUsage', 0)
    variable('GpuMemoryPct', 0)
end

function CycleSensorProvider()
    local current = trim(SKIN:GetVariable('SysSensorProvider', 'auto')):lower()
    local nextProvider = current == 'auto' and 'lhm' or (current == 'lhm' and 'nvml' or 'auto')
    local settings = userSettingsPath()
    SKIN:Bang('!WriteKeyValue', 'Variables', 'SysSensorProvider', nextProvider, settings)
    SKIN:Bang('!SetVariable', 'SysSensorProvider', nextProvider)
    lhmPendingUntil = nextProvider == 'lhm' and (os.time() + 3) or nil
    Update()
    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
end

function Update()
    local now = os.time()
    local provider = trim(SKIN:GetVariable('SysSensorProvider', 'auto')):lower()
    if provider ~= 'auto' and provider ~= 'nvml' and provider ~= 'lhm' then provider = 'auto' end
    local lhmActive = provider == 'lhm' or (provider == 'auto' and trim(SKIN:GetVariable('SysLhmEnabled', '0')) == '1')
    local bridge = SKIN and SKIN.GetMeasure and SKIN:GetMeasure('MeasureGpuBridge')
    local text = bridge and bridge.GetStringValue and bridge:GetStringValue() or ''
    if text == '' then
        local file = io.open(SKIN:GetVariable('@') .. 'Cache/gpu.txt', 'rb')
        text = file and file:read('*a') or ''
        if file then file:close() end
    end

    if SKIN.GetMeasure then
        local cpuMeasure = SKIN:GetMeasure('measureCPU')
        local cpuUsage = cpuMeasure and cpuMeasure.GetValue and cpuMeasure:GetValue()
        local cpuTemp, cpuTempName
        if lhmActive then cpuTemp, cpuTempName = ParseCpuTemp(text, now) end
        if isFinite(cpuUsage) then
            local cpuColor = severity(cpuUsage, 'WarnUsage', 'CritUsage')
            if cpuTemp then
                cpuColor = maxSeverity(cpuColor, severity(cpuTemp, 'WarnTemp', 'CritTemp'))
                option('meterValueCPU', 'Text', string.format('%.0f%% (%.0f[\\x00B0]C)', cpuUsage, cpuTemp))
                option('meterValueCPU', 'ToolTipText', string.format('LHM: %s (%.0f[\\x00B0]C)', cpuTempName, cpuTemp))
            else
                option('meterValueCPU', 'Text', '%1%')
                option('meterValueCPU', 'ToolTipText', '')
            end
            applySeverity('CPU', cpuColor)
        end
        for _, item in ipairs({
            {'RAM', 'measureRAMPct', 'WarnMem', 'CritMem'},
            {'SWAP', 'measureSWAPPct', 'WarnMem', 'CritMem'}
        }) do
            local measure = SKIN:GetMeasure(item[2])
            if measure and measure.GetValue then
                applySeverity(item[1], severity(measure:GetValue(), item[3], item[4]))
            end
        end
    end
    local pagefile = ParsePageFile(text, now)
    if pagefile then
        option('meterValueSWAP', 'Text', pagefile.total > 0 and
            string.format('%.0f%% (%.1f / %.1f GB)', pagefile.pct, pagefile.used, pagefile.total) or '0% (0.0 / 0.0 GB)')
        applySeverity('SWAP', severity(pagefile.pct, 'WarnMem', 'CritMem'))
    else
        option('meterValueSWAP', 'Text', '[measureSWAPPct:0]%')
    end
    updateGpu(text, provider, lhmActive, now)
    updateContextMenu(provider)

    return 0
end
