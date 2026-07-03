-- PenguRP Gun Progression (pengu_gunrunning) - shared config. ASCII only.
--
-- Gang grade gates:
--   Grade 0 (Recruit)     -> can scavenge gun parts from placed part spots.
--   Grade 1 (Member)      -> can use Tier-1 bench (handguns).
--   Grade 2 (Lieutenant)  -> can use Tier-2 bench (SMGs / autopistols).
--   Grade 3+ (Boss)       -> can use Tier-3 bench (shotguns / rifles).
--
-- Admins place spots and benches in-game via /gunpartloc and /gunbenchloc.
-- No live content is placed here: locations = {} until admin adds them.

Config = {}

-- ===================== part scavenging =====================
Config.gatherGrade        = 0       -- minimum gang grade to scavenge parts
Config.gatherDurationMs   = 20000   -- progress bar length for gathering
Config.gatherCooldownSpot = 30 * 60 -- per-spot lockout in seconds (server-side)
Config.gatherCooldownPly  = 10 * 60 -- per-player lockout in seconds

-- Weighted part table: each entry = { item, weight }.
-- Higher weight = more likely. Weights are summed; each draw picks one part.
Config.partPool = {
    { item = 'gun_spring',  weight = 30 },
    { item = 'gun_trigger', weight = 25 },
    { item = 'gun_slide',   weight = 20 },
    { item = 'gun_frame',   weight = 15 },
    { item = 'gun_barrel',  weight = 8  },
    { item = 'gun_stock',   weight = 5  },  -- rarest; needed only for Tier-3
}
Config.gatherMin = 1  -- minimum parts per successful gather
Config.gatherMax = 2  -- maximum parts per successful gather

-- ===================== workbench tiers =====================
-- gradeRequired: minimum gang grade to see AND use this bench's recipes.
-- recipes[n].duration: ms for the crafting progress bar.
-- ingredients: item -> count map; all must be in the player's inventory.
Config.benches = {
    {
        tier          = 1,
        label         = 'Makeshift Pistol Bench',
        gradeRequired = 1,
        recipes = {
            {
                result      = 'WEAPON_PISTOL',
                label       = 'Pistol',
                duration    = 30000,
                ingredients = { gun_frame = 1, gun_slide = 1, gun_spring = 1, gun_trigger = 1 },
            },
            {
                result      = 'WEAPON_SNSPISTOL',
                label       = 'SNS Pistol',
                duration    = 20000,
                ingredients = { gun_frame = 1, gun_spring = 1, gun_trigger = 1 },
            },
            {
                result      = 'WEAPON_REVOLVER',
                label       = 'Revolver',
                duration    = 35000,
                ingredients = { gun_frame = 1, gun_barrel = 1, gun_spring = 2, gun_trigger = 1 },
            },
        },
    },
    {
        tier          = 2,
        label         = 'SMG Fabrication Bench',
        gradeRequired = 2,
        recipes = {
            {
                result      = 'WEAPON_MICROSMG',
                label       = 'Micro SMG',
                duration    = 40000,
                ingredients = { gun_frame = 2, gun_barrel = 1, gun_slide = 1, gun_spring = 2, gun_trigger = 1 },
            },
            {
                result      = 'WEAPON_SMG',
                label       = 'SMG',
                duration    = 55000,
                ingredients = { gun_frame = 2, gun_barrel = 1, gun_stock = 1, gun_spring = 2, gun_trigger = 1 },
            },
            {
                result      = 'WEAPON_APPISTOL',
                label       = 'AP Pistol',
                duration    = 45000,
                ingredients = { gun_frame = 2, gun_barrel = 1, gun_slide = 1, gun_trigger = 1, gun_spring = 1 },
            },
        },
    },
    {
        tier          = 3,
        label         = 'Gang Armory Bench',
        gradeRequired = 3,
        recipes = {
            {
                result      = 'WEAPON_PUMPSHOTGUN',
                label       = 'Pump Shotgun',
                duration    = 60000,
                ingredients = { gun_frame = 2, gun_barrel = 2, gun_stock = 1, gun_spring = 3, gun_trigger = 1 },
            },
            {
                result      = 'WEAPON_ASSAULTRIFLE',
                label       = 'Assault Rifle',
                duration    = 90000,
                ingredients = { gun_frame = 3, gun_barrel = 2, gun_stock = 2, gun_spring = 3, gun_trigger = 2 },
            },
            {
                result      = 'WEAPON_CARBINERIFLE',
                label       = 'Carbine Rifle',
                duration    = 75000,
                ingredients = { gun_frame = 3, gun_barrel = 2, gun_stock = 1, gun_spring = 3, gun_trigger = 2 },
            },
        },
    },
}

-- ===================== gang stash =====================
-- Each gang gets a shared ox_inventory stash (capacity 200 slots / 500 kg).
-- Stash ID pattern: 'gunstash_<gangname>'
Config.stashSlots  = 50
Config.stashWeight = 500000  -- ox_inventory weight is in grams (500 kg)

-- ===================== placement =====================
-- Part spots and benches are stored in DB; this is the ox_target prop used when
-- an admin hovers over the placed zone to remove it.
Config.spotProps   = { 'prop_dumpster_01a', 'prop_dumpster_02a', 'prop_rub_boxpile_04a',
                       'prop_box_ammo01a', 'prop_toolbox_03' }
Config.benchProps  = { 'prop_tool_bench01', 'prop_tool_bench02', 'prop_workbench01' }
