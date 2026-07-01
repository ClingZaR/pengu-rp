-- PenguRP - Gang Reputation & Level (pengu_gangs) CONFIG. Foundation of the gang underworld system.
-- Gangs earn REPUTATION from activity (dealing in turf, holding territory, captures, imports) and
-- LEVEL UP; higher level = bigger illegal-import catalog + better perks. Other resources award rep via
-- exports.pengu_gangs:AddRep(gang, n). All numbers tunable. `Config` is a per-resource global.

Config = {}

-- Cumulative rep required to BE at each level (level -> rep threshold).
-- These are intentionally hard: a gang earns ~75-200 rep per criminal activity.
-- Reaching level 6 requires months of consistent coordinated play.
Config.levels = { [1] = 0, [2] = 5000, [3] = 15000, [4] = 40000, [5] = 90000, [6] = 200000 }
Config.maxLevel = 6

-- Rep awards for activities (callers pass these). TURF is the MAIN rep source: the per-held-zone tick
-- and zone captures dwarf the other (secondary) sources, and the tick scales with how many zones a gang
-- controls - so "the more turf you hold, the faster your gang rep climbs". The secondary sources
-- (crate imports, dealer interactions in pengu_dealers, lab-holding in pengu_drugs) only supplement it.
Config.rep = {
    perZoneTick    = 35,  -- MAIN: per controlled NON-CORE zone, each turf rep tick (pengu_turf repTickMs)
    zoneCaptured   = 600,  -- MAIN: taking control of a zone
    tagOver        = 50,  -- painting over a rival gang's graffiti tag
    drugSaleInTurf = 5,   -- per drug sale a member makes inside their gang's turf
    crateImport    = 300, -- secondary: completing an illegal-import crate retrieval
}
Config.repTickInterval = 600000 -- (legacy) the live turf rep tick is driven by pengu_turf Config.repTickMs

-- GLOBAL per-level perks (per-ZONE perks live in pengu_turf). maxZones = how many non-core zones the
-- gang may hold at once; importDiscount = fraction off illegal-import cost.
Config.levelPerks = {
    [1] = { maxZones = 1, importDiscount = 0.00 },
    [2] = { maxZones = 2, importDiscount = 0.05 },
    [3] = { maxZones = 3, importDiscount = 0.10 },
    [4] = { maxZones = 4, importDiscount = 0.15 },
    [5] = { maxZones = 6, importDiscount = 0.20 },
    [6] = { maxZones = 8, importDiscount = 0.30 },
}
