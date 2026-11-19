-- Lua 5.1 controller checks with isolated personal files and a Rainmeter stand-in.
function RunWidgetTests(root,scratch)
    local function check(condition,message) if not condition then error(message,2) end end
    local planner=dofile(root .. '/@Resources/GameHubLayout.lua')
    for _,maximum in ipairs({600,300}) do
        local plan=planner.plan{favorites=4,categories=7,categoryKeys={'Recent','RPG','Action','Strategy','Other','Platforms','Utilities'},count=8,selected=true,maximum=maximum}
        local p=plan.categoryPositions
        local first=plan.compact and 3 or 2
        check(p[first].x==24 and p[first].y>p[1].y,'Genres did not start on a separate row')
        check(p[first+4].x==24 and p[first+4].y>p[first+2].y+plan.categoryStep,'Launcher groups lack a section gap')
        check(plan.gridY>p[#p].y+plan.categoryStep,'Category buttons overlap tiles')
    end
    local function contents(path)
        local file=assert(io.open(path,'r')); local text=file:read('*a'); file:close(); return text
    end
    local function write(path,text) local file=assert(io.open(path,'w')); file:write(text); file:close() end
    local function library(count,catalog,changed,available,revision)
        local lines={'[Variables]','GameCardH=500','[MeterCatRPG]','Y=74','Text=RPG & ADVENTURE'}
        if revision then table.insert(lines,3,'GameLibraryRevision=' .. revision) end
        for i=1,count do
            local title=i==1 and 'The Witcher 3: Wild Hunt - Complete Edition' or 'Game ' .. i
            local path='D:\\Games\\Game ' .. i .. '\\game.exe'
            lines[#lines+1]='[MeterRPG' .. i .. ']\nY=' .. (74+i*18) .. '\nText=[\\x25B8] ' .. title
            if catalog then
                lines[#lines+1]='GameId=steam:' .. (100+i) .. '\nGamePath=' .. (changed and path:gsub('game.exe','new.exe') or path)
                lines[#lines+1]='GameAvailable=' .. (available==false and '0' or '1') .. '\nGameConfidence=platform\n; GameAlias=' .. path .. '\nLeftMouseUpAction='
            else lines[#lines+1]='LeftMouseUpAction=["' .. path .. '"]' end
        end
        lines[#lines+1]='[MeterCatUtilities]\nY=220\nText=UTILITIES\n[MeterUtilities1]\nY=240\nText=[\\x25B8] Discord\nLeftMouseUpAction=["#pathDiscord#"]'
        write(scratch .. '/GameList.inc',table.concat(lines,'\n'))
    end
    local variables={CURRENTPATH=scratch .. '/',ROOTCONFIG='SlateHUD',['@']=root .. '/@Resources/',
        GameCardH='500',GameCardW='320',StatCardW='222',NotesGap='24',GameMaxCardH='480'}
    local options,hidden,calls,moves,measures={},{},{},{},{}
    SKIN={x=1504,y=21}
    function SKIN:GetVariable(name,default) return variables[name] or default end
    function SKIN:GetMeter(name) return {} end
    function SKIN:GetX() return self.x end
    function SKIN:GetY() return self.y end
    function SKIN:GetMeasure(name)
        local result=measures[name] or {value=-1,text=''}
        return {GetValue=function() return result.value end,GetStringValue=function() return result.text end}
    end
    function SKIN:Bang(command,a,b,c,d)
        calls[#calls+1]={command,a,b,c,d}
        if command=='!SetOption' then options[a]=options[a] or {}; options[a][b]=c
        elseif command=='!SetVariable' then variables[a]=tostring(b)
        elseif command=='!Move' then moves[#moves+1]={a,b,c}
        elseif command=='!HideMeter' or command=='!ShowMeter' then hidden[a]=command=='!HideMeter'
        elseif command=='!HideMeterGroup' or command=='!ShowMeterGroup' then
            for _,part in ipairs({'Hit','Icon','Initial','Label'}) do hidden[a .. part]=command=='!HideMeterGroup' end
        end
    end
    local function commands(measure)
        local count=0
        for _,call in ipairs(calls) do if call[1]=='!CommandMeasure' and call[2]==measure and call[3]=='Run' then count=count+1 end end
        return count
    end
    local function reload() dofile(root .. '/@Resources/GameHub.lua'); Initialize(); Setup() end
    local function category(name)
        for i=1,8 do
            local meter='MeterCategory' .. i
            if not hidden[meter] and options[meter].Text:find(name,1,true) then return i end
        end
        error('Missing category: ' .. name)
    end
    local function visible(title)
        for slot=1,12 do
            local name='GameTile' .. slot
            if hidden[name .. 'Hit']==false and options[name .. 'Label'].Text==title then return slot end
        end
    end
    library(12)
    dofile(root .. '/@Resources/GameHub.lua'); Initialize(); DockNotes()
    check(#moves==0,'Docking ran before setup'); Setup()
    check(hidden.MeterRPG1 and hidden.MeterUtilities1,'Old list hit targets remain visible')
    check(visible('The Witcher 3: Wild Hunt - Complete Edition')==5,'Default category did not show game tiles')
    check(hidden.GameTile5Initial==false and hidden.GameTile5Icon,'Missing icon has no fallback')
    check(tonumber(options.GameTile8Hit.X)==240,'Tiles do not use four columns')
    check(tonumber(variables.GameCardH)<=480,'Expanded grid exceeded height cap')
    check(moves[#moves][1]==1602 and moves[#moves][2]==SKIN.y+tonumber(variables.GameCardH)+24,'Notes dock incorrect')
    local height,count=variables.GameCardH,#moves
    HoverTile(5); HoverTile(6); LeaveTile(5)
    check(options.GameTile6Label.FontColor=='#ColorAccent#','Stale tile leave cleared newer hover')
    for i=1,100 do HoverTile(5+i%8) end
    check(variables.GameCardH==height and #moves==count,'Hover rebuilt the layout')
    ResetHover(); HoverTile(5)
    check(options.MeterHint.Text=='The Witcher 3: Wild Hunt - Complete Edition','Full title lost on hover')
    ChangePage(1)
    check(options.MeterPageNumber.Text=='2 / 2' and visible('Game 9')==5,'Second page unreachable')
    check(tonumber(options.GameTile9Hit.Y)==88 and hidden.GameTile9Hit,'Hidden final-page tile retained hit area')
    check(variables.GameCardH==height,'Final page moved the footer')
    ToggleCategory(category('Utilities'))
    check(visible('Discord')==5 and not visible('Game 9'),'Switching category left stale tiles')
    ToggleCategory(category('RPG & Adventure'))
    check(visible('Game 9')==5,'Category page not remembered')
    reload(); check(visible('Game 9')==5,'Category page did not survive refresh')
    ToggleCategory(category('RPG & Adventure'))
    check(hidden.GameTile5Hit and hidden.MeterPageNext,'Collapsing did not hide grid and pager')
    reload(); check(hidden.GameTile5Hit,'Collapsed view did not persist')
    ToggleCategory(category('RPG & Adventure')); ChangePage(-1)
    OpenTileMenu(5); PinSelectedGame()
    check(visible('The Witcher 3: Wild Hunt - Complete Edition')==1,'Pinned game not shown in shelf')
    check(options.GameTile5Label.Text=='Game 2','Pinned game duplicated in its category')
    Toggle(3); Toggle(4); Toggle(5); Toggle(6)
    check(options.MeterHint.Text:find('Four favorites maximum',1,true),'Favorite limit not enforced')
    check(hidden.GameTile4Hit==false,'Fourth favorite missing')
    local favoritePath=scratch .. '/Favorites.txt'
    reload(); check(options.MeterHint.Text:find('4/4',1,true),'Pins not saved')
    local initialOrder=contents(favoritePath)
    OpenTileMenu(1)
    check(options.Rainmeter.ContextTitle11=='Move favorite right' and options.Rainmeter.ContextTitle12=='',
        'First favorite slot offered Move favorite left')
    MoveFavorite(-1)
    check(options.GameTile1Label.Text=='The Witcher 3: Wild Hunt - Complete Edition' and contents(favoritePath)==initialOrder,
        'Boundary MoveFavorite(-1) on first slot altered visible or saved order')
    OpenTileMenu(4)
    check(options.Rainmeter.ContextTitle11=='Move favorite left' and options.Rainmeter.ContextTitle12=='',
        'Last favorite slot offered Move favorite right')
    MoveFavorite(1)
    check(options.GameTile4Label.Text=='Game 4' and contents(favoritePath)==initialOrder,
        'Boundary MoveFavorite(1) on last slot altered visible or saved order')
    SuiteMenu()
    check(options.Rainmeter.ContextTitle=='Size: Compact' and options.Rainmeter.ContextTitle18=='Blur: Off' and
        options.Rainmeter.ContextTitle19=='---' and options.Rainmeter.ContextTitle20=='Show hidden games' and
        options.Rainmeter.ContextTitle21=='',
        'SuiteMenu did not restore shared slots or append skin action cleanly')
    local realOpen=io.open
    io.open=function(p,m) if p==favoritePath .. '.tmp' and m=='wb' then return nil,'denied' end return realOpen(p,m) end
    OpenTileMenu(1); MoveFavorite(1); io.open=realOpen
    check(options.MeterHint.Text:find('Check folder permissions',1,true) and
        options.GameTile1Label.Text=='The Witcher 3: Wild Hunt - Complete Edition' and
        options.GameTile2Label.Text=='Game 2' and contents(favoritePath)==initialOrder,
        'Failed temp-open reorder changed visible/saved order or lost permission hint')
    local realRename=os.rename
    os.rename=function(from,to) if from==favoritePath and to==favoritePath .. '.bak' then return nil,'locked' end return realRename(from,to) end
    OpenTileMenu(1); MoveFavorite(1); os.rename=realRename
    check(options.MeterHint.Text:find('Please try again',1,true) and
        options.GameTile1Label.Text=='The Witcher 3: Wild Hunt - Complete Edition' and
        options.GameTile2Label.Text=='Game 2' and contents(favoritePath)==initialOrder,
        'Failed backup-rename reorder changed visible/saved order or lost retry hint')
    os.rename=function(from,to) if from==favoritePath .. '.tmp' and to==favoritePath then return nil,'blocked' end return realRename(from,to) end
    OpenTileMenu(1); MoveFavorite(1); os.rename=realRename
    check(options.MeterHint.Text:find('Previous pins retained',1,true) and
        options.GameTile1Label.Text=='The Witcher 3: Wild Hunt - Complete Edition' and
        options.GameTile2Label.Text=='Game 2' and contents(favoritePath)==initialOrder,
        'Failed final-replace reorder changed visible/saved order or lost retained hint')
    OpenTileMenu(1); MoveFavorite(1)
    check(options.GameTile1Label.Text=='Game 2' and options.GameTile2Label.Text=='The Witcher 3: Wild Hunt - Complete Edition','MoveFavorite right did not reorder shelf')
    reload()
    check(options.GameTile1Label.Text=='Game 2','Reordered game favorites did not persist')
    OpenTileMenu(2); MoveFavorite(-1)
    check(options.GameTile1Label.Text=='The Witcher 3: Wild Hunt - Complete Edition','MoveFavorite left did not restore order')
    OpenTileMenu(2); PinSelectedGame(); check(options.MeterHint.Text:find('3/4',1,true),'Tile unpin failed')
    library(12,true,true); reload()
    check(contents(favoritePath):find('steam:101',1,true),'Path pins did not migrate to stable IDs')
    local launched=commands('MeasureLaunch')
    LaunchTile(1)
    check(variables.GameLaunchId=='steam:101' and commands('MeasureLaunch')==launched+1,'Favorite did not launch by stable ID')
    measures.MeasureLaunch={value=1,text='GAMEHUB:LAUNCHED'}; FinishLaunch()
    local revisionA,revisionB=string.rep('a',32),string.rep('b',32)
    library(12,true,true,true,revisionA); reload()
    LaunchTile(1)
    check(variables.GameLaunchRevision==revisionA,'Tile did not send its library revision')
    library(12,true,true,true,revisionB)
    measures.MeasureLaunch.text='GAMEHUB:STALE'; FinishLaunch()
    check(options.MeterHint.Text:find('Select the game again',1,true),'Stale tile did not prompt for retry')
    LaunchTile(1)
    check(variables.GameLaunchRevision==revisionB,'Stale tile did not reload the published library')
    measures.MeasureLaunch.text='GAMEHUB:LAUNCHED'; FinishLaunch()
    library(12,true,false,false); reload()
    launched=commands('MeasureLaunch'); LaunchTile(1)
    check(commands('MeasureLaunch')==launched and options.MeterHint.Text:find('unavailable',1,true),'Offline favorite launched')
    check(options.GameTile1Icon.ImageAlpha=='100','Offline tile is not dimmed')
    write(favoritePath,'steam:901\tMissing game 1\tD:\\missing.exe\nsteam:902\tMissing game 2\tD:\\missing2.exe\n')
    library(12,true); reload(); OpenTileMenu(1); PinSelectedGame()
    check(options.GameTile1Label.Text=='Missing game 2','Missing favorite could not be removed')
    local before=contents(favoritePath)
    local rename=os.rename
    os.rename=function(from,to) if from==favoritePath .. '.tmp' then return nil,'simulated failure' end return rename(from,to) end
    RemoveFavorite(1); os.rename=rename
    check(contents(favoritePath)==before and options.MeterHint.Text:find('Previous pins retained',1,true),'Failed save lost pins or feedback')
    assert(os.rename(favoritePath,favoritePath .. '.bak')); write(favoritePath .. '.tmp','partial data')
    reload(); check(contents(favoritePath)==before,'Interrupted save did not recover pins')
    print('PASS: Icon grid, one category, stable pages, hover, stable-ID pins, offline games, save rollback/recovery')

    -- Search is independent of the selected category, favorites and case.
    ToggleCategory(category('Utilities'))
    measures.MeasureSearchValue={value=0,text='  THE WITCHER  '}; Filter()
    check(visible('The Witcher 3: Wild Hunt - Complete Edition')==5,'Global literal search failed')
    check(options.MeterSubtitle.Text=='1 match' and hidden.MeterClearSearch==false,'Search count or clear control missing')
    measures.MeasureSearchValue.text='Missing [literal] #title'; Filter()
    check(options.MeterSearch.Text=='  Missing \239\188\187literal\239\188\189 \239\188\131title','GameHub display did not escape brackets/hashes as valid UTF-8 fullwidth')
    check(options.MeterSubtitle.Text=='0 matches' and hidden.GameTile5Hit and hidden.MeterEmpty==false,'Empty search left stale tiles')
    ClearSearch(); check(visible('Discord')==5 and hidden.MeterClearSearch,'Search did not restore category')
    variables.GameShowRecent='1'; reload()
    Launch(2); FinishLaunch(); ToggleCategory(category('Recent'))
    check(visible('The Witcher 3: Wild Hunt - Complete Edition')==5,'Recent category did not update after successful launch')
    check(contents(scratch .. '/Recent.txt')=='steam:101\n','Recent identity not stored')
    variables.UiScale='1.125'; Update()
    check(tonumber(options.GameTile5Hit.X)==24*1.125,'Tile geometry did not react to scale change')
    check(moves[#moves][1]==SKIN.x+98*1.125,'Scaled Notes right alignment incorrect')
    variables.UiScale='(1.125)'
    function SKIN:ReplaceVariables(value) return value end
    function SKIN:ParseFormula(value) return tonumber(value:match('^%(([%d.]+)%)$')) end
    Setup(); check(tonumber(options.GameTile5Hit.X)==24*1.125,'Formula scale lost')
    variables.UiScale='1'; variables.GameMaxCardH='280'; variables.WORKAREAY='0'; variables.WORKAREAHEIGHT='620'
    SKIN.y=21; Update()
    check(tonumber(variables.GameCardH)<=280,'Compact tiles exceed screen cap')
    check(hidden.MeterFavoritesTitle,'Small display did not reclaim favorites shelf')
    ToggleCategory(category('Favorites'))
    check(visible('Missing game 2')==5,'Compact view lost favorites access')
    check(moves[#moves][2]+192<=620,'Compact Game Hub crowds Notes out of work area')
    variables.GameMaxCardH='480'; variables.WORKAREAHEIGHT='1080'; Update()
    check(visible('Missing game 2')==1,'Favorites shelf did not return after resize')
    variables.BlurTightFrame='1'; Update()
    check(tonumber(options.GameTile1Hit.X)==16,'Tight frame did not shift GameHub tile X')
    variables.BlurTightFrame='0'; Update()
    variables.UiAnimations='1'; measures.MeasureAnimPower={value=1,text='1'}
    HoverTile(1)
    check(options.GameTile1Hit.SolidColor=='235,170,0,4','Hover animation did not start at alpha 4')
    check(calls[#calls][1]=='!CommandMeasure' and calls[#calls][2]=='MeasureHoverAnim' and calls[#calls][3]=='Execute 1','Hover animation did not execute ActionList1')
    AnimStep(); check(options.GameTile1Hit.SolidColor=='235,170,0,8','AnimStep did not advance hover alpha')
    AnimStep(); AnimStep(); AnimStep(); check(options.GameTile1Hit.SolidColor=='235,170,0,20','AnimStep did not reach target hover alpha')
    LeaveTile(1); measures.MeasureAnimPower={value=0,text='0'}
    HoverTile(1); check(options.GameTile1Hit.SolidColor=='235,170,0,20','Battery saver did not bypass hover animation')
    LeaveTile(1); variables.UiAnimations='0'; measures.MeasureAnimPower=nil
    print('PASS: Search/clear, recent category, formula scaling, compact favorites, tight framing, hover animations and screen-aware Notes docking')

    local scans=commands('MeasureScan'); BeginScan(); BeginScan()
    check(commands('MeasureScan')==scans+1,'Repeated click started concurrent scan')
    measures.MeasureScan={value=1,text='GAMEHUB:FAILED simulated failure'}; FinishScan()
    check(options.MeterBtnScan.Text=='SCAN' and options.MeterHint.Text:find('simulated failure',1,true),'Scan failure feedback missing')
    BeginScan(); measures.MeasureScan={value=103,text=''}; Update()
    check(options.MeterBtnScan.Text=='SCAN','Startup failure left scan button stuck')
    BeginScan(); measures.MeasureScan={value=1,text=''}; FinishScan()
    check(options.MeterHint.Text:find('interrupted',1,true),'Timeout accepted as success')
    BeginScan(); measures.MeasureScan={value=1,text='GAMEHUB:PUBLISHED'}; FinishScan()
    check(calls[#calls][1]=='!Refresh','Published scan did not refresh')
    variables.GameStatusFile=scratch .. '/scan_status.txt'
    write(variables.GameStatusFile,'State=Warning\nSummary=21 games - updated 2026-11-18 10:00\nDetail=1 launch target needs review in Overrides.txt.\nLastSuccess=2026-11-18 10:00\n')
    reload()
    check(options.MeterSubtitle.Text=='21 games' and options.MeterSubtitle.FontColor=='#ColorSecondary#',
        'Plain game count subtitle should stay secondary color when no scan errors/offline games occurred')
    write(variables.GameStatusFile,'State=Warning\nSummary=3 games - scan warnings\nDetail=Drive unavailable\nLastSuccess=2026-10-29 12:00\n')
    reload(); ScanHint()
    check(options.MeterSubtitle.Text=='3 games - scan warnings' and options.MeterSubtitle.FontColor=='#ColorWarn#',
        'Scan warning summary or color missing')
    check(options.MeterHint.Text:find('Drive unavailable',1,true) and options.MeterHint.Text:find('Last successful scan',1,true),'Scan details missing')
    for _,call in ipairs(calls) do check(call[3]~='ToolTipText','Native popup tooltip added') end
    print('PASS: Scan guard, failure/timeout/startup recovery, publication refresh and detailed scan feedback')

    measures.MeasureSearchValue.text='THE WITCHER'; Filter()
    local title='The Witcher 3: Wild Hunt - Complete Edition'
    OpenTileMenu(assert(visible(title))); SetGameCategory('Strategy')
    reload()
    measures.MeasureSearchValue.text='strategy'; Filter()
    check(visible(title),'Category override did not survive catalog reload')
    OpenTileMenu(assert(visible(title))); SetGameHidden(true)
    check(not visible(title),'Hidden game remained in normal search')
    reload(); ToggleHiddenGames()
    OpenTileMenu(assert(visible(title))); SetGameHidden(false); ToggleHiddenGames()
    measures.MeasureSearchValue.text='strategy'; Filter()
    OpenTileMenu(assert(visible(title))); SetGameCategory()
    check(not visible(title),'Category reset retained the override')
    check(commands('MeasureScan')==scans+4,'Changing preferences triggered a game scan')
    do
        local dLines={'[Variables]','GameCardH=348','GameLibraryRevision=' .. string.rep('c',32),'GameEntryCount=1',
            'Game1Category=RPG','Game1Title=Data Only RPG','Game1GameId=steam:888',
            'Game1GamePath=D:\\Games\\Data\\game.exe','Game1GameAvailable=1','Game1GameConfidence=platform',
            'PlatformCount=1','Platform1Title=Steam','Platform1Action=["steam://open/main"]',
            'UtilityCount=1','Utility1Title=Discord','Utility1Action=["#pathDiscord#"]'}
        write(scratch .. '/GameList.inc',table.concat(dLines,'\n'))
        local beforeCalls=#calls
        reload()
        for i=beforeCalls+1,#calls do
            local c=calls[i]
            check(c[1]~='!HideMeter' or not tostring(c[2]):match('^MeterRPG'),
                'Data-only GameList.inc should not emit legacy meter hide bangs')
        end
        ToggleCategory(category('RPG & Adventure'))
        check(visible('Data Only RPG')==5,'Data-only GameList.inc did not load RPG game tile')
        ToggleCategory(category('Platforms'))
        check(visible('Steam')==5,'Data-only GameList.inc did not load Platforms tile')
    end
    print('PASS: Durable game hide/restore, data-only GameList.inc loading and category overrides without rescanning')

    dofile(root .. '/@Resources/Battery.lua')
    local power, label, text, present = DescribeBattery(76, 1, 1, -1, 'Unknown')
    check(power == 'Plugged in' and label == 'Status' and text == 'Charging' and present, 'Charging status incorrect')
    power, label, text = DescribeBattery(100, 1, 4, -1, 'Unknown')
    check(text == 'Fully charged', 'Full charge status incorrect')
    power, label, text = DescribeBattery(80, 1, 4, -1, 'Unknown')
    check(text == 'Not charging', 'Charge-limited AC status incorrect')
    power, label, text = DescribeBattery(56, 0, 4, 7500, '02:05')
    check(power == 'On battery' and label == 'Time left' and text == '02:05', 'Valid lifetime estimate lost')
    power, label, text = DescribeBattery(56, 0, 4, 4294967295, 'Unknown')
    check(label == 'Time left' and text == 'No estimate', 'Unknown lifetime leaked into UI')
    power, label, text, present = DescribeBattery(255, 1, 0, -1, 'Unknown')
    check(not present, 'Battery card visible on a desktop')
    power, label, text = DescribeBattery(255, 255, 255, -1, 'Unknown')
    check(text == 'Power unknown', 'Unavailable power state was guessed')
    print('PASS: Battery charging, full charge, AC limit, lifetime estimate, unavailable time, no battery')
end
