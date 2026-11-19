-- File I/O and persistence helpers for GameHub (library, icons, status, preferences, favorites, recents).
local Data = {}

function Data.normalized(path)
    return tostring(path or ''):gsub('/', '\\'):lower()
end

function Data.legacyId(path)
    local app = path:match('^steam://rungameid/(%d+)$')
    return app and ('steam:' .. app) or ('legacy:' .. Data.normalized(path))
end

function Data.readLibrary(path)
    local entries, games, paths, libraryRevision = {}, {}, {}, 'legacy'
    local file = io.open(path, 'r')
    if not file then return entries, games, paths, libraryRevision end
    local varGames, varPlatforms, varUtilities = {}, {}, {}
    local function ensureIndexed(tbl, idx)
        local n = tonumber(idx)
        if not tbl[n] then tbl[n] = { aliases = {} } end
        return tbl[n]
    end
    local entry
    local function registerEntry(item)
        if item.game and item.path then
            item.catalog = item.id ~= nil
            item.id = item.id or Data.legacyId(item.path)
            if item.available == nil then item.available = true end
            if not games[item.id] or item.available then games[item.id] = item end
            for _, alias in ipairs(item.aliases) do paths[Data.normalized(alias)] = item end
        end
        entries[#entries + 1] = item
        item.index = #entries
    end
    local function appendLegacy()
        if entry and entry.name and entry.y then
            local catKey = entry.name:match('^MeterCat(.+)$')
            if catKey then
                entry.isCategoryHeader = true
                entry.category = catKey
            else
                local itemCat = entry.name:match('^Meter(%a+)%d+$')
                if itemCat then entry.category = itemCat end
            end
            entry.legacyMeter = true
            registerEntry(entry)
        end
    end
    local catNormalize = { RPG='RPG', ACTION='Action', STRATEGY='Strategy', OTHER='Other' }
    local inVariables = false
    for line in file:lines() do
        line = line:gsub('^\239\187\191', ''):gsub('\r$', '')
        local revision = line:match('^GameLibraryRevision=([a-f0-9]+)$')
        if revision and #revision == 32 then libraryRevision = revision end
        local section = line:match('^%[([^%]]+)%]%s*$')
        if section then
            appendLegacy()
            entry = nil
            inVariables = (section == 'Variables')
            if not inVariables then
                entry = { name=section, aliases={}, game=section:match('^MeterRPG%d+$') or
                    section:match('^MeterAction%d+$') or section:match('^MeterStrategy%d+$') or section:match('^MeterOther%d+$') }
            end
        elseif entry then
            local key, value = line:match('^([^=]+)=(.*)$')
            if key == 'Y' then entry.y = tonumber(value)
            elseif key == 'X' then entry.x = tonumber(value)
            elseif key == 'Text' then entry.title = value:gsub('^%[\\x25B8%]%s*', '')
            elseif key == 'GameId' then entry.id = value
            elseif key == 'GamePath' then entry.path = value
            elseif key == 'GameFolder' then entry.folder = value
            elseif key == 'GameAvailable' then entry.available = value == '1'
            elseif key == 'GameConfidence' then entry.confidence = value
            elseif key == '; GameAlias' then entry.aliases[#entry.aliases + 1] = value
            elseif key == 'LeftMouseUpAction' and value ~= '' then
                entry.action = value; entry.path = entry.path or value:match('^%["(.*)"%]$')
            end
        elseif inVariables then
            local gIdx, gField, gVal = line:match('^Game(%d+)(%a+)=(.*)$')
            if gIdx then
                local rec = ensureIndexed(varGames, gIdx)
                rec.game = true
                if gField == 'Category' then rec.category = catNormalize[gVal:upper()] or 'Other'
                elseif gField == 'Title' then rec.title = gVal
                elseif gField == 'GameId' then rec.id = gVal
                elseif gField == 'GamePath' then rec.path = gVal
                elseif gField == 'GameFolder' then rec.folder = gVal
                elseif gField == 'GameAvailable' then rec.available = gVal == '1'
                elseif gField == 'GameConfidence' then rec.confidence = gVal
                end
            else
                local aIdx, aVal = line:match('^; Game(%d+)GameAlias=(.*)$')
                if aIdx then
                    local rec = ensureIndexed(varGames, aIdx)
                    rec.aliases[#rec.aliases + 1] = aVal
                else
                    local pIdx, pField, pVal = line:match('^Platform(%d+)(%a+)=(.*)$')
                    if pIdx then
                        local rec = ensureIndexed(varPlatforms, pIdx)
                        rec.category = 'Platforms'
                        if pField == 'Title' then rec.title = pVal
                        elseif pField == 'Action' and pVal ~= '' then
                            rec.action = pVal; rec.path = pVal:match('^%["(.*)"%]$')
                        end
                    else
                        local uIdx, uField, uVal = line:match('^Utility(%d+)(%a+)=(.*)$')
                        if uIdx then
                            local rec = ensureIndexed(varUtilities, uIdx)
                            rec.category = 'Utilities'
                            if uField == 'Title' then rec.title = uVal
                            elseif uField == 'Action' and uVal ~= '' then
                                rec.action = uVal; rec.path = uVal:match('^%["(.*)"%]$')
                            end
                        end
                    end
                end
            end
        end
    end
    appendLegacy(); file:close()
    local function orderedKeys(tbl)
        local keys = {}
        for k in pairs(tbl) do keys[#keys + 1] = k end
        table.sort(keys)
        return keys
    end
    for _, k in ipairs(orderedKeys(varGames)) do
        local rec = varGames[k]
        if rec.title and rec.path then
            rec.name = 'Game' .. k
            rec.category = rec.category or 'Other'
            registerEntry(rec)
        end
    end
    for _, k in ipairs(orderedKeys(varPlatforms)) do
        local rec = varPlatforms[k]
        if rec.title and rec.action then
            rec.name = 'Platform' .. k
            registerEntry(rec)
        end
    end
    for _, k in ipairs(orderedKeys(varUtilities)) do
        local rec = varUtilities[k]
        if rec.title and rec.action then
            rec.name = 'Utility' .. k
            registerEntry(rec)
        end
    end
    for _, item in ipairs(entries) do
        if item.game and item.path then paths[Data.normalized(item.path)] = item end
    end
    return entries, games, paths, libraryRevision
end

function Data.readStatus(path)
    local status = {}
    local file = io.open(path, 'r')
    if file then
        for line in file:lines() do
            local key, value = line:gsub('\r$', ''):match('^([^=]+)=(.*)$')
            if key then status[key] = value end
        end
        file:close()
    end
    return status
end

function Data.readIcons(path)
    local iconPaths = {}
    local icons = io.open(path, 'r')
    if icons then
        for line in icons:lines() do
            local key, value = line:gsub('\r$', ''):match('^(GameIcon[^=]+)=(.*)$')
            if key then iconPaths[key] = value end
        end
        icons:close()
    end
    return iconPaths
end

function Data.readPreferences(store, path, validCategory)
    local prefs = {}
    for line in (store.recover(path) or ''):gmatch('[^\r\n]+') do
        local id, hidden, category = line:match('^([^\t]+)\t([01])\t(%a*)$')
        if id and (category == '' or validCategory(category)) then
            prefs[id] = {hidden=hidden == '1', category=category ~= '' and category or nil}
        end
    end
    return prefs
end

function Data.savePreferences(store, path, prefs)
    local lines = {}
    for key, value in pairs(prefs) do
        lines[#lines + 1] = table.concat({key, value.hidden and '1' or '0', value.category or ''}, '\t')
    end
    table.sort(lines)
    return store.write(path, table.concat(lines, '\n') .. '\n')
end

function Data.readFavorites(store, path, limit, games, paths)
    local favorites, seen, migration = {}, {}, false
    for line in (store.recover(path) or ''):gmatch('[^\r\n]+') do
        line = line:gsub('^\239\187\191', '')
        if line ~= '' and line:sub(1, 1) ~= '#' and #favorites < limit then
            local id, title, itemPath = line:match('^([^\t]+)\t([^\t]*)\t(.*)$')
            if not id then
                itemPath, title = line, line:match('([^\\/]+)$') or line
                id, migration = Data.legacyId(line), true
            end
            local entry = games[id] or paths[Data.normalized(itemPath)]
            if entry then
                if id ~= entry.id or itemPath ~= entry.path or title ~= entry.title then migration = true end
                id, title, itemPath = entry.id, entry.title, entry.path
            end
            if not seen[id] then favorites[#favorites + 1] = {id=id, title=title, path=itemPath}; seen[id] = true end
        end
    end
    return favorites, migration
end

function Data.saveFavorites(store, path, nextFavorites)
    local lines = { '# GameHub favorites v2: ID, title, previous path (tab separated)' }
    for _, favorite in ipairs(nextFavorites) do
        lines[#lines + 1] = favorite.id .. '\t' .. favorite.title:gsub('[\r\n\t]', ' ') .. '\t' .. favorite.path
    end
    return store.write(path, table.concat(lines, '\n') .. '\n')
end

function Data.readView(store, path)
    local openCategory, pages = nil, {}
    for line in (store.recover(path) or ''):gmatch('[^\r\n]+') do
        local key, value = line:match('^([^=]+)=(.*)$')
        if key == 'OpenCategory' then openCategory = value
        elseif key and key:match('^Page') then pages[key:sub(5)] = tonumber(value) or 1 end
    end
    return openCategory, pages
end

function Data.saveView(store, path, openCategory, pages)
    local lines = {'[View]', 'OpenCategory=' .. (openCategory or '')}
    for key, page in pairs(pages) do lines[#lines + 1] = 'Page' .. key .. '=' .. page end
    return store.write(path, table.concat(lines, '\n') .. '\n')
end

function Data.readRecents(store, path)
    local recentIds = {}
    for id in (store.recover(path) or ''):gmatch('[^\r\n]+') do
        if #recentIds < 4 then recentIds[#recentIds + 1] = id end
    end
    return recentIds
end

function Data.rememberRecent(store, path, recentIds, id)
    local nextIds = {id}
    for _, old in ipairs(recentIds) do if old ~= id and #nextIds < 4 then nextIds[#nextIds + 1] = old end end
    if store.write(path, table.concat(nextIds, '\n') .. '\n') then return nextIds end
    return recentIds
end

return Data
