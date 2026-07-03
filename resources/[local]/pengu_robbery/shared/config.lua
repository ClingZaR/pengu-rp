Config = {}

-- black_money payout ranges
Config.registerMin = 300
Config.registerMax = 800
Config.safeMin     = 1500
Config.safeMax     = 4000

-- Cooldowns in seconds
Config.registerStoreCd  = 45 * 60   -- 45 min: same store between hits
Config.registerPlayerCd = 15 * 60   -- 15 min: same player between hits
Config.safeStoreCd      = 90 * 60   -- 90 min: same safe between cracks
Config.safePlayerCd     = 30 * 60   -- 30 min: same player between safe jobs

-- Item required for safe cracking (already in ox_inventory)
Config.safeToolItem = 'drill'

-- Criminal XP
Config.registerXP = 10
Config.safeXP     = 35
