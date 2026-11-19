local apps, byId, preferences = {}, {}, {}
local categories = {'Communication','Development','Creative','Utilities','System','Productivity'}
local open, search, selected = '', '', nil
local showingHidden = false
local scale, scanning = 1, false
local gridY, rowH, pageSize, favoriteLimit = 102, 72, 8, 8
local page, pageCount, pages = 1, 1, {}
local store, preferenceFile
local hoveredApp, hoveredControl
local hoverStep = 0
local function option(meter,key,value) SKIN:Bang('!SetOption',meter,key,tostring(value)) end
local function show(group,visible) SKIN:Bang(visible and '!ShowMeterGroup' or '!HideMeterGroup',group) end
local function num(name, default)
    local raw = SKIN:GetVariable(name, tostring(default))
    return tonumber(raw) or (SKIN.ParseFormula and SKIN:ParseFormula(SKIN:ReplaceVariables(raw))) or default
end
local function cardShift()
    local tight = num('BlurTightFrame', 0) == 1
    return num('CardShiftX', tight and -8 or 0), num('CardShiftY', tight and -16 or 0)
end
local function at(meter,x,y)
    local sx, sy = cardShift()
    option(meter,'X',(x+sx)*scale); option(meter,'Y',(y+sy)*scale)
end
local function maxCardHeight()
    local configured = num('AppMaxCardH', 540)
    local workY = num('LayoutWorkY', num('WORKAREAY', 0))
    local workH = num('LayoutWorkHeight', num('WORKAREAHEIGHT', 0))
    if workH > 0 then
        local frameW = num('CardFrameW', 16)
        local frameH = num('CardFrameH', 24)
        local tight = num('BlurTightFrame', 0) == 1
        local padY = num('CardPadY', tight and 0 or (frameH - math.floor(frameW / 2)))
        local bottomMargin = tight and math.floor(frameW / 2) or num('ActiveFrameH', frameH)
        local gap = num('CardGap', 8)
        local defaultY = workY + (gap + num('MediaCardH', 140) + gap + num('VisualizerCardH', 44) + frameH + gap + (frameH - math.floor(frameW / 2) - padY)) * scale
        local y = (SKIN and SKIN.GetY) and SKIN:GetY() or defaultY
        local available = math.floor((workY + workH - y) / scale) - bottomMargin
        if available > 0 then configured = math.min(configured, available) end
    end
    return configured
end
local function display(value)
    return tostring(value or ''):gsub('[\r\n\t]',' '):gsub('#','＃'):gsub('%[','［'):gsub('%]','］')
end
local function validCategory(value)
    for _,category in ipairs(categories) do if value==category then return true end end
    return false
end
local function tint(alpha)
    local rgb=SKIN:GetVariable('ColorAccent','235,170,0'):match('(%d+,%s*%d+,%s*%d+)') or '235,170,0'
    return rgb..','..alpha
end
function SetHint(text)
    option('MeterHint','Text',display(text))
    SKIN:Bang('!UpdateMeter','MeterHint'); SKIN:Bang('!Redraw')
end
local function defaultHint()
    if showingHidden then return 'Right-click an app to restore it. Right-click the card for visible apps.' end
    return search~='' and 'Results include favorites | Right-click an app for options' or
        'Right-click an app to pin it or change its category'
end
local function position(app,col,y)
    local x=24+col*72
    at(app.id..'Hit',x,y); at(app.id..'Icon',x+19,y+4)
    at(app.id..'Label',x+35,y+40); at(app.id..'Profile',x+60,y+2)
    show(app.id,true)
    if app.secondary=='' then SKIN:Bang('!HideMeter',app.id..'Profile') end
end
local function favoriteApps()
    local list = {}
    for _,app in ipairs(apps) do
        if app.favorite and not app.hidden then list[#list+1] = app end
    end
    table.sort(list, function(a,b)
        if a.rank ~= b.rank then return (a.rank or math.huge) < (b.rank or math.huge) end
        return a.id < b.id
    end)
    return list
end
local function savePreferences(changes)
    local updated = {}
    for key,value in pairs(preferences) do updated[key] = value end
    for app,value in pairs(changes) do updated[app.key] = value end
    local keys,lines={}, {'# Apps preferences v2: stable shortcut key, favorite, category, hidden, order (tab separated)'}
    for key in pairs(updated) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do
        local value=updated[key]
        lines[#lines+1]=table.concat({key,value.favorite and '1' or '0',value.category,
            value.hidden and '1' or '0',value.rank or 0},'\t')
    end
    if not store.write(preferenceFile,table.concat(lines,'\n')..'\n') then
        SetHint('Could not save changes. Your previous settings are retained.')
        return false
    end
    preferences = updated
    for app,value in pairs(changes) do
        app.favorite,app.category,app.hidden,app.rank = value.favorite,value.category,value.hidden,value.rank
    end
    return true
end
local function preference(favorite,category,hidden,rank)
    return {favorite=favorite,category=category,hidden=hidden,rank=favorite and rank or nil}
end
local function savePreference(app,favorite,category,hidden)
    return savePreferences({[app]=preference(favorite,category,hidden,app.rank)})
end
local function savePage()
    if showingHidden or search~='' or open=='' then return end
    pages[open]=page
    SKIN:Bang('!WriteKeyValue','Variables','AppsPage'..open,page,SKIN:GetVariable('CURRENTPATH')..'View.inc')
end
function Render()
    if hoveredApp or hoveredControl then ResetHover() end
    local favorites,activeItems=favoriteApps(),{}
    local filtering=search~='' or showingHidden
    for _,app in ipairs(apps) do
        show(app.id,false)
        -- Hidden meters must not retain the previous page's window bounds.
        at(app.id..'Hit',24,gridY); at(app.id..'Icon',43,gridY+4)
        at(app.id..'Label',59,gridY+40); at(app.id..'Profile',84,gridY+2)
        option(app.id..'Hit','SolidColor','0,0,0,1')
        option(app.id..'Label','FontColor',SKIN:GetVariable('ColorSecondary'))
        if filtering and (not not app.hidden) == showingHidden and (app.name..' '..app.label):lower():find(search,1,true) then
            activeItems[#activeItems+1]=app
        end
    end
    local heightLimit = maxCardHeight()
    local favRows = math.max(1, math.ceil(#favorites / 4))
    local catHeight = math.ceil(#categories / 2) * 28 + 4
    local compactFavorites = (not filtering) and (open ~= '') and (gridY + favRows * rowH + 10 + catHeight + rowH + 52 > heightLimit)
    local heading = showingHidden and 'HIDDEN  ' or 'RESULTS  '
    option('MeterFavorites','Text',filtering and (heading..#activeItems) or
        (compactFavorites and 'CATEGORIES  (COLLAPSE GROUP FOR FAVORITES)' or ('FAVORITES  '..#favorites..' / '..favoriteLimit)))
    option('MeterSearch','Text',filtering and ('  '..display(search)) or '  Search apps...')
    SKIN:Bang(search~='' and '!ShowMeter' or '!HideMeter','MeterClearSearch')
    SKIN:Bang('!HideMeter','MeterEmpty')
    local y=gridY
    if not filtering and not compactFavorites then
        for i,app in ipairs(favorites) do position(app,(i-1)%4,y+math.floor((i-1)/4)*rowH) end
        if #favorites==0 then
            at('MeterEmpty',24,y+8); option('MeterEmpty','Text','No favorites yet. Right-click an app below to pin it.')
            SKIN:Bang('!ShowMeter','MeterEmpty')
        end
        y=y+favRows*rowH+10
    end
    for i,category in ipairs(categories) do
        local items={}
        for _,app in ipairs(apps) do
            if not app.hidden and not app.favorite and app.category==category then items[#items+1]=app end
        end
        local meter='MeterCategory'..i
        at(meter,24+((i-1)%2)*148,y+math.floor((i-1)/2)*28)
        option(meter,'Text',(open==category and '- ' or '+ ')..category..' '..#items)
        option(meter,'FontColor',SKIN:GetVariable(open==category and 'ColorAccent' or 'ColorSecondary'))
        option(meter,'SolidColor',open==category and tint(18) or SKIN:GetVariable('ColorPill', '255,255,255,7'))
        SKIN:Bang(filtering and '!HideMeter' or '!ShowMeter',meter)
        if not filtering and open==category then activeItems=items end
    end
    if not filtering then y=y+catHeight end
    local maxRows = math.max(1, math.min(2, math.floor((heightLimit - y - 52) / rowH)))
    pageSize = maxRows * 4
    pageCount=math.max(1,math.ceil(#activeItems/pageSize))
    page=math.max(1,math.min(page,pageCount))
    if #activeItems>0 then
        local first=(page-1)*pageSize+1
        local last=math.min(#activeItems,page*pageSize)
        for j=first,last do position(activeItems[j],(j-first)%4,y+math.floor((j-first)/4)*rowH) end
        -- Every page in this group reserves the same rows, including its last page.
        y=y+math.ceil(math.min(#activeItems,pageSize)/4)*rowH+8
    elseif filtering or open~='' then
        at('MeterEmpty',24,y+12)
        local message = 'No unpinned apps in this category.'
        if search~='' then message = 'No matching apps. Try another name or clear the search.'
        elseif showingHidden then message = 'No hidden apps.' end
        option('MeterEmpty','Text',message)
        SKIN:Bang('!ShowMeter','MeterEmpty'); y=y+rowH+8
    end
    local _, sy = cardShift()
    option('MeterFooter','Y',(y+4+sy)*scale); option('MeterHint','Y',(y+27+sy)*scale)
    for _,meter in ipairs({'MeterPrev','MeterPage','MeterNext'}) do
        option(meter,'Y',(y+4+sy)*scale)
        SKIN:Bang(pageCount>1 and '!ShowMeter' or '!HideMeter',meter)
    end
    option('MeterPage','Text',page..' / '..pageCount)
    option('MeterPrev','FontColor',SKIN:GetVariable(page>1 and 'ColorSecondary' or 'ColorMuted'))
    option('MeterNext','FontColor',SKIN:GetVariable(page<pageCount and 'ColorSecondary' or 'ColorMuted'))
    option('MeterPrev','MouseActionCursor',page>1 and 1 or 0)
    option('MeterNext','MouseActionCursor',page<pageCount and 1 or 0)
    option('MeterHint','Text',defaultHint())
    SKIN:Bang('!SetVariable','AppCardH',y+44)
    SKIN:Bang('!UpdateMeter','*'); SKIN:Bang('!Redraw')
end
function Setup()
    local raw=SKIN:GetVariable('UiScale','1')
    scale=tonumber(raw) or SKIN:ParseFormula(SKIN:ReplaceVariables(raw)) or 1
    store=dofile(SKIN:GetVariable('@')..'FileStore.lua')
    preferenceFile=SKIN:GetVariable('AppPreferencesFile',SKIN:GetVariable('CURRENTPATH')..'Preferences.txt')
    preferences={}
    for line in (store.recover(preferenceFile) or ''):gmatch('[^\r\n]+') do
        local key,favorite,category,rest = line:match('^([a-f0-9]+)\t([01])\t([^\t]+)(.*)$')
        if key and #key==64 and validCategory(category) then
            local hidden,rank = rest:match('^\t([01])\t(%d+)$')
            rank = tonumber(rank) or 0
            if rest=='' or hidden then
                preferences[key] = {favorite=favorite=='1',category=category,hidden=hidden=='1',rank=rank>0 and rank or nil}
            end
        end
    end
    apps,byId={},{}
    for i=1,tonumber(SKIN:GetVariable('AppCount','0')) do
        local id=string.format('App%02d',i)
        local app={id=id,key=SKIN:GetVariable(id..'Key',id),name=SKIN:GetVariable(id..'Name',id),
            label=SKIN:GetVariable(id..'Label',id),path=SKIN:GetVariable(id..'Path',''),
            secondary=SKIN:GetVariable(id..'SecondaryAction',''),category=SKIN:GetVariable(id..'Category'),
            favorite=SKIN:GetVariable(id..'Favorite')=='1'}
        local saved=preferences[app.key]
        if saved then
            app.favorite,app.category,app.hidden,app.rank=saved.favorite,saved.category,saved.hidden,saved.rank
        end
        apps[#apps+1]=app; byId[id]=app
    end
    local favorites=favoriteApps()
    for i=favoriteLimit+1,#favorites do favorites[i].favorite=false end
    open=SKIN:GetVariable('AppsOpenCategory','')
    if not validCategory(open) then open='' end
    for _,category in ipairs(categories) do pages[category]=tonumber(SKIN:GetVariable('AppsPage'..category,'1')) or 1 end
    page=pages[open] or 1
    Render()
    local warnings=tonumber(SKIN:GetVariable('AppScanWarnings','0')) or 0
    if #apps==0 then SetHint('Add shortcuts to Desktop / Apps, then click REFRESH.')
    elseif warnings>0 then SetHint('Refreshed '..#apps..' apps; '..warnings..' icons use a fallback. All apps can still launch.') end
    SKIN:Bang('!CommandMeasure','MeasureLayout','Apply()',SKIN:GetVariable('ROOTCONFIG','SlateHUD')..'\\System')
end
function Toggle(category)
    if not validCategory(category) then return end
    savePage(); search=''; showingHidden=false
    open=open==category and '' or category
    page=pages[open] or 1
    SKIN:Bang('!WriteKeyValue','Variables','AppsOpenCategory',open,SKIN:GetVariable('CURRENTPATH')..'View.inc')
    Render()
end
function ChangePage(delta)
    local nextPage=math.max(1,math.min(page+delta,pageCount))
    if nextPage==page then return end
    page=nextPage; savePage(); Render()
end
function EditSearch()
    option('MeasureSearch','DefaultValue',search)
    SKIN:Bang('!CommandMeasure','MeasureSearch','ExecuteBatch 1')
end
function Filter()
    savePage()
    search=SKIN:GetMeasure('MeasureSearchValue'):GetStringValue():sub(1,120):gsub('^%s+',''):gsub('%s+$',''):lower()
    page=1; Render()
end
function ClearSearch() search=''; page=showingHidden and 1 or pages[open] or 1; Render() end
function ToggleHidden()
    savePage()
    showingHidden = not showingHidden
    selected, search = nil, ''
    page = showingHidden and 1 or pages[open] or 1
    Render()
end
local function controlColor(meter)
    local index=tonumber(meter:match('^MeterCategory(%d+)$'))
    if index and categories[index]==open then return SKIN:GetVariable('ColorAccent') end
    if meter=='MeterFooter' then return SKIN:GetVariable('ColorMuted') end
    if meter=='MeterPrev' and page<=1 or meter=='MeterNext' and page>=pageCount then return SKIN:GetVariable('ColorMuted') end
    return SKIN:GetVariable('ColorSecondary')
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
local function stopHoverAnim()
    if hoverStep > 0 then
        hoverStep = 0
        SKIN:Bang('!CommandMeasure', 'MeasureHoverAnim', 'Stop 1')
    end
end
local function clearHighlights()
    stopHoverAnim()
    if hoveredApp then
        option(hoveredApp..'Hit','SolidColor','0,0,0,1')
        option(hoveredApp..'Label','FontColor',SKIN:GetVariable('ColorSecondary'))
        SKIN:Bang('!UpdateMeterGroup',hoveredApp)
        hoveredApp=nil
    end
    if hoveredControl then
        option(hoveredControl,'FontColor',controlColor(hoveredControl))
        SKIN:Bang('!UpdateMeter',hoveredControl)
        hoveredControl=nil
    end
end
function ResetHover()
    clearHighlights(); SetHint(defaultHint())
end
function AnimStep()
    if not hoveredApp or hoverStep <= 0 then stopHoverAnim(); return end
    hoverStep = hoverStep + 1
    local alpha = math.min(20, hoverStep * 4)
    option(hoveredApp..'Hit','SolidColor',tint(alpha))
    SKIN:Bang('!UpdateMeter',hoveredApp..'Hit'); SKIN:Bang('!Redraw')
    if alpha >= 20 then hoverStep = 0 end
end
function Hover(id)
    local app=byId[id]
    if not app or hoveredApp==id then return end
    clearHighlights(); hoveredApp=id
    local animate = canAnimate()
    if animate then hoverStep = 1 end
    option(id..'Hit','SolidColor',tint(animate and 4 or 20))
    option(id..'Label','FontColor',SKIN:GetVariable('ColorAccent'))
    SKIN:Bang('!UpdateMeterGroup',id)
    SetHint(app.name..' | '..app.category..(app.favorite and ' | Pinned' or ''))
    if animate then
        SKIN:Bang('!CommandMeasure','MeasureHoverAnim','Stop 1')
        SKIN:Bang('!CommandMeasure','MeasureHoverAnim','Execute 1')
    end
end
function Leave(id)
    -- A delayed leave from an older tile must not clear the current hover.
    if hoveredApp==id then ResetHover() end
end
function HoverControl(meter)
    if hoveredControl==meter then return end
    local index=tonumber(meter:match('^MeterCategory(%d+)$'))
    local category=index and categories[index]
    local hints={MeterSearch='Type an app name and press Enter. Right-click to clear.',
        MeterClearSearch='Clear search and return to your category.',
        MeterRescan=scanning and 'Refreshing shortcuts and icons...' or 'Refresh shortcuts and app icons.',
        MeterFooter='Open the folder containing your app shortcuts.',
        MeterPrev='Previous page | Scroll up',MeterNext='Next page | Scroll down'}
    local hint=category and (category..' | Unpinned apps; favorites are shown above') or hints[meter]
    if not hint then return end
    clearHighlights(); hoveredControl=meter
    option(meter,'FontColor',SKIN:GetVariable('ColorAccent')); SKIN:Bang('!UpdateMeter',meter)
    SetHint(hint)
end
function LeaveControl(meter)
    if hoveredControl==meter then ResetHover() end
end
local ctxMenu
local function contextMenu()
    if not ctxMenu then ctxMenu=dofile(SKIN:GetVariable('@')..'ContextMenu.lua') end
    return ctxMenu
end
local function menuAction(call)
    return '[!CommandMeasure MeasureApps "'..call..'"]'
end
function SuiteMenu()
    selected=nil
    contextMenu().openSuite(SKIN,{
        {showingHidden and 'Show visible apps' or 'Show hidden apps',menuAction('ToggleHidden()')}
    })
end
function OpenMenu(id)
    local app=byId[id]
    if not app then return end
    selected=app
    local items={
        {showingHidden and 'Show visible apps' or 'Show hidden apps',menuAction('ToggleHidden()')},
        {'-','[]'}
    }
    if app.hidden then
        items[#items+1]={'Restore app',menuAction('ToggleAppHidden()')}
        contextMenu().openCustom(SKIN,items)
        return
    end
    items[#items+1]={app.favorite and 'Unpin from favorites' or 'Pin to favorites',menuAction('ToggleFavorite()')}
    items[#items+1]={'Open shortcut location',menuAction('OpenShortcutLocation()')}
    for _,category in ipairs(categories) do
        items[#items+1]={(app.category==category and '* ' or 'Move to ')..category,menuAction("MoveTo('"..category.."')")}
    end
    if app.secondary~='' then
        items[#items+1]={'Open Personal profile',menuAction('LaunchSecondary()')}
    end
    items[#items+1]={'Hide app',menuAction('ToggleAppHidden()')}
    local favorites = favoriteApps()
    for i,item in ipairs(favorites) do
        if item==app then
            if i>1 then items[#items+1]={'Move favorite left',menuAction('MoveFavorite(-1)')} end
            if i<#favorites then items[#items+1]={'Move favorite right',menuAction('MoveFavorite(1)')} end
        end
    end
    contextMenu().openCustom(SKIN,items)
end
function ToggleFavorite()
    local app=selected
    if not app or app.hidden then return end
    if not app.favorite and #favoriteApps()>=favoriteLimit then SetHint('All eight favorite slots are full. Unpin an app first.'); return end
    if savePreference(app,not app.favorite,app.category) then
        Render(); savePage(); SetHint(app.label..(app.favorite and ' pinned to favorites.' or ' unpinned.'))
    end
end
function ToggleAppHidden()
    local app=selected
    if not app then return end
    local hidden = not app.hidden
    local unpin = not hidden and app.favorite and #favoriteApps() >= favoriteLimit
    if savePreference(app,app.favorite and not unpin,app.category,hidden) then
        Render(); savePage()
        if hidden then SetHint(app.label..' hidden. Right-click the card to show hidden apps.')
        elseif unpin then SetHint(app.label..' restored. Favorites are full, so it is unpinned.')
        else SetHint(app.label..' restored.') end
    end
end
function MoveFavorite(delta)
    if delta~=-1 and delta~=1 then return end
    local favorites = favoriteApps()
    local index
    for i,app in ipairs(favorites) do if app==selected then index=i; break end end
    if not index or not favorites[index+delta] then return end
    favorites[index], favorites[index+delta] = favorites[index+delta], favorites[index]
    local changes = {}
    for i,app in ipairs(favorites) do changes[app] = preference(true,app.category,false,i) end
    if savePreferences(changes) then Render(); SetHint(selected.label..' moved.') end
end
function MoveTo(category)
    if not selected or selected.hidden or not validCategory(category) then return end
    if savePreference(selected,selected.favorite,category) then Render(); savePage(); SetHint(selected.label..' moved to '..category..'.') end
end
function OpenShortcutLocation()
    if selected and selected.path~='' and not selected.path:find('[%[%]#"\r\n]') then
        SKIN:Bang('["explorer.exe" /select,"'..selected.path..'"]')
    end
end
function LaunchSecondary(id)
    local app=id and byId[id] or selected
    if app and app.secondary~='' then SKIN:Bang(app.secondary) end
end
function OpenFolder()
    local path=SKIN:GetVariable('AppShortcutFolder','')
    if path~='' and not path:find('[%[%]#"\r\n]') then SKIN:Bang('["'..path..'"]') end
end
function Scan()
    if scanning then return end
    scanning=true
    option('MeterRescan','Text','SCANNING'); SetHint('Refreshing shortcuts and app icons...')
    SKIN:Bang('!UpdateMeter','MeterRescan'); SKIN:Bang('!Redraw')
    SKIN:Bang('!CommandMeasure','MeasureScanApps','Run')
end
function FinishScan()
    scanning=false
    local output=SKIN:GetMeasure('MeasureScanApps'):GetStringValue()
    if output:find('APPS:PUBLISHED',1,true) then SKIN:Bang('!Refresh'); return end
    option('MeterRescan','Text','RETRY')
    option('MeterRescan','ToolTipText','Refresh failed. Existing apps are retained. '..display(output))
    SetHint('Refresh failed. Existing apps are retained. Click RETRY.')
    SKIN:Bang('!UpdateMeter','MeterRescan'); SKIN:Bang('!Redraw')
end
function Update() return 0 end
