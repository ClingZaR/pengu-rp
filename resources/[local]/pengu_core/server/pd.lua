-- PenguRP: SERVER for the data-driven LEGAL-FACTION interaction system (police/bcso/sasp/ems/...).
-- Responsibilities:
--   * create + seed pengu_pd_locations / _fleet / _armory / _wardrobe (oxmysql), per legal faction,
--   * serve the location/fleet/armoury/wardrobe lists to clients (lib.callback "pengu_pd:*"),
--   * broadcast live updates ("pengu_pd:locationsUpdated") whenever /pdloc|/factionloc changes the list,
--   * register a per-faction personal locker stash,
--   * owner-only /pdloc|/factionloc add|remove|setfaction|list command, gated by ace "pengu.placement".
-- The client (client/armory.lua) renders the armoury as an ox_lib NUI grid fed by the
-- 'pengu_pd:getArmoury' callback + draws gear via the 'pengu_pd:takeArmouryItem' net event (ARMOURY_SHOP
-- below is retained ONLY as the LEO curated catalog + weapon-metadata source, not as an opened shop),
-- and spawns garage vehicles via the GLOBAL qbx callback 'qbx_policejob:server:spawnVehicle'. ASCII only.

local VALID_TYPES = {
    armory   = true,
    locker   = true,
    clothing = true,
    garage   = true,
    duty     = true,
    mugshot  = true, -- booking camera: capture a suspect's mugshot into the MDT
    parking  = true, -- drive an emergency vehicle into the checkpoint to store it
    cell     = true, -- jail: stand here with a charged suspect + /jail to imprison them here
    lobby    = true, -- jail: release/drop point prisoners are sent to when freed
    fingerprint = true, -- LEO: scan the nearest person's prints onto their MDT record (placeable + cruiser-usable)
    helipad  = true, -- air fleet: hold-Alt spawns a helicopter; land a fleet aircraft on it to store it
}

-- Seed rows used ONLY when the table is empty on first run (admin moves them live with /pdloc).
local SEED = {
    { type = 'armory',   label = 'MRPD Armoury',   x =  453.21, y =  -980.03, z = 30.68 },
    { type = 'armory',   label = 'Paleto Armoury', x = -443.37, y =  6008.47, z = 31.63 },
    { type = 'locker',   label = 'MRPD Locker',    x =  449.80, y =  -987.00, z = 30.84 },
    { type = 'clothing', label = 'MRPD Wardrobe',  x =  461.40, y =  -981.60, z = 30.70 },
    { type = 'garage',   label = 'MRPD Garage',    x =  454.50, y = -1017.00, z = 28.40 },
    { type = 'duty',     label = 'MRPD Duty',      x =  440.00, y =  -974.90, z = 30.69 },
    { type = 'mugshot',  label = 'MRPD Booking',   x =  436.40, y =  -975.30, z = 30.69 },
    { type = 'parking',  label = 'MRPD Parking',   x =  454.50, y = -1020.00, z = 28.40 },
    { type = 'cell',     label = 'Jail Cell',      x = 1845.83, y =  2585.90, z = 45.67 },
    { type = 'lobby',    label = 'Release Lobby',  x = 1842.58, y =  2573.43, z = 45.89 },
    { type = 'helipad',  label = 'MRPD Helipad',   x =  449.168, y = -981.325, z = 43.691 },
}

-- ===================== ARMOURY SHOP (no-location bypass) =====================
-- A shop registered WITHOUT a `locations` key takes the ox_inventory registerShopType else-branch:
-- shop.items is set and shop.coords stays nil, so openShop skips the vector3 distance gate while
-- still enforcing shop.groups via server.hasGroup. Mirrors data/shops.lua PoliceArmoury items.
local ARMOURY_SHOP = {
    name   = 'Police Armoury',
    groups = { police = 0, bcso = 0, sasp = 0, sheriff = 0 },
    inventory = {
        { name = 'WEAPON_PISTOL',       price = 0, metadata = { registered = true, serial = 'POL' } },
        { name = 'WEAPON_STUNGUN',      price = 0, metadata = { registered = true, serial = 'POL' } },
        { name = 'ammo-9',              price = 0 },
        { name = 'WEAPON_FLASHLIGHT',   price = 0 },
        { name = 'WEAPON_NIGHTSTICK',   price = 0 },
        { name = 'handcuffs',           price = 0 },
        { name = 'forensic_kit',        price = 0 },
        { name = 'fingerprint_scanner', price = 0 },
        { name = 'hydrogen_peroxide',   price = 0 },
        { name = 'evidence_box',        price = 0 },
        { name = 'WEAPON_CARBINERIFLE', price = 0, metadata = { registered = true, serial = 'POL' }, grade = 3 },
        { name = 'ammo-rifle',          price = 0, grade = 3 },
        { name = 'spikestrip',          price = 0 },
        { name = 'trafficcone',         price = 0 },
    },
    -- NO `locations` key on purpose.
}

-- ============================ helpers ============================

-- All /pdloc feedback prints to chat using our qbx_chat_theme 'pengu:admin' template
-- (tag colour reflects the kind: ok=green, err=red, info=lavender) instead of toast notifications.
local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, msg, kind, tag)
    if src and src > 0 then
        TriggerClientEvent('chat:addMessage', src, {
            templateId = 'pengu:admin',
            args = { tag or 'PDLOC', msg, KIND[kind or 'inform'] or 'info' },
        })
    else
        print('[pengu_pd] ' .. msg)
    end
end

-- Display data (label / icon / give-count) for the lavender armory menu, keyed by
-- item name. The authoritative item set + metadata + grade still come from
-- ARMOURY_SHOP.inventory above, so there is a single source of truth.
local ARMOURY_DISPLAY = {
    ['WEAPON_PISTOL']       = { label = 'Pistol',              icon = 'pistol', count = 1 },
    ['WEAPON_STUNGUN']      = { label = 'Taser',               icon = 'taser',  count = 1 },
    ['ammo-9']              = { label = '9mm Ammo',            icon = 'ammo',   count = 50 },
    ['WEAPON_FLASHLIGHT']   = { label = 'Flashlight',          icon = 'item',   count = 1 },
    ['WEAPON_NIGHTSTICK']   = { label = 'Nightstick',          icon = 'baton',  count = 1 },
    ['handcuffs']           = { label = 'Handcuffs',           icon = 'cuffs',  count = 1 },
    ['forensic_kit']        = { label = 'Forensic Kit',        icon = 'kit',    count = 1 },
    ['fingerprint_scanner'] = { label = 'Fingerprint Scanner', icon = 'scan',   count = 1 },
    ['hydrogen_peroxide']   = { label = 'Evidence Spray',      icon = 'spray',  count = 1 },
    ['evidence_box']        = { label = 'Evidence Box',        icon = 'box',    count = 1 },
    ['WEAPON_CARBINERIFLE'] = { label = 'Carbine Rifle',       icon = 'pistol', count = 1 },
    ['ammo-rifle']          = { label = 'Rifle Ammo',          icon = 'ammo',   count = 60 },
    ['spikestrip']          = { label = 'Spike Strip',         icon = 'item',   count = 1 },
    ['trafficcone']         = { label = 'Traffic Cone',        icon = 'item',   count = 2 },
}

-- Display data for the lavender wardrobe menu, keyed by preset id.
local WARDROBE_DISPLAY = {
    uniform     = { name = 'Officer Uniform', meta = 'Standard patrol',   icon = 'shirt'  },
    swat        = { name = 'SWAT / Tactical', meta = 'Tactical loadout',  icon = 'vest'   },
    armor       = { name = 'Body Armor',      meta = 'Equip vest (100)',  icon = 'armor'  },
    removearmor = { name = 'Remove Armor',    meta = 'Take off the vest', icon = 'remove' },
}

-- ox_inventory label for an arbitrary item (chiefs can now stock anything).
local function oxItemLabel(name)
    local ok, item = pcall(function() return exports.ox_inventory:Items(name) end)
    if ok and item and item.label then return item.label end
    return name
end

-- Display (label/icon/count) for an armory item: the curated table first, else a
-- generic fallback so chief-added arbitrary items still render + give correctly.
local function armoryDisp(name)
    local d = ARMOURY_DISPLAY[name]
    if d then return d end
    return { label = oxItemLabel(name), icon = 'item', count = 1 }
end

-- Display + kind for a wardrobe row. Builtin presets fall back to WARDROBE_DISPLAY;
-- chief-created outfits use their stored label. kind: builtin|outfit|armor|removearmor.
local function wardrobeDisp(r)
    local kind = (r.kind and r.kind ~= '') and r.kind or 'builtin'
    local base = WARDROBE_DISPLAY[r.preset]
    if base then
        return { kind = kind, name = base.name, meta = base.meta, icon = base.icon }
    end
    local icon = (kind == 'armor' and 'armor') or (kind == 'removearmor' and 'remove') or 'shirt'
    return { kind = kind, name = (r.label and r.label ~= '' and r.label) or r.preset, meta = 'Saved outfit', icon = icon }
end

-- On-duty LEGAL-FACTION guard -> returns the player object (or nil). ANY job registered in
-- Factions.legal (police/bcso/sasp/ambulance/...) counts - not just LEO - so the whole
-- loc/fleet/clothing/armoury feature set serves every legal faction, not only the police.
local function onDutyLeo(src)
    local p = exports.qbx_core:GetPlayer(src)
    if not p or not p.PlayerData or not p.PlayerData.job then return nil end
    local job = p.PlayerData.job
    if not Factions.isLegal(job.name) or not job.onduty then return nil end
    return p
end

-- ===================== fleet (per-faction vehicle garage) =====================
-- Each LEO faction (police/bcso/sasp) has its OWN db-backed fleet. The faction
-- lead (isboss = chief) adds/removes cars and sets a full mod PRESET per car;
-- whenever any on-duty officer of that faction pulls the car, the preset applies.
local VALID_ICON = { car = true, suv = true, bike = true, van = true, heli = true }

-- Default fleet seeded once per faction (chiefs customise from there).
local FLEET_SEED = {
    { model = 'police',   label = 'Stanier Cruiser',  icon = 'car'  },
    { model = 'police2',  label = 'Buffalo Cruiser',  icon = 'car'  },
    { model = 'police3',  label = 'Interceptor',      icon = 'car'  },
    { model = 'police4',  label = 'Unmarked Cruiser', icon = 'car'  },
    { model = 'policeb',  label = 'Police Bike',      icon = 'bike' },
    { model = 'policet',  label = 'Transport Van',    icon = 'van'  },
    { model = 'riot',     label = 'Riot Van',         icon = 'van'  },
    { model = 'sheriff',  label = 'Sheriff Cruiser',  icon = 'car'  },
    { model = 'sheriff2', label = 'Sheriff SUV',      icon = 'suv'  },
    { model = 'fbi',      label = 'Unmarked Buffalo', icon = 'car'  },
    { model = 'fbi2',     label = 'Unmarked SUV',     icon = 'suv'  },
    { model = 'pranger',  label = 'Park Ranger',      icon = 'suv'  },
}

-- ===================== per-kind starter seeds (legal factions) =====================
-- Every legal faction of a given job.type gets a starter set the boss then customises.
-- LEO factions get the full police loadout; EMS gets a minimal starter and builds the rest
-- via the Manage Fleet / Armory / Wardrobe menus. New kinds default to the LEO set.
local FLEET_SEED_BY_KIND = {
    leo = FLEET_SEED,
    ems = { { model = 'ambulance', label = 'Ambulance', icon = 'van' } },
    fire = {
        { model = 'firetruk', label = 'Fire Truck',    icon = 'van' },
        { model = 'ambulance', label = 'Rescue Unit',  icon = 'van' },
    },
}

-- ===================== per-faction AIR fleet (helipad) =====================
-- Stored in the SAME pengu_pd_fleet table with air = 1 (ground cars are air = 0). LEO gets a
-- patrol + utility chopper; EMS gets an air ambulance; fire starts empty (chief adds aircraft).
local AIR_FLEET_SEED = {
    { model = 'polmav',   label = 'Police Maverick', icon = 'heli' },
    { model = 'maverick', label = 'Maverick',        icon = 'heli' },
}
local AIR_FLEET_SEED_BY_KIND = {
    leo = AIR_FLEET_SEED,
    ems = { { model = 'polmav', label = 'Air Ambulance', icon = 'heli' } },
    fire = {},
}
-- Wardrobe builtins by kind. uniform/swat are police component presets (LEO only); armor/
-- removearmor are generic SetPedArmour actions. EMS bosses save their own outfits via the
-- in-house clothing designer (captureCurrentOutfit), so no EMS clothing numbers are hardcoded.
local WARDROBE_SEED_BY_KIND = {
    leo = { 'uniform', 'swat', 'armor', 'removearmor' },
    ems = { 'armor', 'removearmor' },
    fire = { 'armor', 'removearmor' }, -- fire chief saves turnout-gear outfits via the designer
}
-- Armoury starter items by kind (uses ARMOURY_SHOP.inventory entries for LEO). EMS starts
-- empty - the boss stocks medical gear via the full-item picker in Manage Armory.
local ARMOURY_SEED_BY_KIND = {
    leo = ARMOURY_SHOP.inventory,
    ems = {},
    fire = {
        { name = 'WEAPON_FIREEXTINGUISHER' },
        { name = 'WEAPON_HATCHET' }, -- fire axe
        { name = 'firstaid' },
        { name = 'bandage' },
    },
}

-- ===================== fleet model exemption (entities blacklist) =====================
-- Several emergency vehicles/aircraft (buzzard, annihilator, maverick, savage, firetruk, ...) sit in
-- qbx_smallresources' entities blacklist so civilians cannot exploit-spawn them. The PD/EMS/Fire fleet
-- spawns them LEGITIMATELY for on-duty members, so we publish every fleet model hash to
-- GlobalState.penguFleetModels; qbx_entitiesblacklist exempts anything in that set (otherwise the
-- server creates the heli, grants keys, then the blacklist instantly deletes it). Rebuilt at boot and
-- whenever a chief adds a vehicle/aircraft. Must be defined BEFORE the fleetAdd/airFleetAdd handlers
-- that call it (a `local function` is only in scope after its declaration).
local function hashModel(set, model)
    if type(model) == 'string' and model ~= '' then
        set[joaat((model:lower():gsub('%s+', '')))] = true
    end
end

-- The seed model set (config FLEET/AIR seeds) - computable synchronously, no DB. Note joaat() is
-- case-insensitive (it lowercases), so these hashes match the entities blacklist's backtick keys
-- (`BUZZARD` == joaat('buzzard')) and the hash GetEntityModel returns for a buzzard spawned by name.
local function fleetSeedSet()
    local set = {}
    for _, group in pairs({ FLEET_SEED_BY_KIND, AIR_FLEET_SEED_BY_KIND }) do
        for _, seed in pairs(group) do
            for _, c in ipairs(seed) do hashModel(set, c.model) end
        end
    end
    return set
end

local function publishFleetModels()
    local set = fleetSeedSet()
    -- plus everything chiefs have added (or that was seeded) in the DB
    local ok, rows = pcall(MySQL.query.await, 'SELECT DISTINCT model FROM pengu_pd_fleet')
    if ok and type(rows) == 'table' then
        for _, r in ipairs(rows) do hashModel(set, r.model) end
    end
    GlobalState.penguFleetModels = set
end

-- Publish the seed set IMMEDIATELY (synchronous, no DB) so the blacklist exempts the default fleet
-- (polmav/maverick/ambulance/firetruk/...) from the very first frame. Without this, an officer who
-- pulls a heli during the ~1s async DB seeding would hit a nil GlobalState.penguFleetModels and the
-- blacklist would delete the heli mid-spawn. The boot thread re-publishes with chief-added DB models.
GlobalState.penguFleetModels = fleetSeedSet()

-- All legal faction job names (keys of Factions.legal), sorted for stable seeding order.
local function legalFactions()
    local out = {}
    for name in pairs(Factions.legal) do out[#out + 1] = name end
    table.sort(out)
    return out
end

-- The kind ('leo','ems',...) for a legal faction, default 'leo'.
local function kindOf(fac)
    local def = Factions.legal[fac]
    return (def and def.kind) or 'leo'
end

local function isBoss(job)
    if not job then return false end
    if job.isboss ~= nil then return job.isboss == true end
    return (job.grade and job.grade.isboss == true) or false
end

-- The player's legal-faction job name (any Factions.legal key) or nil.
local function factionOf(p)
    local job = p and p.PlayerData and p.PlayerData.job
    if not job or not Factions.isLegal(job.name) then return nil end
    return job.name
end

-- On-duty LEO faction boss (chief). Returns player, faction (or nil).
local function chiefOf(src)
    local p = onDutyLeo(src)
    if not p or not isBoss(p.PlayerData.job) then return nil end
    return p, factionOf(p)
end

-- Officer fetches their faction fleet (cars + mod presets + manage permission).
lib.callback.register('pengu_pd:getFleet', function(source)
    local p = onDutyLeo(source)
    local fac = p and factionOf(p)
    if not fac then return { cars = {}, canManage = false } end
    local rows = MySQL.query.await(
        'SELECT id, model, label, icon, grade, mods FROM pengu_pd_fleet WHERE faction = ? AND air = 0 ORDER BY sort, id', { fac }) or {}
    for _, r in ipairs(rows) do
        r.grade = tonumber(r.grade) or 0
        r.mods = (type(r.mods) == 'string' and r.mods ~= '') and json.decode(r.mods) or nil
    end
    return { cars = rows, canManage = isBoss(p.PlayerData.job), faction = fac }
end)

-- Officer fetches their faction AIR fleet (helicopters/planes; same shape as getFleet, air = 1).
lib.callback.register('pengu_pd:getAirFleet', function(source)
    local p = onDutyLeo(source)
    local fac = p and factionOf(p)
    if not fac then return { cars = {}, canManage = false } end
    local rows = MySQL.query.await(
        'SELECT id, model, label, icon, grade, mods FROM pengu_pd_fleet WHERE faction = ? AND air = 1 ORDER BY sort, id', { fac }) or {}
    for _, r in ipairs(rows) do
        r.grade = tonumber(r.grade) or 0
        r.mods = (type(r.mods) == 'string' and r.mods ~= '') and json.decode(r.mods) or nil
    end
    return { cars = rows, canManage = isBoss(p.PlayerData.job), faction = fac }
end)

-- Chief: add a car to the faction fleet.
RegisterNetEvent('pengu_pd:fleetAdd', function(data)
    local p, fac = chiefOf(source)
    if not p or not fac or type(data) ~= 'table' then return end
    local model = type(data.model) == 'string' and data.model:lower():gsub('%s+', '') or ''
    if model == '' then return end
    local label = (type(data.label) == 'string' and data.label ~= '') and data.label or model
    local icon  = VALID_ICON[data.icon] and data.icon or 'car'
    local grade = math.max(0, math.floor(tonumber(data.grade) or 0))
    MySQL.insert.await(
        'INSERT INTO pengu_pd_fleet (faction, model, label, icon, grade, sort) VALUES (?, ?, ?, ?, ?, 999)',
        { fac, model, label, icon, grade })
    publishFleetModels() -- exempt the new model from the entities blacklist
    notify(source, ('Added %s to the %s fleet.'):format(label, fac:upper()), 'success', 'FLEET')
end)

-- Chief: remove a car (must belong to their faction).
RegisterNetEvent('pengu_pd:fleetRemove', function(id)
    local p, fac = chiefOf(source)
    if not p or not fac then return end
    id = tonumber(id)
    if not id then return end
    local affected = MySQL.update.await('DELETE FROM pengu_pd_fleet WHERE id = ? AND faction = ?', { id, fac })
    if affected and affected > 0 then notify(source, 'Removed a vehicle from the fleet.', 'success', 'FLEET') end
    publishFleetModels() -- re-publish so a fully-removed blacklisted model is re-blocked
end)

-- Chief: save the full mod preset for a car (faction-scoped).
RegisterNetEvent('pengu_pd:fleetSetMods', function(id, mods)
    local p, fac = chiefOf(source)
    if not p or not fac then return end
    id = tonumber(id)
    if not id or type(mods) ~= 'table' then return end
    MySQL.update.await('UPDATE pengu_pd_fleet SET mods = ? WHERE id = ? AND faction = ?',
        { json.encode(mods), id, fac })
    notify(source, 'Saved the vehicle preset.', 'success', 'FLEET')
end)

-- Chief: add an aircraft to the faction AIR fleet (air = 1).
RegisterNetEvent('pengu_pd:airFleetAdd', function(data)
    local p, fac = chiefOf(source)
    if not p or not fac or type(data) ~= 'table' then return end
    local model = type(data.model) == 'string' and data.model:lower():gsub('%s+', '') or ''
    if model == '' then return end
    local label = (type(data.label) == 'string' and data.label ~= '') and data.label or model
    local icon  = VALID_ICON[data.icon] and data.icon or 'heli'
    local grade = math.max(0, math.floor(tonumber(data.grade) or 0))
    MySQL.insert.await(
        'INSERT INTO pengu_pd_fleet (faction, model, label, icon, grade, air, sort) VALUES (?, ?, ?, ?, ?, 1, 999)',
        { fac, model, label, icon, grade })
    publishFleetModels() -- exempt the new aircraft from the entities blacklist
    notify(source, ('Added %s to the %s air fleet.'):format(label, fac:upper()), 'success', 'AIR')
end)

-- Chief: remove an aircraft (must belong to their faction's air fleet).
RegisterNetEvent('pengu_pd:airFleetRemove', function(id)
    local p, fac = chiefOf(source)
    if not p or not fac then return end
    id = tonumber(id)
    if not id then return end
    local affected = MySQL.update.await('DELETE FROM pengu_pd_fleet WHERE id = ? AND faction = ? AND air = 1', { id, fac })
    if affected and affected > 0 then notify(source, 'Removed an aircraft from the air fleet.', 'success', 'AIR') end
    publishFleetModels() -- re-publish so a fully-removed blacklisted model is re-blocked
end)

-- Chief: save the full mod preset for an aircraft (faction-scoped, air = 1).
RegisterNetEvent('pengu_pd:airFleetSetMods', function(id, mods)
    local p, fac = chiefOf(source)
    if not p or not fac then return end
    id = tonumber(id)
    if not id or type(mods) ~= 'table' then return end
    MySQL.update.await('UPDATE pengu_pd_fleet SET mods = ? WHERE id = ? AND faction = ? AND air = 1',
        { json.encode(mods), id, fac })
    notify(source, 'Saved the aircraft preset.', 'success', 'AIR')
end)

-- Server-authoritative proximity: the nearest PD location of one of `types` (faction-scoped) within
-- `dist` of the player's REAL server-side position, or nil. Guards armory draws + fleet spawns against
-- FORGED net events fired from anywhere on the map (client-side range checks are bypassable). Defined
-- here so the handlers below - which precede the local fetchLocations - can use it (cfx-lua scope rule).
local function nearestPdLocation(src, types, fac, dist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local pc = GetEntityCoords(ped)
    local rows = MySQL.query.await('SELECT type, x, y, z, heading, faction FROM pengu_pd_locations') or {}
    local best, bestd = nil, (dist or 8.0)
    for i = 1, #rows do
        local r = rows[i]
        if types[r.type] and (r.faction == nil or r.faction == '' or r.faction == fac) then
            local d = #(pc - vector3(r.x + 0.0, r.y + 0.0, r.z + 0.0))
            if d <= bestd then best, bestd = r, d end
        end
    end
    return best
end

-- Robust fleet-vehicle spawner: a FALLBACK the client (spawnPolice) uses when the qbx callback
-- 'qbx_policejob:server:spawnVehicle' returns nothing. qbx fails for (a) models not in qbx_core's
-- vehicle registry - its `GetVehiclesByHash(joaat(model)).type` HARD-ERRORS on a nil entry - and
-- (b) transient owner-sync timeouts where it self-deletes the spawned vehicle. This path resolves the
-- vehicle type SAFELY (pcall + a temp-vehicle probe) and NEVER self-deletes, then returns the netId so
-- the client warps itself in (no fragile server-side ownership dance). On-duty legal members only.
lib.callback.register('pengu_pd:spawnFleetVehicle', function(source, model, x, y, z, h, plate)
    local p = onDutyLeo(source)
    if not p then return end
    if type(model) ~= 'string' or model == '' then return end
    model = model:lower():gsub('%s+', '')
    -- Guard: model must be in this faction's fleet DB (prevents on-duty LEOs spawning arbitrary models).
    local fac = factionOf(p)
    if not fac then return end
    local inFleet = MySQL.scalar.await('SELECT id FROM pengu_pd_fleet WHERE faction = ? AND model = ?', { fac, model })
    if not inFleet then return end
    -- Server-authoritative proximity: the officer must REALLY be at one of their faction's garage /
    -- parking / helipad points, and the vehicle spawns at that point's coords - NOT the client-supplied
    -- x,y,z,h (a forged callback otherwise spawns police vehicles anywhere on the map).
    local loc = nearestPdLocation(source, { garage = true, parking = true, helipad = true }, fac, 15.0)
    if not loc then return end
    x, y, z, h = loc.x, loc.y, loc.z, (loc.heading or 0.0)
    local hash = joaat(model)

    -- nil-safe vehicle TYPE (the value CreateVehicleServerSetter needs). Try the qbx registry first,
    -- then probe a throwaway server vehicle for its type (covers addon models not in the registry).
    local vtype
    local ok, entry = pcall(function() return exports.qbx_core:GetVehiclesByHash(hash) end)
    if ok and type(entry) == 'table' and entry.type and entry.type ~= '' then
        vtype = entry.type
    else
        local temp = CreateVehicle(hash, 0.0, 0.0, -250.0, 0.0, true, true)
        local n = 0
        while not DoesEntityExist(temp) and n < 50 do Wait(10); n = n + 1 end
        if DoesEntityExist(temp) then
            vtype = GetVehicleType(temp)
            DeleteEntity(temp)
        end
        if not vtype or vtype == '' then
            print(('[pengu_core] spawnFleetVehicle: could not resolve type for model %s (hash %d) - spawn rejected'):format(model, hash))
            return
        end
    end

    local veh = CreateVehicleServerSetter(hash, vtype,
        (tonumber(x) or 0.0) + 0.0, (tonumber(y) or 0.0) + 0.0, (tonumber(z) or 0.0) + 0.0, (tonumber(h) or 0.0) + 0.0)
    if not veh or veh == 0 then return end
    local n = 0
    while not DoesEntityExist(veh) and n < 100 do Wait(10); n = n + 1 end
    if not DoesEntityExist(veh) then return end

    if type(plate) == 'string' and plate ~= '' then SetVehicleNumberPlateText(veh, plate) end
    Entity(veh).state:set('penguFleet', true, true)
    pcall(function() exports.qbx_vehiclekeys:GiveKeys(source, veh) end)
    return NetworkGetNetworkIdFromEntity(veh)
end)

-- Tag a just-spawned fleet vehicle as penguFleet SERVER-SIDE (authoritative, always replicates) so the
-- parking checkpoint + helipad store check recognise it. The client also sets this after spawn, but on
-- a slow heli netId sync that client-side set is skipped (lib.waitFor times out) - then a legit buzzard
-- pulled from the police garage is rejected with "only faction fleet vehicles can be parked". This
-- reliable server path closes that gap. On-duty legal members only.
RegisterNetEvent('pengu_pd:tagFleet', function(netId)
    local src = source
    if not onDutyLeo(src) then return end
    netId = tonumber(netId)
    if not netId then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not (veh and veh ~= 0 and DoesEntityExist(veh) and GetEntityType(veh) == 2) then return end
    -- Only allow tagging actual fleet MODELS. Without this an on-duty LEO could pass an arbitrary netId
    -- to tag any civilian vehicle as fleet (then park/delete it). GlobalState.penguFleetModels is the
    -- authoritative set of spawnable fleet models, so a non-fleet vehicle can never be tagged.
    local fm = GlobalState.penguFleetModels
    if not (fm and fm[GetEntityModel(veh)]) then return end
    Entity(veh).state:set('penguFleet', true, true)
end)

-- Menu fetches the faction's issued-gear list from the DB.
lib.callback.register('pengu_pd:getArmoury', function(source)
    local p = onDutyLeo(source)
    local fac = p and factionOf(p)
    if not fac then return { items = {}, canManage = false } end
    local rows = MySQL.query.await(
        'SELECT item, grade FROM pengu_pd_armory WHERE faction = ? AND enabled = 1 ORDER BY sort, id',
        { fac }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local disp = armoryDisp(r.item)
        out[#out + 1] = { item = r.item, label = disp.label, icon = disp.icon, grade = tonumber(r.grade) or 0 }
    end
    return { items = out, canManage = isBoss(p.PlayerData.job) }
end)

-- Authoritative take: re-validate LEO + faction armory DB + player grade.
RegisterNetEvent('pengu_pd:takeArmouryItem', function(itemName)
    local src = source
    local p = onDutyLeo(src)
    if not p or type(itemName) ~= 'string' then return end
    local fac = factionOf(p)
    local grade = (p.PlayerData.job.grade and p.PlayerData.job.grade.level) or 0

    -- Server-authoritative proximity: must really be at one of this faction's armory points (a forged
    -- takeArmouryItem event otherwise hands out weapons/ammo anywhere on the map).
    if not nearestPdLocation(src, { armory = true }, fac, 10.0) then
        notify(src, 'You must be at the armory.', 'error', 'ARMORY')
        return
    end

    local row = MySQL.single.await(
        'SELECT grade, count FROM pengu_pd_armory WHERE faction = ? AND item = ? AND enabled = 1',
        { fac, itemName })
    if not row then return end
    local reqGrade = tonumber(row.grade) or 0
    if grade < reqGrade then
        notify(src, 'You need grade ' .. reqGrade .. ' to draw that.', 'error', 'ARMORY')
        return
    end

    -- Curated catalog items carry metadata (registered weapons, serials); arbitrary
    -- chief-added items are given plain. Count: DB override > curated display > 1.
    local entry
    for i = 1, #ARMOURY_SHOP.inventory do
        if ARMOURY_SHOP.inventory[i].name == itemName then entry = ARMOURY_SHOP.inventory[i]; break end
    end
    local count = tonumber(row.count) or 1 -- DB is authoritative (seeded from curated counts, chief-editable)
    if count < 1 then count = 1 end
    local ok = exports.ox_inventory:AddItem(src, itemName, count, entry and entry.metadata or nil)
    if not ok then
        notify(src, 'Your inventory is full.', 'error', 'ARMORY')
    end
end)

-- Officer fetches their faction's wardrobe (enabled presets they can see).
lib.callback.register('pengu_pd:getWardrobe', function(source)
    local p = onDutyLeo(source)
    local fac = p and factionOf(p)
    if not fac then return { items = {}, canManage = false } end
    local rows = MySQL.query.await(
        'SELECT id, preset, label, kind, components, gender, grade FROM pengu_pd_wardrobe WHERE faction = ? AND enabled = 1 ORDER BY sort, id',
        { fac }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local d = wardrobeDisp(r)
        out[#out + 1] = {
            id = r.id, preset = r.preset, kind = d.kind, name = d.name, meta = d.meta, icon = d.icon,
            grade = tonumber(r.grade) or 0,
            gender = r.gender,
            components = (r.components and r.components ~= '') and json.decode(r.components) or nil,
        }
    end
    return { items = out, canManage = isBoss(p.PlayerData.job) }
end)

-- Chief: fetch full armory (items + catalog of items not yet added) for management.
lib.callback.register('pengu_pd:getArmoryForManage', function(source)
    local p, fac = chiefOf(source)
    if not p or not fac then return nil end
    local rows = MySQL.query.await(
        'SELECT id, item, grade, count FROM pengu_pd_armory WHERE faction = ? AND enabled = 1 ORDER BY sort, id',
        { fac }) or {}
    local inArmory, items = {}, {}
    for _, r in ipairs(rows) do
        local disp = armoryDisp(r.item)
        items[#items + 1] = { id = r.id, item = r.item, label = disp.label, icon = disp.icon, grade = tonumber(r.grade) or 0, count = tonumber(r.count) or 1 }
        inArmory[r.item] = true
    end
    -- Quick-add catalog = this faction kind's curated starter set (not the police gear for a
    -- non-LEO faction). EMS shows an empty curated list and relies on the full-item picker.
    local catalog = {}
    for _, it in ipairs(ARMOURY_SEED_BY_KIND[kindOf(fac)] or {}) do
        if not inArmory[it.name] then
            local disp = ARMOURY_DISPLAY[it.name] or { label = it.name, icon = 'item' }
            catalog[#catalog + 1] = { item = it.name, label = disp.label, icon = disp.icon }
        end
    end
    return { items = items, catalog = catalog, faction = fac }
end)

-- Chief: fetch full wardrobe (all presets, enabled or not) for management.
lib.callback.register('pengu_pd:getWardrobeForManage', function(source)
    local p, fac = chiefOf(source)
    if not p or not fac then return nil end
    local rows = MySQL.query.await(
        'SELECT id, preset, label, kind, grade, enabled FROM pengu_pd_wardrobe WHERE faction = ? ORDER BY sort, id',
        { fac }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local d = wardrobeDisp(r)
        out[#out + 1] = { id = r.id, preset = r.preset, kind = d.kind, name = d.name, meta = d.meta, icon = d.icon, grade = tonumber(r.grade) or 0, enabled = (tonumber(r.enabled) or 1) == 1 }
    end
    return { items = out, faction = fac }
end)

-- Chief: add ANY ox_inventory item to their faction's armory (full customizability).
-- Accepts a plain item name or a table { item, count, grade }.
RegisterNetEvent('pengu_pd:armoryAdd', function(data)
    local p, fac = chiefOf(source)
    if not p or not fac then return end
    local itemName = type(data) == 'table' and data.item or data
    if type(itemName) ~= 'string' or itemName == '' then return end
    local okItem, def = pcall(function() return exports.ox_inventory:Items(itemName) end)
    if not okItem or not def then
        notify(source, ('Unknown item: %s'):format(itemName), 'error', 'ARMORY')
        return
    end
    -- Default grade from the curated catalog if present, else 0; override allowed.
    local grade = 0
    for _, it in ipairs(ARMOURY_SHOP.inventory) do
        if it.name == itemName then grade = it.grade or 0; break end
    end
    if type(data) == 'table' and data.grade ~= nil then grade = math.max(0, math.floor(tonumber(data.grade) or 0)) end
    local count = armoryDisp(itemName).count or 1 -- curated give-count (ammo stacks) as the default
    if type(data) == 'table' and data.count ~= nil then count = math.max(1, math.floor(tonumber(data.count) or 1)) end
    -- A row may already exist either enabled (already stocked) or soft-deleted (enabled=0,
    -- a chief removed it earlier). Re-enable a tombstone instead of inserting a duplicate.
    local existing = MySQL.single.await('SELECT id, enabled FROM pengu_pd_armory WHERE faction = ? AND item = ?', { fac, itemName })
    if existing then
        if tonumber(existing.enabled) == 1 then
            notify(source, 'That item is already stocked.', 'inform', 'ARMORY')
            return
        end
        MySQL.update.await('UPDATE pengu_pd_armory SET enabled = 1, grade = ?, count = ? WHERE id = ?', { grade, count, existing.id })
        notify(source, ('Re-stocked %s in %s armory.'):format(def.label or itemName, fac:upper()), 'success', 'ARMORY')
        return
    end
    MySQL.insert.await('INSERT INTO pengu_pd_armory (faction, item, grade, count, enabled, sort) VALUES (?, ?, ?, ?, 1, 999)',
        { fac, itemName, grade, count })
    notify(source, ('Added %s to %s armory.'):format(def.label or itemName, fac:upper()), 'success', 'ARMORY')
end)

-- Chief: update the give-count for an armory item.
RegisterNetEvent('pengu_pd:armorySetCount', function(id, count)
    local p, fac = chiefOf(source)
    if not p or not fac then return end
    id = tonumber(id); if not id then return end
    count = math.max(1, math.floor(tonumber(count) or 1))
    MySQL.update.await('UPDATE pengu_pd_armory SET count = ? WHERE id = ? AND faction = ?', { count, id, fac })
end)

-- Chief: full ox_inventory item list (name + label) for the "add item" picker.
lib.callback.register('pengu_pd:getAllItems', function(source)
    local p, fac = chiefOf(source)
    if not p or not fac then return {} end
    local all = exports.ox_inventory:Items() or {}
    local out = {}
    for name, def in pairs(all) do
        if type(def) == 'table' then
            out[#out + 1] = { item = name, label = (def.label and def.label ~= '' and def.label) or name }
        end
    end
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    return out
end)

-- Chief: remove an item from their faction's armory. SOFT-delete (enabled=0) so the boot
-- backfill - which re-adds any missing curated/cross-resource item by (faction,item) - cannot
-- resurrect a deliberate removal. getArmoury / getArmoryForManage / takeArmouryItem all filter
-- enabled=1, so the item disappears from the menu and cannot be drawn; armoryAdd re-enables it.
RegisterNetEvent('pengu_pd:armoryRemove', function(id)
    local p, fac = chiefOf(source)
    if not p or not fac then return end
    id = tonumber(id); if not id then return end
    MySQL.update.await('UPDATE pengu_pd_armory SET enabled = 0 WHERE id = ? AND faction = ?', { id, fac })
end)

-- Chief: update grade requirement on an armory item.
RegisterNetEvent('pengu_pd:armorySetGrade', function(id, grade)
    local p, fac = chiefOf(source)
    if not p or not fac then return end
    id = tonumber(id); if not id then return end
    grade = math.max(0, math.floor(tonumber(grade) or 0))
    MySQL.update.await('UPDATE pengu_pd_armory SET grade = ? WHERE id = ? AND faction = ?', { grade, id, fac })
end)

-- Chief: update grade requirement on a wardrobe preset.
RegisterNetEvent('pengu_pd:wardrobeSetGrade', function(id, grade)
    local p, fac = chiefOf(source)
    if not p or not fac then return end
    id = tonumber(id); if not id then return end
    grade = math.max(0, math.floor(tonumber(grade) or 0))
    MySQL.update.await('UPDATE pengu_pd_wardrobe SET grade = ? WHERE id = ? AND faction = ?', { grade, id, fac })
end)

-- Chief: enable or disable a wardrobe preset for their faction.
RegisterNetEvent('pengu_pd:wardrobeToggle', function(id, enabled)
    local p, fac = chiefOf(source)
    if not p or not fac then return end
    id = tonumber(id); if not id then return end
    MySQL.update.await('UPDATE pengu_pd_wardrobe SET enabled = ? WHERE id = ? AND faction = ?',
        { enabled and 1 or 0, id, fac })
end)

-- Chief: save the chief's CURRENT outfit as a new faction wardrobe preset.
-- data = { name = string, components = table (client-captured), gender = 'male'|'female'|'any' }
RegisterNetEvent('pengu_pd:wardrobeAdd', function(data)
    local p, fac = chiefOf(source)
    if not p or not fac or type(data) ~= 'table' then return end
    if type(data.components) ~= 'table' then return end
    local name = type(data.name) == 'string' and data.name:gsub('[^%w%s%-]', ''):sub(1, 40) or ''
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then name = 'Outfit' end
    local gender = (data.gender == 'female' and 'female') or (data.gender == 'male' and 'male') or 'any'
    -- Unique slug per faction, capped to fit preset VARCHAR(32) (base 28 + '_NN' suffix).
    local slug = ('of_' .. name:lower():gsub('[^%w]+', '_')):sub(1, 28)
    local base, n = slug, 1
    while MySQL.single.await('SELECT id FROM pengu_pd_wardrobe WHERE faction = ? AND preset = ?', { fac, slug }) do
        n = n + 1; slug = base .. '_' .. n
    end
    MySQL.insert.await(
        "INSERT INTO pengu_pd_wardrobe (faction, preset, label, kind, components, gender, grade, enabled, sort) VALUES (?, ?, ?, 'outfit', ?, ?, 0, 1, 999)",
        { fac, slug, name, json.encode(data.components), gender })
    notify(source, ('Saved outfit "%s" to %s wardrobe.'):format(name, fac:upper()), 'success', 'WARDROBE')
end)

-- Chief: remove a wardrobe preset (builtin or custom).
RegisterNetEvent('pengu_pd:wardrobeRemove', function(id)
    local p, fac = chiefOf(source)
    if not p or not fac then return end
    id = tonumber(id); if not id then return end
    MySQL.update.await('DELETE FROM pengu_pd_wardrobe WHERE id = ? AND faction = ?', { id, fac })
end)

-- Chief: rename a wardrobe preset.
RegisterNetEvent('pengu_pd:wardrobeRename', function(id, name)
    local p, fac = chiefOf(source)
    if not p or not fac then return end
    id = tonumber(id); if not id then return end
    name = type(name) == 'string' and name:gsub('[^%w%s%-]', ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 40) or ''
    if name == '' then return end
    MySQL.update.await('UPDATE pengu_pd_wardrobe SET label = ? WHERE id = ? AND faction = ?', { name, id, fac })
end)

-- Returns all rows as { id, type, label, x, y, z, heading }.
local function fetchLocations()
    return MySQL.query.await('SELECT id, type, label, x, y, z, heading, invisible, faction FROM pengu_pd_locations ORDER BY id') or {}
end

-- PenguRP jail: publish the chosen 'cell' (jail) + 'lobby' (release) marker coords to server
-- GlobalState so the self-contained jail (server/jail.lua) and every client read them live with
-- no restart. The first row of each type wins. Re-run on boot and after every /pdloc change.
local function publishJailCoords()
    local cell, lobby
    local rows = fetchLocations()
    for i = 1, #rows do
        local r = rows[i]
        if r.type == 'cell' and not cell then
            cell = { x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0, w = (r.heading or 0.0) + 0.0 }
        elseif r.type == 'lobby' and not lobby then
            lobby = { x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0, w = (r.heading or 0.0) + 0.0 }
        end
    end
    GlobalState.penguJailAnchor = cell
    GlobalState.penguJailLobby  = lobby
end

-- Nearest 'cell' pdloc to a world position (server-side). pengu_mdt /jail uses this so a suspect is
-- jailed AT whatever cell the officer is standing next to (not one global anchor).
local function nearestCell(x, y, z)
    local rows = fetchLocations()
    local best, bestSq
    for i = 1, #rows do
        local r = rows[i]
        if r.type == 'cell' then
            local dx, dy, dz = r.x - x, r.y - y, r.z - z
            local sq = dx * dx + dy * dy + dz * dz
            if not bestSq or sq < bestSq then
                bestSq = sq
                best = { x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0, w = (r.heading or 0.0) + 0.0 }
            end
        end
    end
    if best then best.dist = math.sqrt(bestSq) end
    return best
end

exports('GetNearestCell', function(x, y, z)
    return nearestCell(tonumber(x) or 0.0, tonumber(y) or 0.0, tonumber(z) or 0.0)
end)

-- Push the current list to every client so markers/interactions update with no restart.
local function broadcast()
    TriggerClientEvent('pengu_pd:locationsUpdated', -1, fetchLocations())
    publishJailCoords()
end

-- ============================ setup on start ============================

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS pengu_pd_locations (
            id         INT AUTO_INCREMENT PRIMARY KEY,
            type       VARCHAR(24)  NOT NULL,
            label      VARCHAR(64)  NOT NULL DEFAULT '',
            x          FLOAT        NOT NULL,
            y          FLOAT        NOT NULL,
            z          FLOAT        NOT NULL,
            heading    FLOAT        NOT NULL DEFAULT 0.0,
            invisible  TINYINT      NOT NULL DEFAULT 0,
            faction    VARCHAR(24)  NOT NULL DEFAULT '',
            created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    ]])

    -- migration: add the 'invisible' flag to tables created before this feature existed.
    local hasInvisible = MySQL.query.await([[
        SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengu_pd_locations' AND COLUMN_NAME = 'invisible'
    ]])
    if not (hasInvisible and hasInvisible[1] and tonumber(hasInvisible[1].c) == 1) then
        MySQL.query.await('ALTER TABLE pengu_pd_locations ADD COLUMN invisible TINYINT NOT NULL DEFAULT 0')
    end

    -- migration: add per-faction scoping ('' = shared / all legal factions, else members-only)
    -- BEFORE any client-served fetchLocations (which SELECTs `faction`), so a getLocations call on
    -- the first upgrade boot can never hit 'Unknown column faction'. Mirrors the invisible block.
    local hasFaction = MySQL.query.await([[
        SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengu_pd_locations' AND COLUMN_NAME = 'faction'
    ]])
    if not (hasFaction and hasFaction[1] and tonumber(hasFaction[1].c) == 1) then
        MySQL.query.await("ALTER TABLE pengu_pd_locations ADD COLUMN faction VARCHAR(24) NOT NULL DEFAULT ''")
    end

    local countRow = MySQL.query.await('SELECT COUNT(*) AS n FROM pengu_pd_locations')
    local n = (countRow and countRow[1] and countRow[1].n) or 0

    if n == 0 then
        for i = 1, #SEED do
            local s = SEED[i]
            MySQL.insert.await(
                'INSERT INTO pengu_pd_locations (type, label, x, y, z, heading) VALUES (?, ?, ?, ?, ?, ?)',
                { s.type, s.label, s.x, s.y, s.z, 0.0 }
            )
        end
        print(('[pengu_pd] seeded %d default PD locations'):format(#SEED))
    end

    -- Per-faction fleet table + one-time seed (police/bcso/sasp each get the defaults).
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS pengu_pd_fleet (
            id      INT AUTO_INCREMENT PRIMARY KEY,
            faction VARCHAR(24)  NOT NULL,
            model   VARCHAR(48)  NOT NULL,
            label   VARCHAR(64)  NOT NULL DEFAULT '',
            icon    VARCHAR(16)  NOT NULL DEFAULT 'car',
            grade   INT          NOT NULL DEFAULT 0,
            mods    LONGTEXT,
            air     TINYINT      NOT NULL DEFAULT 0,
            sort    INT          NOT NULL DEFAULT 0,
            INDEX idx_fleet_faction (faction)
        )
    ]])

    -- migration: add the 'air' flag (0 = ground car, 1 = aircraft) to fleet tables created before
    -- the helipad feature. MUST run before any getFleet/getAirFleet query and the air seed below;
    -- existing rows default to air = 0 (correct - they are ground cars). Mirrors the invisible block.
    local hasAir = MySQL.query.await([[
        SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengu_pd_fleet' AND COLUMN_NAME = 'air'
    ]])
    if not (hasAir and hasAir[1] and tonumber(hasAir[1].c) == 1) then
        MySQL.query.await('ALTER TABLE pengu_pd_fleet ADD COLUMN air TINYINT NOT NULL DEFAULT 0')
    end

    -- Seed each legal faction that has NO ground-fleet rows yet (covers fresh installs AND a newly
    -- added faction such as EMS, without re-adding cars a boss has since removed). air = 0 only so
    -- car/air seeding stay independent.
    for _, fac in ipairs(legalFactions()) do
        local has = MySQL.query.await('SELECT id FROM pengu_pd_fleet WHERE faction = ? AND air = 0 LIMIT 1', { fac })
        if not has or #has == 0 then
            local seed = FLEET_SEED_BY_KIND[kindOf(fac)] or FLEET_SEED_BY_KIND.leo
            for i = 1, #seed do
                local c = seed[i]
                MySQL.insert.await(
                    'INSERT INTO pengu_pd_fleet (faction, model, label, icon, grade, air, sort) VALUES (?, ?, ?, ?, 0, 0, ?)',
                    { fac, c.model, c.label, c.icon, i })
            end
            if #seed > 0 then print(('[pengu_pd] seeded %s fleet (%d cars)'):format(fac, #seed)) end
        end
    end

    -- Seed each legal faction's AIR fleet (helipad) if it has none yet. Independent of the ground
    -- seed above so an existing server (cars already seeded) still gets its starter aircraft.
    for _, fac in ipairs(legalFactions()) do
        local has = MySQL.query.await('SELECT id FROM pengu_pd_fleet WHERE faction = ? AND air = 1 LIMIT 1', { fac })
        if not has or #has == 0 then
            local seed = AIR_FLEET_SEED_BY_KIND[kindOf(fac)] or AIR_FLEET_SEED_BY_KIND.leo
            for i = 1, #seed do
                local c = seed[i]
                MySQL.insert.await(
                    'INSERT INTO pengu_pd_fleet (faction, model, label, icon, grade, air, sort) VALUES (?, ?, ?, ?, 0, 1, ?)',
                    { fac, c.model, c.label, c.icon, i })
            end
            if #seed > 0 then print(('[pengu_pd] seeded %s air fleet (%d aircraft)'):format(fac, #seed)) end
        end
    end

    -- publish the fleet model set so the entities blacklist exempts legit fleet vehicles/aircraft.
    publishFleetModels()

    -- Per-faction armory: chiefs manage what items are available and at what grade.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS pengu_pd_armory (
            id      INT AUTO_INCREMENT PRIMARY KEY,
            faction VARCHAR(24) NOT NULL,
            item    VARCHAR(64) NOT NULL,
            grade   INT         NOT NULL DEFAULT 0,
            enabled TINYINT     NOT NULL DEFAULT 1,
            sort    INT         NOT NULL DEFAULT 0,
            INDEX idx_armory_faction (faction)
        )
    ]])

    -- Per-faction armoury backfill: for each legal faction, ensure every item in its kind's
    -- starter set exists (seeds fresh installs AND adds newly-introduced catalog items). LEO
    -- gets the police loadout; EMS starts empty (boss stocks medical gear via the picker).
    for _, fac in ipairs(legalFactions()) do
        local seed = ARMOURY_SEED_BY_KIND[kindOf(fac)] or ARMOURY_SEED_BY_KIND.leo or {}
        for i, it in ipairs(seed) do
            local ex = MySQL.query.await(
                'SELECT id FROM pengu_pd_armory WHERE faction = ? AND item = ?', { fac, it.name })
            if not ex or #ex == 0 then
                MySQL.insert.await(
                    'INSERT INTO pengu_pd_armory (faction, item, grade, enabled, sort) VALUES (?, ?, ?, 1, ?)',
                    { fac, it.name, it.grade or 0, i })
            end
        end
    end

    -- Per-faction wardrobe: chiefs toggle presets and set grade requirements.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS pengu_pd_wardrobe (
            id      INT AUTO_INCREMENT PRIMARY KEY,
            faction VARCHAR(24) NOT NULL,
            preset  VARCHAR(32) NOT NULL,
            grade   INT         NOT NULL DEFAULT 0,
            enabled TINYINT     NOT NULL DEFAULT 1,
            sort    INT         NOT NULL DEFAULT 0,
            INDEX idx_wardrobe_faction (faction)
        )
    ]])

    -- Seed each legal faction's wardrobe presets if it has none yet (fresh install OR new faction).
    for _, fac in ipairs(legalFactions()) do
        local has = MySQL.query.await('SELECT id FROM pengu_pd_wardrobe WHERE faction = ? LIMIT 1', { fac })
        if not has or #has == 0 then
            local presets = WARDROBE_SEED_BY_KIND[kindOf(fac)] or WARDROBE_SEED_BY_KIND.leo
            for i, preset in ipairs(presets) do
                MySQL.insert.await(
                    'INSERT INTO pengu_pd_wardrobe (faction, preset, grade, enabled, sort) VALUES (?, ?, 0, 1, ?)',
                    { fac, preset, i })
            end
            if #presets > 0 then print(('[pengu_pd] seeded %s wardrobe (%d presets)'):format(fac, #presets)) end
        end
    end

    -- Idempotent column migrations for full chief customizability (counts + custom outfits).
    local function ensureColumn(tbl, col, ddl)
        local exists = MySQL.scalar.await(
            'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            { tbl, col })
        if not exists then
            MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(tbl, ddl))
            print(('[pengu_pd] migrated %s.%s'):format(tbl, col))
        end
    end
    ensureColumn('pengu_pd_armory',   'count',      '`count` INT NOT NULL DEFAULT 1')
    ensureColumn('pengu_pd_wardrobe', 'label',      '`label` VARCHAR(48) NULL')
    ensureColumn('pengu_pd_wardrobe', 'kind',       "`kind` VARCHAR(16) NOT NULL DEFAULT 'builtin'")
    ensureColumn('pengu_pd_wardrobe', 'components', '`components` TEXT NULL')
    ensureColumn('pengu_pd_wardrobe', 'gender',     "`gender` VARCHAR(8) NOT NULL DEFAULT 'any'")
    -- (pengu_pd_locations.faction is migrated early, right after the 'invisible' column, so the
    -- live getLocations callback never SELECTs a column that doesn't exist yet.)
    -- Tag the seeded action presets so the client applies them correctly.
    MySQL.query.await("UPDATE pengu_pd_wardrobe SET kind = 'armor' WHERE preset = 'armor' AND (kind IS NULL OR kind = 'builtin')")
    MySQL.query.await("UPDATE pengu_pd_wardrobe SET kind = 'removearmor' WHERE preset = 'removearmor' AND (kind IS NULL OR kind = 'builtin')")

    -- Backfill curated give-counts (ammo stacks, cone pairs) onto rows still at the
    -- default of 1, so officers draw the intended amount (ammo-9 = 50, etc). Only
    -- touches rows still at 1, so a chief's deliberate count is never clobbered.
    for _name, _disp in pairs(ARMOURY_DISPLAY) do
        if _disp.count and _disp.count > 1 then
            MySQL.update.await('UPDATE pengu_pd_armory SET count = ? WHERE item = ? AND count = 1', { _disp.count, _name })
        end
    end

    -- Remove the mistakenly auto-seeded 'S95' pistol (WEAPON_PISTOL_MK2 was labelled
    -- S95 in error; S95 is a vehicle). Clears it from every faction armory.
    MySQL.query.await("DELETE FROM pengu_pd_armory WHERE item = 'WEAPON_PISTOL_MK2'")
    -- Radar is now a vehicle HUD, not an item; remove it from every faction armory.
    MySQL.query.await("DELETE FROM pengu_pd_armory WHERE item = 'radargun'")

    -- (No ox_inventory shop is registered: the armoury is an ox_lib NUI grid driven by the
    -- pengu_pd:getArmoury callback + pengu_pd:takeArmouryItem net event, both faction-aware.)

    -- Register a PERSONAL locker (owner=true -> each member gets their own instance, like the
    -- qbx police locker) for every legal faction that does NOT reuse the legacy 'policelocker',
    -- so each agency truly has its OWN locker. police/bcso/sasp keep 'policelocker' (registered
    -- by qbx_police), EMS+future factions get pengu_locker_<job>.
    for _, fac in ipairs(legalFactions()) do
        local stashId = Factions.lockerOf(fac)
        if stashId and stashId ~= 'policelocker' then
            local label = (Factions.legal[fac].label or fac:upper()) .. ' Locker'
            local okL, errL = pcall(function()
                exports.ox_inventory:RegisterStash(stashId, label, 30, 100000, true)
            end)
            if not okL then print(('[pengu_pd] failed to register %s: %s'):format(stashId, tostring(errL))) end
        end
    end

    -- Publish the jail cell/lobby coords for server/jail.lua once the rows exist.
    publishJailCoords()
end)

-- ============================ location callback ============================

lib.callback.register('pengu_pd:getLocations', function(_source)
    return fetchLocations()
end)

-- ============================ /pdloc command (owner-only) ============================

local USAGE = {
    '/pdloc add <type> [label]       - add a point at your coords+heading',
    '/pdloc remove <id>              - delete a point by id',
    '/pdloc setfaction <id> <fac>    - scope a point to one legal faction ("all" = shared)',
    '/pdloc setinvisible <id>        - hide a point marker (the point still works)',
    '/pdloc setvisible <id>          - show a hidden point marker again',
    '/pdloc list                     - list all points (flags hidden + faction-scoped)',
    'valid types: armory, locker, clothing, garage, duty, mugshot, parking, cell, lobby, fingerprint, helipad',
}

local function printUsage(src)
    for i = 1, #USAGE do
        notify(src, USAGE[i], 'inform')
    end
end

local function cmdAdd(src, args)
    if src <= 0 then
        notify(src, 'pdloc add must be run in-game (needs your ped position).', 'error')
        return
    end

    local ptype = args[2] and string.lower(args[2]) or nil
    if not ptype or not VALID_TYPES[ptype] then
        notify(src, 'invalid type. valid: armory, locker, clothing, garage, duty, mugshot, parking, cell, lobby, fingerprint, helipad', 'error')
        return
    end

    -- label = everything after the type, joined with spaces (optional).
    local label = ''
    if args[3] then
        local parts = {}
        for i = 3, #args do parts[#parts + 1] = args[i] end
        label = table.concat(parts, ' ')
    end
    if label == '' then
        label = ptype:sub(1, 1):upper() .. ptype:sub(2) .. ' Point'
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        notify(src, 'could not resolve your ped.', 'error')
        return
    end
    local coords  = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped) + 0.0

    local id = MySQL.insert.await(
        'INSERT INTO pengu_pd_locations (type, label, x, y, z, heading) VALUES (?, ?, ?, ?, ?, ?)',
        { ptype, label, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, heading }
    )

    notify(src, ('added %s point #%s "%s" at %.2f, %.2f, %.2f'):format(ptype, tostring(id), label, coords.x, coords.y, coords.z), 'success')
    broadcast()
end

local function cmdRemove(src, args)
    local id = tonumber(args[2])
    if not id then
        notify(src, 'usage: /pdloc remove <id>', 'error')
        return
    end

    local affected = MySQL.update.await('DELETE FROM pengu_pd_locations WHERE id = ?', { id })
    if affected and affected > 0 then
        notify(src, ('removed point #%d'):format(id), 'success')
        broadcast()
    else
        notify(src, ('no point with id #%d'):format(id), 'error')
    end
end

local function cmdList(src)
    local rows = fetchLocations()
    if #rows == 0 then
        notify(src, 'no PD locations set.', 'inform')
        return
    end
    notify(src, ('PD locations (%d):'):format(#rows), 'inform')
    for i = 1, #rows do
        local r = rows[i]
        local facTag = (r.faction and r.faction ~= '') and (' | ' .. r.faction:upper()) or ''
        notify(src, ('#%s | %s | %s | %.2f, %.2f, %.2f | h %.1f%s%s'):format(
            tostring(r.id), r.type, r.label, r.x, r.y, r.z, r.heading or 0.0, facTag,
            (tonumber(r.invisible) == 1) and ' | INVISIBLE' or ''), 'inform')
    end
end

-- Scope a point to one legal faction, or 'all' to share it with every legal faction.
local function cmdSetFaction(src, args)
    local id  = tonumber(args[2])
    local fac = args[3] and string.lower(args[3]) or nil
    if not id or not fac then
        notify(src, 'usage: /pdloc setfaction <id> <faction|all>', 'error')
        return
    end
    if fac == 'all' or fac == 'shared' or fac == 'none' then fac = '' end
    if fac ~= '' and not Factions.isLegal(fac) then
        notify(src, ('unknown legal faction "%s". valid: %s, or "all"'):format(fac, table.concat(legalFactions(), ', ')), 'error')
        return
    end
    local affected = MySQL.update.await('UPDATE pengu_pd_locations SET faction = ? WHERE id = ?', { fac, id })
    if affected and affected > 0 then
        notify(src, ('point #%d scoped to %s'):format(id, fac == '' and 'ALL legal factions' or fac:upper()), 'success')
        broadcast()
    else
        notify(src, ('no point with id #%d'):format(id), 'error')
    end
end

-- Hide / show a point's marker without deleting it. The point stays fully functional
-- (hold-Alt interaction + proximity hint); only the ring on the floor is removed.
local function cmdSetVisible(src, args, makeInvisible)
    local id = tonumber(args[2])
    if not id then
        notify(src, ('usage: /pdloc %s <id>'):format(makeInvisible and 'setinvisible' or 'setvisible'), 'error')
        return
    end
    local affected = MySQL.update.await('UPDATE pengu_pd_locations SET invisible = ? WHERE id = ?',
        { makeInvisible and 1 or 0, id })
    if affected and affected > 0 then
        notify(src, ('point #%d is now %s'):format(id, makeInvisible and 'INVISIBLE (no marker)' or 'VISIBLE'), 'success')
        broadcast()
    else
        notify(src, ('no point with id #%d'):format(id), 'error')
    end
end

-- Admin location placement. Manages EVERY legal faction's points (police/bcso/sasp/ems/...),
-- not just police, so it is registered under both /pdloc (legacy) and /factionloc (current name).
local function pdlocCommand(src, args)
    if not IsPlayerAceAllowed(src, 'pengu.placement') then
        notify(src, 'you are not allowed to use this command.', 'error')
        return
    end
    -- Requires the qbx admin opt-in: only works after you /aduty.
    if not exports.qbx_core:IsOptin(src) then
        notify(src, 'you must /aduty before using this command.', 'error')
        return
    end

    local sub = args[1] and string.lower(args[1]) or nil
    if sub == 'add' then
        cmdAdd(src, args)
    elseif sub == 'remove' or sub == 'delete' then
        cmdRemove(src, args)
    elseif sub == 'setfaction' or sub == 'faction' then
        cmdSetFaction(src, args)
    elseif sub == 'setinvisible' or sub == 'hide' then
        cmdSetVisible(src, args, true)
    elseif sub == 'setvisible' or sub == 'show' then
        cmdSetVisible(src, args, false)
    elseif sub == 'list' then
        cmdList(src)
    else
        printUsage(src)
    end
end

RegisterCommand('pdloc', pdlocCommand, false)
RegisterCommand('factionloc', pdlocCommand, false)
