-- Binary-safe, same-directory replacement with recovery after an interrupted swap.
local Store = {}
function Store.read(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local bytes = file:read('*a'); file:close()
    return bytes
end
function Store.recover(path)
    local bytes = Store.read(path)
    if bytes then return bytes end
    bytes = Store.read(path .. '.bak')
    if bytes then os.rename(path .. '.bak', path) end
    return bytes
end
function Store.write(path, bytes)
    local temporary, backup = path .. '.tmp', path .. '.bak'
    -- Recover a previous interrupted swap before touching its backup.
    Store.recover(path)
    local file = io.open(temporary, 'wb')
    if not file then return false, 'open' end
    local written = file:write(bytes)
    local closed = file:close()
    if not written or not closed then os.remove(temporary); return false, 'write' end
    local previous = Store.read(path)
    if previous then
        os.remove(backup)
        if not os.rename(path, backup) then os.remove(temporary); return false, 'backup' end
    end
    if not os.rename(temporary, path) then
        if previous then os.rename(backup, path) end
        os.remove(temporary); return false, 'replace'
    end
    os.remove(backup)
    return true
end
return Store
