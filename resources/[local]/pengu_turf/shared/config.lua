-- PenguRP - Gang Territory (pengu_turf) CONFIG. Block-based influence system (revamped).
-- Each gang gets a TINY permanent CORE base (/turf core <gang>). Beyond that, territory is contested
-- admin-placed ZONES whose control is driven by INFLUENCE from TWO sources: controlling the DEALERS
-- inside a zone (keep them happy via pengu_dealers) and SPRAY-PAINTING your gang tag on its walls.
-- Controlling turf is the MAIN driver of gang rep. 100% server-authoritative. ASCII only. luac clean.

Config = {}

-- ===================== influence engine (server/influence.lua) =====================
Config.controlThreshold = 60      -- influence needed to control a non-core block
Config.maxInfluence     = 240     -- per-gang per-zone influence cap
Config.decayMs          = 120000  -- influence decay interval (2 min) - turf must be WORKED to keep
Config.decayPerTick     = 4       -- influence lost per gang per zone per decay tick
Config.repTickMs        = 300000  -- rep tick for held NON-CORE zones (5 min) - turf is the main rep source

-- ===================== gang CORE bases (/turf core <gang>) =====================
-- A gang's permanent home = a TINY uncapturable square block, dropped at the admin's feet with
-- /turf core <gang>. coreSize = side length in metres (kept very small on purpose - the base is a
-- flag, expansion happens out in the contested zones).
Config.coreSize = 12.0

-- ===================== dealer-driven influence (server/territory.lua) =====================
-- "Keeping dealers happy" = CONTROLLING dealers through pengu_dealers (work them so their influence in
-- that system stays at/above its control threshold). Every dealerFeedMs, each dealer a gang CONTROLS
-- that physically sits INSIDE a turf zone feeds dealerInfluencePerFeed to that gang's influence in that
-- zone. This + graffiti are the only two ways to take turf.
Config.dealerFeedMs           = 60000  -- ms between dealer -> turf influence feeds (1 min)
Config.dealerInfluencePerFeed = 18     -- influence a controlled in-zone dealer adds per feed

-- ===================== organic expansion (grid blocks) =====================
-- Gangs EXPAND by tagging fresh walls (and working dealers) on OPEN ground - not just inside admin
-- zones. The world is an implicit grid of gridSize-metre cells; tagging/dealing on an un-owned cell
-- auto-creates a CONTESTED BLOCK there for your gang (still capped by your gang level's maxZones).
-- Abandoned blocks (neutral, no influence, no tags) are auto-removed every autoCleanMs. Admin-placed
-- named zones + cores always take precedence where they overlap a cell.
Config.gridSize    = 80.0     -- side length (m) of an auto-claimed turf block
Config.autoCleanMs = 600000   -- how often abandoned auto-blocks are swept (10 min)

-- ===================== drug-spot bonus (server/bonus.lua) =====================
Config.saleBonusPct = 0.25    -- extra cash % for a drug sale inside your gang's owned block

-- ===================== per-zone perks (admin /turf setperk) =====================
Config.perks = {
    drug_bonus      = { label = 'Drug Market',   saleBonus = 0.25 },
    import_discount = { label = 'Smuggling Hub', discount  = 0.10 },
    crate_speed     = { label = 'Fast Drop',     speedup   = 0.30 },
    rep_mult        = { label = 'Notorious',     mult      = 0.25 },
    stash           = { label = 'Safehouse',     slots     = 50   },
}
Config.perkList = { 'drug_bonus', 'import_discount', 'crate_speed', 'rep_mult', 'stash' }

-- ===================== graffiti / tagging (your gang name on the wall) =====================
Config.spraycanItem      = 'spraycan'
Config.tagInfluence      = 25      -- influence a fresh tag adds
Config.tagTickInfluence  = 3       -- influence each surviving tag tops up per decay tick
Config.maxTagsPerZone    = 4       -- per-gang tag cap inside one zone
Config.tagLifetime       = 7200    -- seconds a tag survives (2 h)
Config.tagPaintInfluence = 25      -- influence stripped when a rival paints over / police remove a tag
Config.tagSprayTime      = 5000    -- ms to spray
Config.tagPaintTime      = 6000    -- ms to paint over
Config.tagReach          = 3.0     -- max HORIZONTAL distance from YOUR PED to the wall hit-point (not the camera)
Config.tagMaxHeight      = 4.0     -- max height (m) above/below you a tag may land (so you can't tag a rooftop)
Config.tagMinSpacing     = 1.5     -- min metres between two of your own gang's tags (no stacking one spot)
Config.maxCosmeticTagsPerGang = 30 -- global cap on a gang's loose vanity (non-gang-name) tags
Config.tagDrawDist       = 30.0    -- tag draw distance
-- on-wall rendering: the typed text is rendered in a DUI (graffiti font) and painted FLAT on the wall as
-- a world-space textured quad. Set graffitiFlat = false to fall back to a simple label drawn at the wall.
Config.graffitiFlat        = true  -- flat graffiti on the wall (DUI) vs a plain on-wall label
Config.graffitiMaxRendered = 6     -- max tags painted flat at once (nearest first; one DUI surface each)
Config.graffitiWidth       = 2.4   -- painted tag width on the wall (m)
Config.graffitiHeight      = 1.2   -- painted tag height on the wall (m)
Config.graffitiMirror      = false -- flip the text horizontally if it ever renders mirrored on your build
Config.tagsPublic        = false   -- false = only criminals + law see tags
Config.lawJobs           = { police = true, bcso = true, sasp = true }

-- ===================== map / blips =====================
Config.neutralColour = 40
Config.blipAlpha     = 128
Config.blipSprite    = 84
-- in-world translucent FLOOR fill over each turf block. Off by default - it reads like an "edit mode"
-- overlay while you run around. Turf still shows as map blips + the influence HUD. Flip to true to see it.
Config.drawTurfFloor = false

-- ===================== gangs =====================
Config.gangs = {
    lostmc   = { label = 'The Lost MC', colour = 5  },
    ballas   = { label = 'Ballas',      colour = 7  },
    vagos    = { label = 'Vagos',       colour = 17 },
    cartel   = { label = 'Cartel',      colour = 1  },
    families = { label = 'Families',    colour = 2  },
    triads   = { label = 'Triads',      colour = 3  },
}
