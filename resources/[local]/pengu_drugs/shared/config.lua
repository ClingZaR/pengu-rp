-- PenguRP - Drug Supply Chain (pengu_drugs) CONFIG. Phase 3.2 PROCESSING tier.
-- The missing MIDDLE of the chain: GROW (qbx_weed) -> [PROCESS/PACKAGE here] -> SELL (qbx_drugs).
-- This first cut uses ONLY items that already exist in ox_inventory (no core items.lua edit): a
-- "weed press" lab turns 5 buds of any strain into 1 weed_brick (the exact item the qbx_drugs
-- delivery system pays out for + the corner-sell turf bonus rides). Cocaine/meth chains drop in
-- later as new labTypes once their precursor items are added. `Config` is a per-resource global.
-- ASCII only. luac clean.

Config = {}

Config.interactDist = 3.0   -- client interaction radius (wider so a lab table at the point never blocks reach); the server re-checks this (+slack) on every process

-- ===================== lab types =====================
-- Each type: label, marker colour, ox_target icon, and a list of recipes. A recipe converts INPUT
-- items -> OUTPUT items behind a skill-check gate. All items must already exist in ox_inventory.
local WEED_STRAINS = {
    'weed_og-kush', 'weed_white-widow', 'weed_skunk', 'weed_amnesia', 'weed_ak47', 'weed_purple-haze',
}
local weedPressRecipes = {}
for _, strain in ipairs(WEED_STRAINS) do
    weedPressRecipes[#weedPressRecipes + 1] = {
        label = 'Press ' .. strain:gsub('weed_', ''):gsub('-', ' '),
        input = { [strain] = 5 },
        output = { ['weed_brick'] = 1 },
        skill = { 'easy', 'medium' }, -- ox_lib lib.skillCheck difficulty (array = multi-stage)
        time  = 6000,
    }
end

Config.labTypes = {
    weed_press = {
        label  = 'Weed Press',
        marker = { r = 80, g = 200, b = 120 }, -- green
        icon   = 'fa-solid fa-cannabis',
        recipes = weedPressRecipes,
    },

    -- COCA FIELD - a respawning PLANT-NODE field (field=true), NOT a fixed recipe point. Each ACTIVE
    -- group of this type keeps up to maxPlants coca plants scattered within `radius` of its placed
    -- anchor(s). Harvest a plant -> it despawns -> after a random regrowMin..regrowMax delay a fresh one
    -- grows at a NEW random spot, back up to maxPlants. Yields coca_leaf (feeds the Cocaine Lab).
    -- Implemented by server/fields.lua + client/fields.lua. (coca_field/weed_field have NO recipes.)
    coca_field = {
        label              = 'Coca Field',
        icon               = 'fa-solid fa-seedling',
        field              = true,
        plantModel         = 'prop_plant_01a',
        plantModelFallback = 'prop_plant_01b',
        yield              = { item = 'coca_leaf', min = 2, max = 4 }, -- per harvest (RNG range)
        skill              = 'easy',
        harvestTime        = 5000,
        maxPlants          = 6,      -- max grown at once PER GROUP
        radius             = 14.0,   -- scatter radius (m) around the placed anchor(s)
        regrowMin          = 30000,  -- RNG regrow delay min (ms)
        regrowMax          = 90000,  -- RNG regrow delay max (ms)
    },

    -- CANNABIS FIELD - same respawning plant-node system as coca, for marijuana. Yields weed buds
    -- (weed_og-kush) that the Weed Press turns into weed_brick. Place with /labadd weed_field <group>.
    weed_field = {
        label              = 'Cannabis Field',
        icon               = 'fa-solid fa-cannabis',
        field              = true,
        plantModel         = 'bkr_prop_weed_med_01a',
        plantModelFallback = 'bkr_prop_weed_lrg_01a',
        yield              = { item = 'weed_og-kush', min = 3, max = 5 },
        skill              = 'easy',
        harvestTime        = 5000,
        maxPlants          = 6,
        radius             = 14.0,
        regrowMin          = 30000,
        regrowMax          = 90000,
    },
    cocaine = {
        label  = 'Cocaine Lab',
        marker = { r = 235, g = 235, b = 245 }, -- white-ish
        icon   = 'fa-solid fa-flask',
        recipes = {
            { label = 'Wash to paste', input = { ['coca_leaf'] = 4 },  output = { ['coca_paste'] = 1 }, skill = { 'medium', 'hard' }, time = 8000 },
            { label = 'Cut and bag',   input = { ['coca_paste'] = 1 }, output = { ['cokebaggy'] = 3 },  skill = 'medium',            time = 6000 },
            { label = 'Press brick',   input = { ['cokebaggy'] = 10 }, output = { ['coke_brick'] = 1 }, skill = { 'hard', 'hard' },  time = 9000 },
        },
    },

    -- METH chain. meth_supply GATHERS pseudo (cooldown-gated, like coca_field); the meth lab cooks
    -- pseudo -> meth_batch -> meth. The finished `meth` item already existed + is corner-sellable, so
    -- selling keeps the turf bonus. pseudo/meth_batch were added to ox_inventory items.lua.
    meth_supply = {
        label  = 'Pseudo Supply',
        marker = { r = 200, g = 160, b = 60 }, -- amber
        icon   = 'fa-solid fa-pills',
        recipes = {
            { label = 'Collect pseudoephedrine', input = {}, output = { ['pseudo'] = 2 }, skill = 'easy', time = 5000, cooldown = 25000 },
        },
    },
    meth = {
        label  = 'Meth Lab',
        marker = { r = 120, g = 230, b = 230 }, -- cyan
        icon   = 'fa-solid fa-vial',
        recipes = {
            { label = 'Cook batch',  input = { ['pseudo'] = 4 },     output = { ['meth_batch'] = 1 }, skill = { 'medium', 'hard' }, time = 9000 },
            { label = 'Crystallize', input = { ['meth_batch'] = 1 }, output = { ['meth'] = 3 },        skill = { 'hard', 'hard' },   time = 8000 },
        },
    },
}

-- ===================== lab groups (multi-table clusters) =====================
-- Each group = one "drug lab" location made up of multiple table interaction points.
-- All tables in a group share the same active/disabled state; controlled with
-- /labenable <group_name> and /labdisable <group_name>.
-- Tables are placed at (x+dx, y+dy, z). group_name: unique, lowercase, no spaces.
-- Add more tables to a group in-game with /labadd <type> <group_name> [label].
Config.labGroups = {} -- cleared; admin places labs fresh with /labadd

Config.defaultLabel = 'Drug Lab'

-- World visual per lab type so each lab is VISIBLE up close (they were invisible ox_target spheres with
-- no blip - criminal points stay unmarked on the map by design, so the on-site ped IS the locator).
-- `ped = true` spawns a ped, false spawns a prop. The sphere zone still handles the interaction. Each
-- model is IsModelValid-guarded. Tune freely (e.g. swap to lab-equipment props if you prefer).
-- NOTE: coca_field/weed_field are NOT here - field types render as live PLANT NODES (client/fields.lua),
-- so the anchor itself has no prop. Only PROCESS labs get a static visual.
Config.visuals = {
    weed_press  = { model = 'bkr_prop_weed_table_01a',      ped = false }, -- weed processing table
    cocaine     = { model = 'bkr_prop_coke_cut_01',         ped = false }, -- cocaine cutting table
    meth_supply = { model = 'bkr_prop_meth_pseudoephedrine', ped = false }, -- pseudo supply
    meth        = { model = 'bkr_prop_meth_table01a',       ped = false }, -- meth lab table
}
