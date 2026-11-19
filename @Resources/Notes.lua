-- Durable per-page edits and opt-in daily checkboxes. Daily resets preserve the
-- task text and undo history; old undo snapshots are normalized before restoring.
local store, data, ctxMenu, page, undo, ready, initFailed, checkedDay, retryAt, selected
local defaultHint = 'Right-click a task for options'
local fields = {'Note', 'Status', 'Daily', 'DailyDay'}
local function contextMenu()
    if not ctxMenu then ctxMenu = dofile(SKIN:GetVariable('@') .. 'ContextMenu.lua') end
    return ctxMenu
end
local function menuAction(call)
    return '[!CommandMeasure MeasureNotes "' .. call .. '"]'
end
local function display(text)
    return tostring(text or ''):gsub('[\r\n\t]', ' '):gsub('#', '＃'):gsub('%[', '［'):gsub('%]', '］')
end
local function cleanInput(text)
    return tostring(text or ''):gsub('[\r\n\t]', ' '):gsub('"', "'"):gsub('^%s+', ''):gsub('%s+$', '')
end
local function default(field)
    return (field == 'Status' or field == 'Daily') and '0' or ''
end
local function hint(text)
    SKIN:Bang('!SetOption', 'meterHint', 'Text', display(text))
    SKIN:Bang('!UpdateMeter', 'meterHint'); SKIN:Bang('!Redraw')
end
local function validRow(row)
    row = tonumber(row)
    return row and row == math.floor(row) and row >= 1 and row <= 5 and row or nil
end
local function day()
    local hour = tonumber(SKIN:GetVariable('DailyResetHour', '4')) or 4
    return data.day(math.max(0, math.min(23, math.floor(hour))))
end
local function apply(changes)
    for key, value in pairs(changes) do
        SKIN:Bang('!SetVariable', key, value)
        if key == 'PageTitle' then
            SKIN:Bang('!SetVariable', 'PageDisplayTitle', display(value))
        else
            local row = key:match('^Note([1-5])$')
            if row then SKIN:Bang('!SetVariable', 'NoteDisplay' .. row, display(value)) end
        end
    end
end
local function render()
    local total, done, daily = 0, 0, 0
    local title = display(SKIN:GetVariable('PageTitle', 'Page ' .. SKIN:GetVariable('CurrentPage', '1')))
    SKIN:Bang('!SetVariable', 'PageDisplayTitle', title)
    SKIN:Bang('!SetOption', 'meterTitle', 'Text', title)
    for row = 1, 5 do
        local text = SKIN:GetVariable('Note' .. row, '')
        local shown = display(text)
        local recurring = text ~= '' and SKIN:GetVariable('Daily' .. row, '0') == '1'
        SKIN:Bang('!SetVariable', 'NoteDisplay' .. row, shown)
        SKIN:Bang('!SetOption', 'meterText' .. row, 'Text', text == '' and '+ Add task' or shown)
        local width = recurring and '(152*#UiScale#)' or '(172*#UiScale#)'
        SKIN:Bang('!SetOption', 'meterText' .. row, 'W', width)
        SKIN:Bang('!SetOption', 'MeasureInput' .. row, 'W', width)
        SKIN:Bang(recurring and '!ShowMeter' or '!HideMeter', 'meterDaily' .. row)
        if text ~= '' then
            total = total + 1
            if recurring then daily = daily + 1 end
            if SKIN:GetVariable('Status' .. row, '0') == '1' then done = done + 1 end
        end
    end
    local progress = total == 0 and 'Click a row to add a task' or done .. '/' .. total .. ' done'
    if daily > 0 then progress = progress .. '  |  ' .. daily .. ' daily' end
    SKIN:Bang('!SetOption', 'meterProgress', 'Text', progress)
end
local function refresh()
    render(); SKIN:Bang('!UpdateMeasureGroup', 'NoteMeasures')
    SKIN:Bang('!UpdateMeter', '*'); SKIN:Bang('!Redraw')
end
function Initialize()
    store = dofile(SKIN:GetVariable('@') .. 'FileStore.lua')
    data = dofile(SKIN:GetVariable('@') .. 'NotesData.lua')
    page, ready, initFailed, checkedDay, retryAt, selected = SKIN:GetVariable('PageFile'), false, false, nil, 0, nil
    undo = page .. '.undo'
    store.recover(page)
    SKIN:Bang(store.recover(undo) and '!ShowMeter' or '!HideMeter', 'meterBtnUndo')
end
local function rollover(force)
    local today = day()
    if not force and (checkedDay == today or os.time() < retryAt) then return true end
    local paths, prefix = {page}, page:match('^(.*[/\\])Page[123]%.inc$')
    if prefix then paths = {}; for number = 1, 3 do paths[#paths + 1] = prefix .. 'Page' .. number .. '.inc' end end
    local success, changed = true, false
    for _, path in ipairs(paths) do
        local bytes = store.recover(path)
        local doc = data.parse(bytes)
        if not doc then success = false
        else
            local changes = data.rollover(doc, today)
            if next(changes) then
                local updated = data.patch(doc, changes)
                if updated and store.write(path, updated) then
                    if path == page then apply(changes); changed = true end
                else success = false end
            end
        end
    end
    checkedDay = success and today or nil
    retryAt = success and 0 or os.time() + 60
    if changed then refresh() end
    if not success then hint('Daily reset could not save. Retrying in one minute.'); return false end
    return true
end
function Ready()
    -- Initialization completes after all personal pages and meters exist. Read the
    -- recovered page too: Rainmeter may have loaded defaults before recovery ran.
    if initFailed then
        SKIN:Bang('!SetOption', 'meterHint', 'MouseActionCursor', '0')
        SKIN:Bang('!SetOption', 'meterHint', 'LeftMouseUpAction', '')
    end
    initFailed = false
    local doc = data.parse(store.recover(page))
    if not doc then hint('Could not read this page. Refresh to retry.'); return end
    local values = {PageTitle = data.get(doc, 'PageTitle', 'Page ' .. SKIN:GetVariable('CurrentPage', '1'))}
    for row = 1, 5 do
        for _, field in ipairs(fields) do
            values[field .. row] = data.get(doc, field .. row, default(field))
        end
    end
    apply(values); ready = true
    SKIN:Bang(store.recover(undo) and '!ShowMeter' or '!HideMeter', 'meterBtnUndo')
    rollover(true); refresh()
end
function FailReady()
    initFailed, ready = true, false
    SKIN:Bang('!SetOption', 'meterHint', 'MouseActionCursor', '1')
    SKIN:Bang('!SetOption', 'meterHint', 'LeftMouseUpAction', '[!Refresh]')
    hint('Notes unavailable; click here or refresh to retry')
end
function ResetHint()
    if initFailed then hint('Notes unavailable; click here or refresh to retry')
    elseif ready then hint(defaultHint) end
end
local function commit(changes)
    local bytes = store.recover(page)
    local doc = data.parse(bytes)
    local updated = doc and data.patch(doc, changes)
    if not updated then hint('Could not read this page. Your tasks were left unchanged.'); return false end
    if updated == bytes then return true end
    if not store.write(undo, bytes) then hint('Could not save recovery copy. Your page was left unchanged.'); return false end
    SKIN:Bang('!ShowMeter', 'meterBtnUndo')
    if not store.write(page, updated) then hint('Could not save. Your previous tasks were retained.'); return false end
    apply(changes); refresh(); return true
end
function Edit(row)
    if initFailed then hint('Notes unavailable; click here or refresh to retry'); return end
    row = tonumber(row)
    if row ~= 0 and not validRow(row) then return end
    local measure = row == 0 and 'MeasureInputTitle' or ('MeasureInput' .. row)
    local key = row == 0 and 'PageTitle' or ('Note' .. row)
    local value = display(SKIN:GetVariable(key, '')):gsub('"', "'")
    SKIN:Bang('!SetOption', measure, 'DefaultValue', value)
    SKIN:Bang('!CommandMeasure', measure, 'ExecuteBatch 1')
end
function Save(row)
    if initFailed then hint('Notes unavailable; click here or refresh to retry'); return end
    row = tonumber(row)
    if row ~= 0 and not validRow(row) then return end
    if ready and not rollover(true) then return end
    local measure = row == 0 and 'MeasureCommitTitle' or 'MeasureCommit' .. row
    local text = cleanInput(SKIN:GetMeasure(measure):GetStringValue())
    local key = row == 0 and 'PageTitle' or 'Note' .. row
    if row == 0 and text == '' then text = 'Page ' .. SKIN:GetVariable('CurrentPage') end
    if text == SKIN:GetVariable(key, '') then return end
    local changes = {[key] = text}
    if row > 0 and text == '' then
        changes['Status' .. row], changes['Daily' .. row], changes['DailyDay' .. row] = '0', '0', ''
    end
    commit(changes)
end
function Toggle(row)
    if initFailed then hint('Notes unavailable; click here or refresh to retry'); return end
    row = validRow(row); if not row then return end
    if ready and not rollover(true) then return end
    if SKIN:GetVariable('Note' .. row, '') == '' then
        SKIN:Bang('!SetOption', 'MeasureInput' .. row, 'DefaultValue', '')
        SKIN:Bang('!CommandMeasure', 'MeasureInput' .. row, 'ExecuteBatch 1'); return
    end
    commit({['Status' .. row] = SKIN:GetVariable('Status' .. row, '0') == '1' and '0' or '1'})
end
function ToggleDaily(row)
    if initFailed then hint('Notes unavailable; click here or refresh to retry'); return end
    row = validRow(row or selected); if not row or SKIN:GetVariable('Note' .. row, '') == '' then return end
    if ready and not rollover(true) then return end
    local enabled = SKIN:GetVariable('Daily' .. row, '0') ~= '1'
    if commit({['Daily' .. row] = enabled and '1' or '0', ['DailyDay' .. row] = enabled and day() or ''}) then
        hint(enabled and ('Daily task: resets at ' .. SKIN:GetVariable('DailyResetHour', '4') .. ':00 local time.') or 'One-time task: no automatic reset.')
    end
end
function SuiteMenu()
    selected = nil
    contextMenu().openSuite(SKIN)
end
function MoveTask(delta)
    if initFailed then hint('Notes unavailable; click here or refresh to retry'); return end
    local row = validRow(selected)
    if not ready or not row or (delta ~= -1 and delta ~= 1) then return end
    local other = validRow(row + delta)
    if not other or SKIN:GetVariable('Note' .. row, '') == '' or not rollover(true) then return end
    local changes = {}
    for _, field in ipairs(fields) do
        changes[field .. row] = SKIN:GetVariable(field .. other, default(field))
        changes[field .. other] = SKIN:GetVariable(field .. row, default(field))
    end
    if commit(changes) then
        selected = other
        hint(delta == -1 and 'Task moved up.' or 'Task moved down.')
    end
end
function OpenMenu(row)
    if initFailed then hint('Notes unavailable; click here or refresh to retry'); return end
    row = validRow(row); if not row then return end
    if SKIN:GetVariable('Note' .. row, '') == '' then Toggle(row); return end
    selected = row
    local items = {
        {SKIN:GetVariable('Daily' .. row, '0') == '1' and 'Make one-time' or 'Repeat daily', menuAction('ToggleDaily()')},
        {'Delete task (undo available)', menuAction("Clear('" .. row .. "')")}
    }
    for _, delta in ipairs({-1, 1}) do
        if validRow(row + delta) then
            items[#items + 1] = {delta == -1 and 'Move up' or 'Move down', menuAction('MoveTask(' .. delta .. ')')}
        end
    end
    contextMenu().openCustom(SKIN, items)
end
function Hover(row)
    if initFailed then hint('Notes unavailable; click here or refresh to retry'); return end
    row = validRow(row); if not row then return end
    local text = SKIN:GetVariable('Note' .. row, '')
    if text == '' then hint('Click to add a task. Right-click a task for options.'); return end
    local recurring = SKIN:GetVariable('Daily' .. row, '0') == '1'
    hint((recurring and 'Daily | ' or '') .. text)
end
function Clear(which)
    if initFailed then hint('Notes unavailable; click here or refresh to retry'); return end
    if ready and not rollover(true) then return end
    local changes = {}
    for row = 1, 5 do
        local completed = SKIN:GetVariable('Status' .. row, '0') == '1' and SKIN:GetVariable('Daily' .. row, '0') ~= '1'
        if (which == 'all' or which == tostring(row) or which == 'done' and completed) and SKIN:GetVariable('Note' .. row, '') ~= '' then
            changes['Note' .. row], changes['Status' .. row], changes['Daily' .. row], changes['DailyDay' .. row] = '', '0', '0', ''
        end
    end
    if next(changes) and not commit(changes) then return end
    for _, name in ipairs({'meterConfirmLabel','meterConfirmDone','meterConfirmAll','meterConfirmCancel'}) do SKIN:Bang('!HideMeter', name) end
    SKIN:Bang('!ShowMeter', 'meterHint')
    hint(which == 'done' and 'Cleared completed one-time tasks. Daily tasks kept.' or defaultHint); refresh()
end
function Undo()
    if initFailed then hint('Notes unavailable; click here or refresh to retry'); return end
    if ready and not rollover(true) then return end
    local history, current = store.recover(undo), store.read(page)
    local doc = data.parse(history)
    if not doc or not current then hint('No recovery copy available.'); return end
    -- An old snapshot must not bring yesterday's checkmarks into today's list.
    local changes = data.rollover(doc, day())
    if next(changes) then history = data.patch(doc, changes) end
    if not history or not store.write(page, history) then hint('Could not restore. Recovery copy retained.'); return end
    if not store.write(undo, current) then
        SKIN:Bang('!Log', 'Notes: restored page, but could not save redo history.', 'Warning')
    end
    SKIN:Bang('!Refresh')
end
function Update()
    if ready then rollover(false) end
    return 0
end
