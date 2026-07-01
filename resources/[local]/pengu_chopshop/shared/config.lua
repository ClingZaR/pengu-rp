-- PenguRP - Chop Shop (pengu_chopshop) CONFIG.
-- Steal a WANTED-model car (the list rotates hourly; the mechanic dealer tells you what's wanted),
-- bring it to a chop point and strip it (NO tool needed - the shop has everything) for CAR PARTS.
-- You then sell those parts to a mechanic dealer (placed separately via /dealeradd) for dirty money +
-- gang influence. Player-REGISTERED vehicles and non-wanted models are rejected. Server-authoritative.
-- `Config` is a per-resource global. ASCII only. luac clean.

Config = {}

Config.zoneRadius  = 30.0     -- vehicle must be within this of a chop point to be choppable
Config.targetDist  = 3.5      -- how close the player must be to the vehicle to target it
Config.chopTime    = 15000    -- ms to strip
Config.cooldown    = 60000    -- ms between chops per player (server-enforced)
Config.dirtyItem   = 'black_money'

-- The chop shop has all the tools on site -> NO item required to strip a car here. (Set to an item
-- name like 'toolbox' to require one again.)
Config.requireTool = false

-- CAR PARTS a chop yields (the mechanic dealer buys exactly these; selling anything else is refused).
-- Each chop drops a RANDOM subset of these (Config.partsPerChop distinct kinds) so output varies per
-- car. Items are defined in ox_inventory data/items.lua (chop_* ).
Config.parts = {
    { item = 'chop_engine',    label = 'Engine Block',        min = 1, max = 1 },
    { item = 'chop_gearbox',   label = 'Gearbox',             min = 1, max = 1 },
    { item = 'chop_ecu',       label = 'ECU Unit',            min = 1, max = 2 },
    { item = 'chop_door',      label = 'Car Door',            min = 1, max = 2 },
    { item = 'chop_wheel',     label = 'Alloy Wheel',         min = 2, max = 4 },
    { item = 'chop_bumper',    label = 'Bumper',              min = 1, max = 2 },
    { item = 'chop_catalytic', label = 'Catalytic Converter', min = 1, max = 1 },
    { item = 'chop_battery',   label = 'Car Battery',         min = 1, max = 1 },
    { item = 'chop_radio',     label = 'Stereo Unit',         min = 1, max = 1 },
    { item = 'chop_seat',      label = 'Leather Seat',        min = 1, max = 2 },
}
Config.partsPerChop = { min = 3, max = 5 } -- how many DISTINCT part kinds one chop yields

-- WANTED cars: you may ONLY chop a model on this list. It is RANDOMIZED and REFRESHES every
-- wantedRefreshMs - chop the wanted cars before the window closes or a new list is drawn. The mechanic
-- dealer (pengu_dealers) shows the live list + time remaining (GlobalState.penguChopWanted[/Until]).
Config.wantedPool = {
    'sultan', 'kuruma', 'futo', 'banshee', 'comet5', 'sentinel', 'elegy2', 'jester3',
    'gauntlet', 'dominator', 'buffalo', 'sultanrs', 'feltzer2', 'schafter2',
}
Config.wantedCount     = 3
Config.wantedRefreshMs = 3600000 -- 1 hour: the list refreshes (and the clock resets) this often

-- Ambient props spawned in the chop zone (visible workshop dressing). IsModelValid-guarded;
-- any invalid model name is logged to console and skipped (see client spawnProps).
-- NOTE: no mechanic PED spawns here anymore - place a mechanic dealer yourself with /dealeradd mechanic.
Config.chopProps = {
    { model = 'prop_tool_bench02', dx = -3.0, dy =  2.0, dz = 0.0 }, -- workbench
    { model = 'prop_toolchest_05', dx = -3.0, dy = -1.0, dz = 0.0 }, -- rolling tool trolley
    { model = 'prop_engine_01',    dx = -4.5, dy =  0.5, dz = 0.0 }, -- engine block / hoist dressing
}

-- No seeded chop points (fresh start). Admin places points live with /choploc add.
Config.seeds = {}

Config.defaultLabel = 'Chop Shop'
