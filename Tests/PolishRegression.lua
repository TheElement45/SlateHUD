function TestLayout(root, scratch)
    local function check(v,m) if not v then error(m,2) end end
    dofile(root .. '/@Resources/Layout.lua')
    for _,case in ipairs({{1920,1080,1},{1920,1080,1.125},{1536,824,1.125},{1366,728,1.125},{1280,680,1.125}}) do
        local w,h,preferred=unpack(case)
        for _,origin in ipairs({0,-1920}) do
            local s=preferred
            local p,wrapped,fitted=PlanLayout({x=origin,y=40,w=w,h=h},s,false,false)
            check(not wrapped,'Automatic mode wrapped instead of fitting the top row')
            if w==1920 then check(fitted==s,'External monitor preferred size changed')
            else check(fitted<s,'Laptop widgets were not reduced to fit') end
            s=fitted
            check(p[''].x>=origin+88*s-0.01,'Music covers the desktop icon rail')
            check(p.Apps.x==p[''].x,'Laptop Apps lost sidebar alignment')
            check(p.Apps.y+(540+24)*s<=40+h,'Expanded six-category Apps falls outside the work area')
            local boxes={}
            for name,size in pairs({['']={336,208},Disks={238,192},Network={238,192},System={238,334},Games={336,220}}) do
                local point=p[name]
                check(math.abs(point.y-p.Games.y)<0.01,'Top-row card moved onto desktop icons: '..name)
                check(point.x >= origin and point.x+size[1]*s <= origin+w+1,'Card outside monitor horizontally: '..name)
                check(point.y >= 40 and point.y+size[2]*s <= 40+h+1,'Card outside monitor vertically: '..name)
                local box={point.x,point.y,point.x+size[1]*s,point.y+size[2]*s}
                for _,other in ipairs(boxes) do
                    check(box[3]<=other[1] or box[1]>=other[3] or box[4]<=other[2] or box[2]>=other[4],'Cards overlap')
                end
                boxes[#boxes+1]=box
            end
        end
    end
    local p,wrapped,fitted=PlanLayout({x=0,y=0,w=1536,h=864},1.125,true,false)
    check(wrapped and fitted==1.125,'Explicit shelf mode did not preserve preferred size')
    local vars={PWORKAREAX='0',PWORKAREAY='0',PWORKAREAWIDTH='1920',PWORKAREAHEIGHT='1080',UiScale='1.125',
        ['@']=root..'/@Resources/',LayoutStateFile=scratch..'/Display.inc',LayoutWorkWidth='1920',
        MonitorSnapshotFile=scratch..'/monitors.txt'}
    local calls={}
    SKIN={GetVariable=function(_,key,fallback) return vars[key] or fallback end}
    function SKIN:Bang(...) calls[#calls+1]={...} end
    dofile(root..'/@Resources/Layout.lua');Update()
    local first=#calls
    vars.PWORKAREAWIDTH,vars.PWORKAREAHEIGHT='1536','864'
    Update()
    check(calls[#calls][1]=='!RefreshGroup' and #calls==first+1,'Display change moved windows without reloading geometry')
    -- A fresh script instance models the group refresh. It must not refresh itself again.
    vars.UiScale=tostring(FitScale(1536,1.125,false))
    vars.LayoutWorkWidth='1536'
    dofile(root..'/@Resources/Layout.lua');Update()
    check(calls[#calls][1]~='!RefreshGroup','Monitor switch entered a refresh loop')
    local count=#calls;Update();check(#calls==count,'Unchanged display repeated work')
    vars.UiScale='(0.950)'
    function SKIN:ReplaceVariables(value) return value end
    function SKIN:ParseFormula(value) return tonumber(value:match('^%(([%d.]+)%)$')) end
    dofile(root..'/@Resources/Layout.lua');Update()
    local moved
    for _,call in ipairs(calls) do if call[1]=='!Move' and call[4]=='SlateHUD\\System' then moved=call end end
    check(moved and moved[3]==7,'Formula-valued fitted scale was treated as the default size')
    check(FitScale(1536,1.125,false)==0.95,'Laptop compact preset was not selected')
    check(FitScale(1536,1.125,false,0.9)==0.9,'Custom laptop compact size was ignored')
    check(FitScale(1920,1.125,false)==1.125,'External display did not restore preferred size')
    check(FitScale(1920,1.125,false,0.95,true)==0.95,'Full HD laptop missed compact size')
    local laptop = {x=1920,y=392,w=1920,h=1080,role='laptop'}
    local lp,_,ls = PlanLayout(laptop,1.125,false,false,0.95)
    check(ls==0.95,'Laptop role did not reach layout sizing')
    check(lp.System.x+238*ls<=lp.Games.x,'Laptop System overlaps Games')
    check(lp.Battery.x+238*ls<=lp.Games.x,'Laptop Battery overlaps Games')
    local lpHist = PlanLayout(laptop,1.125,false,false,0.95,true)
    check(math.abs((lpHist.Battery.y - lp.Battery.y) - 40*ls) < 0.01,'System history did not shift Battery card down')
    local tightVars = {BlurTightFrame='1'}
    local prevSkin = SKIN
    SKIN = {GetVariable=function(_,k,d) return tightVars[k] or d end}
    local tp,_,ts = PlanLayout({x=0,y=0,w=1920,h=1080},1,false,false)
    check(math.abs(tp.Games.x - (1920 - 8 - (320 + 16) + 8)) < 0.01 and math.abs(tp.Games.y - 24) < 0.01,
        'Tight blur frame layout did not preserve visible screen card bounds')
    SKIN = prevSkin
    local store=dofile(root..'/@Resources/FileStore.lua')
    local realTime=os.time
    local clock=1000
    os.time=function() return clock end
    vars.PWORKAREAWIDTH,vars.PWORKAREAHEIGHT='1920','1040'
    vars['WORKAREAX@2'],vars['WORKAREAY@2'],vars['WORKAREAWIDTH@2'],vars['WORKAREAHEIGHT@2']='-1536','0','1536','864'
    local function sample(occupied, external)
        local text=('UPDATED=%d\nBB\tlaptop\t0\t125\t-1536\t0\t1920\t1080\t0\n'):format(clock)
        if external then text=text..('AA\texternal\t1\t100\t0\t0\t1920\t1040\t%d\n'):format(occupied and 1 or 0) end
        check(store.write(vars.MonitorSnapshotFile,text),'Monitor fixture could not publish')
        Update()
    end
    local function movedTo(id)
        local text = store.read(vars.LayoutStateFile)
        return text:find('LayoutDisplayId=' .. id .. '\n',1,true) ~= nil
    end
    dofile(root..'/@Resources/Layout.lua')
    sample(false,true); check(movedTo('AA'),'Auto did not prefer the external display')
    clock=1001; sample(true,true)
    clock=1002; sample(false,true)
    check(movedTo('AA'),'Unstable fullscreen moved the suite')
    for time=1003,1005 do clock=time; sample(true,true) end
    check(movedTo('BB'),'Stable fullscreen did not select the laptop')
    local laptopState = store.read(vars.LayoutStateFile)
    check(laptopState:find('LayoutWorkWidth=1536\nLayoutWorkHeight=864\n',1,true),
        'Laptop layout used the helper\'s physical dimensions instead of Rainmeter\'s work area')
    local firstLaptopMove = #calls
    Update()
    local gamesMove
    for i=firstLaptopMove+1,#calls do
        local call = calls[i]
        if call[1]=='!Move' and call[4]=='SlateHUD\\Games' then gamesMove = call end
    end
    check(gamesMove and gamesMove[2]==math.floor(-344*0.95),
        'Game Hub did not move to the right edge of Rainmeter\'s laptop work area')
    vars.LayoutPlacement='external'; Update(); check(movedTo('AA'),'Manual external did not override fullscreen')
    vars.LayoutPlacement='laptop'; Update(); check(movedTo('BB'),'Manual laptop mode did not apply')
    vars.LayoutPlacement='auto'
    for time=1006,1008 do clock=time; sample(false,true) end
    check(movedTo('AA'),'Fullscreen exit did not restore external placement')
    clock=1013; vars.LayoutPlacement='laptop'; Update()
    check(movedTo('BB'),'Stale helper disabled manual placement to an available display')
    vars.LayoutPlacement='auto'
    clock=1014; sample(false,false); check(movedTo('BB'),'Unplugged external display did not fall back')
    clock=1015
    local inventory='SKINS=1\nSKIN\tSystem\t1\nSKIN\tApps\t0\n'
    check(store.write(vars.MonitorSnapshotFile,('UPDATED=%d\nAA\texternal\t1\t100\t0\t0\t1920\t1080\t0\n'):format(clock)..inventory),
        'Visibility fixture failed')
    local firstVisibility = #calls
    Update(); Update()
    local movedApps, refreshedSystem = false, false
    for i=firstVisibility+1,#calls do
        local call=calls[i]
        check(call[1]~='!RefreshGroup' and not (call[1]=='!Refresh' and call[2]=='SlateHUD\\Apps'),
            'Display switch reloaded a hidden skin')
        if call[1]=='!Move' then
            check(call[4]=='SlateHUD\\Apps' or call[4]=='SlateHUD\\System','Display switch moved an unloaded skin')
            if call[4]=='SlateHUD\\Apps' then movedApps=true end
        end
        if call[1]=='!Refresh' and call[2]=='SlateHUD\\System' then refreshedSystem=true end
    end
    check(movedApps and refreshedSystem,'Loaded hidden and visible skins did not update correctly')
    check(store.write(vars.MonitorSnapshotFile,('UPDATED=%d\nAA\texternal\t1\t100\t0\t0\t1920\t1080\t0\n')
        :format(clock)..inventory:gsub('Apps\t0','Apps\t1')),'Visibility fixture failed')
    local start = #calls
    Update()
    local reloadedApp = false
    for i=start+1,#calls do
        local call=calls[i]
        if call[1]=='!Refresh' and call[2]=='SlateHUD\\Apps' then reloadedApp=true end
    end
    check(reloadedApp,'Newly shown skin never refreshed its geometry')
    vars['WORKAREAX@2'],vars['WORKAREAY@2'],vars['WORKAREAWIDTH@2'],vars['WORKAREAHEIGHT@2']='1920','432','1536','864'
    clock=1020
    check(store.write(vars.MonitorSnapshotFile,
        ('UPDATED=%d\nAA\texternal\t1\t100\t0\t0\t1920\t1040\t0\nBB\tlaptop\t0\t125\t1920\t392\t1920\t1080\t0\n'):format(clock)),
        'Mixed-DPI origin fixture failed')
    vars.LayoutPlacement='laptop'
    local beforeMixedMove = #calls
    Update(); Update()
    local mixedState = store.read(vars.LayoutStateFile)
    check(mixedState:find('LayoutWorkWidth=1536\nLayoutWorkHeight=864\nLayoutWorkX=1920\nLayoutWorkY=432\nLayoutDisplayId=BB\nLayoutDisplayRole=laptop\n',1,true),
        'Fresh mixed-DPI snapshot kept helper origin instead of matched Rainmeter work area')
    local mixedGamesMove
    for i=beforeMixedMove+1,#calls do
        local call = calls[i]
        if call[1]=='!Move' and call[4]=='SlateHUD\\Games' then mixedGamesMove = call end
    end
    check(mixedGamesMove and mixedGamesMove[3]==439,'Fresh mixed-DPI placement moved Game Hub to wrong Y origin')
    clock=1030
    vars.LayoutPlacement='external'; Update(); Update()
    vars.LayoutPlacement='laptop'
    local beforeStaleMixedMove = #calls
    Update(); Update()
    local staleMixedState = store.read(vars.LayoutStateFile)
    check(staleMixedState:find('LayoutWorkWidth=1536\nLayoutWorkHeight=864\nLayoutWorkX=1920\nLayoutWorkY=432\nLayoutDisplayId=BB\nLayoutDisplayRole=laptop\n',1,true),
        'Stale mixed-DPI snapshot kept helper origin instead of matched Rainmeter work area')
    local staleGamesMove
    for i=beforeStaleMixedMove+1,#calls do
        local call = calls[i]
        if call[1]=='!Move' and call[4]=='SlateHUD\\Games' then staleGamesMove = call end
    end
    check(staleGamesMove and staleGamesMove[3]==439,'Stale mixed-DPI placement moved Game Hub to wrong Y origin')
    vars.StatCardW = '280'
    vars.WideCardW = '360'
    local shrunkScale = FitScale(1920, 1.25, false)
    local customPlan = PlanLayout({x=0,y=0,w=1920,h=1080}, 1.0, false, false)
    check(shrunkScale < 1.25, 'Custom larger card metrics did not tighten FitScale')
    check(customPlan.Games.x == 1920 - 8 - 376, 'Custom WideCardW override did not shift Games X placement')
    vars.StatCardW = nil
    vars.WideCardW = nil
    local savedAt = vars['@']
    local callsBeforeToggle = #calls
    vars['@'] = scratch .. '/'
    vars.LayoutMode = '0'
    Toggle()
    local wroteMode, refreshedGroup = false, false
    for i = callsBeforeToggle + 1, #calls do
        local c = calls[i]
        if c[1] == '!WriteKeyValue' and c[2] == 'Variables' and c[3] == 'LayoutMode' and c[4] == '1' then wroteMode = true end
        if c[1] == '!RefreshGroup' and c[2] == 'SlateHUD' then refreshedGroup = true end
    end
    check(wroteMode, 'Toggle() did not write LayoutMode=1 via !WriteKeyValue')
    check(refreshedGroup, 'Toggle() did not trigger !RefreshGroup SlateHUD')
    local usf = io.open(scratch .. '/UserSettings.inc', 'r')
    check(usf ~= nil, 'Toggle() did not seed UserSettings.inc')
    if usf then
        local ust = usf:read('*a')
        usf:close()
        check(ust:find('%[Variables%]') ~= nil, 'Seeded UserSettings.inc missing [Variables] header')
    end
    vars['@'] = savedAt
    vars.LayoutMode = nil
    os.time=realTime
    print('PASS: Fitted single-row laptop layouts, unchanged external size, monitor offsets, display-change refresh and no refresh loop')
end

function TestGpu(root,scratch)
    local function check(v,m) if not v then error(m,2) end end
    dofile(root .. '/@Resources/System.lua')
    local gpu=ParseGpu('0, 0, 8192, -1, -1, -1\nUPDATED=1000',1005)
    check(gpu and gpu[1]==0 and gpu[3]==8192,'Valid idle GPU or unsupported optional sensors rejected')
    local pf=ParsePageFile('0, 0, 8192, -1, -1, -1\nUPDATED=1000\nPAGEFILE=536870912,2147483648',1005)
    check(pf and math.abs(pf.used-0.5)<0.001 and math.abs(pf.total-2.0)<0.001 and math.abs(pf.pct-25)<0.001,'Valid pagefile sample rejected')
    check(ParsePageFile('0, 0, 8192, -1, -1, -1\nUPDATED=900\nPAGEFILE=536870912,2147483648',1005)==nil,'Stale pagefile sample accepted')
    check(ParsePageFile('0, 0, 8192, -1, -1, -1\nUPDATED=1000\nPAGEFILE=3000,2000',1005)==nil,'Invalid pagefile sample accepted')
    for _,text in ipairs({'0,0,6144,0,0,-1','-1,-1,-1,-1,-1,-1\nUPDATED=1000',
        '101,10,8192,40,20,0\nUPDATED=1000','20,9000,8192,40,20,0\nUPDATED=1000',
        '1,2,0,40,20,0\nUPDATED=1000','1,2,8192,40,20,x\nUPDATED=1000',
        '1,2,8192,40,20,0\nUPDATED=900','1,2,8192,40,20,0\nUPDATED=1100'}) do
        check(ParseGpu(text,1005)==nil,'Bad/stale telemetry accepted: '..text)
    end
    local store=dofile(root .. '/@Resources/FileStore.lua')
    local sysDir=scratch .. '/sys/'
    local gpuPath=scratch .. '/gpu.txt'
    local varsFile=scratch .. '/Variables.inc'
    check(store.write(varsFile,'[Variables]\nSysHistory=0\n'),'System variables fixture failed')
    local now=os.time()
    check(store.write(gpuPath,('25, 2048, 8192, 55, 45, 30\nUPDATED=%d'):format(now)),'GPU fixture failed')
    local vars={['@']=scratch .. '/',WarnUsage='80',CritUsage='95',WarnTemp='75',CritTemp='85',WarnMem='80',CritMem='92',SysHistory='0'}
    local measures={measureCPU=30,measureRAMPct=50,measureSWAPPct=40}
    local options,calls={},{}
    local realOpen=io.open
    io.open=function(p,m) if p==scratch .. '/Cache/gpu.txt' then return realOpen(gpuPath,m) end return realOpen(p,m) end
    SKIN={
        GetVariable=function(_,k,d) return vars[k] or d end,
        GetMeasure=function(_,k) return {GetValue=function() return measures[k] end} end,
        Bang=function(_,cmd,a,b,c,d)
            calls[#calls+1]={cmd,a,b,c,d}
            if cmd=='!SetOption' then options[a]=options[a] or {}; options[a][b]=c
            elseif cmd=='!SetVariable' then vars[a]=b end
        end
    }
    Update()
    check(options.meterBarGPU.BarColor=='#colorBar#' and options.meterBarCPU.BarColor=='#colorBar#','Normal GPU/CPU bar did not use #colorBar#')
    local count=#calls
    Update()
    check(#calls==count,'Unchanged System telemetry reissued UI bangs')
    measures.measureCPU=85; measures.measureRAMPct=95; Update()
    check(options.meterBarCPU.BarColor=='#ColorWarn#' and options.meterBarRAM.BarColor=='#ColorCrit#','CPU/RAM threshold severity did not update')
    check(store.write(gpuPath,('55, 2048, 8192, 55, 45, 30\nUPDATED=%d\nPAGEFILE=1932735283,2147483648'):format(now)),'Active GPU fixture failed')
    Update()
    check(options.meterValueSWAP.Text=='90% (1.8 / 2.0 GB)' and options.meterBarSWAP.BarColor=='#ColorWarn#','Pagefile used/total GB and severity did not update')
    check(vars.GpuUsage=='55' and options.meterHistory.MeasureName2=='measureGPU' and
        options.meterHistory.LineColor2=='130,170,255,230' and
        options.meterHistoryLabel.Text=='Recent load (CPU / GPU)',
        'Active GPU sample was not bound to history chart')
    check(store.write(gpuPath,('55, 2048, 8192, 55, 45, 30\nUPDATED=%d\nPAGEFILE=1932735283,2147483648'):format(now - 20)),'Expired GPU fixture failed')
    Update()
    check(options.meterValueSWAP.Text=='[measureSWAPPct:0]%' and options.meterBarSWAP.BarColor=='#colorBar#','Expired pagefile sample did not fall back to measureSWAPPct')
    check(options.meterValueGPU.Text=='Unavailable' and options.meterHistory.MeasureName2=='' and
        options.meterHistory.LineColor2=='0,0,0,0' and
        options.meterHistoryLabel.Text=='Recent load (CPU / GPU unavailable)',
        'Expired GPU sample was graphed as 0% instead of marking GPU history unavailable')
    check(store.write(gpuPath,('0, 1024, 8192, 40, 15, 0\nUPDATED=%d'):format(now)),'Idle GPU fixture failed')
    Update()
    check(options.meterValueGPU.Text=='0% (40[\\x00B0]C)' and vars.GpuUsage=='0' and
        options.meterHistory.MeasureName2=='measureGPU' and
        options.meterHistory.LineColor2=='130,170,255,230' and
        options.meterHistoryLabel.Text=='Recent load (CPU / GPU)',
        'Genuine 0% idle GPU reading was not restored to history chart')
    vars.ColorHistory2='255,90,200,245'; Update()
    check(options.meterHistory.LineColor2=='255,90,200,245','Themed ColorHistory2 override did not apply to history chart')
    vars.ColorHistory2=nil; Update()
    ToggleHistory()
    io.open=realOpen
    check(vars.SysHistory=='1','System history toggle did not update variable')
    local lastWrite = calls[#calls - 2]
    check(lastWrite and lastWrite[1]=='!WriteKeyValue' and lastWrite[3]=='SysHistory' and
        lastWrite[5]==scratch..'/UserSettings.inc','System history toggle did not write to UserSettings.inc')
    check((store.read(scratch..'/UserSettings.inc') or ''):find('[Variables]',1,true),'System history toggle did not initialize UserSettings.inc')
    ToggleAnimations()
    check(vars.UiAnimations=='1','System animations toggle did not update variable')
    local animWrite = calls[#calls - 2]
    check(calls[#calls] and calls[#calls][1]=='!RefreshGroup' and calls[#calls][2]=='SlateHUD','System animations toggle did not refresh SlateHUD group')
    check(animWrite and animWrite[1]=='!WriteKeyValue' and animWrite[3]=='UiAnimations' and
        animWrite[5]==scratch..'/UserSettings.inc','System animations toggle did not write to UserSettings.inc')
    do
        local tempVal, tempName = ParseCpuTemp(('0, 0, 8192, 40, 10, 0\nUPDATED=%d\nCPUTEMP=64.5|CPU Package'):format(now), now)
        check(tempVal and math.abs(tempVal - 64.5) < 0.01 and tempName == 'CPU Package', 'Valid CPUTEMP line rejected')
        check(ParseCpuTemp(('UPDATED=%d\nCPUTEMP=64.5|CPU Package'):format(now - 20), now) == nil, 'Stale CPUTEMP sample accepted')
        check(ParseCpuTemp(('UPDATED=%d\nCPUTEMP=20|Distance to TjMax'):format(now), now) == nil, 'Distance to TjMax was treated as CPU temp')
        check(ParseCpuTemp(('UPDATED=%d\nCPUTEMP=999|CPU Package'):format(now), now) == nil, 'Out-of-range CPUTEMP accepted')

        local lhmParsed = ParseLhmGpu(('UPDATED=%d\nLHMGPU=42, 2048, 8192, 61, 145, 1450, RPM'):format(now), now)
        check(lhmParsed and lhmParsed.usage == 42 and lhmParsed.usedMiB == 2048 and lhmParsed.totalMiB == 8192 and
            lhmParsed.tempC == 61 and lhmParsed.powerW == 145 and lhmParsed.fan == 1450 and lhmParsed.fanUnit == 'RPM',
            'Valid LHMGPU snapshot parsing failed')
        check(ParseLhmGpu(('UPDATED=%d\nLHMGPU=42, 2048, 8192, 61, 145, 1450, RPM'):format(now - 20), now) == nil,
            'Stale LHMGPU snapshot accepted')

        local origOpen = io.open
        io.open = function(p, m) if p == scratch .. '/Cache/gpu.txt' then return origOpen(gpuPath, m) end return origOpen(p, m) end

        -- auto + SysLhmEnabled=1 combines healthy NVML GPU with LHM CPU temp.
        vars.SysSensorProvider = 'auto'; vars.SysLhmEnabled = '1'
        measures.measureCPU = 30
        check(store.write(gpuPath, ('10, 1024, 8192, 45, 25, 0\nUPDATED=%d\nCPUTEMP=88|CPU Package'):format(now)), 'Active NVML+LHM fixture failed')
        Update()
        check(options.meterValueCPU.Text == '30% (88[\\x00B0]C)' and options.meterBarCPU.BarColor == '#ColorCrit#',
            'LHM CPU temp display or WarnTemp/CritTemp severity failed')
        check(options.meterValueCPU.ToolTipText == 'LHM: CPU Package (88[\\x00B0]C)', 'LHM CPU temp tooltip incorrect')
        check(options.meterValueGPU.Text == '10% (45[\\x00B0]C)', 'Auto provider dropped healthy NVML GPU')

        -- auto + SysLhmEnabled=0 ignores LHM lines even if present in gpu.txt.
        vars.SysLhmEnabled = '0'
        Update()
        check(options.meterValueCPU.Text == '%1%', 'Disabled SysLhmEnabled still displayed CPUTEMP in auto mode')

        -- NVML absent/unavailable -> auto + SysLhmEnabled=1 falls back to LHM GPU (AMD/Intel support).
        vars.SysLhmEnabled = '1'
        check(store.write(gpuPath, ('-1, -1, -1, -1, -1, -1\nUPDATED=%d\nCPUTEMP=65|Core (Tctl/Tdie)\nLHMGPU=42, 2048, 8192, 61, 145, 1450, RPM'):format(now)),
            'Unavailable NVML + LHM GPU fixture failed')
        Update()
        check(options.meterValueGPU.Text == '42% (61[\\x00B0]C)' and options.meterValueVRAM.Text == '2.0 / 8.0 GB',
            'Auto fallback to LHM GPU failed')
        check(options.meterValueGPU.ToolTipText:find('Source: LibreHardwareMonitor', 1, true) and
            options.meterValueGPU.ToolTipText:find('145 W', 1, true) and
            options.meterValueGPU.ToolTipText:find('1450 RPM', 1, true), 'LHM GPU tooltip/units incorrect')
        check(vars.GpuUsage == '42' and options.meterHistory.MeasureName2 == 'measureGPU',
            'LHM GPU usage did not feed GPU history graph')

        -- Partial LHM GPU (usage present, VRAM total unavailable) keeps GPU alive and marks VRAM Unavailable.
        check(store.write(gpuPath, ('-1, -1, -1, -1, -1, -1\nUPDATED=%d\nLHMGPU=42, 2048, -1, 61, -1, -1, %%'):format(now)),
            'Partial LHM GPU fixture failed')
        Update()
        check(options.meterValueGPU.Text == '42% (61[\\x00B0]C)' and options.meterValueVRAM.Text == 'Unavailable' and
            options.meterBarVRAM.BarColor == '#ColorMuted#', 'Partial LHM GPU without VRAM total did not handle VRAM gracefully')

        -- LHM offline/absent in lhm mode must never fall back to 0°C / 0%.
        vars.SysSensorProvider = 'lhm'
        check(store.write(gpuPath, ('-1, -1, -1, -1, -1, -1\nUPDATED=%d'):format(now)), 'Offline LHM fixture failed')
        Update()
        check(options.meterValueCPU.Text == '%1%' and options.meterBarCPU.BarColor == '#colorBar#',
            'Offline LHM CPU temp was not cleared cleanly')
        check(options.meterValueGPU.Text == 'Unavailable' and options.meterBarGPU.BarColor == '#ColorMuted#' and
            vars.GpuUsage == '0' and options.meterHistory.MeasureName2 == '',
            'Offline LHM GPU displayed 0% instead of Unavailable')

        -- Explicit nvml provider ignores LHM even when LHM lines are present.
        check(store.write(gpuPath, ('-1, -1, -1, -1, -1, -1\nUPDATED=%d\nCPUTEMP=88|CPU Package\nLHMGPU=42, 2048, 8192, 61, 145, 55, %%'):format(now)),
            'Explicit nvml ignore fixture failed')
        vars.SysSensorProvider = 'nvml'
        Update()
        check(options.meterValueCPU.Text == '%1%' and options.meterValueGPU.Text == 'Unavailable',
            'Explicit nvml mode still used LHM readings')

        -- Menu actions persist to UserSettings.inc and cycle auto -> lhm -> nvml -> auto.
        local beforeLhm = #calls
        vars.SysLhmEnabled = '0'; ToggleLhm()
        check(vars.SysLhmEnabled == '1', 'ToggleLhm did not enable SysLhmEnabled')
        check(options.Rainmeter and options.Rainmeter.ContextTitle22 == 'Toggle LHM sensors (On)',
            'ToggleLhm did not update ContextTitle22 state')
        local wroteLhm = false
        for i = beforeLhm + 1, #calls do
            local c = calls[i]
            if c[1] == '!WriteKeyValue' and c[3] == 'SysLhmEnabled' and c[4] == '1' and
                c[5] == scratch .. '/UserSettings.inc' then
                wroteLhm = true
            end
        end
        check(wroteLhm, 'ToggleLhm did not write to UserSettings.inc')
        check(store.write(gpuPath, ('10, 1024, 8192, 45, 25, 0\nUPDATED=%d'):format(now)),
            'NVML transition fixture failed')
        vars.SysSensorProvider = 'auto'; vars.SysLhmEnabled = '0'; Update()
        check(options.Rainmeter.ContextTitle20 == 'Toggle CPU/GPU history (On)' and
            options.Rainmeter.ContextTitle21 == 'Toggle UI animations (On)' and
            options.Rainmeter.ContextTitle22 == 'Toggle LHM sensors (Off)' and
            options.Rainmeter.ContextTitle23 == 'GPU sensor priority: Auto',
            'System context menu titles did not reflect live state')
        CycleSensorProvider()
        check(vars.SysSensorProvider == 'lhm' and vars.SysLhmEnabled == '0',
            'CycleSensorProvider did not advance auto -> lhm without mutating SysLhmEnabled')
        check(options.Rainmeter.ContextTitle23 == 'GPU sensor priority: LHM' and
            options.meterValueGPU.Text == 'Checking...',
            'CycleSensorProvider auto -> lhm missed live label or Checking transition grace')
        CycleSensorProvider()
        check(vars.SysSensorProvider == 'nvml' and
            options.Rainmeter.ContextTitle23 == 'GPU sensor priority: NVML' and
            options.meterValueGPU.Text == '10% (45[\\x00B0]C)',
            'CycleSensorProvider did not advance lhm -> nvml')
        CycleSensorProvider()
        check(vars.SysSensorProvider == 'auto' and
            options.Rainmeter.ContextTitle23 == 'GPU sensor priority: Auto',
            'CycleSensorProvider did not wrap nvml -> auto')
        vars.PreferredUiScale = '1.125'; vars.CardOpacity = '85'; vars.LayoutPlacement = 'auto'
        vars.CurrentTheme = 'Cyberpunk'; vars.AcrylicBlur = 'None'
        Update()
        check(options.Rainmeter.ContextTitle == 'Size: Compact' and
            options.Rainmeter.ContextTitle2 == '* Size: Readable' and
            options.Rainmeter.ContextTitle5 == '* Background: Frosted Glass' and
            options.Rainmeter.ContextTitle6 == '* Display: Auto' and
            options.Rainmeter.ContextTitle11 == '* Theme: Cyberpunk' and
            options.Rainmeter.ContextTitle18 == '* Blur: Off',
            'System suite menu presets did not mark active choices with * ')
        vars.PreferredUiScale = nil; vars.CardOpacity = nil; vars.LayoutPlacement = nil
        vars.CurrentTheme = nil; vars.AcrylicBlur = nil

        -- Plugin bridge MeasureGpuBridge is preferred when non-empty and falls back when empty.
        vars.SysSensorProvider = 'auto'; vars.SysLhmEnabled = '0'
        local prevMeasure = SKIN.GetMeasure
        SKIN.GetMeasure = function(_, name)
            if name == 'MeasureGpuBridge' then
                return {GetStringValue = function() return ('37, 1536, 8192, 58, 95, 40\nUPDATED=%d'):format(now) end}
            end
            return prevMeasure(_, name)
        end
        io.open = function(p, m)
            if p == scratch .. '/Cache/gpu.txt' then error('System.lua opened disk gpu.txt while MeasureGpuBridge had data') end
            return origOpen(p, m)
        end
        Update()
        check(vars.GpuUsage == '37' and options.meterValueGPU.Text:find('37%', 1, true) ~= nil,
            'System.lua did not consume MeasureGpuBridge snapshot')
        SKIN.GetMeasure = prevMeasure
        io.open = origOpen
    end
    print('PASS: GPU idle versus failure, malformed samples, optional sensors, memoized CPU/RAM/GPU colors and stale/future timestamps')
end

function TestNotes(root,scratch)
    local function check(v,m) if not v then error(m,2) end end
    local store=dofile(root .. '/@Resources/FileStore.lua')
    local path=scratch..'/Page1.inc'
    local original='[Variables]\r\nPageTitle=TASKS\r\nNote1=Original rain \233\155\168\r\nStatus1=0\r\n'
    check(store.write(path,original),'Fixture write failed')
    local vars={['@']=root..'/@Resources/',PageFile=path,CurrentPage='1',PageTitle='TASKS',Note1='Original rain \233\155\168',Status1='0'}
    local commit,hidden,options='Edited',{},{}
    SKIN={}
    function SKIN:GetVariable(k,d) return vars[k] or d end
    function SKIN:GetMeasure(k) return {GetStringValue=function() return commit end} end
    function SKIN:Bang(command,a,b,c,d)
        if command=='!SetVariable' then vars[a]=b
        elseif command=='!SetOption' then options[a]=options[a] or {};options[a][b]=c
        elseif command=='!ShowMeter' or command=='!HideMeter' then hidden[a]=command=='!HideMeter'
        elseif command=='!WriteKeyValue' then
            local text=assert(store.read(d))
            local pattern='\n'..b..'=[^\r\n]*'
            if text:find(pattern) then text=text:gsub(pattern,function() return '\n'..b..'='..c end)
            else text=text..b..'='..c..'\r\n' end
            check(store.write(d,text),'Fixture mutation failed')
        end
    end
    dofile(root..'/@Resources/Notes.lua');Initialize()
    check(hidden.meterBtnUndo,'Undo visible before first edit')
    Save(1)
    check(store.read(path..'.undo')==original,'Edit did not preserve exact Unicode snapshot')
    check(vars.Note1=='Edited' and not hidden.meterBtnUndo,'Edit not applied or undo missing')
    local edited=store.read(path)
    -- Reloading another tab cannot consume this page's history.
    vars.PageFile=scratch..'/Page2.inc';store.write(vars.PageFile,'[Variables]\nNote1=Other\n')
    dofile(root..'/@Resources/Notes.lua');Initialize()
    check(hidden.meterBtnUndo,'History leaked across pages')
    vars.PageFile=path
    dofile(root..'/@Resources/Notes.lua');Initialize()
    check(not hidden.meterBtnUndo,'History lost after tab/skin refresh')
    Undo()
    check(store.read(path)==original and store.read(path..'.undo')==edited,'Undo/redo snapshot incorrect')
    Undo();check(store.read(path)==edited,'Redo lost the edited page')
    local previousUndo=store.read(path..'.undo')
    Clear('done');check(store.read(path..'.undo')==previousUndo,'No-op clear destroyed undo')
    local realOpen=io.open
    io.open=function(p,mode) if p==path..'.undo.tmp' and mode=='wb' then return nil,'locked' end return realOpen(p,mode) end
    commit='Must not save';Save(1)
    io.open=realOpen
    check(vars.Note1=='Edited' and store.read(path)==edited,'Failed recovery save modified the page')
    Toggle(1);check(vars.Status1=='1','Checkbox toggle failed')
    check(options.meterProgress.Text=='1/1 done','Completion count incorrect')
    Clear('done');check(vars.Note1=='' and vars.Status1=='0','Clear completed did not reset text/status')
    local binary='\255\254[\000V\000a\000r\000]\000\r\000\n\000'
    check(store.write(scratch..'/binary',binary) and store.read(scratch..'/binary')==binary,'UTF-16 bytes changed')
    local realRename=os.rename
    os.rename=function(a,b) if a==path..'.tmp' then return nil,'blocked' end return realRename(a,b) end
    local before=store.read(path)
    check(not store.write(path,'bad') and store.read(path)==before,'Replacement failure did not roll back')
    os.rename=realRename
    assert(os.rename(path,path..'.bak'))
    check(store.recover(path)==before and store.read(path)==before,'Interrupted swap did not recover')
    print('PASS: Durable per-page undo/redo, edit/clear/toggle recovery, failed-save blocking, Unicode and interrupted-write recovery')
end

function TestMedia(root,scratch,entrySource)
    local function check(v,m) if not v then error(m,2) end end
    local text='TITLE=Idle||STATE=0||DUR=00:00||CAPS=0,0,0,0'
    local options,calls,hidden,variables,acPower={}, {}, {}, {}, 1
    local store=dofile(root..'/@Resources/FileStore.lua')
    local path=scratch..'/media-health.txt'
    local statusPath=scratch..'/media-status.txt'
    local function health(age,connected)
        check(store.write(path,('UPDATED=%d\nCONNECTED=%d'):format(os.time()-age,connected and 1 or 0)),'Heartbeat fixture failed')
    end
    health(0,true)
    local SKIN={}
    function SKIN:GetVariable(name,default)
        if name=='@' then return root..'/@Resources/' end
        if name=='MediaHealthFile' then return path end
        if name=='MediaStatusFile' then return statusPath end; if variables[name]~=nil then return variables[name] end
        return default
    end
    function SKIN:Bang(command,a,b,c)
        calls[#calls+1]={command,a,b,c}
        if command=='!SetOption' then options[a]=options[a] or {};options[a][b]=c
        elseif command=='!SetVariable' then variables[a]=b
        elseif command=='!HideMeterGroup' or command=='!ShowMeterGroup' then hidden[a]=command=='!HideMeterGroup' end
    end
    local entry=setmetatable({}, {__index=_G})
    setfenv(assert(loadstring(entrySource,'@MediaUnicode.lua')),entry)()
    check(type(entry.Update)=='function','Rainmeter could not find Update before Initialize')
    entry.SKIN=SKIN
    entry.Initialize()
    local Update,Control,RestoreControls=entry.Update,entry.Control,entry.RestoreControls
    local function sample()
        check(store.write(statusPath,text),'Media fixture failed')
        Update()
    end
    sample()
    local parsed=entry.ParseMedia('TITLE=A | B||ARTIST=\233\155\168||COVER=||PLAYER=Brave||CAPS=1,1,1,0')
    check(parsed.TITLE=='A | B' and parsed.COVER=='' and parsed.PLAYER=='Brave','Empty media fields or single pipes broke parsing')
    check(hidden.MediaTimeline,'Idle timestamps remained visible')
    check(options.MeterTrackTitle.Y=='((36+#CardShiftY#)*#UiScale#)' and options.MeterArtistName.Y=='((58+#CardShiftY#)*#UiScale#)',
        'Idle media header was not vertically balanced without timeline')
    local n=#calls;Control('next');check(#calls==n,'Inactive next control sent a command')
    Control('playpause');check(calls[#calls][2]=='MeasureOpenMusic','Idle play did not open music')
    text='TITLE=Live||ARTIST=\233\155\168||STATE=1||DUR=00:00||CAPS=1,1,1,0';sample()
    check(variables.MediaTitle=='Live' and variables.MediaArtist=='\233\155\168','Active Unicode metadata did not reach the skin')
    n=#calls;Control('seek',50);check(#calls==n,'Unsupported seek sent a command')
    text='TITLE=Track||STATE=2||DUR=03:12||PLAYER=com.github.th-ch.youtube-music||CAPS=1,1,1,1';sample()
    check(variables.MediaSession=='YouTube Music','Player label exposed the YouTube Music app ID')
    check(not hidden.MediaTimeline,'Paused track lost its timeline')
    check(options.MeterTrackTitle.Y=='((27+#CardShiftY#)*#UiScale#)' and options.MeterArtistName.Y=='((47+#CardShiftY#)*#UiScale#)',
        'Active timeline track did not restore compact header Y coordinates')
    Control('seek',150);check(options.MeasureSMTCCmd.Parameter=='seek 100','Seek was not bounded')
    Control('nextplayer');check(options.MeasureSMTCCmd.Parameter=='nextplayer','Session cycling command missing')
    Control('lockplayer');check(options.MeasureSMTCCmd.Parameter=='lockplayer','Session lock command missing')
    Control('resetplayer');check(options.MeasureSMTCCmd.Parameter=='resetplayer','Session reset command missing')
    local cmdOutput = 'MEDIA:ERROR Could not reset player preference'
    function SKIN:GetMeasure(name)
        if name=='MeasureSMTCCmd' then return {GetStringValue=function() return cmdOutput end} end
    end
    entry.FinishControl()
    check(variables.MediaSession=='Command failed' and options.MeterNextPlayer.FontColor=='#ColorCrit#' and
        options.MeterNextPlayer.ToolTipText=='Could not reset player preference',
        'Reset player failure was not surfaced in the UI')
    cmdOutput = ''
    check(store.write(statusPath,'TITLE=Delayed Track||ARTIST=Artist||STATE=1||DUR=02:30||PLAYER=Spotify||CAPS=1,1,1,1'),
        'Delayed media snapshot fixture failed')
    entry.FinishControl()
    check(variables.MediaTitle=='Delayed Track' and variables.MediaSession=='Spotify' and
        options.MeterNextPlayer.FontColor=='#ColorSecondary#',
        'FinishControl did not redraw immediately from published command snapshot')
    text='TITLE=Stopped track||STATE=0||DUR=03:12||PLAYER=Brave||CAPS=1,1,1,1';sample()
    Control('playpause');check(options.MeasureSMTCCmd.Parameter=='playpause','Stopped session was mistaken for no player')
    do
        local origMeasure=SKIN.GetMeasure
        function SKIN:GetMeasure(name)
            if name=='MeasureAnimPower' then
                return {GetValue=function() return acPower end,GetStringValue=function() return tostring(acPower) end}
            end
            return origMeasure(self,name)
        end
        variables.UiAnimations='1'; variables.UiAnimationsBatterySaver='1'; acPower=1
        calls={}
        Control('seek',42)
        local exec1=false
        for _,cmd in ipairs(calls) do
            if cmd[1]=='!CommandMeasure' and cmd[2]=='MeasureUiAnim' and cmd[3]=='Execute 1' then exec1=true end
        end
        check(exec1,'Seek did not trigger progress pulse animation')
        entry.RestoreProgress()
        check(options.MeterProgressBar and options.MeterProgressBar.BarColor=='#ColorAccent#','RestoreProgress did not reset bar color')
        calls={}
        entry.FlashVolume()
        local exec2=false
        for _,cmd in ipairs(calls) do
            if cmd[1]=='!CommandMeasure' and cmd[2]=='MeasureUiAnim' and cmd[3]=='Execute 2' then exec2=true end
        end
        check(exec2,'FlashVolume did not trigger volume highlight animation')
        acPower=0; calls={}
        Control('seek',45); entry.FlashVolume()
        for _,cmd in ipairs(calls) do
            check(cmd[2]~='MeasureUiAnim','Battery saver should suppress media UI animations')
        end
        variables.UiAnimations=nil; variables.UiAnimationsBatterySaver=nil; SKIN.GetMeasure=origMeasure
    end
    health(20,true); Update()
    check(hidden.MediaTimeline and options.MeterNextPlayer.MouseActionCursor=='0','Stale heartbeat left playback controls active')
    local before=#calls; Control('nextplayer'); check(#calls==before,'Stale helper accepted playback commands')
    health(0,true); Update()
    check(not hidden.MediaTimeline and options.MeterNextPlayer.MouseActionCursor=='1','Unchanged media did not recover with fresh heartbeat')
    local unchanged=#calls; Update()
    check(#calls==unchanged,'Unchanged media republished the UI')
    options.MeterPrevButton.FontColor='#ColorAccent#'
    RestoreControls()
    check(options.MeterPrevButton.FontColor=='#ColorPrimary#','Cached media failed to restore hover color')
    check(options.MeterPlayPauseButton.MouseOverAction and options.MeterPlayPauseButton.MouseOverAction:find('#ColorPrimary#',1,true),
        'Play/Pause hover did not contrast with resting #ColorAccent#')
    check(options.MeterPrevButton.MouseOverAction and options.MeterPrevButton.MouseOverAction:find('#ColorAccent#',1,true),
        'Prev hover did not highlight with #ColorAccent#')
    assert(os.remove(statusPath)); Update()
    check(hidden.MediaTimeline,'Missing media snapshot retained the old track')

    -- Plugin bridge (MeasureMediaBridge / MeasureMediaHealthBridge) path & Bang dispatch
    do
        local bridgeVars = {['@'] = root .. '/@Resources/'}
        local bridgeCalls, bridgeVarsOut = {}, {}
        local bridgeEntry = setmetatable({}, {__index = _G})
        local bridgeSkin = {}
        function bridgeSkin:GetVariable(name, default)
            if bridgeVars[name] ~= nil then return bridgeVars[name] end
            if bridgeVarsOut[name] ~= nil then return bridgeVarsOut[name] end
            return default
        end
        function bridgeSkin:GetMeasure(name)
            if name == 'MeasureMediaHealthBridge' then
                return {GetStringValue = function() return ('UPDATED=%d\nCONNECTED=1'):format(os.time()) end}
            elseif name == 'MeasureMediaBridge' then
                return {GetStringValue = function() return 'TITLE=Bridged Track||ARTIST=Artist||STATE=1||DUR=02:00||PLAYER=Spotify||CAPS=1,1,1,1' end}
            end
        end
        function bridgeSkin:Bang(command, a, b, c)
            bridgeCalls[#bridgeCalls + 1] = {command, a, b, c}
            if command == '!SetVariable' then bridgeVarsOut[a] = b end
        end
        local origOpen = io.open
        io.open = function(p, m)
            if type(p) == 'string' and p:find(root .. '/@Resources/Cache/', 1, true) == 1 then
                return origOpen(scratch .. '/bridge-' .. p:sub(#(root .. '/@Resources/Cache/') + 1), m)
            end
            return origOpen(p, m)
        end
        local ok, err = pcall(function()
            setfenv(assert(loadstring(entrySource, '@MediaUnicode.lua')), bridgeEntry)()
            bridgeEntry.SKIN = bridgeSkin
            bridgeEntry.Initialize()
            bridgeEntry.Update()
            check(bridgeVarsOut.MediaTitle == 'Bridged Track' and bridgeVarsOut.MediaSession == 'Spotify',
                'Media.lua did not read snapshots from MeasureMediaBridge')
            bridgeEntry.Control('next')
            local lastCall = bridgeCalls[#bridgeCalls]
            check(lastCall and lastCall[1] == '!CommandMeasure' and lastCall[2] == 'MeasureMediaBridge' and lastCall[3] == 'next',
                'Media.lua did not route control bang through MeasureMediaBridge')
            local origMeasure = bridgeSkin.GetMeasure
            bridgeSkin.GetMeasure = function(_, name)
                if name == 'MeasureMediaBridge' or name == 'MeasureMediaHealthBridge' then
                    return {GetStringValue = function() return '' end}
                end
                return origMeasure(_, name)
            end
            bridgeEntry.Update()
            check(bridgeVarsOut.MediaTitle == 'Media helper offline',
                'Empty plugin bridge did not fall back to missing disk cache')
        end)
        io.open = origOpen
        if not ok then error(err, 2) end
    end
    print('PASS: Idle media UI, live/paused timelines, supported controls, bounded seeking and session cycling')
end

function TestWatchdog(root,scratch)
    local path=scratch..'/helper-health.txt'
    local store=dofile(root..'/@Resources/FileStore.lua')
    local realTime=os.time
    local clock,calls=100,0
    os.time=function() return clock end
    SKIN={GetVariable=function(_,name,default)
        if name=='@' then return root..'/@Resources/' end
        if name=='HelperHealthFile' then return path end
        return default
    end, Bang=function(_,command,measure,action)
        assert(command=='!CommandMeasure' and measure=='MeasureHelper' and action=='Run')
        calls=calls+1
    end}
    assert(store.write(path,'UPDATED=100'))
    dofile(root..'/@Resources/HelperWatchdog.lua'); Check(); Update()
    assert(calls==0,'Healthy helper spawned a process')
    clock=116; Update(); Check()
    assert(calls==1,'Stale helper recovery missing or duplicated on refresh')
    clock=120; Update(); assert(calls==1,'Watchdog retried too quickly')
    clock=131; Update(); assert(calls==2,'Failed startup did not retry')
    assert(store.write(path,'UPDATED=131')); clock=136; Update()
    assert(calls==2,'Recovered helper still spawned watchdog processes')
    assert(store.write(path,'UPDATED=999')); clock=150; Update()
    assert(calls==3,'Future heartbeat suppressed recovery')
    os.time=realTime
    print('PASS: Healthy watchdog silence, stale/future heartbeat recovery, retry limits and recovery')
end

function TestBatteryUpdates(root)
    local values={measureBattPct=25,measureBattAC=1,measureBattStatus=1,measureBattLife=0}
    local calls,options,vars=0,{},{}
    SKIN={GetVariable=function(_,name,default) return vars[name] or default end}
    function SKIN:GetMeasure(name)
        return {GetValue=function() return values[name] end,GetStringValue=function() return 'Unknown' end}
    end
    function SKIN:Bang(command,name,key,value)
        calls=calls+1
        if command=='!SetOption' then options[name..':'..key]=value
        elseif command=='!SetVariable' then vars[name]=key end
    end
    dofile(root..'/@Resources/Battery.lua'); Update()
    assert(options['meterValueBattPct:FontColor']=='#colorText#' and vars.BatteryFillColor=='#colorBar#','Charging battery showed a discharge warning')
    local before=calls; Update()
    assert(calls==before,'Unchanged battery republished the UI')
    values.measureBattAC=0; Update()
    assert(options['meterValueBattPct:FontColor']=='#ColorWarn#' and vars.BatteryFillColor=='#ColorWarn#','Unplugging did not update warning color')
    values.measureBattPct=10; Update()
    assert(options['meterValueBattPct:FontColor']=='#ColorCrit#' and vars.BatteryFillColor=='#ColorCrit#','Critical battery color did not update')
    values.measureBattAC=1; Update()
    assert(options['meterValueBattPct:FontColor']=='#colorText#' and vars.BatteryFillColor=='#colorBar#','Plugging in retained discharge warning')
    do
        local origVar,origMeasure,origBang=SKIN.GetVariable,SKIN.GetMeasure,SKIN.Bang
        local blurVars={BlurFile='#@#Blur.inc',AcrylicBlur='Acrylic'}
        local blurType='Acrylic'
        function SKIN:GetVariable(name,default) return blurVars[name]~=nil and blurVars[name] or origVar(self,name,default) end
        function SKIN:GetMeasure(name)
            if name=='MeasureBlur' then return {GetStringValue=function() return blurType end} end
            return origMeasure(self,name)
        end
        function SKIN:Bang(cmd,a,b,c)
            if cmd=='!SetOption' and a=='MeasureBlur' and b=='Type' then blurType=c end
            return origBang(self,cmd,a,b,c)
        end
        values.measureBattStatus=0; Update()
        assert(blurType=='None','Hiding desktop battery did not suppress MeasureBlur')
        values.measureBattStatus=4; values.measureBattPct=88; Update()
        assert(blurType=='Acrylic','Restoring battery did not restore MeasureBlur')
        SKIN.GetVariable,SKIN.GetMeasure,SKIN.Bang=origVar,origMeasure,origBang
    end
    print('PASS: Unchanged battery silence and immediate charging/discharging color transitions')
end

function TestVisualizer(root,scratch)
    local function check(v,m) if not v then error(m,2) end end
    local vars={ROOTCONFIG='SlateHUD',VisualMode='0',VisualizerBatterySaver='1',
        VisualizerGradient='270 | 255,255,255,255 ; 0.0 | 80,80,80,140 ; 1.0'}
    local peak,ac,clock=0,1,100
    local calls={}
    SKIN={GetVariable=function(_,k,d) return vars[k] or d end}
    function SKIN:GetMeasure(k) return {GetValue=function() return k=='MeasureAudioPeak' and peak or ac end} end
    function SKIN:Bang(...) calls[#calls+1]={...} end
    local realTime=os.time;os.time=function() return clock end
    dofile(root..'/@Resources/Visualizer.lua');Setup();Update();clock=103;Update()
    local dimmed=false
    for _,call in ipairs(calls) do
        if call[1]=='!SetOption' and call[2]=='MeterStaticBaseline' and call[3]=='Grad' then
            dimmed=call[4]=='270 | 255,255,255,64 ; 0.0 | 80,80,80,35 ; 1.0'
        end
    end
    check(dimmed,'Idle baseline did not preserve theme colors with reduced alpha')
    check(calls[#calls][1]=='!ActivateConfig' and calls[#calls][3]=='Idle.ini','Silence did not select slow idle skin')
    vars.VisualMode='1';peak=0.5;ac=0
    dofile(root..'/@Resources/Visualizer.lua');Setup();Update()
    check(calls[#calls][3]=='Economy.ini','Battery wake did not select reduced animation')
    vars.VisualMode='2';ac=1
    dofile(root..'/@Resources/Visualizer.lua');Update()
    check(calls[#calls][3]=='Visualizer.ini','AC did not restore full animation')
    local store=dofile(root..'/@Resources/FileStore.lua')
    vars['@'],vars.MonitorSnapshotFile,vars.VisualizerModeFile=root..'/@Resources/',scratch..'/visual-displays.txt',scratch..'/visual-mode.txt'
    local function sample(occupied)
        check(store.write(vars.MonitorSnapshotFile,('UPDATED=%d\nAA\texternal\t1\t100\t0\t0\t1920\t1080\t%d\nSKINS=1\nSKIN\tVisualizer\t0\n')
            :format(clock,occupied and 1 or 0)),'Display fixture failed')
        Update()
    end
    vars.VisualMode='2';ac=0
    dofile(root..'/@Resources/Visualizer.lua')
    for time=104,106 do clock=time; sample(true) end
    check(calls[#calls][3]=='Suspended.ini' and store.read(vars.VisualizerModeFile)=='2\nHIDE=Suspended.ini',
        'Fullscreen did not suspend and remember battery mode and visibility')
    vars.VisualMode='3'
    function SKIN:GetMeasure() error('Suspended visualizer sampled an audio measure') end
    dofile(root..'/@Resources/Visualizer.lua'); Setup()
    check(calls[#calls][1]=='!Hide','Suspended variant showed the hidden visualizer')
    for time=107,109 do clock=time; sample(false) end
    check(calls[#calls][3]=='Economy.ini','Fullscreen exit did not restore battery mode')
    check(store.read(vars.VisualizerModeFile)=='2\nHIDE=Economy.ini','Resuming lost the hidden state')
    vars.BlurFile='#@#Blur.inc'; vars.AcrylicBlur='Acrylic'; vars.VisualizerHideIdle='1'
    local blurType='Acrylic'
    local blurType,origBang='Acrylic',SKIN.Bang
    peak=0
    function SKIN:GetMeasure(name)
        if name=='MeasureBlur' then return {GetStringValue=function() return blurType end} end
        if vars.VisualMode=='3' then error('Suspended visualizer sampled an audio measure') end
        return {GetValue=function() return name=='MeasureAudioPeak' and peak or ac end}
    end
    function SKIN:Bang(cmd,a,b,c)
        if cmd=='!SetOption' and a=='MeasureBlur' and b=='Type' then blurType=c end
        return origBang(self,cmd,a,b,c)
    end
    vars.VisualMode='1'; dofile(root..'/@Resources/Visualizer.lua'); Setup()
    Update()
    check(blurType=='None','Hidden idle visualizer did not suppress MeasureBlur')
    vars.BlurFile=''; SKIN.Bang=origBang
    os.time=realTime
    print('PASS: Silent idle, audio wake-up, battery animation and AC recovery')
end

function TestDisks(root)
    dofile(root..'/@Resources/Disks.lua')
    local function severity(total,free,percent)
        return DiskSeverity(total,free,percent,85,95,20,5)
    end
    assert(severity(0,0,100)=='missing','Disconnected disk reported low capacity')
    assert(severity(100e9,5e9,45)=='critical','Critical remaining-GB boundary failed')
    assert(severity(100e9,20e9,45)=='warning','Warning remaining-GB boundary failed')
    assert(severity(1000e9,21e9,95)=='critical','Percentage warning did not take precedence')
    assert(severity(100e9,21e9,84)=='normal','Safe drive triggered a warning')
    assert(DiskSeverity(100e9,1,1,85,95,0,0)=='normal','Disabled thresholds triggered a warning')
    print('PASS: Decimal disk thresholds, highest severity and missing drives')
end
