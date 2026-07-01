-- PenguRP Money Laundering (pengu_launder) - SERVER. Admin-placeable laundromats (/washloc, pdloc
-- recipe). Laundering is ASYNC + contestable:
--   START : your black_money goes into the machine; the wash takes time SCALED BY AMOUNT.
--   COLLECT: come back after it finishes to pull CLEAN CASH onto your person (deposit at a bank yourself).
--   ROB   : while a wash runs, a RIVAL standing at the machine can skim the clean cash (contest).
-- One wash per laundromat at a time. Active washes persist across restarts (pengu_launder_active) and
-- replicate to GlobalState.penguLaunderActive for clients. ASCII only. luac clean.

local qbx = exports.qbx_core
local ox  = exports.ox_inventory
local ACE = 'pengu.launder'

POINTS = {} -- id -> { id, label, x, y, z }
WASH   = {} -- pointId -> { ownerCid, ownerName, amount, clean, readyAt(os.time secs) }

-- chat feedback via the qbx_chat_theme 'pengu:admin' template.
local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, msg, kind, tag)
    if not src or src <= 0 then print('[pengu_launder] ' .. tostring(msg)); return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { tag or 'LAUNDER', msg, KIND[kind or 'inform'] or 'info' },
    })
end

-- ===================== persistence + replication =====================
local function ensureColumn(tbl, col, ddl)
    local ex = MySQL.scalar.await(
        'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tbl, col })
    if not ex then MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(tbl, ddl)) end
end

local function loadPoints()
    local rows = MySQL.query.await('SELECT id, label, x, y, z FROM pengu_launder_points ORDER BY id') or {}
    local t = {}
    for _, r in ipairs(rows) do
        t[r.id] = { id = r.id, label = r.label, x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0 }
    end
    POINTS = t
    return t
end

local function pointArray()
    local arr = {}
    for _, p in pairs(POINTS) do arr[#arr + 1] = p end
    return arr
end

local function broadcast()
    TriggerClientEvent('pengu_launder:pointsUpdated', -1, pointArray())
end

-- replicate the live wash state so clients can show "in use (rob it)" vs "collect" vs "launder".
local function publishWashes()
    local out = {}
    for pid, w in pairs(WASH) do
        if not w.pending then
            out[tostring(pid)] = { ownerCid = w.ownerCid, ownerName = w.ownerName, amount = w.amount, readyAt = w.readyAt }
        end
    end
    GlobalState.penguLaunderActive = out
end

local function saveWash(pid, w)
    MySQL.update.await(
        'INSERT INTO pengu_launder_active (point_id, owner_cid, owner_name, amount, clean, ready_at) ' ..
        'VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner_cid=VALUES(owner_cid), ' ..
        'owner_name=VALUES(owner_name), amount=VALUES(amount), clean=VALUES(clean), ready_at=VALUES(ready_at)',
        { pid, w.ownerCid, w.ownerName, w.amount, w.clean, w.readyAt })
end

local function clearWash(pid)
    WASH[pid] = nil
    MySQL.update.await('DELETE FROM pengu_launder_active WHERE point_id = ?', { pid })
    publishWashes()
end

lib.callback.register('pengu_launder:getPoints', function(_) return pointArray() end)

-- ===================== boot =====================
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_launder_points (
                id         INT AUTO_INCREMENT PRIMARY KEY,
                label      VARCHAR(64) NOT NULL DEFAULT '',
                x          FLOAT       NOT NULL,
                y          FLOAT       NOT NULL,
                z          FLOAT       NOT NULL,
                created_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ]])
        ensureColumn('pengu_launder_points', 'label', "`label` VARCHAR(64) NOT NULL DEFAULT ''")
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_launder_active (
                point_id   INT         NOT NULL PRIMARY KEY,
                owner_cid  VARCHAR(64) NOT NULL,
                owner_name VARCHAR(64) NOT NULL DEFAULT '',
                amount     INT         NOT NULL,
                clean      INT         NOT NULL,
                ready_at   INT         NOT NULL
            )
        ]])
        local cnt = MySQL.scalar.await('SELECT COUNT(*) FROM pengu_launder_points')
        if (tonumber(cnt) or 0) == 0 then
            for _, s in ipairs(Config.seeds or {}) do
                MySQL.insert.await('INSERT INTO pengu_launder_points (label, x, y, z) VALUES (?, ?, ?, ?)',
                    { s.label or Config.defaultLabel, s.x + 0.0, s.y + 0.0, s.z + 0.0 })
            end
            print(('[pengu_launder] seeded %d laundromat(s)'):format(#(Config.seeds or {})))
        end
        loadPoints()
        -- restore in-progress washes
        local active = MySQL.query.await('SELECT point_id, owner_cid, owner_name, amount, clean, ready_at FROM pengu_launder_active') or {}
        for _, r in ipairs(active) do
            if POINTS[r.point_id] then
                WASH[r.point_id] = {
                    ownerCid = r.owner_cid, ownerName = r.owner_name,
                    amount = tonumber(r.amount) or 0, clean = tonumber(r.clean) or 0,
                    readyAt = tonumber(r.ready_at) or 0,
                }
            else
                MySQL.update.await('DELETE FROM pengu_launder_active WHERE point_id = ?', { r.point_id }) -- orphan
            end
        end
    end)
    if not ok then print('[pengu_launder] BOOT FAILED: ' .. tostring(err)) end
    broadcast(); publishWashes()
    local n = 0; for _ in pairs(POINTS) do n = n + 1 end
    print(('[pengu_launder] %s (%d laundromats).'):format(ok and 'ready' or 'DEGRADED', n))
end)

-- ===================== helpers =====================
local function washSeconds(amount)
    return (Config.baseSeconds or 30) + math.floor((amount or 0) / 1000) * (Config.secondsPer1k or 4)
end

local function cidOf(p) return p and p.PlayerData and p.PlayerData.citizenid end
local function nameOf(p)
    local c = p and p.PlayerData and p.PlayerData.charinfo
    if c then
        local n = ('%s %s'):format(c.firstname or '', c.lastname or '')
        return (n:gsub('^%s+', ''):gsub('%s+$', ''))
    end
    return 'Unknown'
end

local function nearPoint(src, point)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z)) <= (Config.interactDist + 2.0)
end

local function srcOfCid(cid)
    for src, p in pairs(qbx:GetQBPlayers() or {}) do
        if cidOf(p) == cid then return src end
    end
end

-- An admin removing a laundromat mid-wash must NOT vaporise money the player already paid in. Cash the
-- wash out to its owner if they are online (offline owners forfeit - a rare admin-only edge), then clear.
local function settleWashOnRemoval(id)
    local w = WASH[id]
    if not w or w.pending then if w then clearWash(id) end; return end
    local owner = srcOfCid(w.ownerCid)
    if owner then
        local p = qbx:GetPlayer(owner)
        if p then p.Functions.AddMoney('cash', w.clean, 'laundered-money-admin-removed') end
        notify(owner, ('The laundromat was decommissioned mid-wash - you were paid out $%d clean cash.'):format(w.clean), 'inform')
    end
    clearWash(id)
end

local busy = {} -- src -> true (anti double-call lock spanning awaits)

-- ===================== START a wash =====================
lib.callback.register('pengu_launder:start', function(src, pointId, amount)
    if busy[src] then return false end
    amount = math.floor(tonumber(amount) or 0)
    local point = POINTS[tonumber(pointId) or -1]
    if not point then return false end
    if amount < (Config.minWash or 1) or amount > (Config.maxWash or 1) then
        notify(src, ('You can wash between $%d and $%d at a time.'):format(Config.minWash, Config.maxWash), 'error')
        return false
    end
    if WASH[point.id] then notify(src, 'This laundromat is already running a wash.', 'error'); return false end
    if not nearPoint(src, point) then notify(src, 'You are too far from the laundromat.', 'error'); return false end

    local p = qbx:GetPlayer(src)
    if not p then return false end
    local have = ox:Search(src, 'count', Config.dirtyItem) or 0
    if have < amount then notify(src, ('You only have $%d in dirty money.'):format(have), 'error'); return false end

    busy[src] = true
    local result = false
    -- claim the machine BEFORE any further work so two starts can't race the same point
    WASH[point.id] = { pending = true }
    if ox:RemoveItem(src, Config.dirtyItem, amount) then
        local clean = math.floor(amount * (1 - (Config.fee or 0)))
        local secs  = washSeconds(amount)
        local w = {
            ownerCid = cidOf(p), ownerName = nameOf(p),
            amount = amount, clean = clean, readyAt = os.time() + secs,
        }
        WASH[point.id] = w
        saveWash(point.id, w); publishWashes()
        notify(src, ('Wash started: $%d dirty -> $%d clean cash in ~%dm%02ds. Come back to collect (or guard it).')
            :format(amount, clean, math.floor(secs / 60), secs % 60), 'success')
        -- alert police to suspicious financial activity near the laundromat
        pcall(function()
            local c = GetEntityCoords(GetPlayerPed(src))
            exports.pengu_core:Dispatch(c, {
                message = 'Suspicious Financial Activity', code = '10-35',
                icon = 'fas fa-money-bill-wave', priority = 3,
                jobs = { 'police', 'bcso', 'sasp' },
            })
        end)
        result = true
    else
        WASH[point.id] = nil -- release the claim on failure
        notify(src, 'Could not start the wash.', 'error')
    end
    busy[src] = nil
    return result
end)

-- ===================== COLLECT a finished wash =====================
lib.callback.register('pengu_launder:collect', function(src, pointId)
    if busy[src] then return false end
    local point = POINTS[tonumber(pointId) or -1]
    if not point then return false end
    local w = WASH[point.id]
    if not w or w.pending then notify(src, 'Nothing is washing here.', 'error'); return false end
    local p = qbx:GetPlayer(src)
    if not p then return false end
    if cidOf(p) ~= w.ownerCid then notify(src, 'This wash is not yours.', 'error'); return false end
    if not nearPoint(src, point) then notify(src, 'You are too far from the laundromat.', 'error'); return false end

    local left = w.readyAt - os.time()
    if left > 0 then
        notify(src, ('Still washing - ready in ~%dm%02ds.'):format(math.floor(left / 60), left % 60), 'inform')
        return false
    end

    busy[src] = true
    -- Only consume the wash once the cash is actually credited (AddMoney can be rejected by a money
    -- hook); otherwise the clean cash would vanish from the economy.
    if w.clean > 0 and not p.Functions.AddMoney(Config.payType or 'cash', w.clean, 'laundered-money') then
        notify(src, 'Could not hand over the cash - try collecting again.', 'error')
        busy[src] = nil
        return false
    end
    notify(src, ('Collected $%d clean CASH. Deposit it at a bank to keep it safe.'):format(w.clean), 'success')
    clearWash(point.id)
    busy[src] = nil
    return true
end)

-- ===================== ROB an in-progress wash (contest) =====================
lib.callback.register('pengu_launder:rob', function(src, pointId)
    if busy[src] then return false end
    local point = POINTS[tonumber(pointId) or -1]
    if not point then return false end
    local w = WASH[point.id]
    if not w or w.pending then notify(src, 'Nothing is washing here.', 'error'); return false end
    local p = qbx:GetPlayer(src)
    if not p then return false end
    if cidOf(p) == w.ownerCid then notify(src, 'You cannot rob your own wash - collect it instead.', 'error'); return false end
    if not nearPoint(src, point) then notify(src, 'You are too far from the laundromat.', 'error'); return false end

    busy[src] = true
    local skim = math.floor(w.clean * (Config.robCutPct or 0.5))
    -- Only consume the wash once the skim is actually credited (AddMoney can be hook-rejected).
    if skim > 0 and not p.Functions.AddMoney(Config.payType or 'cash', skim, 'laundered-money-robbed') then
        notify(src, 'Could not grab the cash - try again.', 'error')
        busy[src] = nil
        return false
    end
    notify(src, ('You skimmed $%d in clean cash from the machine.'):format(skim), 'success')
    -- alert the owner if online
    local victim = srcOfCid(w.ownerCid)
    if victim then notify(victim, ('Someone robbed your wash at "%s"! You lost $%d.'):format(point.label, w.clean), 'error') end
    clearWash(point.id)
    busy[src] = nil
    return true
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)

-- ===================== /washloc admin (pdloc recipe) =====================
local function cmdAdd(src, args)
    if src <= 0 then notify(src, 'run this in-game (it needs your position).', 'error'); return end
    local label = (#args >= 2) and table.concat({ table.unpack(args, 2) }, ' '):sub(1, 64) or Config.defaultLabel
    local c = GetEntityCoords(GetPlayerPed(src))
    local okIns = pcall(MySQL.insert.await, 'INSERT INTO pengu_launder_points (label, x, y, z) VALUES (?, ?, ?, ?)',
        { label, c.x + 0.0, c.y + 0.0, c.z + 0.0 })
    if not okIns then notify(src, 'could not add laundromat (db error).', 'error'); return end
    loadPoints(); broadcast()
    notify(src, ('added laundromat "%s" at your position.'):format(label), 'success')
end

local function cmdRemove(src, args)
    local id = tonumber(args[2])
    if not id then notify(src, 'usage: /washloc remove <id>', 'error'); return end
    local affected = MySQL.update.await('DELETE FROM pengu_launder_points WHERE id = ?', { id })
    if affected and affected > 0 then
        if WASH[id] then settleWashOnRemoval(id) end -- pay out any active wash instead of destroying it
        loadPoints(); broadcast(); notify(src, ('removed laundromat #%d.'):format(id), 'success')
    else notify(src, 'no laundromat with that id.', 'error') end
end

local function cmdList(src)
    local any = false
    for _, p in pairs(POINTS) do
        any = true
        local w = WASH[p.id]
        local tag = (w and not w.pending) and (' [washing $%d by %s]'):format(w.amount or 0, w.ownerName or '?') or ''
        notify(src, ('#%d "%s" (%.0f,%.0f,%.0f)%s'):format(p.id, p.label, p.x, p.y, p.z, tag), 'inform')
    end
    if not any then notify(src, 'no laundromats placed.', 'inform') end
end

RegisterCommand('washloc', function(src, args)
    if not IsPlayerAceAllowed(src, ACE) then notify(src, 'you are not allowed to manage laundromats.', 'error'); return end
    if not exports.qbx_core:IsOptin(src) then notify(src, 'you must /aduty before using /washloc.', 'error'); return end
    local sub = tostring(args[1] or ''):lower()
    if     sub == 'add'    then cmdAdd(src, args)
    elseif sub == 'remove' or sub == 'delete' then cmdRemove(src, args)
    elseif sub == 'list'   then cmdList(src)
    else
        notify(src, '/washloc add [label] - add a laundromat at your position', 'inform')
        notify(src, '/washloc remove <id> - delete one', 'inform')
        notify(src, '/washloc list        - list laundromats (shows active washes)', 'inform')
    end
end, false)
