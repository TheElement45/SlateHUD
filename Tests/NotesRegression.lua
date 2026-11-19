function TestDailyNotes(root, scratch)
    local function check(value, message) if not value then error(message, 2) end end
    local store = dofile(root .. '/@Resources/FileStore.lua')
    local data = dofile(root .. '/@Resources/NotesData.lua')
    local realDate, realTime, realOpen, realRename = os.date, os.time, io.open, os.rename
    local clock
    local function at(year, month, day, hour, minute, second)
        clock = realTime({year=year, month=month, day=day, hour=hour, min=minute or 0, sec=second or 0})
    end
    os.date = function(format, time) return realDate(format, time or clock) end
    os.time = function(value) return value and realTime(value) or clock end
    at(2026, 11, 2, 3, 59, 59)
    check(data.day(4) == '2026-11-01', 'Pre-4AM date incorrect')
    at(2026, 11, 2, 4); check(data.day(4) == '2026-11-02', '4AM boundary incorrect')
    at(2027, 1, 1, 0); check(data.day(4) == '2026-12-31', 'Year boundary incorrect')
    at(2028, 3, 1, 3); check(data.day(4) == '2028-02-29', 'Leap day boundary incorrect')
    at(2026, 11, 2, 3, 59, 59)

    local page = scratch .. '/Page1.inc'
    local page2, page3 = scratch .. '/Page2.inc', scratch .. '/Page3.inc'
    local original = '[Variables]\r\nPageTitle=TASKS\r\n; Keep this comment\r\nNote1=Daily rain \233\155\168\r\nStatus1=1\r\nDaily1=1\r\nDailyDay1=2026-11-01\r\nNote2=One-time\r\nStatus2=1\r\n'
    check(store.write(page, original), 'Fixture save failed')
    check(store.write(page2, original), 'Second page save failed')
    check(store.write(page3, '[Variables]\nNote1=Ordinary\nStatus1=1\n'), 'Third page save failed')
    check(store.write(page .. '.undo', original), 'Undo fixture failed')
    local vars = {['@']=root .. '/@Resources/', PageFile=page, CurrentPage='1', DailyResetHour='4'}
    local options, hidden, calls, commit = {}, {}, {}, ''
    SKIN = {}
    function SKIN:GetVariable(key, default) return vars[key] or default end
    function SKIN:GetMeasure() return {GetStringValue=function() return commit end} end
    function SKIN:Bang(command, a, b, c)
        calls[#calls+1] = {command, a, b, c}
        if command == '!SetVariable' then vars[a] = b
        elseif command == '!SetOption' then options[a] = options[a] or {}; options[a][b] = c
        elseif command == '!ShowMeter' or command == '!HideMeter' then hidden[a] = command == '!HideMeter' end
    end
    local function reload() dofile(root .. '/@Resources/Notes.lua'); Initialize(); Ready() end
    local function saved(path, key) return data.get(assert(data.parse(store.read(path))), key, '') end
    reload()
    check(vars.Status1 == '1' and vars.Status2 == '1', 'Pre-4AM checkmarks changed')
    check(not hidden.meterDaily1 and hidden.meterDaily2, 'Daily indicator incorrect')
    check(options.meterText1.W == '(152*#UiScale#)' and options.meterText2.W == '(172*#UiScale#)', 'Repeat marker reduced ordinary task width')
    check(options.meterProgress.Text == '2/2 done  |  1 daily', 'Daily progress incorrect')
    at(2026, 11, 2, 4); Update()
    check(vars.Status1 == '0' and vars.Status2 == '1', 'Daily reset affected ordinary tasks')
    check(saved(page2, 'Status1') == '0' and saved(page3, 'Status1') == '1', 'Inactive tabs reset incorrectly')
    check(vars.Note1 == 'Daily rain \233\155\168' and saved(page, 'DailyDay1') == '2026-11-02', 'Daily text or day lost')
    check(store.read(page .. '.undo') == original, 'Automatic reset overwrote undo')
    check(store.read(page):find('; Keep this comment', 1, true), 'Page comments lost')
    local writes = 0
    local idleCalls = #calls
    io.open = function(path, mode) if mode == 'wb' then writes = writes + 1 end; return realOpen(path, mode) end
    for i=1,120 do Update() end
    io.open = realOpen; check(writes == 0, 'Unchanged day writes to disk')
    check(#calls == idleCalls, 'Unchanged notes repeatedly updated the UI')
    Toggle(1); reload(); check(vars.Status1 == '1', 'Same-day restart unchecked completed task')
    at(2026, 11, 2, 1); reload(); check(vars.Status1 == '1', 'Backward clock reset task')
    at(2026, 11, 5, 10); reload(); check(vars.Status1 == '0', 'Multi-day restart did not catch up')

    -- Enabling daily on a checked one-time task preserves its current state.
    ToggleDaily(2)
    check(vars.Daily2 == '1' and vars.Status2 == '1' and vars.DailyDay2 == '2026-11-05', 'Opt-in reset an existing task')
    ToggleDaily(2); check(vars.Daily2 == '0' and vars.Status2 == '1', 'Opt-out changed completion')
    OpenMenu(1); check(options.Rainmeter.ContextTitle == 'Make one-time', 'Daily menu incorrect')
    OpenMenu(2); check(options.Rainmeter.ContextTitle == 'Repeat daily', 'One-time menu incorrect')
    ToggleDaily(); check(vars.Daily2 == '1', 'Menu applied daily to wrong row')
    SuiteMenu()
    check(options.Rainmeter.ContextTitle == 'Size: Compact' and options.Rainmeter.ContextTitle18 == 'Blur: Off' and options.Rainmeter.ContextTitle19 == '', 'Suite menu did not restore shared slots')
    ToggleDaily(); check(vars.Daily2 == '1', 'Background menu retained selected row')
    Toggle(1); Clear('done')
    check(vars.Note1 ~= '' and vars.Note2 ~= '' and vars.Status1 == '1', 'Cleanup deleted daily tasks')
    ToggleDaily(2); Clear('done')
    check(vars.Note2 == '' and vars.Daily2 == '0' and vars.DailyDay2 == '', 'Cleanup did not clear one-time task and metadata')
    Clear('1'); check(vars.Note1 == '' and vars.Daily1 == '0', 'Explicit delete did not remove daily task')
    Undo(); reload(); check(vars.Note1 ~= '' and vars.Daily1 == '1', 'Undo did not restore daily task')
    Clear('all'); check(vars.Note1 == '', 'Clear all kept a daily task')
    Undo(); reload(); check(vars.Note1 ~= '', 'Undo clear-all failed')

    -- Keep the old history but never restore yesterday's completed daily status.
    check(store.write(page .. '.undo', original), 'History fixture failed')
    Undo(); reload()
    check(vars.Status1 == '0' and vars.DailyDay1 == '2026-11-05' and vars.Status2 == '1', 'Undo resurrected stale daily completion')
    Toggle(1); Toggle(1); Undo(); reload()
    check(vars.Status1 == '1', 'Same-day undo should restore completion')
    Undo(); reload(); check(vars.Status1 == '0', 'Same-day redo failed')

    -- A failed publication cannot advance the day or show unsaved state.
    Toggle(1)
    local before = store.read(page)
    at(2026, 11, 6, 4)
    io.open = function(path, mode) if path == page .. '.tmp' and mode == 'wb' then return nil, 'locked' end; return realOpen(path, mode) end
    Update()
    check(store.read(page) == before and vars.Status1 == '1' and vars.DailyDay1 == '2026-11-05', 'Failed reset changed state')
    check(options.meterHint.Text:find('Retrying', 1, true), 'Reset failure feedback missing')
    io.open = realOpen
    clock = clock + 60; Update()
    check(vars.Status1 == '0' and vars.DailyDay1 == '2026-11-06', 'Failed reset did not retry')
    before = store.read(page)
    os.rename = function(from, to) if from == page .. '.tmp' then return nil, 'locked' end; return realRename(from, to) end
    ToggleDaily(1)
    check(store.read(page) == before and vars.Daily1 == '1', 'Failed recurrence save changed state')
    commit = 'Must not appear'; Save(1)
    check(store.read(page) == before and vars.Note1 ~= commit, 'Failed edit appeared saved')
    os.rename = realRename
    commit = ''; Save(1)
    check(vars.Note1 == '' and vars.Daily1 == '0' and vars.DailyDay1 == '', 'Empty edit kept recurrence metadata')
    commit = 'New task'; Save(1)
    check(vars.Daily1 == '0', 'Reused row inherited daily setting')
    local previous = store.read(page)
    for _, value in ipairs({-1, 1.5, 6, 'bad'}) do Toggle(value); ToggleDaily(value); Save(value); OpenMenu(value) end
    check(store.read(page) == previous, 'Invalid row modified data')
    -- Interrupted replacement is recovered and loaded into the active variables.
    assert(os.rename(page, page .. '.bak')); vars.Note1 = 'Stale'; reload()
    check(vars.Note1 == 'New task' and store.read(page) == previous, 'Recovery left stale UI variables')
    ToggleDaily(1); Toggle(1)
    local beforeMove, otherPage = store.read(page), store.read(page2)
    OpenMenu(1); MoveTask(-1)
    check(store.read(page)==beforeMove,'Move above first row changed the page')
    MoveTask(1)
    check(vars.Note2=='New task' and vars.Status2=='1' and vars.Daily2=='1' and
        vars.DailyDay2=='2026-11-06' and vars.Note1=='One-time','Moving a task lost row metadata')
    check(store.read(page2)==otherPage,'Move modified another page')
    Undo(); reload()
    check(store.read(page)==beforeMove and vars.Note1=='New task','Undo did not restore pre-move order')

    -- Rainmeter syntax characters are neutralized in display mirrors and Edit() DefaultValue.
    commit = 'Fix #ColorAccent# [MeasureStatus1] "quote"'; Save(1)
    check(options.meterText1.Text == "Fix \239\188\131ColorAccent\239\188\131 \239\188\187MeasureStatus1\239\188\189 'quote'", 'Task display did not escape Rainmeter syntax')
    check(vars.NoteDisplay1 == options.meterText1.Text, 'NoteDisplay mirror out of sync')
    vars.Note1 = 'Raw #Var# [Bang] """triple"""'
    Edit(1)
    check(options.MeasureInput1.DefaultValue == "Raw \239\188\131Var\239\188\131 \239\188\187Bang\239\188\189 '''triple'''", 'Edit DefaultValue leaked raw Rainmeter syntax or quotes')

    -- Initialization failure keeps retry click responsive and blocks task mutations.
    local beforeFail = store.read(page)
    FailReady()
    check(options.meterHint.LeftMouseUpAction == '[!Refresh]' and options.meterHint.MouseActionCursor == '1', 'Init failure did not arm retry click')
    Toggle(1); Edit(1)
    check(store.read(page) == beforeFail, 'Init failure allowed page mutation')
    Ready()

    os.date, os.time = realDate, realTime
    print('PASS: Daily 4AM rollover, inactive pages, restart catch-up, clock rollback, opt-in/out, menus, cleanup, undo, save failures and recovery')

    -- Encoding and unrelated bytes survive whole-page transactions.
    local unicode = '\233\155\168 \240\159\152\128'
    local function wide(ascii, little)
        return (ascii:gsub('.', function(c) return little and c .. '\0' or '\0' .. c end))
    end
    for _, little in ipairs({true, false}) do
        local bom = little and '\255\254' or '\254\255'
        local chars = little and '\232\150 \0\061\216\000\222' or '\150\232\0 \216\061\222\000'
        local bytes = bom .. wide('[Variables]\r\nNote1=', little) .. chars .. wide('\r\nStatus1=1\r\n[Other]\r\nStatus1=keep\r\n', little)
        local doc = assert(data.parse(bytes))
        check(data.get(doc, 'Note1') == unicode, 'UTF-16 decoding failed')
        check(data.patch(doc, {}) == bytes, 'UTF-16 round trip changed bytes')
        local changed = data.patch(doc, {Status1='0', Daily1='1', DailyDay1='2026-11-06'})
        check(changed:sub(1,2) == bom and changed:find(chars,1,true), 'UTF-16 Unicode changed')
        check(changed:find(wide('[Other]\r\nStatus1=keep', little),1,true), 'Unrelated section changed')
        local parsed = assert(data.parse(changed))
        check(data.get(parsed, 'Status1') == '0' and data.get(parsed, 'Daily1') == '1', 'Added keys outside Variables')
        local edited = data.patch(parsed, {Note1=unicode .. ' updated'})
        check(data.get(assert(data.parse(edited)), 'Note1') == unicode .. ' updated', 'UTF-16 edit lost Unicode')
    end
    local bytes = '\239\187\191[Variables]\nNote1=' .. unicode .. '\nStatus1=1'
    local edited = data.patch(assert(data.parse(bytes)), {Daily1='1', Status1='0'})
    check(edited:sub(1,3) == '\239\187\191' and edited:find(unicode,1,true), 'UTF-8 BOM or Unicode lost')
    check(data.get(assert(data.parse(edited)), 'Daily1') == '1', 'Missing trailing newline broke added key')
    check(not data.parse('\255\254[\0x') and not data.parse('invalid page'), 'Malformed document accepted')
    local duplicate = assert(data.parse('[Variables]\nstatus1 =1\nSTATUS1=1\n'))
    check(data.patch(duplicate, {Status1='0'}) == '[Variables]\nstatus1 =0\nSTATUS1=0\n', 'Case-insensitive duplicates not updated')
    print('PASS: UTF-8/UTF-16 LE/BE, emoji, comments, sections, missing newline, duplicate keys and malformed-file protection')
end
