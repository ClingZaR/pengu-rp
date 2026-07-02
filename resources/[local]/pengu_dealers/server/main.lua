-- PenguRP Illegal Dealers (pengu_dealers) - SERVER.
-- Dealer ped placement + server-authoritative sell/buy callbacks. Each transaction awards
-- Criminal XP, gang rep, and dealer INFLUENCE. Influence tracks which gang "controls" each
-- dealer (controls = most influence >= Config.controlThreshold). Controlled dealer count
-- is the primary turf-growth metric alongside graffiti tags. ASCII only. luac clean.

local qbx = exports.qbx_core
local ox  = exports.ox_inventory
local ACE = 'pengu.dealers'

DEALERS = {} -- id -> { id, type, label, x, y, z, h, active, zone_key }
OUTFITS = {} -- gang -> dealer_type -> { {comp, draw, tex}, ... }

-- Push the current outfit map to GlobalState so clients apply it on ped spawn.
local function publishOutfits()
    local state = {}
    for gang, types in pairs(OUTFITS) do
        state[gang] = {}
        for dtype, comps in pairs(types) do state[gang][dtype] = comps end
    end
    GlobalState.penguDealerOutfits = state
end

-- Recompute which gang strictly controls each active dealer (same tie-break as GetControlledDealers)
-- and publish as GlobalState.penguDealerControl {["dealerId"] = "gangname"}.
-- Clients watch this bag to re-skin peds live on takeover.
local function computeControlMap()
    local rows = MySQL.query.await(
        [[SELECT di.dealer_id, di.gang FROM pengu_dealer_influence di
          WHERE di.influence >= ?
            AND di.dealer_id IN (SELECT id FROM pengu_dealers WHERE active = 1)
            AND NOT EXISTS (
                SELECT 1 FROM pengu_dealer_influence di2
                WHERE di2.dealer_id = di.dealer_id
                  AND di2.gang <> di.gang
                  AND di2.influence >= di.influence
            )]],
        { Config.controlThreshold or 80 }) or {}
    local map = {}
    for _, r in ipairs(rows) do map[tostring(r.dealer_id)] = r.gang end
    GlobalState.penguDealerControl = map
end

local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, msg, kind, tag)
    if not src or src <= 0 then print('[pengu_dealers] ' .. tostring(msg)); return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { tag or 'DEALER', msg, KIND[kind or 'inform'] or 'info' },
    })
end

local function getGang(src)
    local p = qbx:GetPlayer(src)
    local g = p and p.PlayerData and p.PlayerData.gang
    local name = g and g.name
    if not name or name == 'none' then return nil end
    -- only CRIMINAL gangs can build dealer influence (matches pengu_turf GangOf); otherwise a
    -- non-criminal gang could lead a dealer but pengu_turf would filter it -> the block silently
    -- never renders. Factions comes from @pengu_core/shared/factions.lua.
    if Factions and Factions.isCriminal and not Factions.isCriminal(name) then return nil end
    return name
end

local function addInfluence(dealerId, gang, amount)
    if not gang or gang == '' then return end
    local cap = Config.maxInfluence or 100
    MySQL.query(
        [[INSERT INTO pengu_dealer_influence (dealer_id, gang, influence)
          VALUES (?, ?, ?)
          ON DUPLICATE KEY UPDATE influence = LEAST(?, influence + ?), last_interaction = CURRENT_TIMESTAMP]],
        { dealerId, gang, math.min(cap, amount), cap, amount })
end

-- shared XP + rep + influence award on every successful dealer interaction
local function rewardInteraction(src, dealerId, def)
    local gang = getGang(src)
    pcall(function()
        exports.pengu_xp:Award(src, def.interactXP.category, def.interactXP.amount)
        if gang then
            exports.pengu_gangs:AddRep(gang, def.gangRep)
            addInfluence(dealerId, gang, def.influence)
        end
    end)
    -- schedule a control-map recompute after the fire-and-forget influence write commits
    if gang then SetTimeout(3000, computeControlMap) end
end

-- ===================== persistence =====================
local function loadDealers()
    local rows = MySQL.query.await(
        'SELECT id, dealer_type, label, x, y, z, h, active, zone_key FROM pengu_dealers ORDER BY id') or {}
    local t = {}
    for _, r in ipairs(rows) do
        t[r.id] = {
            id       = r.id,
            type     = r.dealer_type,
            label    = r.label,
            x        = r.x + 0.0,
            y        = r.y + 0.0,
            z        = r.z + 0.0,
            h        = (r.h or 0.0) + 0.0,
            active   = (tonumber(r.active) or 1) == 1,
            zone_key = r.zone_key or '',
        }
    end
    DEALERS = t
end

local function dealerArray()
    local arr = {}
    for _, d in pairs(DEALERS) do if d.active then arr[#arr + 1] = d end end
    return arr
end

local function broadcast() TriggerClientEvent('pengu_dealers:updated', -1, dealerArray()) end

lib.callback.register('pengu_dealers:get', function(_) return dealerArray() end)

-- ===================== boot =====================
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_dealers (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                dealer_type VARCHAR(16) NOT NULL,
                label       VARCHAR(64) NOT NULL DEFAULT '',
                x           FLOAT       NOT NULL,
                y           FLOAT       NOT NULL,
                z           FLOAT       NOT NULL,
                h           FLOAT       NOT NULL DEFAULT 0.0,
                active      TINYINT(1)  NOT NULL DEFAULT 1,
                zone_key    VARCHAR(32) NOT NULL DEFAULT '',
                created_at  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ]])
        -- upgrade: add zone_key to existing tables
        local ex = MySQL.scalar.await(
            'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?',
            { 'pengu_dealers', 'zone_key' })
        if not ex then MySQL.query.await("ALTER TABLE pengu_dealers ADD COLUMN zone_key VARCHAR(32) NOT NULL DEFAULT ''") end
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_dealer_influence (
                dealer_id        INT         NOT NULL,
                gang             VARCHAR(24) NOT NULL,
                influence        INT         NOT NULL DEFAULT 0,
                last_interaction TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (dealer_id, gang),
                INDEX idx_gang (gang),
                INDEX idx_influence (dealer_id, influence DESC)
            )
        ]])
        loadDealers()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_dealer_outfits (
                gang        VARCHAR(24) NOT NULL,
                dealer_type VARCHAR(16) NOT NULL,
                component   TINYINT     NOT NULL,
                drawable    SMALLINT    NOT NULL,
                texture     TINYINT     NOT NULL DEFAULT 0,
                PRIMARY KEY (gang, dealer_type, component)
            )
        ]])
        local orows = MySQL.query.await(
            'SELECT gang, dealer_type, component, drawable, texture FROM pengu_dealer_outfits') or {}
        for _, r in ipairs(orows) do
            OUTFITS[r.gang]              = OUTFITS[r.gang]              or {}
            OUTFITS[r.gang][r.dealer_type] = OUTFITS[r.gang][r.dealer_type] or {}
            local list = OUTFITS[r.gang][r.dealer_type]
            list[#list + 1] = { comp = r.component, draw = r.drawable, tex = r.texture }
        end
    end)
    if not ok then print('[pengu_dealers] BOOT FAILED: ' .. tostring(err)) end
    broadcast()
    publishOutfits()
    computeControlMap()
    local n = 0; for _ in pairs(DEALERS) do n = n + 1 end
    print(('[pengu_dealers] %s (%d dealer(s)).'):format(ok and 'ready' or 'DEGRADED', n))
end)

-- the current chop wanted-car models (set by pengu_chopshop) as a lookup set.
local function wantedModelSet()
    local set = {}
    local w = GlobalState.penguChopWanted
    if type(w) == 'table' then for _, m in ipairs(w) do set[m] = true end end
    return set
end

-- ===================== mechanic: sell car parts =====================
local busy = {}
lib.callback.register('pengu_dealers:sellParts', function(src, dealerId, item)
    if busy[src] then return false end
    local d = DEALERS[tonumber(dealerId)]
    if not d or d.type ~= 'mechanic' then return false end
    local def = Config.dealerTypes.mechanic
    local price
    for _, acc in ipairs(def.accepts or {}) do
        if acc.item == item then price = acc.price; break end
    end
    if not price then return false end
    busy[src] = true
    local result = false
    pcall(function()
        -- PROVENANCE: only buy parts whose SOURCE car (item metadata.model, stamped at chop time) is on
        -- the CURRENT wanted list. Parts from a now-expired list are refused. Sells the whole batch.
        local wanted = wantedModelSet()
        local slots  = ox:Search(src, 'slots', item) or {}
        local total, toRemove = 0, {}
        for _, s in ipairs(slots) do
            local mdl = s.metadata and s.metadata.model
            if mdl and wanted[mdl] and (s.count or 0) > 0 then
                total = total + s.count
                toRemove[#toRemove + 1] = { slot = s.slot, count = s.count }
            end
        end
        if total < 1 then
            notify(src, 'He only buys parts from the cars on the current wanted list.', 'error', 'DEALER'); return
        end
        if not ox:CanCarryItem(src, Config.dirtyItem, total * price) then
            notify(src, 'Too much dirty cash to carry - stash some first.', 'error', 'DEALER'); return
        end
        local removed = 0
        for _, r in ipairs(toRemove) do
            if ox:RemoveItem(src, item, r.count, nil, r.slot) then removed = removed + r.count end
        end
        if removed < 1 then return end
        ox:AddItem(src, Config.dirtyItem, removed * price)
        rewardInteraction(src, d.id, def)
        notify(src, ('Sold %dx %s for $%d dirty.'):format(removed, item, removed * price), 'success', 'DEALER')
        result = true
    end)
    busy[src] = nil
    return result
end)

-- standings shown in the dealer menu: every gang's influence (0-maxInfluence) on this dealer.
lib.callback.register('pengu_dealers:getStandings', function(_src, dealerId)
    local id = tonumber(dealerId)
    if not id or not DEALERS[id] then return nil end
    local rows = MySQL.query.await(
        'SELECT gang, influence FROM pengu_dealer_influence WHERE dealer_id = ? ORDER BY influence DESC', { id }) or {}
    local standings = {}
    for _, r in ipairs(rows) do
        standings[#standings + 1] = { gang = r.gang, influence = tonumber(r.influence) or 0 }
    end
    return { threshold = Config.controlThreshold or 80, max = Config.maxInfluence or 100, standings = standings }
end)

-- ===================== drug dealer: sell drugs =====================
lib.callback.register('pengu_dealers:sellDrugs', function(src, dealerId, item)
    if busy[src] then return false end
    local d = DEALERS[tonumber(dealerId)]
    if not d or d.type ~= 'drug_dealer' then return false end
    local def = Config.dealerTypes.drug_dealer
    local price
    for _, acc in ipairs(def.accepts or {}) do
        if acc.item == item then price = acc.price; break end
    end
    if not price then return false end
    -- PenguRP demand: scale the fixed unit price by the server-wide demand factor (pengu_drugs
    -- owns the model; item name IS the demand key; 1.0 when unavailable; never below $1/unit).
    local demandOk, demand = pcall(function() return exports.pengu_drugs:GetDemand(item) end)
    price = math.max(1, math.floor(price * ((demandOk and tonumber(demand)) or 1.0) + 0.5))
    busy[src] = true
    local result = false
    pcall(function()
        -- batch-sell the whole held stack (consistent with the mechanic's parts sell).
        local count = ox:Search(src, 'count', item) or 0
        if count < 1 then return end
        if not ox:CanCarryItem(src, Config.dirtyItem, count * price) then
            notify(src, 'Too much dirty cash to carry - stash some first.', 'error', 'DEALER'); return
        end
        if not ox:RemoveItem(src, item, count) then return end
        ox:AddItem(src, Config.dirtyItem, count * price)
        -- PenguRP demand: report the completed sale - each unit sold softens this drug's demand
        pcall(function() exports.pengu_drugs:RecordDrugSale(item, count) end)
        -- bonus criminal XP on top of the drug XP
        pcall(function() exports.pengu_xp:Award(src, 'criminal', 50) end)
        rewardInteraction(src, d.id, def)
        notify(src, ('Moved %dx %s - $%d dirty in your pocket.'):format(count, item, count * price), 'success', 'DEALER')
        result = true
    end)
    busy[src] = nil
    return result
end)

-- ===================== doctor: buy medical/buffs =====================
-- generic BUY callback for ANY sells-type dealer (doctor / armor / general). Server-authoritative:
-- re-checks the dealer type carries a sells list + proximity + gang level + dirty money + carry space.
lib.callback.register('pengu_dealers:buyGoods', function(src, dealerId, idx)
    if busy[src] then return false end
    local d = DEALERS[tonumber(dealerId)]
    if not d then return false end
    local def = Config.dealerTypes[d.type]
    if not def or not def.sells then return false end
    local entry = def.sells[tonumber(idx)]
    if not entry then return false end

    -- proximity to the dealer ped (server-authoritative)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    if #(GetEntityCoords(ped) - vector3(d.x, d.y, d.z)) > (Config.interactDist + 3.0) then
        notify(src, 'You are not at the dealer.', 'error', 'DEALER'); return false
    end

    -- level gate (gang must be at the required level; guarded - degrade to level 1)
    local gang = getGang(src)
    local okLvl, level = pcall(function() return exports.pengu_gangs:GetLevel(gang) end)
    level = (gang and okLvl and tonumber(level)) or 1
    if (entry.minLevel or 1) > level then
        notify(src, ('Your gang needs to be level %d for that.'):format(entry.minLevel), 'error', 'DEALER')
        return false
    end

    local price = entry.price or 0
    local count = entry.count or 1
    busy[src] = true
    local result = false
    pcall(function()
        if (ox:Search(src, 'count', Config.dirtyItem) or 0) < price then
            notify(src, "You don't have enough dirty money.", 'error', 'DEALER'); return
        end
        if not ox:CanCarryItem(src, entry.item, count) then
            notify(src, 'No inventory space for that.', 'error', 'DEALER'); return
        end
        if not ox:RemoveItem(src, Config.dirtyItem, price) then return end
        ox:AddItem(src, entry.item, count)
        rewardInteraction(src, d.id, def)
        notify(src, ('Acquired %s for $%d.'):format(entry.label or entry.item, price), 'success', 'DEALER')
        result = true
    end)
    busy[src] = nil
    return result
end)

-- ===================== weapons dealer: order weapons (crate drop) =====================
-- The catalog + buy logic + crate drop live in pengu_blackmarket; this dealer is the placeable,
-- gang-controllable front for it. Ordering awards dealer influence/rep/XP like any other dealer.
lib.callback.register('pengu_dealers:weaponCatalog', function(_)
    local ok, cat = pcall(function() return exports.pengu_blackmarket:GetCatalog() end)
    return (ok and cat) or {}
end)

lib.callback.register('pengu_dealers:buyWeapon', function(src, dealerId, catIdx)
    if busy[src] then return false end
    local d = DEALERS[tonumber(dealerId)]
    if not d or d.type ~= 'weapons' then return false end
    -- proximity to the dealer ped (server-authoritative)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    if #(GetEntityCoords(ped) - vector3(d.x, d.y, d.z)) > (Config.interactDist + 3.0) then
        notify(src, 'You are not at the dealer.', 'error', 'DEALER'); return false
    end
    busy[src] = true
    local result = false
    local ok, bought = pcall(function() return exports.pengu_blackmarket:OrderWeapon(src, catIdx) end)
    if ok and bought then
        -- ONLY dealer influence on order (this is the turf mechanic). Gang rep + criminal XP for a weapon
        -- are granted by pengu_blackmarket when the buyer actually PRIES THE CRATE OPEN - so an order whose
        -- crate expires or gets intercepted pays no rep/XP, and a successful import is not double-rewarded.
        local gang = getGang(src)
        if gang then pcall(function() addInfluence(d.id, gang, Config.dealerTypes.weapons.influence or 5) end) end
        result = true
    end
    busy[src] = nil
    return result
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)

-- ===================== influence decay ("keep your dealers happy") =====================
-- Every gang's influence on every dealer bleeds down each tick; a gang that stops working a dealer
-- slides below controlThreshold and the projected turf block releases. Then nudge pengu_turf to
-- recompute so released blocks vanish promptly (instead of waiting on its own slower tick).
CreateThread(function()
    while true do
        Wait(Config.influenceDecayMs or 600000)
        local dec = Config.influenceDecay or 3
        local ok = pcall(function()
            MySQL.query.await('UPDATE pengu_dealer_influence SET influence = GREATEST(0, influence - ?)', { dec })
            MySQL.query.await('DELETE FROM pengu_dealer_influence WHERE influence <= 0')
        end)
        if ok then
            pcall(function() exports.pengu_turf:RecomputeDealerTurf() end)
            pcall(computeControlMap) -- refresh outfit skins after decay may shift control
        end
    end
end)

-- ===================== exports (other systems read influence) =====================
-- The list of active dealers CURRENTLY CONTROLLED by a gang (highest per-dealer influence >= threshold,
-- strictly greater than any rival). pengu_turf projects a turf BLOCK around each one - this is the
-- dealer-driven turf-growth path (graffiti is the other). Returns { {id,x,y,z,gang,label}, ... }.
exports('GetControlledDealers', function()
    local rows = MySQL.query.await(
        [[SELECT di.dealer_id, di.gang FROM pengu_dealer_influence di
          WHERE di.influence >= ?
            AND di.dealer_id IN (SELECT id FROM pengu_dealers WHERE active = 1)
            AND NOT EXISTS (
                SELECT 1 FROM pengu_dealer_influence di2
                WHERE di2.dealer_id = di.dealer_id AND di2.gang <> di.gang AND di2.influence >= di.influence
            )]],
        { Config.controlThreshold or 80 }) or {}
    local seen, out = {}, {}
    for _, r in ipairs(rows) do
        local d = DEALERS[r.dealer_id]
        if d and d.active and not seen[r.dealer_id] then
            seen[r.dealer_id] = true
            out[#out + 1] = { id = d.id, x = d.x, y = d.y, z = d.z, gang = r.gang, label = d.label }
        end
    end
    return out
end)

exports('GetInfluence', function(dealerId, gang)
    local row = MySQL.scalar.await(
        'SELECT influence FROM pengu_dealer_influence WHERE dealer_id = ? AND gang = ?',
        { tonumber(dealerId), gang })
    return tonumber(row) or 0
end)

-- How many dealers a gang CONTROLS (influence >= threshold). Turf/expansion reads this.
exports('GetControlledCount', function(gang)
    local row = MySQL.scalar.await(
        [[SELECT COUNT(*) FROM pengu_dealer_influence di
          WHERE di.gang = ? AND di.influence >= ?
            AND di.dealer_id IN (SELECT id FROM pengu_dealers WHERE active = 1)
            AND NOT EXISTS (
                SELECT 1 FROM pengu_dealer_influence di2
                WHERE di2.dealer_id = di.dealer_id AND di2.gang <> ? AND di2.influence >= di.influence
            )]],
        { gang, Config.controlThreshold, gang })
    return tonumber(row) or 0
end)

-- Reset all influence for a gang (admin penalty)
exports('ResetInfluence', function(gang)
    MySQL.query.await('DELETE FROM pengu_dealer_influence WHERE gang = ?', { gang })
    pcall(function() exports.pengu_turf:RecomputeDealerTurf() end) -- drop that gang's dealer blocks now
end)

-- ===================== admin commands =====================
local function adminOk(src)
    if src <= 0 then return true end
    if not IsPlayerAceAllowed(src, ACE) then notify(src, 'not allowed.', 'error'); return false end
    if not exports.qbx_core:IsOptin(src) then notify(src, '/aduty required.', 'error'); return false end
    return true
end

RegisterCommand('dealeradd', function(src, args)
    if not adminOk(src) then return end
    local dtype = tostring(args[1] or ''):lower()
    if not Config.dealerTypes[dtype] then
        local valid = {}; for k in pairs(Config.dealerTypes) do valid[#valid + 1] = k end
        notify(src, 'types: ' .. table.concat(valid, ', '), 'error'); return
    end
    table.remove(args, 1)
    local label = (#args > 0) and table.concat(args, ' ') or (Config.dealerTypes[dtype].label or 'Dealer')
    local ped   = GetPlayerPed(src)
    local c     = GetEntityCoords(ped)
    local h     = GetEntityHeading(ped)
    -- No zone to set: a controlled dealer auto-projects a turf BLOCK around its own position.
    local newId = MySQL.insert.await(
        'INSERT INTO pengu_dealers (dealer_type, label, x, y, z, h) VALUES (?, ?, ?, ?, ?, ?)',
        { dtype, label, c.x + 0.0, c.y + 0.0, c.z + 0.0, h + 0.0 })
    DEALERS[newId] = { id = newId, type = dtype, label = label,
                       x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0, h = h + 0.0, active = true, zone_key = '' }
    broadcast()
    notify(src, ('placed %s dealer #%d "%s". A gang that controls it (>= %d influence) claims turf around it.')
        :format(dtype, newId, label, Config.controlThreshold or 80), 'success', 'DEALER')
end, false)

RegisterCommand('dealerremove', function(src, args)
    if not adminOk(src) then return end
    local id = tonumber(args[1])
    if not id or not DEALERS[id] then notify(src, 'usage: /dealerremove <id>', 'error'); return end
    local label = DEALERS[id].label
    MySQL.query.await('DELETE FROM pengu_dealers WHERE id = ?', { id })
    MySQL.query.await('DELETE FROM pengu_dealer_influence WHERE dealer_id = ?', { id })
    DEALERS[id] = nil
    broadcast()
    pcall(function() exports.pengu_turf:RecomputeDealerTurf() end) -- remove its projected block now
    computeControlMap()
    notify(src, ('removed dealer #%d "%s".'):format(id, label), 'success', 'DEALER')
end, false)

RegisterCommand('dealerlist', function(src)
    if not adminOk(src) then return end
    local any = false
    for id, d in pairs(DEALERS) do
        local status = d.active and 'ON' or 'OFF'
        notify(src, ('#%d [%s] %s (%s)  %.0f,%.0f,%.0f'):format(
            id, status, d.label, d.type, d.x, d.y, d.z), 'inform', 'DEALER')
        any = true
    end
    if not any then notify(src, 'no dealers placed yet. /dealeradd <type> to add one.', 'inform', 'DEALER') end
end, false)

-- /dealerinfluence <gang>: how many dealers that gang controls + total influence
RegisterCommand('dealerinfluence', function(src, args)
    if not adminOk(src) then return end
    local gang = tostring(args[1] or ''):lower()
    if gang == '' then notify(src, 'usage: /dealerinfluence <gang>', 'error'); return end
    local rows = MySQL.query.await(
        'SELECT dealer_id, influence FROM pengu_dealer_influence WHERE gang = ? ORDER BY influence DESC',
        { gang }) or {}
    if #rows == 0 then notify(src, gang .. ' has no dealer influence yet.', 'inform', 'DEALER'); return end
    local controlled = 0
    for _, r in ipairs(rows) do
        local status = (tonumber(r.influence) or 0) >= (Config.controlThreshold or 80) and 'CTRL' or '    '
        if status == 'CTRL' then controlled = controlled + 1 end
        notify(src, ('[%s] dealer #%d  inf=%d'):format(status, r.dealer_id, r.influence), 'inform', 'DEALER')
    end
    notify(src, ('%s controls %d dealer(s).'):format(gang, controlled), 'inform', 'DEALER')
end, false)

-- ===================== gang outfit commands =====================
-- /gangoutfit set <gang> <type> <component> <drawable> [texture]
--   Sets which ped component variation to apply when the dealer is controlled by <gang>.
--   component 11 = top/jacket | 8 = undershirt | 3 = torso/arms | 1 = mask/bandana | 7 = accessory
--   Run twice with the same gang+type+component to update it (ON DUPLICATE KEY UPDATE).
--   Tip for mechanic (s_m_y_xmech_01): try component 8 (undershirt) or 1 (face bandana).
--   Tip for doctor (s_m_m_doctor_01): the neutral role suits no top; skip or use comp 7 (accessory).
-- /gangoutfit clear <gang> [type]  -- wipes outfit(s) for a gang
-- /gangoutfit list [gang]           -- shows all configured outfits
RegisterCommand('gangoutfit', function(src, args)
    if not adminOk(src) then return end
    local sub = tostring(args[1] or ''):lower()

    if sub == 'set' then
        local gang  = tostring(args[2] or ''):lower()
        local dtype = tostring(args[3] or ''):lower()
        local comp  = tonumber(args[4])
        local draw  = tonumber(args[5])
        local tex   = tonumber(args[6]) or 0
        if gang == '' then
            notify(src, 'usage: /gangoutfit set <gang> <type> <component> <drawable> [texture]', 'error', 'OUTFIT'); return
        end
        if not Config.dealerTypes[dtype] then
            local valid = {}; for k in pairs(Config.dealerTypes) do valid[#valid + 1] = k end
            notify(src, 'unknown type. valid: ' .. table.concat(valid, ', '), 'error', 'OUTFIT'); return
        end
        if not comp or not draw then
            notify(src, 'component and drawable must be numbers (e.g. /gangoutfit set lostmc drug_dealer 11 42 0)', 'error', 'OUTFIT'); return
        end
        MySQL.query.await(
            [[INSERT INTO pengu_dealer_outfits (gang, dealer_type, component, drawable, texture)
              VALUES (?, ?, ?, ?, ?)
              ON DUPLICATE KEY UPDATE drawable = VALUES(drawable), texture = VALUES(texture)]],
            { gang, dtype, comp, draw, tex })
        OUTFITS[gang]              = OUTFITS[gang]              or {}
        OUTFITS[gang][dtype]       = OUTFITS[gang][dtype]       or {}
        local list = OUTFITS[gang][dtype]
        local replaced = false
        for i, e in ipairs(list) do
            if e.comp == comp then list[i] = { comp = comp, draw = draw, tex = tex }; replaced = true; break end
        end
        if not replaced then list[#list + 1] = { comp = comp, draw = draw, tex = tex } end
        publishOutfits()
        notify(src, ('set %s %s: component %d -> drawable %d texture %d'):format(gang, dtype, comp, draw, tex), 'success', 'OUTFIT')

    elseif sub == 'clear' then
        local gang  = tostring(args[2] or ''):lower()
        local dtype = args[3] and tostring(args[3]):lower() or nil
        if gang == '' then
            notify(src, 'usage: /gangoutfit clear <gang> [type]', 'error', 'OUTFIT'); return
        end
        if dtype then
            MySQL.query.await('DELETE FROM pengu_dealer_outfits WHERE gang = ? AND dealer_type = ?', { gang, dtype })
            if OUTFITS[gang] then OUTFITS[gang][dtype] = nil end
            notify(src, ('cleared %s %s outfit.'):format(gang, dtype), 'success', 'OUTFIT')
        else
            MySQL.query.await('DELETE FROM pengu_dealer_outfits WHERE gang = ?', { gang })
            OUTFITS[gang] = nil
            notify(src, ('cleared all outfits for %s.'):format(gang), 'success', 'OUTFIT')
        end
        publishOutfits()

    elseif sub == 'list' then
        local filterGang = args[2] and tostring(args[2]):lower() or nil
        local any = false
        for g, types in pairs(OUTFITS) do
            if not filterGang or g == filterGang then
                for dtype, comps in pairs(types) do
                    for _, c in ipairs(comps) do
                        notify(src, ('%s | %s | comp %d draw %d tex %d'):format(g, dtype, c.comp, c.draw, c.tex), 'inform', 'OUTFIT')
                        any = true
                    end
                end
            end
        end
        if not any then
            notify(src, 'no gang outfits set yet. use /gangoutfit set <gang> <type> <comp> <draw> [tex]', 'inform', 'OUTFIT')
        end

    else
        notify(src, 'subcommands: set | clear | list', 'error', 'OUTFIT')
    end
end, false)
