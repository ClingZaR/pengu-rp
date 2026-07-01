-- PenguRP Civilian Gathering Jobs (pengu_jobs) - SERVER. Admin-placeable gather/sell points
-- (/jobloc, pdloc recipe) + server-authoritative gather + sell callbacks. ASCII only. luac clean.

local qbx = exports.qbx_core
local ox  = exports.ox_inventory
local ACE = 'pengu.jobs'

POINTS = {} -- id -> { id, ptype, label, x, y, z }

local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, msg, kind, tag)
    if not src or src <= 0 then print('[pengu_jobs] ' .. tostring(msg)); return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { tag or 'JOBS', msg, KIND[kind or 'inform'] or 'info' },
    })
end

local function isKnownType(pt)
    return (Config.gatherTypes and Config.gatherTypes[pt] ~= nil)
        or (Config.sellTypes and Config.sellTypes[pt] ~= nil)
        or (Config.shopTypes and Config.shopTypes[pt] ~= nil)
end

-- ===================== persistence + replication =====================
local function ensureColumn(tbl, col, ddl)
    local ex = MySQL.scalar.await(
        'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tbl, col })
    if not ex then MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(tbl, ddl)) end
end

local function loadPoints()
    local rows = MySQL.query.await('SELECT id, ptype, label, x, y, z FROM pengu_job_points ORDER BY id') or {}
    local t = {}
    for _, r in ipairs(rows) do
        t[r.id] = { id = r.id, ptype = r.ptype, label = r.label, x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0 }
    end
    POINTS = t
    return t
end

local function pointArray()
    local arr = {}
    for _, p in pairs(POINTS) do arr[#arr + 1] = p end
    return arr
end

local function broadcast() TriggerClientEvent('pengu_jobs:pointsUpdated', -1, pointArray()) end
lib.callback.register('pengu_jobs:getPoints', function(_) return pointArray() end)

-- ===================== boot =====================
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_job_points (
                id         INT AUTO_INCREMENT PRIMARY KEY,
                ptype      VARCHAR(32) NOT NULL,
                label      VARCHAR(64) NOT NULL DEFAULT '',
                x          FLOAT       NOT NULL,
                y          FLOAT       NOT NULL,
                z          FLOAT       NOT NULL,
                created_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ]])
        ensureColumn('pengu_job_points', 'label', "`label` VARCHAR(64) NOT NULL DEFAULT ''")
        local cnt = MySQL.scalar.await('SELECT COUNT(*) FROM pengu_job_points')
        if (tonumber(cnt) or 0) == 0 then
            for _, s in ipairs(Config.seeds or {}) do
                if isKnownType(s.ptype) then
                    MySQL.insert.await('INSERT INTO pengu_job_points (ptype, label, x, y, z) VALUES (?, ?, ?, ?, ?)',
                        { s.ptype, s.label or Config.defaultLabel, s.x + 0.0, s.y + 0.0, s.z + 0.0 })
                end
            end
            print(('[pengu_jobs] seeded %d job point(s)'):format(#(Config.seeds or {})))
        end
        loadPoints()
    end)
    if not ok then print('[pengu_jobs] BOOT FAILED: ' .. tostring(err)) end
    broadcast()
    local n = 0; for _ in pairs(POINTS) do n = n + 1 end
    print(('[pengu_jobs] %s (%d points).'):format(ok and 'ready' or 'DEGRADED', n))
end)

-- ===================== shared helpers =====================
local function nearPoint(src, point)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z)) <= (Config.interactDist + 2.0)
end

-- ===================== gather (server-authoritative) =====================
local busy = {}
local cooldowns = {}

lib.callback.register('pengu_jobs:gather', function(src, pointId, recipeIdx)
    if busy[src] then return false end
    local point = POINTS[tonumber(pointId) or -1]
    local def = point and Config.gatherTypes[point.ptype]
    local recipe = def and def.recipes and def.recipes[tonumber(recipeIdx) or -1]
    if not recipe then return false end

    local cdKey, now = ('%d|%d'):format(point.id, tonumber(recipeIdx)), GetGameTimer()
    if recipe.cooldown and recipe.cooldown > 0 then
        local mine = cooldowns[src]
        if mine and mine[cdKey] and now < mine[cdKey] then
            notify(src, ('Rest a moment - %ds.'):format(math.ceil((mine[cdKey] - now) / 1000)), 'error'); return false
        end
    end
    if not nearPoint(src, point) then notify(src, 'You are too far from the spot.', 'error'); return false end
    -- tool requirement (read-only check, NOT consumed - you just need to hold the tool)
    if recipe.tool and (ox:Search(src, 'count', recipe.tool) or 0) < 1 then
        notify(src, ('You need a %s to do this.'):format(recipe.tool), 'error'); return false
    end

    busy[src] = true
    local okDone = false
    -- inputs (mining is empty-input); ordered: check inputs -> CanCarry outputs -> remove -> add
    for item, qty in pairs(recipe.input or {}) do
        if (ox:Search(src, 'count', item) or 0) < qty then notify(src, 'You lack the materials.', 'error'); busy[src] = nil; return false end
    end
    for item, qty in pairs(recipe.output or {}) do
        if not ox:CanCarryItem(src, item, qty) then notify(src, 'Your inventory is full.', 'error'); busy[src] = nil; return false end
    end
    local removed = {}
    for item, qty in pairs(recipe.input or {}) do
        if ox:RemoveItem(src, item, qty) then removed[item] = (removed[item] or 0) + qty
        else for ri, rq in pairs(removed) do ox:AddItem(src, ri, rq) end; busy[src] = nil; return false end
    end
    for item, qty in pairs(recipe.output or {}) do
        if item == '__stress__' then
            -- virtual output: relieve stress instead of giving an item
            local p2 = qbx:GetPlayer(src)
            if p2 then
                local cur = tonumber(p2.PlayerData.metadata.stress) or 0
                local nxt = math.max(0, cur - math.abs(qty))
                p2.Functions.SetMetaData('stress', nxt)
                TriggerClientEvent('hud:client:UpdateStress', src, nxt)
            end
        elseif not ox:AddItem(src, item, qty) then
            notify(src, 'Inventory full - some materials were dropped.', 'error')
        end
    end
    okDone = true

    if okDone and recipe.cooldown and recipe.cooldown > 0 then
        cooldowns[src] = cooldowns[src] or {}
        cooldowns[src][cdKey] = GetGameTimer() + recipe.cooldown
    end
    busy[src] = nil
    if okDone then
        notify(src, ('Gathered %s.'):format(recipe.label or 'materials'), 'success')
        TriggerEvent('pengu_xp:onGather', src, point.ptype)
    end
    return okDone
end)

-- ===================== sell (server-authoritative) =====================
lib.callback.register('pengu_jobs:sell', function(src, pointId, item)
    if busy[src] then return false end
    local point = POINTS[tonumber(pointId) or -1]
    local def = point and Config.sellTypes[point.ptype]
    local price = def and def.prices and def.prices[item]
    if not price or price <= 0 then return false end
    if not nearPoint(src, point) then notify(src, 'You are too far from the dealer.', 'error'); return false end

    busy[src] = true
    local result = false
    local count = ox:Search(src, 'count', item) or 0
    if count <= 0 then
        notify(src, 'You have none of that to sell.', 'error')
    elseif ox:RemoveItem(src, item, count) then
        local total = count * price
        local p = qbx:GetPlayer(src)
        if p and p.Functions and p.Functions.AddMoney
            and p.Functions.AddMoney(def.account or 'bank', total, 'job-sale') then
            notify(src, ('Sold %dx %s for $%d.'):format(count, item, total), 'success')
            TriggerEvent('pengu_xp:onSell', src, point.ptype)
            result = true
        else
            ox:AddItem(src, item, count) -- refund if the payout did not apply
            notify(src, 'Sale failed - items returned.', 'error')
        end
    else
        notify(src, 'Sale failed.', 'error')
    end
    busy[src] = nil
    return result
end)

-- ===================== shop buy (server-authoritative) - SELLS items TO players =====================
lib.callback.register('pengu_jobs:shopBuy', function(src, pointId, item)
    if busy[src] then return false end
    local point = POINTS[tonumber(pointId) or -1]
    local def = point and Config.shopTypes and Config.shopTypes[point.ptype]
    local price = def and def.items and def.items[item]
    if not price or price <= 0 then return false end
    if not nearPoint(src, point) then notify(src, 'You are too far from the shop.', 'error'); return false end

    busy[src] = true
    local result = false
    local p = qbx:GetPlayer(src)
    local acct = def.account or 'bank'
    local bal = (p and p.Functions and p.Functions.GetMoney and p.Functions.GetMoney(acct)) or 0
    if not p then
        -- no player object; nothing to do
    elseif bal < price then
        notify(src, ('You need $%d.'):format(price), 'error')
    elseif not ox:CanCarryItem(src, item, 1) then
        notify(src, 'You cannot carry that.', 'error')
    elseif p.Functions.RemoveMoney(acct, price, 'job-tool') then
        if ox:AddItem(src, item, 1) then
            notify(src, ('Bought %s for $%d.'):format(item, price), 'success')
            result = true
        else
            p.Functions.AddMoney(acct, price, 'job-tool-refund') -- refund if the item could not be given
            notify(src, 'Purchase failed - could not carry the item.', 'error')
        end
    else
        notify(src, 'Purchase failed.', 'error')
    end
    busy[src] = nil
    return result
end)

AddEventHandler('playerDropped', function() busy[source] = nil; cooldowns[source] = nil end)

-- ===================== /jobloc admin (pdloc recipe) =====================
local function cmdAdd(src, args)
    if src <= 0 then notify(src, 'run this in-game (it needs your position).', 'error'); return end
    local ptype = tostring(args[2] or ''):lower()
    if not isKnownType(ptype) then notify(src, ('invalid type "%s".'):format(ptype), 'error'); return end
    local label = (#args >= 3) and table.concat({ table.unpack(args, 3) }, ' '):sub(1, 64) or Config.defaultLabel
    local c = GetEntityCoords(GetPlayerPed(src))
    local okIns = pcall(MySQL.insert.await, 'INSERT INTO pengu_job_points (ptype, label, x, y, z) VALUES (?, ?, ?, ?, ?)',
        { ptype, label, c.x + 0.0, c.y + 0.0, c.z + 0.0 })
    if not okIns then notify(src, 'could not add point (db error).', 'error'); return end
    loadPoints(); broadcast()
    notify(src, ('added %s point "%s" at your position.'):format(ptype, label), 'success')
end

local function cmdRemove(src, args)
    local id = tonumber(args[2])
    if not id then notify(src, 'usage: /jobloc remove <id>', 'error'); return end
    local affected = MySQL.update.await('DELETE FROM pengu_job_points WHERE id = ?', { id })
    if affected and affected > 0 then loadPoints(); broadcast(); notify(src, ('removed point #%d.'):format(id), 'success')
    else notify(src, 'no point with that id.', 'error') end
end

local function cmdList(src)
    local any = false
    for _, p in pairs(POINTS) do
        any = true
        notify(src, ('#%d %s "%s" (%.0f,%.0f,%.0f)'):format(p.id, p.ptype, p.label, p.x, p.y, p.z), 'inform')
    end
    if not any then notify(src, 'no job points placed.', 'inform') end
end

RegisterCommand('jobloc', function(src, args)
    if not IsPlayerAceAllowed(src, ACE) then notify(src, 'you are not allowed to manage job points.', 'error'); return end
    if not exports.qbx_core:IsOptin(src) then notify(src, 'you must /aduty before using /jobloc.', 'error'); return end
    local sub = tostring(args[1] or ''):lower()
    if     sub == 'add'    then cmdAdd(src, args)
    elseif sub == 'remove' or sub == 'delete' then cmdRemove(src, args)
    elseif sub == 'list'   then cmdList(src)
    else
        local types = {}
        for k in pairs(Config.gatherTypes) do types[#types + 1] = k end
        for k in pairs(Config.sellTypes) do types[#types + 1] = k end
        notify(src, '/jobloc add <type> [label] | remove <id> | list', 'inform')
        notify(src, 'types: ' .. table.concat(types, ', '), 'inform')
    end
end, false)
