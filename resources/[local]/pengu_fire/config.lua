-- PenguRP - Fire Department mechanic config (shared). The fire JOB / stations / fleet / gear /
-- clothing all come from the faction system (Factions.legal.fire in pengu_core); this resource
-- only adds the actual fightable FIRES + extinguishing + pay. ASCII only.
Config = {}

-- Jobs whose ON-DUTY members can fight fires and earn the reward.
Config.fireJobs = { fire = true }

-- Reward (bank) paid to EACH firefighter who helped put a fire out.
Config.rewardPerFire = 750

-- At most this many fires burning server-wide at once.
Config.maxActiveFires = 2
-- ...of which at most this many may be PLAYER-REPORTED (/firecall), so reported fires can never
-- occupy every slot and starve the random-fire system.
Config.maxReportFires = 1
-- Player-reported fires burn out faster than the /firecall cooldown, so a pair of alts cannot
-- keep a grief fire parked permanently.
Config.reportExpireMs = 240000 -- 4 min

-- Random structure fires: a new one every [min,max] ms, only while a firefighter is on duty.
Config.randomFires = true
Config.spawnIntervalMs = { min = 600000, max = 1200000 } -- 10-20 min

-- A fire auto-burns-out after this long if nobody extinguishes it (so it never lingers forever).
Config.autoExpireMs = 900000 -- 15 min

-- /firecall: any player can report a fire AT THEIR LOCATION (RP). Per-player cooldown to stop spam.
Config.firecallCooldownMs = 300000 -- 5 min

-- Extinguishing tuning.
Config.extinguishWeapon = `WEAPON_FIREEXTINGUISHER`
Config.fireHealth       = 100   -- "HP" a fire must lose to go out
Config.damagePerSpray   = 6     -- HP removed per valid spray tick (server-applied)
Config.sprayIntervalMs  = 500   -- client throttle + server rate-limit per player
Config.extinguishRadius = 9.0   -- how close a firefighter must be to spray it
Config.fireCluster      = 5     -- how many script-fire sources make up one fire scene

-- Random fire locations (ground-level, populated areas). vec3.
Config.locations = {
    vec3(-1037.0, -1395.0, 5.0),  -- Vespucci Beach
    vec3(120.0,  -1940.0, 21.0),  -- Davis
    vec3(-47.0,  -1758.0, 29.0),  -- Grove St gas station
    vec3(265.0,  -1260.0, 29.0),  -- Mission Row
    vec3(1135.0,  -982.0, 46.0),  -- Mirror Park
    vec3(-707.0,  -914.0, 19.0),  -- Little Seoul
    vec3(1693.0,  4929.0, 42.0),  -- Grapeseed
    vec3(1961.0,  3740.0, 32.0),  -- Sandy Shores
}
