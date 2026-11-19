local last = {}

function DiskSeverity(total, free, percent, warnPercent, critPercent, warnGB, critGB)
    if total <= 0 then return 'missing' end
    local remaining = free / 1000000000
    if percent >= critPercent or (critGB > 0 and remaining <= critGB) then return 'critical' end
    if percent >= warnPercent or (warnGB > 0 and remaining <= warnGB) then return 'warning' end
    return 'normal'
end

function Update()
    local warn = tonumber(SKIN:GetVariable('WarnDisk','85')) or 85
    local crit = tonumber(SKIN:GetVariable('CritDisk','95')) or 95
    local warnGB = tonumber(SKIN:GetVariable('WarnDiskFreeGB','20')) or 20
    local critGB = tonumber(SKIN:GetVariable('CritDiskFreeGB','5')) or 5
    local colors = {missing='#ColorMuted#',critical='#ColorCrit#',warning='#ColorWarn#',normal='#colorText#'}
    for i, suffix in ipairs({'C','D','E'}) do
        local total = SKIN:GetMeasure('measureTotalDisk'..suffix):GetValue()
        local free = SKIN:GetMeasure('measureFreeDisk'..suffix):GetValue()
        local used = SKIN:GetMeasure('measurePercentDisk'..suffix):GetValue()
        local state = DiskSeverity(total,free,used,warn,crit,warnGB,critGB)
        local missing = state == 'missing'
        local value = missing and 'Not present' or ('%.1f GB free'):format(free / 1000000000)
        local previous = last[suffix] or {}
        if previous.state ~= state then
            local label = 'meterLabelDisk'..suffix
            SKIN:Bang('!SetOption','meterValueDisk'..suffix,'FontColor',colors[state])
            SKIN:Bang('!SetOption','meterBarDisk'..suffix,'BarColor',state=='normal' and '#colorBar#' or colors[state])
            SKIN:Bang('!SetOption',label,'Text','#disk'..i..'#\\'..(missing and '' or ' %1'))
            SKIN:Bang('!SetOption',label,'FontColor',missing and '#ColorMuted#' or '#colorText#')
            SKIN:Bang(missing and '!DisableMouseAction' or '!EnableMouseAction',label,'LeftMouseUpAction')
        end
        if previous.value ~= value then SKIN:Bang('!SetOption','meterValueDisk'..suffix,'Text',value) end
        last[suffix] = {state=state,value=value}
    end
    return 0
end
