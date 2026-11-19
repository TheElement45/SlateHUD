-- Persistent identities, removable offline favorites, scan feedback, and Notes docking.
local entries, games, paths, favorites = {}, {}, {}, {}
local ready, lastDock, scanning, launching = false, nil, false, false
local favoriteFile, statusFile, notesConfig, baseHeight, migration
local status, limit = {}, 4
local groups, pages, pageNumber, pageCount = {}, {}, 1, 1
local openCategory, tiles, hovered, visibleCategories = nil, {}, nil, {}
local hoverStep = 0
local layout, viewFile, layoutSignature
local search, recentIds, recentFile, store, data = '', {}, nil, nil, nil
local pendingLaunch
local iconPaths = {}
local libraryRevision, libraryPath, iconPath = 'legacy', nil, nil
local sourceEntries = {}
local gamePreferences, gamePreferencesFile, menuSelection = {}, nil, nil
local showingHidden = false
local categories = {'RPG', 'Action', 'Strategy', 'Other'}
local categoryLabels = {Platforms='Platforms', RPG='RPG & Adventure', Action='Action & Shooters',
    Strategy='Strategy & Simulation', Other='Other Games', Utilities='Utilities'}

local function isHidden(id)
    return gamePreferences[id] and gamePreferences[id].hidden
end
local function validCategory(category)
    for _, value in ipairs(categories) do if value == category then return true end end
    return false
end
local function scale()
    local value = SKIN:GetVariable('UiScale','1')
    return tonumber(value) or (SKIN.ParseFormula and SKIN:ParseFormula(SKIN:ReplaceVariables(value))) or 1
end
local function num(name, default)
    local raw = SKIN:GetVariable(name, tostring(default))
    return tonumber(raw) or (SKIN.ParseFormula and SKIN:ParseFormula(SKIN:ReplaceVariables(raw))) or default
end
local function cardShift()
    local tight = num('BlurTightFrame', 0) == 1
    return num('CardShiftX', tight and -8 or 0), num('CardShiftY', tight and -16 or 0)
end

local function option(meter, key, value)
    if (key == 'X' or key == 'Y' or key == 'W' or key == 'H') and tonumber(value) then value = tonumber(value) * scale() end
    if key == 'Padding' then value = tostring(value):gsub('%d+',function(n) return tostring(tonumber(n)*scale()) end) end
    SKIN:Bang('!SetOption', meter, key, tostring(value))
end
local function display(text)
    return tostring(text or ''):gsub('[\r\n\t]', ' '):gsub('#', '＃'):gsub('%[', '［'):gsub('%]', '］')
end

function SetHint(text)
    option('MeterHint', 'Text', display(text))
    SKIN:Bang('!UpdateMeter', 'MeterHint'); SKIN:Bang('!Redraw')
end
function ClearHint()
    if showingHidden then SetHint('Right-click a game to restore it.')
    else SetHint('Right-click a game for options (' .. #favorites .. '/' .. limit .. ' pinned)') end
end
local function entryHint(entry)
    SetHint(entry.title .. (entry.available == false and ' - unavailable; scan to retry' or
        (entry.confidence == 'uncertain' and ' - check launch target in Overrides.txt' or '')))
end
function Hint(index)
    local entry = entries[tonumber(index)]
    if entry then entryHint(entry) end
end
function HintFavorite(slot)
    local favorite = favorites[tonumber(slot)]
    if not favorite then return end
    local entry = games[favorite.id]
    if entry and entry.available then entryHint(entry)
    else SetHint(favorite.title .. ' - unavailable. Right-click to unpin.') end
end

local function hideLegacyMeters()
    for _, entry in ipairs(sourceEntries) do
        SKIN:Bang('!HideMeter', entry.name); option(entry.name, 'Y', 88)
        option(entry.name, 'H', 1); option(entry.name, 'W', 1)
    end
end

local function readLibrary(path)
    entries, games, paths, libraryRevision = data.readLibrary(path)
    sourceEntries = {}
    for _, entry in ipairs(entries) do
        if entry.legacyMeter then sourceEntries[#sourceEntries + 1] = entry end
    end
    hideLegacyMeters()
end

local function buildGroups()
    groups = {}
    local byKey = {}
    local function groupFor(key)
        if not byKey[key] then
            local group = {key=key, items={}}
            byKey[key] = group
            groups[#groups + 1] = group
        end
        return byKey[key]
    end
    for _, entry in ipairs(entries) do
        if entry.isCategoryHeader and entry.category then
            groupFor(entry.category).title = entry.title
        end
    end
    for _, entry in ipairs(entries) do
        if not entry.isCategoryHeader then
            local key = entry.category or entry.name:match('^Meter(%a+)%d+$')
            if key then
                local saved = gamePreferences[entry.id]
                local group = groupFor(saved and saved.category or key)
                entry.categoryTitle = group.title or categoryLabels[group.key] or group.key
                group.items[#group.items + 1] = entry
            end
        end
    end
end

local function layoutLimit()
    local maximum = tonumber(SKIN:GetVariable('GameMaxCardH', '480')) or 480
    local workHeight = tonumber(SKIN:GetVariable('LayoutWorkHeight')) or tonumber(SKIN:GetVariable('WORKAREAHEIGHT'))
    if workHeight then
        local bottom = (tonumber(SKIN:GetVariable('LayoutWorkY')) or tonumber(SKIN:GetVariable('WORKAREAY')) or 0) + workHeight
        local reserve = tonumber(SKIN:GetVariable('GameNotesReserve', '260')) or 260
        local gap = tonumber(SKIN:GetVariable('NotesGap', '24')) or 24
        local frameW = num('CardFrameW', 16)
        local frameH = num('CardFrameH', 24)
        local bottomPad = num('BlurTightFrame', 0) == 1 and math.floor(frameW / 2) or num('ActiveFrameH', frameH)
        maximum = math.min(maximum, (bottom - SKIN:GetY()) / scale() - reserve - gap - bottomPad)
    end
    return math.max(220, math.floor(maximum))
end

local function readStatus()
    status = data.readStatus(statusFile)
    local summary = status.Summary or 'Game library'
    summary = summary:gsub(' %- updated .*$','')
    if status.State == 'Running' then summary = 'Previous scan interrupted - scan to retry' end
    option('MeterSubtitle', 'Text', display(summary))
    local warn = status.State and status.State ~= 'Success' and not summary:match('^%d+ games?$')
    option('MeterSubtitle', 'FontColor', warn and '#ColorWarn#' or '#ColorSecondary#')
end
function ScanHint()
    local text = status.Detail
    if not text or text == '' then text = 'Scan and update installed games' end
    if status.LastSuccess and status.LastSuccess ~= '' then text = text .. ' | Last successful scan: ' .. status.LastSuccess end
    SetHint(text)
end

local function saveFavorites(nextFavorites)
    local ok, stage = data.saveFavorites(store, favoriteFile, nextFavorites)
    if not ok then
        if stage == 'open' then SetHint('Could not save favorites. Check folder permissions.')
        elseif stage == 'replace' then SetHint('Could not save favorites. Previous pins retained.')
        else SetHint('Could not save favorites. Please try again.') end
        return false
    end
    return true
end

local function readIcons()
    iconPaths = data.readIcons(iconPath)
end

function Initialize()
    local folder = SKIN:GetVariable('CURRENTPATH')
    local resourceDir = SKIN:GetVariable('@', folder .. '..\\@Resources\\')
    store = dofile(resourceDir .. 'FileStore.lua')
    data = dofile(resourceDir .. 'GameHubData.lua')
    iconPath = resourceDir .. 'Cache/GameIcons.inc'
    libraryPath = folder .. 'GameList.inc'
    readIcons()
    favoriteFile = folder .. 'Favorites.txt'
    viewFile = folder .. 'View.inc'
    recentFile = folder .. 'Recent.txt'
    gamePreferencesFile = folder .. 'Preferences.txt'
    gamePreferences = data.readPreferences(store, gamePreferencesFile, validCategory)
    recentIds = data.readRecents(store, recentFile)
    layout = dofile(SKIN:GetVariable('@', folder .. '..\\@Resources\\') .. 'GameHubLayout.lua')
    statusFile = SKIN:GetVariable('GameStatusFile', folder .. '..\\@Resources\\Cache\\game_scan_status.txt')
    notesConfig = SKIN:GetVariable('ROOTCONFIG', 'SlateHUD') .. '\\Notes'
    baseHeight = tonumber(SKIN:GetVariable('GameCardH')) or 324
    readLibrary(libraryPath)
    buildGroups()
    openCategory, pages = data.readView(store, viewFile)
    favorites, migration = data.readFavorites(store, favoriteFile, limit, games, paths)
end

function DockNotes()
    if not ready then return end
    local x, y = SKIN:GetX(), SKIN:GetY()
    local height = tonumber(SKIN:GetVariable('GameCardH')) or baseHeight
    local width = tonumber(SKIN:GetVariable('GameCardW')) or tonumber(SKIN:GetVariable('WideCardW')) or 320
    local notesWidth = tonumber(SKIN:GetVariable('StatCardW')) or 222
    local gap = tonumber(SKIN:GetVariable('NotesGap')) or 24
    SKIN:Bang('!Move', x + (width - notesWidth) * scale(), y + (height + gap) * scale(), notesConfig)
    lastDock = { x, y, height }
end
local function saveView()
    if not data.saveView(store, viewFile, openCategory, pages) then SetHint('Could not save category layout.') end
end
local function iconKey(entry)
    return 'GameIcon' .. (entry.id or entry.title or ''):gsub('[^%w]','')
end
local function pinnedEntries()
    local result={}
    for slot,favorite in ipairs(favorites) do
        local entry=games[favorite.id]
        local tile={id=favorite.id,title=favorite.title,path=favorite.path,
            available=entry and entry.available or false,favoriteSlot=slot,game=true}
        if entry then for key,value in pairs(entry) do tile[key]=value end end
        if not isHidden(favorite.id) then result[#result+1]=tile end
    end
    return result
end
local function categoriesForView(pinned)
    local result={}
    if SKIN:GetVariable('GameShowRecent','0')=='1' then
        local recent={key='Recent',title='Recent',items={}}
        for _,id in ipairs(recentIds) do
            if games[id] and not isHidden(id) then recent.items[#recent.items+1]=games[id] end
        end
        result[#result+1]=recent
    end
    local ordered={}
    for _,key in ipairs({'RPG','Action','Strategy','Other','Platforms','Utilities'}) do
        local found=nil
        for _,group in ipairs(groups) do if group.key==key then found=group; break end end
        if found or validCategory(key) then ordered[#ordered+1]=found or {key=key,items={}} end
    end
    for _,group in ipairs(ordered) do
        local visible={key=group.key,title=categoryLabels[group.key] or group.title or group.key,items={}}
        for _,entry in ipairs(group.items) do
            if not isHidden(entry.id) and (not entry.game or not pinned[entry.id]) then visible.items[#visible.items+1]=entry end
        end
        result[#result+1]=visible
    end
    return result
end
local function tint(alpha)
    return (SKIN:GetVariable('ColorAccent','235,170,0'):match('(%d+,%s*%d+,%s*%d+)') or '235,170,0') .. ',' .. alpha
end
local function tileColor(entry) return entry.available==false and '#ColorMuted#' or '#ColorSecondary#' end
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
local function resetHighlight()
    stopHoverAnim()
    if hovered then
        local name='GameTile' .. hovered
        option(name .. 'Hit','SolidColor','0,0,0,1')
        if tiles[hovered] then option(name .. 'Label','FontColor',tileColor(tiles[hovered])) end
        SKIN:Bang('!UpdateMeterGroup',name); hovered=nil
    end
end
function AnimStep()
    if not hovered or not tiles[hovered] or hoverStep <= 0 then stopHoverAnim(); return end
    hoverStep = hoverStep + 1
    local name = 'GameTile' .. hovered .. 'Hit'
    local alpha = math.min(20, hoverStep * 4)
    option(name,'SolidColor',tint(alpha))
    SKIN:Bang('!UpdateMeter',name); SKIN:Bang('!Redraw')
    if alpha >= 20 then hoverStep = 0 end
end
function HoverTile(slot)
    slot=tonumber(slot)
    local entry=tiles[slot]
    if not entry or hovered==slot then return end
    resetHighlight(); hovered=slot
    local animate = canAnimate()
    if animate then hoverStep = 1 end
    option('GameTile' .. slot .. 'Hit','SolidColor',tint(animate and 4 or 20))
    option('GameTile' .. slot .. 'Label','FontColor','#ColorAccent#')
    SKIN:Bang('!UpdateMeterGroup','GameTile' .. slot); entryHint(entry)
    if animate then
        SKIN:Bang('!CommandMeasure','MeasureHoverAnim','Stop 1')
        SKIN:Bang('!CommandMeasure','MeasureHoverAnim','Execute 1')
    end
end
function LeaveTile(slot)
    if hovered==tonumber(slot) then resetHighlight(); ClearHint() end
end
function ResetHover() resetHighlight(); ClearHint() end
function LaunchTile(slot)
    local entry=tiles[tonumber(slot)]
    if not entry or isHidden(entry.id) then return end
    if entry.favoriteSlot then LaunchFavorite(entry.favoriteSlot)
    elseif entry.game then Launch(entry.index)
    elseif entry.action then SKIN:Bang(entry.action) end
end
local function positionTile(slot,entry,column,y,rowHeight)
    local name='GameTile' .. slot
    local sx, sy = cardShift()
    local x=24+column*72+sx
    local ty=y+sy
    local small=rowHeight<72
    tiles[slot]=entry
    option(name .. 'Hit','X',x); option(name .. 'Hit','Y',ty); option(name .. 'Hit','H',rowHeight-2)
    option(name .. 'Icon','X',x+19); option(name .. 'Icon','Y',ty+3)
    option(name .. 'Initial','X',x+35); option(name .. 'Initial','Y',ty+3)
    option(name .. 'Label','X',x+35); option(name .. 'Label','Y',ty+(small and 33 or 40))
    option(name .. 'Label','H',16)
    option(name .. 'Label','FontColor',tileColor(entry)); option(name .. 'Label','Text',display(entry.title))
    option(name .. 'Initial','Text',(entry.title:match('[A-Za-z0-9][A-Za-z0-9]?') or '?'):upper())
    local icon=iconPaths[iconKey(entry)] or ''
    option(name .. 'Icon','ImageName',icon); option(name .. 'Icon','ImageAlpha',entry.available==false and 100 or 255)
    SKIN:Bang('!ShowMeterGroup',name)
    SKIN:Bang(icon=='' and '!HideMeter' or '!ShowMeter',name .. 'Icon')
    SKIN:Bang(icon=='' and '!ShowMeter' or '!HideMeter',name .. 'Initial')
end
local function render()
    resetHighlight(); tiles={}
    local maximum=layoutLimit()
    local pinned={}
    for _,favorite in ipairs(favorites) do pinned[favorite.id]=true end
    local favoriteItems=pinnedEntries()
    local categories=categoriesForView(pinned)
    if openCategory==nil then
        openCategory=categories[1] and categories[1].key or ''
        for _,group in ipairs(categories) do
            if #group.items>0 and (group.key=='Recent' or group.key=='RPG') then openCategory=group.key; break end
        end
    end
    local active,selected={},false
    for _,group in ipairs(categories) do if group.key==openCategory then active=group.items; selected=true end end
    if openCategory=='Favorites' then active=favoriteItems; selected=true end
    if showingHidden or search~='' then
        active={}; selected=true
        local seen={}
        for _,entry in ipairs(entries) do
            if entry.path and (not not isHidden(entry.id)) == showingHidden and not seen[entry.id or entry.name] and
                (entry.title .. ' ' .. (entry.categoryTitle or '')):lower():find(search:lower(),1,true) then
                active[#active+1]=entry; seen[entry.id or entry.name]=true
            end
        end
    end
    if showingHidden then categories, favoriteItems = {}, {} end
    local categoryKeys={}
    for _,group in ipairs(categories) do categoryKeys[#categoryKeys+1]=group.key end
    local plan=layout.plan{favorites=#favoriteItems,categories=#categories,categoryKeys=categoryKeys,count=#active,
        maximum=maximum,page=pageNumber,selected=selected}
    if plan.compact and #favoriteItems>0 then
        table.insert(categories,1,{key='Favorites',title='Favorites',items=favoriteItems})
    elseif openCategory=='Favorites' and search=='' and not showingHidden then
        openCategory=''; active={}; selected=false
        plan=layout.plan{favorites=#favoriteItems,categories=#categories,categoryKeys=categoryKeys,count=0,maximum=maximum,page=1}
    end
    pageNumber,pageCount=plan.page,plan.pages
    local sx, sy = cardShift()
    layoutSignature=maximum .. ':' .. scale() .. ':' .. sx .. ',' .. sy; visibleCategories=categories
    for slot=1,12 do
        local name='GameTile' .. slot
        SKIN:Bang('!HideMeterGroup',name)
        for _,part in ipairs({'Hit','Icon','Initial','Label'}) do option(name .. part,'Y',88+sy) end
        option(name .. 'Hit','SolidColor','0,0,0,1')
    end
    SKIN:Bang((plan.compact or showingHidden) and '!HideMeter' or '!ShowMeter','MeterFavoritesTitle')
    local hiddenPins = #favorites - #favoriteItems
    option('MeterFavoritesTitle','Text','FAVORITES  ' .. #favoriteItems .. ' / ' .. limit ..
        (hiddenPins > 0 and '  |  ' .. hiddenPins .. ' hidden' or ''))
    SKIN:Bang('!HideMeter','MeterEmptyFavorites')
    if not plan.compact and not showingHidden then
        if #favoriteItems==0 then SKIN:Bang('!ShowMeter','MeterEmptyFavorites') end
        for slot,entry in ipairs(favoriteItems) do positionTile(slot,entry,slot-1,108,72) end
    end
    for index=1,8 do
        local name='MeterCategory' .. index
        local group=categories[index]
        SKIN:Bang(group and '!ShowMeter' or '!HideMeter',name); option(name,'Y',88+sy)
        if group then
            option(name,'X',plan.categoryPositions[index].x+sx)
            option(name,'Y',plan.categoryPositions[index].y+sy)
            -- Padding contributes to the meter bounds; retain the 140px button width.
            option(name,'W',130)
            option(name,'H',plan.categoryStep-12)
            option(name,'Padding','5,4,5,4')
            option(name,'FontSize',7.5*scale())
            local current=search=='' and group.key==openCategory
            option(name,'Text',(current and '- ' or '+ ') .. group.title .. ' ' .. #group.items)
            option(name,'FontColor',current and '#ColorAccent#' or '#ColorSecondary#')
            option(name,'SolidColor',current and tint(18) or SKIN:GetVariable('ColorPill', '255,255,255,7'))
        end
    end
    SKIN:Bang('!HideMeter','MeterEmpty'); option('MeterEmpty','Y',88+sy)
    if #active==0 and selected then
        option('MeterEmpty','Y',plan.gridY+10+sy)
        option('MeterEmpty','Text',search~='' and 'No matching games. Try another name.' or
            (showingHidden and 'No hidden games.' or
                (openCategory=='Recent' and 'Launch a game here to add it to Recent.' or 'No unpinned games in this category.')))
        SKIN:Bang('!ShowMeter','MeterEmpty')
    else
        for index=plan.first,plan.last do
            local offset=index-plan.first
            positionTile(5+offset,active[index],offset%4,plan.gridY+math.floor(offset/4)*plan.rowHeight,plan.rowHeight)
        end
    end
    SKIN:Bang('!SetVariable','GameCardH',plan.height)
    option('MeterSubtitle','Y',plan.footerY+sy); option('MeterSubtitle','W',pageCount>1 and 158 or 288)
    option('MeterHint','Y',plan.hintY+sy); option('MeterHint','H',plan.compact and 16 or 28)
    for _,name in ipairs({'MeterPagePrev','MeterPageNumber','MeterPageNext'}) do
        option(name,'Y',plan.footerY+sy); SKIN:Bang(pageCount>1 and '!ShowMeter' or '!HideMeter',name)
    end
    option('MeterPageNumber','Text',pageNumber .. ' / ' .. pageCount)
    option('MeterPagePrev','FontColor',pageNumber>1 and '#ColorSecondary#' or '#ColorMuted#')
    option('MeterPageNext','FontColor',pageNumber<pageCount and '#ColorSecondary#' or '#ColorMuted#')
    readStatus()
    if showingHidden then option('MeterSubtitle','Text',#active .. ' hidden')
    elseif search~='' then option('MeterSubtitle','Text',#active .. (#active==1 and ' match' or ' matches')) end
    option('MeterSearch','Text',search=='' and '  Search games...' or '  ' .. display(search))
    SKIN:Bang(search=='' and '!HideMeter' or '!ShowMeter','MeterClearSearch')
    SKIN:Bang('!UpdateMeter','*'); SKIN:Bang('!Redraw'); ClearHint(); DockNotes()
end
local ctxMenu
local function contextMenu()
    if not ctxMenu then
        local folder = SKIN:GetVariable('CURRENTPATH') or ''
        ctxMenu = dofile(SKIN:GetVariable('@', folder .. '..\\@Resources\\') .. 'ContextMenu.lua')
    end
    return ctxMenu
end
local function menuAction(call)
    return '[!CommandMeasure MeasureGameHub "' .. call .. '"]'
end
local function hiddenItem()
    return {showingHidden and 'Show visible games' or 'Show hidden games', menuAction('ToggleHiddenGames()')}
end
function SuiteMenu()
    menuSelection = nil
    contextMenu().openSuite(SKIN, {hiddenItem()})
end
function ToggleHiddenGames()
    showingHidden = not showingHidden
    menuSelection, search = nil, ''
    pageNumber = showingHidden and 1 or pages[openCategory] or 1
    render()
end
function OpenTileMenu(slot)
    local entry = tiles[tonumber(slot)]
    if not entry or not entry.game then SuiteMenu(); return end
    menuSelection = entry
    local items = {
        hiddenItem(),
        {'-', '[]'}
    }
    if isHidden(entry.id) then
        items[#items + 1] = {'Restore game', menuAction('SetGameHidden(false)')}
    else
        local pinned = entry.favoriteSlot
        for _, favorite in ipairs(favorites) do if favorite.id == entry.id then pinned = true; break end end
        items[#items + 1] = {pinned and 'Unpin from favorites' or 'Pin to favorites', menuAction('PinSelectedGame()')}
        items[#items + 1] = {'Open installation folder', menuAction('OpenInstallation()')}
        items[#items + 1] = {'Hide game', menuAction('SetGameHidden(true)')}
        for _, category in ipairs(categories) do
            items[#items + 1] = {'Change category to ' .. categoryLabels[category], menuAction("SetGameCategory('" .. category .. "')")}
        end
        items[#items + 1] = {'Reset category', menuAction('SetGameCategory()')}
        local visibleRank, visibleTotal = nil, 0
        for _, favorite in ipairs(favorites) do
            if not isHidden(favorite.id) then
                visibleTotal = visibleTotal + 1
                if favorite.id == entry.id then visibleRank = visibleTotal end
            end
        end
        if visibleRank then
            if visibleRank > 1 then items[#items + 1] = {'Move favorite left', menuAction('MoveFavorite(-1)')} end
            if visibleRank < visibleTotal then items[#items + 1] = {'Move favorite right', menuAction('MoveFavorite(1)')} end
        end
    end
    contextMenu().openCustom(SKIN, items)
end
function MoveFavorite(delta)
    if delta ~= -1 and delta ~= 1 or not menuSelection then return end
    local visibleSlots, current = {}, nil
    for index, favorite in ipairs(favorites) do
        if not isHidden(favorite.id) then
            visibleSlots[#visibleSlots + 1] = index
            if favorite.id == menuSelection.id then current = #visibleSlots end
        end
    end
    local target = current and visibleSlots[current + delta]
    if not target then return end
    local source = visibleSlots[current]
    local nextFavorites = {}
    for index, favorite in ipairs(favorites) do nextFavorites[index] = favorite end
    nextFavorites[source], nextFavorites[target] = nextFavorites[target], nextFavorites[source]
    if saveFavorites(nextFavorites) then
        favorites = nextFavorites
        render()
        SetHint(menuSelection.title .. ' moved.')
    end
end
local function saveGamePreference(id,hidden,category)
    local previous = gamePreferences[id]
    gamePreferences[id] = (hidden or category) and {hidden=hidden,category=category} or nil
    if not data.savePreferences(store, gamePreferencesFile, gamePreferences) then
        gamePreferences[id] = previous
        SetHint('Could not save changes. Your previous settings are retained.')
        return
    end
    buildGroups()
    render()
    return true
end
function SetGameHidden(hidden)
    local entry = menuSelection
    if not entry or not games[entry.id] then SetHint('This game is unavailable. Scan to restore its catalog entry.'); return end
    local saved = gamePreferences[entry.id]
    if saveGamePreference(entry.id,hidden,saved and saved.category) then
        SetHint(hidden and 'Game hidden. Right-click the card to show hidden games.' or 'Game restored.')
    end
end
function SetGameCategory(category)
    local entry = menuSelection
    if not entry or not games[entry.id] or (category and not validCategory(category)) then return end
    if saveGamePreference(entry.id,isHidden(entry.id),category) then
        SetHint(category and ('Category set to '..categoryLabels[category]..'.') or 'Catalog category restored.')
    end
end
function PinSelectedGame()
    local entry = menuSelection
    if not entry or isHidden(entry.id) then return end
    if entry.favoriteSlot then RemoveFavorite(entry.favoriteSlot)
    else Toggle(entry.index) end
end
function OpenInstallation()
    local entry = menuSelection
    if not entry or not entry.catalog or not entry.folder or entry.folder=='' then
        SetHint('No installation folder is recorded for this game.')
        return
    end
    if launching then SetHint('Game action already in progress.'); return end
    launching, pendingLaunch = true, nil
    SKIN:Bang('!SetVariable','GameLaunchId',entry.id)
    SKIN:Bang('!SetVariable','GameLaunchRevision',libraryRevision)
    SKIN:Bang('!SetVariable','GameLaunchMode','-OpenFolder')
    SKIN:Bang('!UpdateMeasure','MeasureLaunch')
    SKIN:Bang('!CommandMeasure','MeasureLaunch','Run')
    SetHint('Opening installation folder...')
end
function EditSearch()
    SKIN:Bang('!SetOption','MeasureSearch','DefaultValue',search)
    SKIN:Bang('!CommandMeasure','MeasureSearch','ExecuteBatch 1')
end
function Filter()
    if not showingHidden and search=='' and openCategory then pages[openCategory]=pageNumber end
    search=SKIN:GetMeasure('MeasureSearchValue'):GetStringValue():sub(1,120):gsub('^%s+',''):gsub('%s+$','')
    pageNumber=1; render()
end
function ClearSearch() search=''; pageNumber=showingHidden and 1 or pages[openCategory] or 1; render() end
local function remember(id)
    recentIds = data.rememberRecent(store, recentFile, recentIds, id)
end
function CategoryHint(index)
    local group=visibleCategories[tonumber(index)]
    if group then SetHint(group.title .. ' | ' .. #group.items .. ' items | Click to ' ..
        (openCategory==group.key and 'collapse' or 'expand')) end
end
function ToggleCategory(index)
    local group=visibleCategories[tonumber(index)]
    if not group then return end
    if search=='' and openCategory then pages[openCategory]=pageNumber end
    search=''; openCategory=openCategory==group.key and '' or group.key
    pageNumber=pages[openCategory] or 1
    render(); saveView()
end
function ChangePage(delta)
    local nextPage=math.max(1,math.min(pageCount,pageNumber+(tonumber(delta) or 0)))
    if nextPage~=pageNumber then
        pageNumber=nextPage; render()
        if not showingHidden and search=='' and openCategory then pages[openCategory]=pageNumber; saveView() end
    end
end
function Setup()
    ready = true; pageNumber=pages[openCategory] or pageNumber; render()
    if migration then migration = not saveFavorites(favorites) end
end
function PlaceNotes()
    if not ready then return end
    local sx, sy = cardShift()
    if layoutSignature ~= layoutLimit() .. ':' .. scale() .. ':' .. sx .. ',' .. sy then render()
    else DockNotes() end
end
function RemoveFavorite(slot)
    slot = tonumber(slot)
    if not favorites[slot] then return end
    local nextFavorites = {}
    for index, favorite in ipairs(favorites) do if index ~= slot then nextFavorites[#nextFavorites + 1] = favorite end end
    if saveFavorites(nextFavorites) then favorites = nextFavorites; render() end
end
function Toggle(index)
    local entry = entries[tonumber(index)]
    if not entry or not entry.game or not entry.path then return end
    for slot, favorite in ipairs(favorites) do if favorite.id == entry.id then RemoveFavorite(slot); return end end
    if #favorites >= limit then SetHint('Four favorites maximum. Unpin one with right-click.'); return end
    local nextFavorites = {}
    for _, favorite in ipairs(favorites) do nextFavorites[#nextFavorites + 1] = favorite end
    nextFavorites[#nextFavorites + 1] = { id=entry.id, title=entry.title, path=entry.path }
    if saveFavorites(nextFavorites) then favorites = nextFavorites; render() end
end
function Launch(index)
    local entry = entries[tonumber(index)]
    if not entry or not entry.game or isHidden(entry.id) then return end
    if not entry.available then entryHint(entry); return end
    if launching then SetHint('Launch already in progress.'); return end
    if not entry.catalog then SKIN:Bang(entry.action); remember(entry.id); render(); return end -- Legacy includes.
    launching = true
    pendingLaunch = entry.id
    SKIN:Bang('!SetVariable', 'GameLaunchId', entry.id)
    SKIN:Bang('!SetVariable', 'GameLaunchRevision', libraryRevision)
    SKIN:Bang('!SetVariable', 'GameLaunchMode', '')
    SKIN:Bang('!UpdateMeasure', 'MeasureLaunch'); SKIN:Bang('!CommandMeasure', 'MeasureLaunch', 'Run')
    SetHint('Opening ' .. entry.title .. '...')
end
function LaunchFavorite(slot)
    local favorite = favorites[tonumber(slot)]
    local entry = favorite and games[favorite.id]
    if entry and entry.available then Launch(entry.index) else HintFavorite(slot) end
end
function FinishLaunch()
    launching = false
    local measure = SKIN:GetMeasure('MeasureLaunch')
    local output = measure and measure:GetStringValue() or ''
    if output:find('GAMEHUB:STALE', 1, true) then
        entries, games, paths, libraryRevision, menuSelection = {}, {}, {}, 'legacy', nil
        readLibrary(libraryPath)
        readIcons()
        buildGroups()
        render()
        SetHint('Library updated. Select the game again.')
    elseif output:find('GAMEHUB:FOLDER', 1, true) then
        SetHint('Installation folder opened.')
    elseif not output:find('GAMEHUB:LAUNCHED', 1, true) then
        SetHint(output:match('GAMEHUB:FAILED (.*)') or 'Could not launch game. Scan or check its override.')
    elseif pendingLaunch then
        remember(pendingLaunch); render()
    end
    pendingLaunch = nil
end
function BeginScan()
    if scanning then SetHint('Scan already in progress.'); return end
    scanning = true
    option('MeterBtnScan', 'Text', 'SCANNING...'); option('MeterSubtitle', 'Text', 'Scanning installed games...')
    SKIN:Bang('!UpdateMeter', '*'); SKIN:Bang('!Redraw'); SKIN:Bang('!CommandMeasure', 'MeasureScan', 'Run')
end
function FinishScan()
    scanning = false
    local measure = SKIN:GetMeasure('MeasureScan')
    local output = measure and measure:GetStringValue() or ''
    if output:find('GAMEHUB:PUBLISHED', 1, true) then SKIN:Bang('!Refresh'); return end
    option('MeterBtnScan', 'Text', 'SCAN')
    local message = output:match('GAMEHUB:FAILED (.*)') or
        (output:find('GAMEHUB:BUSY', 1, true) and 'Another scan is already running.' or 'Scan interrupted or could not start. Previous library retained.')
    option('MeterSubtitle', 'Text', 'Scan incomplete - library retained')
    SKIN:Bang('!UpdateMeter', '*'); SetHint(message)
end
function Update()
    if ready then
        local x, y = SKIN:GetX(), SKIN:GetY()
        local height = tonumber(SKIN:GetVariable('GameCardH')) or baseHeight
        local maximum = layoutLimit()
        local sx, sy = cardShift()
        if layoutSignature ~= maximum .. ':' .. scale() .. ':' .. sx .. ',' .. sy then render()
        elseif not lastDock or lastDock[1] ~= x or lastDock[2] ~= y or lastDock[3] ~= height then DockNotes() end
        -- RunCommand can fail to start without invoking FinishAction.
        if scanning or launching then
            local measure = SKIN:GetMeasure(scanning and 'MeasureScan' or 'MeasureLaunch')
            if measure and measure:GetValue() >= 100 then
                if scanning then FinishScan() else FinishLaunch() end
            end
        end
    end
    return 0
end
