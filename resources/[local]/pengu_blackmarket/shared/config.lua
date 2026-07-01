-- PenguRP - Black Market (pengu_blackmarket) CONFIG. Phase 3.4.
-- Weapons are sold by the placeable, gang-controllable "weapons" Arms Dealer in pengu_dealers; THIS
-- resource just owns the CRATE DROP a weapon order produces (catalog below + the OrderWeapon export).
-- SMALL goods (ammo/attachments) are handed over on the spot; WEAPONS are NOT - the order takes dirty
-- money and DROPS a crate (Config.dropSites) the buyer must collect and pry open with a crowbar.
-- Server-authoritative. `Config` is a per-resource global. ASCII only. luac clean.

Config = {}

Config.dirtyItem = 'black_money'

-- ===== weapon crate drops =====
-- where a weapon shipment can drop (server picks one per order). The buyer gets a GPS waypoint to it;
-- the crate prop + retrieval zone spawn there until collected or it expires.
Config.dropSites = {
    { x = 1237.0,  y = -3110.0, z = 5.0,  label = 'Elysian Island container yard' },
    { x = 24.0,    y = -1750.0, z = 29.0, label = 'Davis back alley' },
    { x = 1700.0,  y = 4920.0,  z = 42.0, label = 'Grapeseed back road' }, -- open solid ground (was the
                                                                            -- Vespucci canals = water risk)
    { x = 2348.0,  y = 3133.0,  z = 48.2, label = 'Sandy Shores airfield' },
    { x = -445.0,  y = -1690.0, z = 19.0, label = 'La Mesa rail yard' },
    { x = 152.0,   y = -3206.0, z = 5.9,  label = 'Terminal docks' },
}
-- crate model. IMPORTANT: GTA cannot scale plain props (SetEntityScale is a no-op on objects), so
-- changing the SIZE means choosing a different MODEL. This is the SMALLER military-crate variant of the
-- original prop_mil_crate_01 (which was too big); prop_box_ammo07a/prop_gun_case_01 were too small.
-- Other VALID options on this build, roughly SMALL -> LARGE - just swap the value below:
--   prop_box_ammo04a        (small ammo box)
--   prop_mil_crate_02       (small military crate)      <- current
--   prop_drop_armscrate_01  (arms drop crate, medium)
--   prop_crate_02a          (medium wooden crate)
--   prop_mil_crate_01       (large military crate, the original)
Config.crateModel  = 'prop_mil_crate_02'
-- fallback if crateModel ever fails IsModelValid on this build (retrieval also has a sphere-zone fallback):
Config.crateModelFallback = 'prop_box_ammo07a'
Config.crateExpire = 1800                -- seconds an undelivered crate survives before it is forfeited
Config.dropBlip    = { sprite = 478, colour = 5, scale = 0.9, label = 'Weapon Drop' }
Config.crateDist   = 2.5                 -- retrieval interaction radius
Config.streamIn    = 40.0               -- spawn the crate prop/zone within this many metres (close enough
                                        -- that static collision is loaded so the prop snaps to the ground)
Config.streamOut   = 55.0               -- despawn it again beyond this

-- the item required to PRY A CRATE OPEN (owner or rival). Reusable - it is NOT consumed on use.
-- WEAPON_CROWBAR already exists in ox_inventory (data/weapons.lua) with a matching image.
Config.crowbarItem = 'WEAPON_CROWBAR'

-- rival interception is timed server-side so it cannot be script-skipped: a rival must hold the crate
-- for at least interceptMinSeconds (kept just under the client skillcheck+progress), and one rival's
-- claim blocks others for interceptClaimWindow seconds.
Config.interceptMinSeconds  = 4
Config.interceptClaimWindow = 30

-- carry visual: the crate prop attached to your ped while you carry it. Tune offsets if it clips.
Config.carry = {
    bone     = 28422,   -- SKEL_R_Hand
    px       = 0.12, py = 0.02, pz = -0.22,
    rx       = 60.0, ry = 160.0, rz = 0.0,
    animDict = 'anim@heists@box_carry@',
    animClip = 'idle',
}

-- Illegal import catalog. weapon=true -> 1 unregistered weapon; else gives `count` units.
-- minLevel = gang level required (pengu_gangs:GetLevel). Thresholds match the new hard curve:
--   Lvl 2 = 5,000 rep | Lvl 3 = 15,000 | Lvl 4 = 40,000 | Lvl 5 = 90,000 | Lvl 6 = 200,000
-- Study the time it takes players to accumulate rep and balance prices accordingly.
Config.catalog = {
    -- LEVEL 1 (entry / all gangs)
    { item = 'WEAPON_SNSPISTOL',      label = 'SNS Pistol',          price = 8000,   weapon = true, minLevel = 1 },
    { item = 'ammo-9',                label = '9mm Ammo (x30)',      price = 1200,   count = 30,   minLevel = 1 },
    { item = 'spraycan',              label = 'Spray Cans (x5)',     price = 750,    count = 5,    minLevel = 1 },

    -- LEVEL 2 (5,000 rep — several weeks of regular crime)
    { item = 'WEAPON_PISTOL',         label = 'Pistol .50',          price = 15000,  weapon = true, minLevel = 2 },
    { item = 'at_suppressor_light',   label = 'Suppressor (Light)',  price = 32000,               minLevel = 2 },
    { item = 'ammo-rifle',            label = 'Rifle Ammo (x30)',    price = 1800,   count = 30,   minLevel = 2 },

    -- LEVEL 3 (15,000 rep — committed, organised gang)
    { item = 'WEAPON_APPISTOL',       label = 'AP Pistol',           price = 28000,  weapon = true, minLevel = 3 },
    { item = 'WEAPON_PUMPSHOTGUN',    label = 'Pump Shotgun',        price = 40000,  weapon = true, minLevel = 3 },
    { item = 'at_ar_flsh',            label = 'Flashlight (AR)',     price = 12000,               minLevel = 3 },

    -- LEVEL 4 (40,000 rep — established crew, months of play)
    { item = 'WEAPON_MICROSMG',       label = 'Micro SMG',           price = 55000,  weapon = true, minLevel = 4 },
    { item = 'WEAPON_SMG',            label = 'SMG',                 price = 75000,  weapon = true, minLevel = 4 },
    { item = 'at_suppressor',         label = 'Suppressor (Heavy)',  price = 55000,               minLevel = 4 },

    -- LEVEL 5 (90,000 rep — top-tier street gang, rare)
    { item = 'WEAPON_CARBINERIFLE',   label = 'Carbine Rifle',       price = 130000, weapon = true, minLevel = 5 },
    { item = 'WEAPON_BULLPUPRIFLE',   label = 'Bullpup Rifle',       price = 110000, weapon = true, minLevel = 5 },
    { item = 'at_scope_small',        label = 'Compact Scope',       price = 45000,               minLevel = 5 },

    -- LEVEL 6 (200,000 rep — legendary status, near-impossible to reach)
    { item = 'WEAPON_SPECIALCARBINE', label = 'Special Carbine',     price = 220000, weapon = true, minLevel = 6 },
    { item = 'WEAPON_ASSAULTRIFLE',   label = 'Assault Rifle',       price = 200000, weapon = true, minLevel = 6 },
    { item = 'at_scope_medium',       label = 'Medium Scope',        price = 90000,               minLevel = 6 },
}
