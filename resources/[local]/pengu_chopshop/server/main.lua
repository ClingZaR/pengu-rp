-- PenguRP Chop Shop (pengu_chopshop) - SERVER. Admin-placeable chop points (/choploc, pdloc recipe)
-- + a server-authoritative chop callback that validates the vehicle (exists, near a chop point, NOT
-- player-registered), deletes it, and pays dirty money + parts. ASCII only. luac clean.

local qbx = exports.qbx_core
local ox  = exports.ox_inventory
local ACE = 'pengu.chop'

POINTS = {} -- id -> { id, label, x, y, z }

-- WANTED list: a RANDOM subset of Config.wantedPool that refreshes every Config.wantedRefreshMs (1h).
-- You may ONLY chop a wanted model; miss the window and a fresh random list is drawn. Published to
-- GlobalState.penguChopWanted (names) + penguChopWantedUntil (unix epoch the current list expires) so
-- the mechanic dealer can show the list + a countdown.
local WANTED      = {} -- joaat(model) -> true (the only choppable models right now)
local WANTED_NAME = {} -- joaat(model) -> model name string (stamped onto chopped parts as provenance)
local wantedNames = {} -- current model names (for GlobalState.penguChopWanted)

local function computeWanted()
    local pool = Config.wantedPool or {}
    WANTED, WANTED_NAME, wantedNames = {}, {}, {}
    if #pool == 0 then
        GlobalState.penguChopWanted = {}
        GlobalState.penguChopWantedUntil = 0
        return
    end
    -- Fisher-Yates shuffle a copy, take the first wantedCount (genuinely random each refresh).
    local copy = {}
    for i, m in ipairs(pool) do copy[i] = m end
    for i = #copy, 2, -1 do
        local j = math.random(1, i)
        copy[i], copy[j] = copy[j], copy[i]
    end
    local count = math.min(Config.wantedCount or 3, #copy)
    for i = 1, count do
        WANTED[joaat(copy[i])] = true
        WANTED_NAME[joaat(copy[i])] = copy[i]
        wantedNames[#wantedNames + 1] = copy[i]
    end
    GlobalState.penguChopWanted = wantedNames
    GlobalState.penguChopWantedUntil = os.time() + math.floor((Config.wantedRefreshMs or 3600000) / 1000)
end

CreateThread(function()
    math.randomseed(os.time())
    computeWanted()
    while true do
        Wait(Config.wantedRefreshMs or 3600000) -- refresh (and reset the clock) every hour
        computeWanted()
    end
end)

-- notify() helper: chat feedback via the cross-resource qbx_chat_theme 'pengu:admin' template.
-- Wanted cars are revealed by talking to a mechanic dealer (pengu_dealers); there is no /hotlist command.
local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, msg, kind, tag)
    if not src or src <= 0 then print('[pengu_chopshop] ' .. tostring(msg)); return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { tag or 'CHOP', msg, KIND[kind or 'inform'] or 'info' },
    })
end

local function getCid(src)
    local p = qbx:GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

-- ===================== persistence + replication =====================
local function ensureColumn(tbl, col, ddl)
    local ex = MySQL.scalar.await(
        'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tbl, col })
    if not ex then MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(tbl, ddl)) end
end

local function loadPoints()
    local rows = MySQL.query.await('SELECT id, label, x, y, z FROM pengu_chop_points ORDER BY id') or {}
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
    TriggerClientEvent('pengu_chop:pointsUpdated', -1, pointArray())
end

lib.callback.register('pengu_chop:getPoints', function(_) return pointArray() end)

-- ===================== boot =====================
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_chop_points (
                id         INT AUTO_INCREMENT PRIMARY KEY,
                label      VARCHAR(64) NOT NULL DEFAULT '',
                x          FLOAT       NOT NULL,
                y          FLOAT       NOT NULL,
                z          FLOAT       NOT NULL,
                created_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ]])
        ensureColumn('pengu_chop_points', 'label', "`label` VARCHAR(64) NOT NULL DEFAULT ''")
        local cnt = MySQL.scalar.await('SELECT COUNT(*) FROM pengu_chop_points')
        if (tonumber(cnt) or 0) == 0 then
            for _, s in ipairs(Config.seeds or {}) do
                MySQL.insert.await('INSERT INTO pengu_chop_points (label, x, y, z) VALUES (?, ?, ?, ?)',
                    { s.label or Config.defaultLabel, s.x + 0.0, s.y + 0.0, s.z + 0.0 })
            end
            print(('[pengu_chopshop] seeded %d chop point(s)'):format(#(Config.seeds or {})))
        end
        loadPoints()
    end)
    if not ok then print('[pengu_chopshop] BOOT FAILED: ' .. tostring(err)) end
    broadcast()
    local n = 0; for _ in pairs(POINTS) do n = n + 1 end
    print(('[pengu_chopshop] %s (%d chop points).'):format(ok and 'ready' or 'DEGRADED', n))
end)

-- ===================== chop (server-authoritative) =====================
local busy = {}        -- src -> true while a chop is mid-flight
local cooldowns = {}   -- src -> next-allowed GetGameTimer()
local choppingVeh = {} -- netId -> true while a vehicle is being chopped (cross-player lock)

lib.callback.register('pengu_chop:chop', function(src, netId)
    -- Lock BEFORE any await. The player_vehicles lookup yields; if the lock were taken after it, two
    -- concurrent calls for the same vehicle would both pass, both DeleteEntity (2nd is a no-op) and
    -- both pay = double payout. Acquire src + per-vehicle locks here, with NO await in between.
    if busy[src] then return false end
    netId = tonumber(netId) or -1
    local now = GetGameTimer()
    if cooldowns[src] and now < cooldowns[src] then
        notify(src, ('Lay low - %ds before the next job.'):format(math.ceil((cooldowns[src] - now) / 1000)), 'error')
        return false
    end

    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return false end
    if choppingVeh[netId] then return false end

    busy[src] = true
    choppingVeh[netId] = true

    local result = false
    pcall(function()
        -- near a chop point?
        local atChop = false
        local vcoords = GetEntityCoords(veh)
        for _, p in pairs(POINTS) do
            if #(vcoords - vector3(p.x, p.y, p.z)) <= (Config.zoneRadius or 30.0) then atChop = true; break end
        end
        if not atChop then notify(src, 'Get the vehicle inside the chop shop.', 'error'); return end

        -- reject PLAYER-REGISTERED vehicles entirely (no self-farm, no griefing owned cars). YIELDS.
        -- Normalize BOTH sides (strip whitespace + upper) so the match is robust to plate spacing, and
        -- REJECT a blank plate rather than skipping the check (an empty plate must not bypass it).
        local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('%s+', ''):upper()
        if plate == '' then
            notify(src, 'That plate is unreadable - cannot process it here.', 'error'); return
        end
        local owner = MySQL.scalar.await(
            "SELECT citizenid FROM player_vehicles WHERE UPPER(REPLACE(plate, ' ', '')) = ?", { plate })
        if owner then notify(src, 'This vehicle is registered to someone - too hot to chop.', 'error'); return end

        -- re-validate after the await (the vehicle could have despawned / been deleted meanwhile)
        if not DoesEntityExist(veh) then return end

        -- ONLY wanted models can be chopped (the list rotates hourly; the mechanic shows it).
        if not (WANTED[GetEntityModel(veh)] == true) then
            notify(src, 'This model is not wanted right now - check the mechanic for the current chop list.', 'error'); return
        end

        -- optional tool gate: OFF by default (the shop has everything), but honour Config.requireTool if
        -- an admin sets it to an item name so the config knob actually works.
        if Config.requireTool and Config.requireTool ~= false and Config.requireTool ~= '' then
            if (ox:Search(src, 'count', Config.requireTool) or 0) < 1 then
                notify(src, ('You need a %s to strip a car here.'):format(Config.requireTool), 'error'); return
            end
        end

        -- Roll a RANDOM subset of CAR PARTS (distinct kinds vary per car).
        local pool = {}
        for _, part in ipairs(Config.parts or {}) do pool[#pool + 1] = part end
        for i = #pool, 2, -1 do local j = math.random(1, i); pool[i], pool[j] = pool[j], pool[i] end
        local ppc    = Config.partsPerChop or { min = 3, max = 5 }
        local nKinds = math.min(#pool, math.random(ppc.min or 3, ppc.max or 5))
        local rolled = {}
        for i = 1, nKinds do
            local part = pool[i]
            local n = math.random(part.min or 1, part.max or 1)
            if n > 0 then rolled[#rolled + 1] = { item = part.item, count = n } end
        end

        -- Verify the player can CARRY the WHOLE payout BEFORE destroying the car. Per-item CanCarryItem
        -- does NOT reserve space, so several heavy parts can each pass alone yet not fit together (the
        -- first AddItem would succeed, the rest silently fail = lost parts). So ALSO sum the total weight
        -- and check it once with CanCarryWeight.
        local defs = ox:Items()
        local totalWeight = 0
        for _, rp in ipairs(rolled) do
            local def = defs and defs[rp.item]
            totalWeight = totalWeight + ((def and def.weight or 0) * rp.count)
            if not ox:CanCarryItem(src, rp.item, rp.count) then
                notify(src, 'Your inventory is too full for the parts - clear some space first.', 'error'); return
            end
        end
        if totalWeight > 0 and not ox:CanCarryWeight(src, totalWeight) then
            notify(src, 'Those parts are too heavy to carry all at once - clear some space first.', 'error'); return
        end

        -- stamp each part with the SOURCE car so a mechanic dealer can later verify it came from a
        -- currently-wanted model (the wanted list rotates; stale parts must not still sell).
        local mdl  = WANTED_NAME[GetEntityModel(veh)]
        local meta = mdl and { model = mdl, description = ('Stripped from a %s.'):format(mdl) } or nil

        DeleteEntity(veh)
        for _, rp in ipairs(rolled) do ox:AddItem(src, rp.item, rp.count, meta) end

        cooldowns[src] = now + (Config.cooldown or 0)
        notify(src, 'Stripped the car for parts - move them to a mechanic dealer to cash out.', 'success')
        -- XP + gang rep
        pcall(function()
            exports.pengu_xp:Award(src, 'criminal', 100)
            local p = qbx:GetPlayer(src)
            local g = p and p.PlayerData and p.PlayerData.gang
            if g and g.name and g.name ~= 'none' then
                exports.pengu_gangs:AddRep(g.name, 75)
            end
        end)
        result = true
    end)

    busy[src] = nil
    choppingVeh[netId] = nil
    return result
end)

AddEventHandler('playerDropped', function() busy[source] = nil; cooldowns[source] = nil end)

-- ===================== /choploc admin (pdloc recipe) =====================
local function cmdAdd(src, args)
    if src <= 0 then notify(src, 'run this in-game (it needs your position).', 'error'); return end
    local label = (#args >= 2) and table.concat({ table.unpack(args, 2) }, ' '):sub(1, 64) or Config.defaultLabel
    local c = GetEntityCoords(GetPlayerPed(src))
    local okIns = pcall(MySQL.insert.await, 'INSERT INTO pengu_chop_points (label, x, y, z) VALUES (?, ?, ?, ?)',
        { label, c.x + 0.0, c.y + 0.0, c.z + 0.0 })
    if not okIns then notify(src, 'could not add chop point (db error).', 'error'); return end
    loadPoints(); broadcast()
    notify(src, ('added chop point "%s" at your position.'):format(label), 'success')
end

local function cmdRemove(src, args)
    local id = tonumber(args[2])
    if not id then notify(src, 'usage: /choploc remove <id>', 'error'); return end
    local affected = MySQL.update.await('DELETE FROM pengu_chop_points WHERE id = ?', { id })
    if affected and affected > 0 then loadPoints(); broadcast(); notify(src, ('removed chop point #%d.'):format(id), 'success')
    else notify(src, 'no chop point with that id.', 'error') end
end

local function cmdList(src)
    local any = false
    for _, p in pairs(POINTS) do
        any = true
        notify(src, ('#%d "%s" (%.0f,%.0f,%.0f)'):format(p.id, p.label, p.x, p.y, p.z), 'inform')
    end
    if not any then notify(src, 'no chop points placed.', 'inform') end
end

RegisterCommand('choploc', function(src, args)
    if not IsPlayerAceAllowed(src, ACE) then notify(src, 'you are not allowed to manage chop points.', 'error'); return end
    if not exports.qbx_core:IsOptin(src) then notify(src, 'you must /aduty before using /choploc.', 'error'); return end
    local sub = tostring(args[1] or ''):lower()
    if     sub == 'add'    then cmdAdd(src, args)
    elseif sub == 'remove' or sub == 'delete' then cmdRemove(src, args)
    elseif sub == 'list'   then cmdList(src)
    else
        notify(src, '/choploc add [label] - add a chop point at your position', 'inform')
        notify(src, '/choploc remove <id> - delete one', 'inform')
        notify(src, '/choploc list        - list chop points', 'inform')
    end
end, false)
