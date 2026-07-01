-- PenguRP Black Market (pengu_blackmarket) - SERVER. Exposes the arms CATALOG + a server-authoritative
-- OrderWeapon(src, catIdx) export (gang-gated + level + black_money + discounts), called by the placeable
-- "weapons" Arms Dealer in pengu_dealers. SMALL goods (ammo/attachments) are handed over instantly;
-- WEAPONS are NOT - ordering a weapon spawns an illegal CRATE DROP at a random drop site
-- (GlobalState.penguCrates). The buyer drives there, PICKS UP the crate (carries it), can DROP it
-- anywhere, then PRIES IT OPEN with a crowbar to recover the weapon. Crates are runtime (no DB).
-- ASCII only. luac clean.

local qbx = exports.qbx_core
local ox  = exports.ox_inventory

local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, msg, kind)
    if not src or src <= 0 then return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { 'MARKET', msg, KIND[kind or 'inform'] or 'info' },
    })
end

local function playerOf(src) return qbx:GetPlayer(src) end
local function cidOf(src)
    local p = playerOf(src)
    return p and p.PlayerData and p.PlayerData.citizenid
end

-- criminal gang key for a source, or nil (mirrors pengu_core resolveFaction criminal path).
local function gangOf(src)
    local p = playerOf(src)
    local g = p and p.PlayerData and p.PlayerData.gang
    local name = g and g.name
    if not name or name == 'none' or not Factions.isCriminal(name) then return nil end
    return name
end

local function srcOfCid(cid)
    for src, p in pairs(qbx:GetQBPlayers() or {}) do
        if p.PlayerData and p.PlayerData.citizenid == cid then return src end
    end
end

-- does this player physically have a crowbar on them right now?
local function hasCrowbar(src)
    return (ox:Search(src, 'count', Config.crowbarItem) or 0) >= 1
end

-- (The roving dealer was retired: weapons are now sold by placeable, gang-controllable "weapons" dealers
-- in pengu_dealers, which call the OrderWeapon export below. This resource only owns the crate drops.)

-- ===================== weapon crate drops =====================
-- CRATES is a resource-wide GLOBAL (no `local`) so the admin/test commands lower in this file can
-- reach it. state = 'dropped' (sitting in the world) or 'carried' (on a player's back).
CRATES = {} -- id -> { id, ownerCid, item, label, x, y, z, state, carrier, expiresAt }
local crateSeq = 0

-- publish ONLY dropped crates - carried crates are rendered locally by their carrier.
local function publishCrates()
    local out = {}
    for id, c in pairs(CRATES) do
        if c.state == 'dropped' then
            out[tostring(id)] = { ownerCid = c.ownerCid, x = c.x, y = c.y, z = c.z, label = c.label }
        end
    end
    GlobalState.penguCrates = out
end

-- clear any stale bag left over from a previous resource lifetime: GlobalState persists for the whole
-- server process, but in-memory CRATES resets to {} on a resource restart. Without this, a restart would
-- leave clients rendering phantom, uninteractable crates the server no longer knows about.
publishCrates()

-- core crate creator. site = { x, y, z, label }. Returns the new crate id.
local function makeCrate(ownerCid, ownerGang, item, label, site, expireSecs)
    crateSeq = crateSeq + 1
    local id = crateSeq
    CRATES[id] = {
        id = id, ownerCid = ownerCid, ownerGang = ownerGang, item = item, label = label or item,
        x = site.x + 0.0, y = site.y + 0.0, z = site.z + 0.0,
        state = 'dropped', carrier = nil, locked = false, claim = nil,
        expiresAt = os.time() + (expireSecs or Config.crateExpire or 1800),
    }
    publishCrates()
    return id
end

local function spawnCrate(src, entry, gang)
    local sites = Config.dropSites or {}
    if #sites == 0 then return false end
    local site = sites[math.random(#sites)]
    -- crate_speed zone perk: holding that zone type trims expiry by 30%
    local expireBase = Config.crateExpire or 1800
    if gang then
        local ok, hp = pcall(function() return exports.pengu_turf:HasPerk(gang, 'crate_speed') end)
        if ok and hp then expireBase = math.floor(expireBase * 0.70) end
    end
    makeCrate(cidOf(src), gang, entry.item, entry.label or entry.item, site, expireBase)
    TriggerClientEvent('pengu_blackmarket:shipmentOrdered', src,
        { x = site.x + 0.0, y = site.y + 0.0, z = site.z + 0.0, label = site.label or 'drop site' })
    notify(src, ('Shipment paid. Your %s drops at %s - get there, grab the crate and crack it open with a crowbar.')
        :format(entry.label or 'weapon', site.label or 'the drop'), 'success')
    -- alert police to the arms deal at the buyer's location (i.e. the weapons dealer they bought from)
    pcall(function()
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            exports.pengu_core:Dispatch(
                vector3(c.x, c.y, c.z),
                { message = 'Illegal Arms Deal in Progress', code = '10-57',
                  icon = 'fas fa-gun', priority = 1, jobs = { 'police', 'bcso', 'sasp' } }
            )
        end
    end)
    return true
end

-- expire undelivered crates (carried crates do not expire - the owner is actively handling them)
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        local changed = false
        for id, c in pairs(CRATES) do
            if c.state == 'dropped' and c.expiresAt and c.expiresAt <= now then
                CRATES[id] = nil; changed = true
                local owner = srcOfCid(c.ownerCid)
                if owner then notify(owner, ('Your %s shipment was seized - you never collected it.'):format(c.label or 'weapon'), 'error') end
            end
        end
        if changed then publishCrates() end
    end
end)

-- ===================== order a weapon/good (server export; called by pengu_dealers) =====================
local busy = {}

-- Validates criminal gang + level + dirty money (with gang/zone discounts), then either schedules a
-- CRATE DROP (weapons) or hands the goods over instantly (ammo/attachments). PROXIMITY is the CALLER's
-- responsibility: pengu_dealers checks the player is at its weapons dealer before calling this.
-- catIdx indexes Config.catalog (see the GetCatalog export). Returns true on success.
local function orderWeapon(src, catIdx)
    if busy[src] then return false end
    local gang = gangOf(src)
    if not gang then notify(src, 'You have no contacts - join a crew.', 'error'); return false end -- gang only

    local entry = Config.catalog and Config.catalog[tonumber(catIdx) or -1]
    if not entry then return false end

    -- level gate: gang must have reached the item's minimum level (guarded - degrade to level 1 if down)
    local okL, gangLevel = pcall(function() return exports.pengu_gangs:GetLevel(gang) end)
    gangLevel = (okL and tonumber(gangLevel)) or 1
    if (entry.minLevel or 1) > gangLevel then
        notify(src, ('Your crew needs to reach level %d to order that.'):format(entry.minLevel or 1), 'error')
        return false
    end

    busy[src] = true
    local result = false
    local price = tonumber(entry.price) or 0
    -- apply level discount (pengu_gangs) + zone import_discount perk (pengu_turf)
    local okP, perks   = pcall(function() return exports.pengu_gangs:GetLevelPerks(gang) end)
    local lvlDiscount  = (okP and perks and perks.importDiscount) or 0.0
    local zoneDiscount = 0.0
    local zpOk, zpHas  = pcall(function() return exports.pengu_turf:HasPerk(gang, 'import_discount') end)
    if zpOk and zpHas then zoneDiscount = 0.10 end
    if lvlDiscount + zoneDiscount > 0 then
        price = math.max(1, math.floor(price * (1.0 - lvlDiscount - zoneDiscount)))
    end
    local have = ox:Search(src, 'count', Config.dirtyItem) or 0
    if price <= 0 then
        -- misconfigured entry; do nothing
    elseif have < price then
        notify(src, ('You need $%d in dirty money.'):format(price), 'error')
    elseif entry.weapon then
        -- weapons are NOT handed over: take payment, schedule a crate drop to go retrieve.
        if ox:RemoveItem(src, Config.dirtyItem, price) then
            if spawnCrate(src, entry, gang) then
                result = true
            else
                ox:AddItem(src, Config.dirtyItem, price) -- refund if no drop site configured
                notify(src, 'No drop could be arranged. Money returned.', 'error')
            end
        else
            notify(src, 'Deal fell through.', 'error')
        end
    elseif not ox:CanCarryItem(src, entry.item, entry.count or 1) then
        notify(src, 'You cannot carry that.', 'error')
    elseif ox:RemoveItem(src, Config.dirtyItem, price) then
        ox:AddItem(src, entry.item, entry.count or 1)
        notify(src, ('Bought %s for $%d dirty.'):format(entry.label or entry.item, price), 'success')
        result = true
    else
        notify(src, 'Deal fell through.', 'error')
    end
    busy[src] = nil
    return result
end
exports('OrderWeapon', orderWeapon)

-- the arms catalog (item/label/price/weapon/count/minLevel) so pengu_dealers can build its buy menu.
exports('GetCatalog', function() return Config.catalog end)

-- ===================== pick up / carry / drop =====================
-- the OWNER picks up their crate to carry it (so they can move it somewhere safe before opening).
lib.callback.register('pengu_blackmarket:pickup', function(src, crateId)
    if busy[src] then return false end
    local c = CRATES[tonumber(crateId) or -1]
    if not c then notify(src, 'The crate is gone.', 'error'); return false end
    if c.state ~= 'dropped' then notify(src, 'That crate is already being moved.', 'error'); return false end
    if cidOf(src) ~= c.ownerCid then notify(src, 'This shipment is not yours.', 'error'); return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    if #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) > (Config.crateDist + 3.0) then
        notify(src, 'You are not at the crate.', 'error'); return false
    end

    c.state = 'carried'
    c.carrier = src
    c.claim = nil -- any rival intercept claim is void once the crate moves
    c.expiresAt = nil -- pause expiry while it is being carried
    publishCrates() -- drops it from the world view; the carrier renders it on their back
    return true
end)

-- set a carried crate back down at the carrier's CURRENT (server-side) position.
lib.callback.register('pengu_blackmarket:dropCarried', function(src, crateId)
    local c = CRATES[tonumber(crateId) or -1]
    if not c or c.carrier ~= src then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    c.x, c.y, c.z = coords.x + 0.0, coords.y + 0.0, coords.z + 0.0
    c.state = 'dropped'
    c.carrier = nil
    c.claim = nil -- a freshly dropped crate must be claimed again before it can be intercepted
    c.expiresAt = os.time() + (Config.crateExpire or 1800)
    publishCrates()
    return true
end)

-- ===================== pry a crate open (owner) =====================
-- requires a crowbar; only works on a DROPPED crate (carry it down first).
lib.callback.register('pengu_blackmarket:retrieve', function(src, crateId)
    if busy[src] then return false end
    local c = CRATES[tonumber(crateId) or -1]
    if not c then notify(src, 'The crate is gone.', 'error'); return false end
    if c.state ~= 'dropped' then notify(src, 'Set the crate down before you crack it.', 'error'); return false end
    if cidOf(src) ~= c.ownerCid then notify(src, 'This shipment is not yours.', 'error'); return false end
    if not hasCrowbar(src) then notify(src, 'You need a crowbar to pry it open.', 'error'); return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    if #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) > (Config.crateDist + 3.0) then
        notify(src, 'You are not at the crate.', 'error'); return false
    end
    if c.locked then notify(src, 'Someone is already cracking that crate.', 'error'); return false end

    busy[src] = true
    c.locked = true -- reserve the crate independently of which source acts (prevents any double-grant)
    local result = false
    if not ox:CanCarryItem(src, c.item, 1) then
        notify(src, 'You need a free inventory slot for the weapon - clear some space, the crate is still here.', 'error')
    elseif ox:AddItem(src, c.item, 1) then
        notify(src, ('You pried the crate open: %s.'):format(c.label or 'weapon'), 'success')
        CRATES[c.id] = nil -- only consume the crate once the item is actually in the inventory
        publishCrates()
        -- award gang rep + personal XP for a successful import
        local rGang = gangOf(src)
        if rGang then
            pcall(function()
                exports.pengu_gangs:AddRep(rGang, exports.pengu_gangs:RepValue('crateImport'))
            end)
        end
        TriggerEvent('pengu_xp:onCrime', src, 100)
        result = true
    else
        notify(src, 'You need a free inventory slot for the weapon - clear some space, the crate is still here.', 'error') -- crate preserved for a retry
    end
    c.locked = false
    busy[src] = nil
    return result
end)

-- ===================== intercept a crate (rival gang) =====================
-- Any criminal gang member from a DIFFERENT gang can crack a rival's DROPPED crate - needs a crowbar.
-- Difficulty is server-authoritative: the rival must CLAIM the crate (step 1) before the client runs its
-- skillcheck/progress, then COMPLETE it (step 2) only after enough real time has elapsed - so a scripted
-- client cannot jump straight to a finished grab.
local function rivalCheck(src, c)
    if not c then return false, 'The crate is already gone.' end
    if c.state ~= 'dropped' then return false, 'The crate is already gone.' end
    if cidOf(src) == c.ownerCid then return false, 'This is your own shipment - open it normally.' end
    local g = gangOf(src)
    if not g then return false, 'You are not in a gang.' end
    if c.ownerGang and g == c.ownerGang then return false, "That is your own crew's shipment." end
    if not hasCrowbar(src) then return false, 'You need a crowbar to crack it.' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, nil end
    if #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) > (Config.crateDist + 3.0) then
        return false, 'You are not close enough to the crate.'
    end
    return true
end

-- step 1: stake a claim before the client does its work
lib.callback.register('pengu_blackmarket:beginIntercept', function(src, crateId)
    local c = CRATES[tonumber(crateId) or -1]
    local ok, msg = rivalCheck(src, c)
    if not ok then if msg then notify(src, msg, 'error') end return false end
    if c.locked then notify(src, 'Someone is already cracking that crate.', 'error'); return false end
    if c.claim and c.claim.src ~= src and (os.time() - c.claim.at) < (Config.interceptClaimWindow or 30) then
        notify(src, 'A rival is already cracking that crate.', 'error'); return false
    end
    c.claim = { src = src, at = os.time() }
    return true
end)

-- step 2: complete the interception (validates the claim + minimum elapsed time + a fresh re-check)
lib.callback.register('pengu_blackmarket:stealCrate', function(src, crateId)
    if busy[src] then return false end
    local c = CRATES[tonumber(crateId) or -1]
    local ok, msg = rivalCheck(src, c)
    if not ok then if msg then notify(src, msg, 'error') end return false end
    if not c.claim or c.claim.src ~= src then notify(src, 'You have not started cracking that crate.', 'error'); return false end
    if (os.time() - c.claim.at) < (Config.interceptMinSeconds or 4) then notify(src, 'Not so fast.', 'error'); return false end
    if c.locked then notify(src, 'Someone is already cracking that crate.', 'error'); return false end

    busy[src] = true
    c.locked = true
    local result = false
    if not ox:CanCarryItem(src, c.item, 1) then
        notify(src, 'You need a free inventory slot for the weapon - clear some space, the crate is still here.', 'error')
    elseif ox:AddItem(src, c.item, 1) then
        notify(src, ('Intercepted the %s.'):format(c.label or 'weapon'), 'success')
        -- alert the original owner if online
        local ownerSrc = srcOfCid(c.ownerCid)
        if ownerSrc then notify(ownerSrc, ('Your %s shipment was intercepted by a rival.'):format(c.label or 'the drop'), 'error') end
        CRATES[c.id] = nil
        publishCrates()
        -- award rep to the intercepting gang (half of normal import rep)
        local tGang = gangOf(src)
        if tGang then
            pcall(function()
                local base = (exports.pengu_gangs:RepValue('crateImport') or 300)
                exports.pengu_gangs:AddRep(tGang, math.floor(base * 0.5))
            end)
        end
        TriggerEvent('pengu_xp:onCrime', src, 100)
        result = true
    else
        notify(src, 'You need a free inventory slot for the weapon - clear some space, the crate is still here.', 'error')
    end
    c.locked = false
    busy[src] = nil
    return result
end)

-- if a carrier disconnects, set their crate back down where it was picked up so it is not lost.
AddEventHandler('playerDropped', function()
    local src = source
    busy[src] = nil
    local changed = false
    for _, c in pairs(CRATES) do
        if c.claim and c.claim.src == src then c.claim = nil end
        if c.carrier == src then
            c.state = 'dropped'
            c.carrier = nil
            c.claim = nil
            c.expiresAt = os.time() + (Config.crateExpire or 1800)
            changed = true
        end
    end
    if changed then publishCrates() end
end)

-- ===================== admin / test commands =====================
-- gated by the pengu.blackmarket ace (granted to owners in server.cfg) OR any admin principal.
local function isAdmin(src)
    if src == 0 then return true end -- server console
    return IsPlayerAceAllowed(src, 'pengu.blackmarket')
        or IsPlayerAceAllowed(src, 'group.admin')
        or IsPlayerAceAllowed(src, 'admin')
        or IsPlayerAceAllowed(src, 'command')
end

-- /givecrowbar [playerId]  - give a crowbar to yourself (or the given id)
RegisterCommand('givecrowbar', function(src, args)
    if not isAdmin(src) then notify(src, 'No permission.', 'error'); return end
    local target = tonumber(args[1]) or src
    if target <= 0 then return end
    if ox:AddItem(target, Config.crowbarItem, 1) then
        notify(src, ('Gave a crowbar to %d.'):format(target), 'success')
        if target ~= src then notify(target, 'You received a crowbar.', 'inform') end
    else
        notify(src, 'Could not give the crowbar (inventory full?).', 'error')
    end
end, false)

-- /giveblackmoney [amount] [playerId]  - top up dirty money so you can test real buys
RegisterCommand('giveblackmoney', function(src, args)
    if not isAdmin(src) then notify(src, 'No permission.', 'error'); return end
    local amount = math.floor(tonumber(args[1]) or 0)
    local target = tonumber(args[2]) or src
    if amount <= 0 then notify(src, 'Usage: /giveblackmoney [amount] [id]', 'error'); return end
    if target <= 0 then return end
    if ox:AddItem(target, Config.dirtyItem, amount) then
        notify(src, ('Gave $%d dirty money to %d.'):format(amount, target), 'success')
    else
        notify(src, 'Could not give dirty money.', 'error')
    end
end, false)

-- /spawntestcrate [weaponName]  - drop a crate at YOUR feet, owned by you (skips dealer/gang/rep).
RegisterCommand('spawntestcrate', function(src, args)
    if not isAdmin(src) then notify(src, 'No permission.', 'error'); return end
    if src == 0 then print('[pengu_blackmarket] /spawntestcrate must be run in-game'); return end
    local item = args[1] or 'WEAPON_CARBINERIFLE'
    -- verify against ox_inventory's item list (weapon names are UPPERCASE in ox). Stay lenient so a
    -- valid weapon is never wrongly rejected; only warn on something that cannot be verified.
    local def = ox:Items(item)
    if not def and ox:Items(item:upper()) then item = item:upper(); def = ox:Items(item) end
    if not def then
        notify(src, ('Could not verify "%s" - spawning anyway. If it is a typo the crate will not open; /clearcrates to reset.'):format(item), 'inform')
    end
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local cid = cidOf(src)
    if not cid then notify(src, 'You are not loaded.', 'error'); return end
    local label = (def and def.label) or item
    makeCrate(cid, gangOf(src), item, label, { x = coords.x, y = coords.y, z = coords.z, label = 'test drop' })
    TriggerClientEvent('pengu_blackmarket:shipmentOrdered', src,
        { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0, label = 'test drop (your position)' })
    notify(src, ('Test crate dropped at your feet (%s). Pick it up and crack it with a crowbar.'):format(label), 'success')
end, false)

-- /testdrop [weapon]  - drop a crate at a random REAL drop site + set your GPS (tests distant-drop render)
RegisterCommand('testdrop', function(src, args)
    if not isAdmin(src) then notify(src, 'No permission.', 'error'); return end
    if src == 0 then print('[pengu_blackmarket] /testdrop must be run in-game'); return end
    local item = args[1] or 'WEAPON_CARBINERIFLE'
    local def = ox:Items(item)
    if not def and ox:Items(item:upper()) then item = item:upper(); def = ox:Items(item) end
    if not def then notify(src, ('Could not verify "%s" - spawning anyway.'):format(item), 'inform') end
    local sites = Config.dropSites or {}
    if #sites == 0 then notify(src, 'No drop sites configured.', 'error'); return end
    local site = sites[math.random(#sites)]
    local cid = cidOf(src)
    if not cid then notify(src, 'You are not loaded.', 'error'); return end
    local label = (def and def.label) or item
    makeCrate(cid, gangOf(src), item, label, site)
    TriggerClientEvent('pengu_blackmarket:shipmentOrdered', src,
        { x = site.x + 0.0, y = site.y + 0.0, z = site.z + 0.0, label = site.label or 'drop site' })
    notify(src, ('Test drop (%s) at %s - GPS set. Drive there to confirm the crate renders.'):format(label, site.label or 'a drop site'), 'success')
end, false)

-- /clearcrates  - wipe every active crate (world + carried) for a clean test
RegisterCommand('clearcrates', function(src, args)
    if not isAdmin(src) then notify(src, 'No permission.', 'error'); return end
    local n = 0
    for _, c in pairs(CRATES) do
        n = n + 1
        if c.carrier then TriggerClientEvent('pengu_blackmarket:cancelCarry', c.carrier) end
    end
    CRATES = {}
    publishCrates()
    notify(src, ('Cleared %d crate(s).'):format(n), 'success')
end, false)
