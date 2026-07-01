-- PenguRP: SELF-CONTAINED JAIL for the pdloc system (SERVER).
--
-- Sentencing is driven by the MDT: pengu_mdt's /jail sums a suspect's outstanding charges and
-- calls our JailPlayerCustom export. THIS module owns the actual imprisonment:
--   * teleports the prisoner to the pdloc 'cell' marker,
--   * runs a server-authoritative per-minute countdown that survives relogs / crashes
--     (persisted to the pengu_jail table by citizenid),
--   * releases them to the pdloc 'lobby' marker when (a) time is served, (b) an ADMIN runs
--     /unjail (skip the remaining sentence), or (c) an on-duty LEO runs /release.
--
-- The cell + lobby coordinates come from GlobalState.penguJailAnchor / penguJailLobby, which
-- server/pd.lua publishes from the pengu_pd_locations table, so the owner picks BOTH locations
-- live with /pdloc (no restart). ASCII only. luac clean.

local MAX_JAIL_MINUTES = 60 -- hard cap on any single sentence (mirrors the previous xt-prison cap)

-- runtime map: src -> { cid = citizenid, left = minutesRemaining }
local JAILED = {}

-- ============================ coords (from pdloc via GlobalState) ============================

local function cellCoords()
    local g = GlobalState.penguJailAnchor
    if not g then return nil end
    return { x = g.x, y = g.y, z = g.z, w = g.w or 0.0 }
end

local function lobbyCoords()
    local g = GlobalState.penguJailLobby
    if not g then return nil end
    return { x = g.x, y = g.y, z = g.z, w = g.w or 0.0 }
end

-- ============================ chat feedback (same template as pd.lua) ============================

local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, msg, kind)
    if src and src > 0 and GetPlayerName(src) ~= nil then
        TriggerClientEvent('chat:addMessage', src, {
            templateId = 'pengu:admin',
            args = { 'JAIL', msg, KIND[kind or 'inform'] or 'info' },
        })
    end
end

-- ============================ persistence ============================

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS pengu_jail (
            citizenid    VARCHAR(64) NOT NULL PRIMARY KEY,
            minutes_left INT         NOT NULL DEFAULT 0,
            cell_x       FLOAT       NULL,
            cell_y       FLOAT       NULL,
            cell_z       FLOAT       NULL,
            cell_w       FLOAT       NULL,
            updated_at   TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]])
    for _, col in ipairs({ 'cell_x', 'cell_y', 'cell_z', 'cell_w' }) do
        local ex = MySQL.scalar.await(
            'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            { 'pengu_jail', col })
        if not ex then MySQL.query.await(('ALTER TABLE pengu_jail ADD COLUMN %s FLOAT NULL'):format(col)) end
    end
end)

-- fire-and-forget (called once per prisoner per minute) - no .await so the loop never blocks.
-- Stores the prisoner's assigned cell so relog/crash resume returns them to the SAME cell.
local function persist(cid, left, cell)
    if not cid then return end
    if cell then
        MySQL.update(
            'INSERT INTO pengu_jail (citizenid, minutes_left, cell_x, cell_y, cell_z, cell_w) VALUES (?, ?, ?, ?, ?, ?) ' ..
            'ON DUPLICATE KEY UPDATE minutes_left = VALUES(minutes_left), cell_x = VALUES(cell_x), cell_y = VALUES(cell_y), cell_z = VALUES(cell_z), cell_w = VALUES(cell_w)',
            { cid, left, cell.x, cell.y, cell.z, cell.w or 0.0 })
    else
        MySQL.update(
            'INSERT INTO pengu_jail (citizenid, minutes_left) VALUES (?, ?) ON DUPLICATE KEY UPDATE minutes_left = VALUES(minutes_left)',
            { cid, left })
    end
end

local function clearDb(cid)
    if not cid then return end
    MySQL.update('DELETE FROM pengu_jail WHERE citizenid = ?', { cid })
end

-- ============================ helpers ============================

local function getCid(src)
    local p = exports.qbx_core:GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function isAdmin(src)
    return IsPlayerAceAllowed(src, 'admin')
end

local function isLeoOnDuty(src)
    local p = exports.qbx_core:GetPlayer(src)
    local job = p and p.PlayerData and p.PlayerData.job
    return job ~= nil and job.type == 'leo' and job.onduty == true
end

-- ============================ release ============================

-- Free a prisoner: clear runtime + DB state and (if online) drop them at the lobby marker.
local function release(src)
    local rec = JAILED[src]
    JAILED[src] = nil
    local cid = (rec and rec.cid) or getCid(src)
    clearDb(cid)
    -- Single choke point for EVERY release path (served / labor->0 / bail / /release /
    -- /unjail / pardon): announce it so other resources can clear per-prisoner state.
    if cid then TriggerEvent('pengu_jail:server:released', src, cid) end
    if src and GetPlayerName(src) ~= nil then
        Player(src).state:set('penguJailMinutes', 0, true)
        TriggerClientEvent('pengu_jail:client:release', src, lobbyCoords())
    end
    return rec and rec.left or 0
end

-- ============================ jail entry ============================

-- Imprison an ONLINE player for `minutes` real minutes at the pdloc cell. Returns true on success.
local function jail(src, minutes, cell)
    minutes = math.floor(tonumber(minutes) or 0)
    if minutes < 0 then minutes = 0 end
    if minutes > MAX_JAIL_MINUTES then minutes = MAX_JAIL_MINUTES end
    if minutes == 0 then return false end

    cell = cell or cellCoords() -- back-compat: fall back to the first 'cell' pdloc
    if not cell then return false end -- no 'cell' marker placed yet
    cell = { x = cell.x + 0.0, y = cell.y + 0.0, z = cell.z + 0.0, w = (cell.w or 0.0) + 0.0 }

    local cid = getCid(src)
    if not cid then return false end

    JAILED[src] = { cid = cid, left = minutes, cell = cell }
    persist(cid, minutes, cell)
    Player(src).state:set('penguJailMinutes', minutes, true)
    TriggerClientEvent('pengu_jail:client:enter', src, { cell = cell, minutes = minutes })
    return true
end

-- ============================ exports ============================

-- Called by pengu_mdt's /jail after it sums outstanding charges (cell = the officer's nearest cell).
exports('JailPlayerCustom', function(targetSrc, minutes, cell)
    return jail(tonumber(targetSrc), minutes, type(cell) == 'table' and cell or nil) and true or false
end)

exports('ReleasePlayerCustom', function(targetSrc)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not JAILED[targetSrc] then return false end
    release(targetSrc)
    return true
end)

-- minutes remaining (0 if not jailed) - handy for other resources / the MDT roster.
exports('GetJailMinutes', function(targetSrc)
    local rec = JAILED[tonumber(targetSrc)]
    return rec and rec.left or 0
end)

-- Reduce remaining minutes (prison labor, judicial reductions, guilty-plea cuts).
-- Releases the prisoner if it reaches 0. Returns the new remaining minutes.
exports('ReduceJailMinutes', function(targetSrc, mins)
    targetSrc = tonumber(targetSrc)
    local rec = JAILED[targetSrc]
    if not rec then return 0 end
    mins = math.max(0, math.floor(tonumber(mins) or 0))
    rec.left = math.max(0, rec.left - mins)
    if rec.left <= 0 then
        release(targetSrc)
        return 0
    end
    persist(rec.cid, rec.left, rec.cell)
    Player(targetSrc).state:set('penguJailMinutes', rec.left, true)
    TriggerClientEvent('pengu_jail:client:tick', targetSrc, rec.left)
    return rec.left
end)

-- ============================ countdown (server-authoritative) ============================

CreateThread(function()
    while true do
        Wait(60000)
        for src, rec in pairs(JAILED) do
            if GetPlayerName(src) == nil then
                -- went offline without a clean playerDropped: persist + drop from runtime.
                persist(rec.cid, rec.left, rec.cell)
                JAILED[src] = nil
            else
                rec.left = rec.left - 1
                if rec.left <= 0 then
                    persist(rec.cid, 0, rec.cell)
                    notify(src, 'You have served your sentence. You are free to go.', 'success')
                    release(src)
                else
                    persist(rec.cid, rec.left, rec.cell)
                    Player(src).state:set('penguJailMinutes', rec.left, true)
                    TriggerClientEvent('pengu_jail:client:tick', src, rec.left)
                end
            end
        end
    end
end)

-- ============================ relog / crash resume ============================

-- The client asks on (re)spawn whether it owes time; re-jail so disconnecting can't skip a sentence.
RegisterNetEvent('pengu_jail:server:checkStatus', function()
    local src = source
    local cid = getCid(src)
    if not cid then return end

    if JAILED[src] then return end -- already tracked this session

    local row = MySQL.query.await('SELECT minutes_left, cell_x, cell_y, cell_z, cell_w FROM pengu_jail WHERE citizenid = ?', { cid })
    local r = row and row[1]
    local left = r and tonumber(r.minutes_left) or 0
    if left and left > 0 then
        local cell
        if r.cell_x ~= nil then
            cell = { x = r.cell_x + 0.0, y = r.cell_y + 0.0, z = r.cell_z + 0.0, w = (r.cell_w or 0.0) + 0.0 }
        else
            cell = cellCoords() -- pre-migration row: fall back to the first cell
        end
        if not cell then return end -- no cell configured; leave them free until one exists
        JAILED[src] = { cid = cid, left = left, cell = cell }
        Player(src).state:set('penguJailMinutes', left, true)
        TriggerClientEvent('pengu_jail:client:enter', src, { cell = cell, minutes = left })
    end
end)

-- Persist remaining time when a prisoner disconnects mid-sentence.
AddEventHandler('playerDropped', function()
    local src = source
    local rec = JAILED[src]
    if rec then
        persist(rec.cid, rec.left, rec.cell)
        JAILED[src] = nil
    end
end)

-- ============================ commands ============================

-- ADMIN ONLY: skip the remaining sentence and release now.
RegisterCommand('unjail', function(src, args)
    if not isAdmin(src) then
        notify(src, 'Admin only.', 'error')
        return
    end
    -- Admin commands require being on admin duty, same as qbx_core's own admin commands.
    if not exports.qbx_core:IsOptin(src) then
        notify(src, 'You must /aduty before using /unjail.', 'error')
        return
    end
    local id = tonumber(args[1])
    if not id then
        notify(src, 'Usage: /unjail <id>', 'error')
        return
    end
    if not exports.qbx_core:GetPlayer(id) then
        notify(src, 'Invalid id (player must be online).', 'error')
        return
    end
    if not JAILED[id] then
        notify(src, 'That player is not jailed.', 'error')
        return
    end
    local left = release(id)
    notify(src, ('Released #%d (skipped %d min).'):format(id, left), 'success')
    notify(id, 'You have been released early by an administrator.', 'inform')
end, false)

-- ON-DUTY LEO: release a prisoner (e.g. bail / early discretionary release) to the lobby.
RegisterCommand('release', function(src, args)
    if not isLeoOnDuty(src) then
        notify(src, 'On-duty LEO only.', 'error')
        return
    end
    local id = tonumber(args[1])
    if not id then
        notify(src, 'Usage: /release <id>', 'error')
        return
    end
    if not exports.qbx_core:GetPlayer(id) then
        notify(src, 'Invalid id (player must be online).', 'error')
        return
    end
    if not JAILED[id] then
        notify(src, 'That player is not jailed.', 'error')
        return
    end
    release(id)
    notify(src, ('Released #%d.'):format(id), 'success')
    notify(id, 'You have been released from jail.', 'inform')
end, false)

-- ANYONE: check your own remaining jail time. Reads the REAL pengu jail (the banner uses the same
-- value), fixing the old /jailtime which read xt-prison's bypassed state and always said 0.
RegisterCommand('jailtime', function(src)
    if src <= 0 then return end
    local rec = JAILED[src]
    local left = rec and rec.left or 0
    if left > 0 then
        notify(src, ('You have %d minute%s left in jail.'):format(left, left == 1 and '' or 's'), 'inform')
    else
        notify(src, 'You are not in jail.', 'inform')
    end
end, false)
