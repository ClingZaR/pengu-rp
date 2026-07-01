-- PenguRP - Civilian Gathering Jobs (pengu_jobs) CONFIG. Phase 4.1.
-- A generalizable GATHER -> SELL loop for legal income (the legal mirror of the drug gather chain).
-- v1 ships MINING using only EXISTING ox_inventory items (no core items.lua edit): mine ore at a
-- mining spot, sell metals to a scrap dealer for CLEAN bank money. Fishing/lumberjack drop in later
-- as new gatherTypes once their items exist. `Config` is a per-resource global. ASCII only.

Config = {}

Config.interactDist = 3.0 -- a bit wider so a large prop (furnace/saw bench) at the point never blocks reach

-- GATHER point types: each has recipes (input map -> output map; empty input = pure gather), a skill
-- gate, a duration, and a per-recipe cooldown (server-enforced). Mirrors the pengu_drugs lab shape.
Config.gatherTypes = {
    mine = {
        label  = 'Mining Spot',
        icon   = 'fa-solid fa-gem',
        marker = { r = 150, g = 150, b = 165 },
        recipes = {
            { label = 'Mine ore', tool = 'pickaxe', input = {}, output = { ['metalscrap'] = 2, ['iron'] = 1 }, skill = 'easy',   time = 6000, cooldown = 8000 },
            { label = 'Deep vein', tool = 'pickaxe', input = {}, output = { ['copper'] = 1, ['aluminum'] = 1 }, skill = 'medium', time = 9000, cooldown = 15000 },
        },
    },
    fish = {
        label  = 'Fishing Spot',
        icon   = 'fa-solid fa-fish',
        marker = { r = 70, g = 150, b = 230 },
        recipes = {
            { label = 'Cast line', tool = 'fishingrod', input = {}, output = { ['raw_fish'] = 1 }, skill = 'easy', time = 8000, cooldown = 6000 },
        },
    },
    tree = {
        label  = 'Logging Site',
        icon   = 'fa-solid fa-tree',
        marker = { r = 120, g = 90, b = 50 },
        recipes = {
            { label = 'Chop wood', tool = 'axe', input = {}, output = { ['wood'] = 2 }, skill = 'medium', time = 8000, cooldown = 7000 },
        },
    },
    farm = {
        label  = 'Farm Field',
        icon   = 'fa-solid fa-seedling',
        marker = { r = 100, g = 180, b = 80 },
        recipes = {
            { label = 'Plant & harvest', tool = 'farm_seed', input = {}, output = { corn = 2, potato = 1, carrot = 1 }, skill = 'easy',   time = 10000, cooldown = 12000 },
        },
    },
    hunt = {
        label  = 'Hunting Ground',
        icon   = 'fa-solid fa-crosshairs',
        marker = { r = 180, g = 120, b = 60 },
        recipes = {
            { label = 'Track and hunt', tool = 'hunting_knife', input = {}, output = { raw_venison = 1, rabbit_fur = 1 }, skill = 'medium', time = 12000, cooldown = 20000 },
        },
    },
    butcher = {
        label  = 'Butcher Block',
        icon   = 'fa-solid fa-drumstick-bite',
        marker = { r = 210, g = 90, b = 90 },
        recipes = {
            { label = 'Butcher venison', input = { raw_venison = 2 }, output = { venison_steak = 3, leather = 1 }, skill = 'medium', time = 8000 },
            { label = 'Tan fur',         input = { rabbit_fur = 3 },  output = { leather = 1 },                    skill = 'easy',   time = 6000 },
        },
    },
    gym = {
        label  = 'Gym',
        icon   = 'fa-solid fa-dumbbell',
        marker = { r = 200, g = 80, b = 200 },
        recipes = {
            { label = 'Light workout',  output = { __stress__ = 15 }, skill = 'easy',   time = 8000,  cooldown = 60000,
              anim = { dict = 'amb@world_human_push_ups@male@idle_a',   clip = 'idle_a' } },
            { label = 'Hard workout',   output = { __stress__ = 30 }, skill = 'medium', time = 12000, cooldown = 120000,
              anim = { dict = 'amb@world_human_sit_ups@male@idle_a',    clip = 'idle_a' } },
            { label = 'Yoga session',   output = { __stress__ = 20 }, skill = 'easy',   time = 10000, cooldown = 90000,
              anim = { dict = 'amb@world_human_yoga@male@idle_a',       clip = 'idle_a' } },
        },
    },
    -- PROCESSING tier (input recipes, no cooldown - self-limited by needing raw materials). Smelting
    -- metalscrap (sells 12) into steel (sells 80) gives a real reason to process, not just sell raw.
    smelter = {
        label  = 'Smelter',
        icon   = 'fa-solid fa-fire',
        marker = { r = 230, g = 120, b = 40 },
        recipes = {
            { label = 'Smelt steel', input = { ['metalscrap'] = 3 }, output = { ['steel'] = 1 }, skill = 'medium', time = 7000 },
        },
    },
    grill = {
        label  = 'Grill',
        icon   = 'fa-solid fa-fire-burner',
        marker = { r = 220, g = 140, b = 60 },
        recipes = {
            { label = 'Cook fish',        input = { ['raw_fish'] = 1 },                                    output = { ['cooked_fish'] = 1 },    skill = 'easy',   time = 5000 },
            { label = 'Cook venison',     input = { ['raw_venison'] = 1 },                                 output = { ['venison_steak'] = 1 },  skill = 'easy',   time = 7000 },
            { label = 'Make veg soup',    input = { ['corn'] = 1, ['potato'] = 1, ['carrot'] = 1 },       output = { ['vegetable_soup'] = 2 }, skill = 'medium', time = 10000 },
        },
    },
    sawmill = {
        label  = 'Sawmill',
        icon   = 'fa-solid fa-tree',
        marker = { r = 150, g = 110, b = 70 },
        recipes = {
            { label = 'Mill planks', input = { ['wood'] = 2 }, output = { ['plank'] = 1 }, skill = 'medium', time = 7000 },
        },
    },
}

-- SELL point types: a price list (item -> clean money per unit). Selling pays to `account`.
Config.sellTypes = {
    metaldealer = {
        label   = 'Scrap Dealer',
        icon    = 'fa-solid fa-coins',
        marker  = { r = 90, g = 200, b = 120 },
        account = 'bank', -- qbx_core is cash=0 / all-in-bank
        prices  = { metalscrap = 12, iron = 40, copper = 55, aluminum = 50, steel = 80 },
    },
    fishmarket = {
        label   = 'Fish Market',
        icon    = 'fa-solid fa-fish',
        marker  = { r = 70, g = 150, b = 230 },
        account = 'bank',
        prices  = { raw_fish = 35, cooked_fish = 70 },
    },
    lumberyard = {
        label   = 'Lumber Yard',
        icon    = 'fa-solid fa-tree',
        marker  = { r = 120, g = 90, b = 50 },
        account = 'bank',
        prices  = { wood = 25, plank = 55 },
    },
    farmmarket = {
        label   = 'Farm Stand',
        icon    = 'fa-solid fa-carrot',
        marker  = { r = 100, g = 180, b = 80 },
        account = 'bank',
        prices  = { corn = 30, potato = 25, carrot = 20 },
    },
    butcher_market = {
        label   = 'Butcher Market',
        icon    = 'fa-solid fa-drumstick-bite',
        marker  = { r = 210, g = 90, b = 90 },
        account = 'bank',
        prices  = { raw_venison = 60, venison_steak = 120, rabbit_fur = 40, leather = 80 },
    },
    foodmarket = {
        label   = 'Food Stall',
        icon    = 'fa-solid fa-bowl-food',
        marker  = { r = 240, g = 170, b = 80 },
        account = 'bank',
        prices  = { cooked_fish = 70, venison_steak = 120, vegetable_soup = 90 },
    },
}

-- SHOP point types: SELL items TO players for clean money (the reverse of sellTypes) - e.g. the tools
-- that gather recipes now require. account = where the money is taken from.
Config.shopTypes = {
    hardware = {
        label   = 'Hardware Store',
        icon    = 'fa-solid fa-screwdriver-wrench',
        marker  = { r = 200, g = 180, b = 60 },
        account = 'bank',
        items   = { pickaxe = 500, axe = 450, fishingrod = 350, farm_seed = 100, hunting_knife = 300 },
    },
}

-- DELIVERY point types: a depot where players start a courier route (3-5 random stops from
-- Config.deliveryStops, one 'package' item per stop, paid per delivered stop by the server).
Config.deliveryTypes = {
    depot = {
        label  = 'Delivery Depot',
        icon   = 'fa-solid fa-truck-fast',
        marker = { r = 230, g = 190, b = 90 },
    },
}

-- Delivery tuning. Payment per stop = basePay + (depot->stop metres / 100) * payPer100m, capped
-- by maxDistancePay, then scaled by the delivery perk. All computed server-side from the
-- server's own stop list; the client only ever receives coords + labels.
Config.delivery = {
    item          = 'package', -- one per stop; removed on delivery/route close, no other use
    minStops      = 3,
    maxStops      = 5,
    basePay       = 120,       -- $ per stop
    payPer100m    = 8,         -- $ per full 100m depot->stop (straight line)
    maxDistancePay = 800,      -- cap on the distance part of a stop's pay
    account       = 'bank',
    deliverDist   = 5.0,       -- stop interaction radius (server re-checks with slack)
    deliverTime   = 5000,      -- ms progress per hand-over
    loadTime      = 3000,      -- ms progress loading packages at the depot
    timeoutMin    = 30,        -- route expires after this many minutes
}

-- Courier stop pool (script-config defaults; storefronts across city + county). The server picks
-- minStops..maxStops random entries per route. Tune/extend freely.
Config.deliveryStops = {
    { label = 'Innocence Blvd 24/7',    x = 24.47,    y = -1346.62, z = 29.5   },
    { label = 'Grove Street LTD',       x = -48.02,   y = -1757.51, z = 29.42  },
    { label = 'Mirror Park LTD',        x = 1163.37,  y = -323.8,   z = 69.21  },
    { label = 'Little Seoul LTD',       x = -707.5,   y = -914.26,  z = 19.22  },
    { label = 'Vespucci Robs Liquor',   x = -1222.91, y = -906.98,  z = 12.33  },
    { label = 'El Rancho Robs Liquor',  x = 1135.81,  y = -982.28,  z = 46.42  },
    { label = 'Hawick Robs Liquor',     x = -1487.55, y = -379.11,  z = 40.16  },
    { label = 'Clinton Ave 24/7',       x = 373.55,   y = 325.56,   z = 103.57 },
    { label = 'Sandy Shores 24/7',      x = 1960.54,  y = 3740.65,  z = 32.34  },
    { label = 'Grapeseed 24/7',         x = 1697.87,  y = 4924.4,   z = 42.06  },
    { label = 'Paleto Bay 24/7',        x = 1729.2,   y = 6414.71,  z = 35.04  },
    { label = 'Route 68 24/7',          x = 549.13,   y = 2671.75,  z = 42.16  },
    { label = 'Banham Canyon 24/7',     x = -3038.94, y = 585.95,   z = 7.91   },
    { label = 'Mount Chiliad 24/7',     x = 2678.92,  y = 3280.6,   z = 55.24  },
    { label = 'Senora Robs Liquor',     x = 1166.02,  y = 2708.93,  z = 38.16  },
}

-- XP perks (index = level 1..5 in the matching pengu_xp category for that point's ptype).
-- gatherCooldownMult scales recipe cooldowns; sellBonusPct scales sell payouts (1 + pct);
-- deliveryBonusPct scales delivery per-stop pay (1 + pct).
Config.perks = {
    gatherCooldownMult = { 1.0, 0.95, 0.90, 0.85, 0.80 },
    sellBonusPct       = { 0, 0.02, 0.04, 0.07, 0.10 },
    deliveryBonusPct   = { 0, 0.02, 0.04, 0.07, 0.10 },
}

-- seed points (admin re-places live with /jobloc). ptype is a gather OR sell type key.
-- seed-on-empty only (admin adds more live with /jobloc add <type>).
Config.seeds = {
    { ptype = 'mine',        label = 'Davis Quarry Mine',  x = 2949.0,  y = 2792.0,  z = 40.5 },
    { ptype = 'metaldealer', label = 'Quarry Scrap Buyer', x = 2954.0,  y = 2747.0,  z = 43.5 },
    { ptype = 'fish',        label = 'Pier Fishing',       x = -1850.0, y = -1235.0, z = 8.6  },
    { ptype = 'fishmarket',  label = 'Fish Market',        x = -1820.0, y = -1193.0, z = 14.3 },
    { ptype = 'tree',        label = 'Paleto Logging',     x = -560.0,  y = 5360.0,  z = 70.0 },
    { ptype = 'lumberyard',  label = 'Lumber Yard',        x = -530.0,  y = 5350.0,  z = 70.0 },
    { ptype = 'smelter',     label = 'Quarry Smelter',     x = 2962.0,  y = 2783.0,  z = 41.0 },
    { ptype = 'grill',       label = 'Pier Grill',         x = -1827.0, y = -1196.0, z = 14.3 },
    { ptype = 'sawmill',     label = 'Paleto Sawmill',     x = -525.0,  y = 5345.0,  z = 70.0 },
    { ptype = 'hardware',    label = 'Quarry Hardware',    x = 2748.0,  y = 3472.0,  z = 55.7 },
    { ptype = 'farm',        label = 'Grapeseed Farm',     x = 2449.0,  y = 4979.0,  z = 46.5 },
    { ptype = 'farmmarket',  label = 'Grapeseed Farm Stand', x = 2427.0, y = 4946.0, z = 44.7 },
    { ptype = 'hunt',        label = 'Alamo Sea Hunting',  x = -610.0,  y = 5590.0,  z = 60.0 },
    { ptype = 'butcher',     label = 'Alamo Butcher Block', x = -585.0, y = 5575.0,  z = 60.0 },
    { ptype = 'butcher_market', label = 'Alamo Butcher Market', x = -565.0, y = 5560.0, z = 60.0 },
    { ptype = 'gym',           label = 'Muscle Sands Gym',     x = -1193.0, y = -1566.0, z = 4.6  },
    { ptype = 'gym',           label = 'Mirror Park Gym',      x = 1219.0,  y = -1405.0, z = 35.0 },
    { ptype = 'grill',         label = 'Grapeseed Campfire',   x = 2440.0, y = 4968.0, z = 46.0 },
    { ptype = 'foodmarket',    label = 'Grapeseed Food Stall', x = 2420.0, y = 4956.0, z = 44.5 },
    { ptype = 'depot',         label = 'PostOP Depot',         x = -424.44, y = -2789.4, z = 6.0 },
}

Config.defaultLabel = 'Job Point'

-- Map blips so players can FIND legal job points (criminal points stay unmarked by design).
-- sprite/colour are GTA blip ids - tune freely. Falls back to a plain marker if a type is missing.
Config.blipScale = 0.85
Config.blips = {
    mine        = { sprite = 618, colour = 20, name = 'Mine' },
    smelter     = { sprite = 436, colour = 47, name = 'Smelter' },
    fish        = { sprite = 68,  colour = 42, name = 'Fishing Spot' },
    tree        = { sprite = 237, colour = 25, name = 'Logging Site' },
    grill       = { sprite = 267, colour = 47, name = 'Grill' },
    sawmill     = { sprite = 237, colour = 25, name = 'Sawmill' },
    metaldealer = { sprite = 605, colour = 2,  name = 'Scrap Dealer' },
    fishmarket  = { sprite = 356, colour = 2,  name = 'Fish Market' },
    lumberyard  = { sprite = 605, colour = 2,  name = 'Lumber Yard' },
    hardware       = { sprite = 402, colour = 5,  name = 'Hardware Store' },
    farm           = { sprite = 50,  colour = 25, name = 'Farm Field' },
    farmmarket     = { sprite = 356, colour = 2,  name = 'Farm Stand' },
    hunt           = { sprite = 112, colour = 47, name = 'Hunting Ground' },
    butcher        = { sprite = 99,  colour = 46, name = 'Butcher Block' },
    butcher_market = { sprite = 99,  colour = 2,  name = 'Butcher Market' },
    foodmarket     = { sprite = 52,  colour = 47, name = 'Food Stall' },
    gym            = { sprite = 311, colour = 81, name = 'Gym' },
    depot          = { sprite = 477, colour = 47, name = 'Delivery Depot' },
}
Config.blipDefault = { sprite = 1, colour = 0 }

-- World visual per point type so each spot is VISIBLE up close (they were invisible ox_target spheres
-- before - only a map blip, nothing on the ground). `ped = true` spawns a ped, false spawns a prop.
-- The existing sphere zone still handles the interaction. Tune freely - each is IsModelValid-guarded,
-- so a bad/unknown model just shows nothing rather than erroring.
Config.visuals = {
    mine        = { model = 'prop_tool_pickaxe',  ped = false }, -- pickaxe at the dig site
    fish        = { model = 'prop_fishing_rod_01', ped = false },
    tree        = { model = 'prop_log_01',         ped = false },
    smelter     = { model = 'v_8_furnace',         ped = false }, -- furnace
    grill       = { model = 'prop_bbq_3',          ped = false },
    sawmill     = { model = 'prop_bandsaw_01',     ped = false }, -- saw bench
    metaldealer = { model = 'prop_rub_scrap_03',   ped = false }, -- scrap pile you sell to
    fishmarket  = { model = 'prop_fish_slice_01',  ped = false },
    lumberyard  = { model = 'prop_log_01',         ped = false },
    hardware       = { model = 'prop_tool_bench02',   ped = false }, -- tool bench
    farm           = { model = 'prop_veg_crop_02_cab', ped = false }, -- cabbage patch
    hunt           = { model = 'prop_deer_dead',       ped = false }, -- carcass marker
    butcher        = { model = 'prop_butch_blk_01',    ped = false }, -- butcher block
    farmmarket     = { model = 'prop_veg_crop_01_cab', ped = false },
    butcher_market = { model = 'prop_butch_blk_01',    ped = false },
    foodmarket     = { model = 'prop_food_stall_03',   ped = false },
    gym            = { model = 'prop_gym_bar_01',      ped = false },
    depot          = { model = 'prop_boxpile_07d',     ped = false }, -- pallet of parcels
}
