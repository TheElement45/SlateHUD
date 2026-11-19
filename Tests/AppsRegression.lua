function RunAppsTests(root,scratch)
    local function check(value,message) if not value then error(message,2) end end
    local function key(i) return string.rep('0',62)..string.format('%02x',i) end
    local preferenceFile=scratch..'/AppsPreferences.txt'
    local vars={['@']=root..'/@Resources/',CURRENTPATH=scratch..'/',ROOTCONFIG='SlateHUD',
        ColorSecondary='white',ColorAccent='10,120,240,255',ColorMuted='muted',UiScale='1.125',
        AppCount='22',AppPreferencesFile=preferenceFile,AppShortcutFolder='C:/Fixtures/Apps'}
    for i=1,22 do
        local id=string.format('App%02d',i)
        vars[id..'Key']=key(i); vars[id..'Name']='Application '..i; vars[id..'Label']='App '..i
        vars[id..'Path']='C:/Fixtures/Apps/Application '..i..'.lnk'
        vars[id..'Favorite']=i<=8 and '1' or '0'
        vars[id..'Category']=i==9 and 'Communication' or (i<=11 and 'Development' or (i<=14 and 'Creative' or 'Utilities'))
    end
    vars.App01SecondaryAction='["C:/Fixtures/Personal - Brave.lnk"]'
    local options,visible,meters,calls={},{},{},{}
    local output,query,acPower='','',1
    SKIN={}
    function SKIN:GetVariable(name,fallback) return vars[name] or fallback end
    function SKIN:ReplaceVariables(value) return value end
    function SKIN:ParseFormula(value) return tonumber(value) end
    function SKIN:GetMeasure(name)
        if name=='MeasureAnimPower' then return {GetValue=function() return acPower end} end
        return {GetStringValue=function() return name=='MeasureSearchValue' and query or output end}
    end
    function SKIN:Bang(command,a,b,c,d)
        calls[#calls+1]={command,a,b,c,d}
        if command=='!SetOption' then options[a]=options[a] or {}; options[a][b]=c end
        if command=='!SetVariable' then vars[a]=b end
        if command=='!WriteKeyValue' then vars[b]=tostring(c) end
        if command=='!ShowMeterGroup' then visible[a]=true end
        if command=='!HideMeterGroup' then visible[a]=false end
        if command=='!ShowMeter' then meters[a]=true end
        if command=='!HideMeter' then meters[a]=false end
    end
    local function load()
        dofile(root..'/@Resources/Apps.lua'); Setup()
    end
    load()
    local count=0; for _,v in pairs(visible) do if v then count=count+1 end end
    check(count==8,'Default view should show eight favorites')
    local compactHeight=vars.AppCardH
    check(compactHeight<=400,'Collapsed launcher is no longer compact')
    check(options.MeterFavorites.Text=='FAVORITES  8 / 8','Favorites limit is not visible')
    check(options.MeterCategory1.Y==options.MeterCategory2.Y,'Category controls lost their two-column layout')
    check(options.MeterCategory5.Y==options.MeterCategory6.Y and
        tonumber(options.MeterCategory5.Y)>tonumber(options.MeterCategory3.Y),'Six categories did not use three rows')
    Toggle('Utilities')
    check(vars.AppCardH==compactHeight+152,'Eight utility apps should use two extra rows')
    check(visible.App15 and visible.App22,'Expanded utility apps missing')
    Toggle('Development')
    check(not visible.App15 and visible.App10,'Switching groups did not hide previous apps')
    check(tonumber(options.App15Hit.Y)==102*1.125,'Hidden meters retain expanded bounds')
    Toggle('Development'); check(vars.AppCardH==compactHeight,'Collapsed card did not shrink')

    OpenMenu('App09'); ToggleFavorite()
    check(options.MeterHint.Text:find('full',1,true),'Ninth favorite was not refused')
    check(options.MeterFavorites.Text=='FAVORITES  8 / 8','Pin limit was exceeded')
    OpenMenu('App01')
    check(options.Rainmeter.ContextTitle3=='Unpin from favorites','Pinned app menu is incorrect')
    check(options.Rainmeter.ContextTitle11=='Open Personal profile','Profile action missing or overlaps new category actions')
    check(options.Rainmeter.ContextTitle9=='Move to System' and options.Rainmeter.ContextTitle10=='Move to Productivity','New categories missing from app menu')
    LaunchSecondary()
    check(calls[#calls][1]==vars.App01SecondaryAction,'Profile shortcut arguments were lost')
    ToggleFavorite()
    check(options.MeterFavorites.Text=='FAVORITES  7 / 8','Unpin did not update favorites')
    OpenMenu('App09'); ToggleFavorite(); MoveTo('Creative')
    check(options.MeterFavorites.Text=='FAVORITES  8 / 8','Available favorite slot could not be filled')
    local file=assert(io.open(preferenceFile,'rb')); local saved=file:read('*a'); file:close()
    check(saved:find(key(9)..'\t1\tCreative',1,true),'Pin/category changes were not saved by stable identity')
    OpenShortcutLocation()
    check(calls[#calls][1]=='["explorer.exe" /select,"C:/Fixtures/Apps/Application 9.lnk"]','Shortcut location targets the wrong file')
    SuiteMenu()
    check(options.Rainmeter.ContextTitle=='Size: Compact' and options.Rainmeter.ContextTitle18=='Blur: Off' and options.Rainmeter.ContextTitle19=='---' and options.Rainmeter.ContextTitle20=='Show hidden apps' and options.Rainmeter.ContextTitle21=='' and calls[#calls][1]=='!SkinMenu','Background menu retained app actions')

    -- Reordering the generated catalog must not transfer a pin to a different app.
    for _,field in ipairs({'Key','Name','Label','Path','Favorite','Category','SecondaryAction'}) do
        vars['App09'..field],vars['App10'..field]=vars['App10'..field],vars['App09'..field]
    end
    load()
    OpenMenu('App10')
    check(options.Rainmeter.ContextTitle3=='Unpin from favorites','Pin was lost or attached to catalog position')
    check(options.Rainmeter.ContextTitle7=='* Creative','Category override was lost after reload')
    OpenMenu('App01'); check(options.Rainmeter.ContextTitle3=='Pin to favorites','Unpin was not durable')

    -- A failed preference write must not mutate the visible configuration.
    vars.AppPreferencesFile=scratch..'/missing/folder/Preferences.txt'
    load(); OpenMenu('App01'); ToggleFavorite()
    check(options.MeterHint.Text:find('Could not save',1,true),'Persistence failure has no feedback')
    OpenMenu('App01'); check(options.Rainmeter.ContextTitle3=='Unpin from favorites','Failed save changed the in-memory pin')
    vars.AppPreferencesFile=preferenceFile

    vars.AppCount='32'
    for i=23,32 do
        local id=string.format('App%02d',i)
        vars[id..'Key']=key(i); vars[id..'Name']='Application '..i; vars[id..'Label']='App '..i
        vars[id..'Favorite']='0'; vars[id..'Category']='Utilities'
    end
    vars.AppsOpenCategory='Utilities'; vars.AppsPageUtilities='1'
    load()
    local expanded,footer=vars.AppCardH,options.MeterPrev.Y
    check(visible.App15 and not visible.App23 and options.MeterPage.Text=='1 / 3','Large category was not paged')
    ChangePage(1)
    check(not visible.App15 and visible.App23 and visible.App30 and not visible.App31,'Second page has wrong apps')
    ChangePage(1)
    check(visible.App31 and visible.App32 and not visible.App23,'Last page is missing apps')
    check(vars.AppCardH==expanded and options.MeterPrev.Y==footer,'Last page moved the card or navigation controls')
    ChangePage(1); check(options.MeterPage.Text=='3 / 3','Paging exceeded the last page')
    Toggle('Development'); Toggle('Utilities')
    check(options.MeterPage.Text=='3 / 3','Category did not remember its page')
    load(); check(options.MeterPage.Text=='3 / 3','Page was lost after skin reload')

    query='  APPLICATION 31  '; Filter()
    check(visible.App31 and not visible.App32 and options.MeterFavorites.Text=='RESULTS  1','Case-insensitive search failed')
    check(meters.MeterCategory1==false,'Search results retained category controls')
    query='Application 1'; Filter()
    check(visible.App01,'Search omitted a favorite or used the category filter')
    query='['; Filter()
    check(options.MeterFavorites.Text=='RESULTS  0' and meters.MeterEmpty,'Search interpreted a Lua pattern or omitted empty feedback')
    ClearSearch(); check(options.MeterPage.Text=='3 / 3','Clearing search did not restore the category page')

    local hoverStart=#calls+1
    Hover('App01')
    check(options.App01Label.FontColor=='10,120,240,255' and options.App01Hit.SolidColor=='10,120,240,20','Hover ignores configured accent')
    Hover('App02'); Leave('App01')
    check(options.App01Label.FontColor=='white' and options.App02Label.FontColor=='10,120,240,255','Fast hover left the previous tile highlighted')
    check(options.MeterHint.Text:find('Application 2',1,true),'Delayed leave cleared the current app hint')
    for i=1,100 do
        local current=string.format('App%02d',i%8+1)
        local previous=string.format('App%02d',(i+7)%8+1)
        Hover(current); Leave(previous)
    end
    HoverControl('MeterCategory5'); HoverControl('MeterCategory6'); LeaveControl('MeterCategory5')
    check(options.MeterHint.Text:find('Productivity',1,true),'Stale control leave cleared the latest hint')
    LeaveControl('MeterCategory6')
    HoverControl('MeterCategory4'); LeaveControl('MeterCategory4')
    check(options.MeterCategory4.FontColor=='10,120,240,255','Leaving the active category lost its accent')
    ResetHover()
    for i=hoverStart,#calls do
        local call=calls[i]
        check(call[1]~='!ShowMeterGroup' and call[1]~='!HideMeterGroup','Hover rebuilds app visibility')
        check(not (call[1]=='!UpdateMeter' and call[2]=='*'),'Hover updates the entire widget')
        check(not (call[1]=='!SetOption' and (call[3]=='X' or call[3]=='Y' or call[3]=='ToolTipText')),'Hover repositions meters or recreates popup tooltips')
    end
    Hover('App01')
    Leave('App01'); check(options.App01Label.FontColor=='white','Hover accent not cleared')
    vars.UiAnimations='1'; vars.UiAnimationsBatterySaver='1'; acPower=1
    local animStart=#calls+1
    Hover('App01')
    check(options.App01Hit.SolidColor=='10,120,240,4','Animated hover did not start from soft tint alpha')
    local firedTimer=false
    for i=animStart,#calls do
        if calls[i][1]=='!CommandMeasure' and calls[i][2]=='MeasureHoverAnim' and calls[i][3]=='Execute 1' then firedTimer=true end
    end
    check(firedTimer,'Animated hover did not start ActionTimer')
    for _,expectedAlpha in ipairs({8,12,16,20}) do
        AnimStep()
        check(options.App01Hit.SolidColor=='10,120,240,'..expectedAlpha,'Hover animation step did not ramp alpha to '..expectedAlpha)
    end
    for i=animStart,#calls do
        check(not (calls[i][1]=='!UpdateMeter' and calls[i][2]=='*'),'Animated hover triggered full skin meter update')
    end
    Leave('App01')
    acPower=0
    Hover('App02')
    check(options.App02Hit.SolidColor=='10,120,240,20','Battery saver did not bypass animated hover timer')
    Leave('App02')
    vars.UiAnimations='0'; acPower=1
    OpenFolder(); check(calls[#calls][1]=='["C:/Fixtures/Apps"]','Shortcut folder link did not open')
    Scan(); local before=#calls; Scan(); check(#calls==before,'Concurrent refresh started')
    output='APPS:FAILED test'; FinishScan(); check(options.MeterRescan.Text=='RETRY','Refresh failure has no retry')
    Scan(); output='APPS:PUBLISHED 32 WARNINGS 1'; FinishScan(); check(calls[#calls][1]=='!Refresh','Successful scan did not reload')

    -- Additional configured favorites are demoted into categories, never extra rows.
    vars.AppCount='32'; vars.AppPreferencesFile=scratch..'/NoPreferences.txt'
    for i=1,32 do vars[string.format('App%02dFavorite',i)]='1' end
    vars.AppsOpenCategory=''
    load(); count=0; for _,v in pairs(visible) do if v then count=count+1 end end
    check(count==8 and vars.AppCardH==compactHeight,'Configured favorite overflow escaped the eight-slot cap')

    vars.AppCount='34'
    for i,category in ipairs({'System','Productivity'}) do
        local id=string.format('App%02d',32+i)
        vars[id..'Key']=key(32+i); vars[id..'Name']=category..' fixture'; vars[id..'Label']=category
        vars[id..'Favorite']='0'; vars[id..'Category']=category
    end
    load(); Toggle('System')
    check(visible.App33 and not visible.App34 and tonumber(options.App33Hit.Y)>tonumber(options.MeterCategory6.Y),'System group overlaps the third category row')
    Toggle('Productivity'); check(visible.App34 and not visible.App33,'Productivity group did not switch exclusively')
    OpenMenu('App34'); MoveTo('System')
    load(); Toggle('System')
    check(visible.App33 and visible.App34,'New category overrides did not persist')

    dofile(root..'/@Resources/Layout.lua')
    for _,case in ipairs({{1920,1080},{1536,864},{1280,720}}) do
        local w,h=unpack(case)
        local p,_,s=PlanLayout({x=0,y=0,w=w,h=h},1.125,false,false)
        check(p.Apps.x==p[''].x,'Launcher lost music alignment')
        check(p.Apps.y>=p.Visualizer.y+60*s,'Launcher overlaps visualizer')
        check(p.Apps.y+(expanded+24)*s<=h,'Expanded launcher exceeds supported monitor height')
    end
    -- Viewport fitting clamps expanded category page size and reclaims favorites shelf when vertically constrained.
    vars.AppsPageUtilities='1'; load()
    vars.LayoutWorkY='0'; vars.LayoutWorkHeight='820'
    SKIN.GetY=function() return 256 end
    Toggle('Utilities')
    check((tonumber(vars.AppCardH)+24)*1.125<=820-256,'Viewport fitting did not clamp Apps card height inside work area')
    check(visible.App01 and visible.App15 and not visible.App19,'Constrained viewport did not reduce category page size while keeping favorites')
    vars.LayoutWorkHeight='720'
    Render()
    check((tonumber(vars.AppCardH)+24)*1.125<=720-256,'Compact-favorites viewport fitting exceeded work area')
    check(not visible.App01 and options.MeterFavorites.Text:find('COLLAPSE GROUP',1,true),'Tight viewport did not reclaim favorites shelf')
    vars.LayoutWorkHeight='560'
    Render()
    check(not visible.App01 and visible.App15 and not visible.App19,'Sub-314px viewport did not keep single compact category row without favorites')
    vars.LayoutWorkHeight=nil; vars.LayoutWorkY=nil; SKIN.GetY=nil; Toggle('Utilities')
    for i=9,32 do vars[string.format('App%02dFavorite',i)]='0' end
    load()
    local left = tonumber(options.App02Hit.X)
    OpenMenu('App02'); MoveFavorite(1)
    check(tonumber(options.App02Hit.X)>left,'Favorite move did not change displayed order')
    load()
    check(tonumber(options.App02Hit.X)>left,'Favorite order was lost on refresh')
    OpenMenu('App02'); ToggleAppHidden()
    check(not visible.App02,'Hidden favorite remained visible')
    query='Application 2'; Filter()
    check(not visible.App02,'Hidden app leaked into search results')
    load(); ToggleHidden()
    check(visible.App02,'Hidden app was not available to restore after refresh')
    OpenMenu('App02'); ToggleAppHidden(); ToggleHidden()
    check(visible.App02,'Restored favorite was not visible')
    local normalX=tonumber(options.App01Hit.X)
    vars.BlurTightFrame='1'; Render()
    check(math.abs(tonumber(options.App01Hit.X)-(normalX-8*1.125))<0.01,'Tight blur frame did not shift App tile coordinates')
    vars.BlurTightFrame='0'; Render()
    print('PASS: Apps layout, categories, paging, search, menus, scan recovery, durable hiding and favorite order')
end
