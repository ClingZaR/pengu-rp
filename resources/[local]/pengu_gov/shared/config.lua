-- PenguRP Government (pengu_gov) - SHARED CONFIG. ASCII only.

Config = {
    -- offices that /election open accepts -> display label
    offices = { mayor = 'Mayor', council = 'City Council' },

    registrationFee  = 1000,  -- $ (bank) to appear on the mayor ballot via /runformayor
    councilFee       = 500,   -- $ (bank) to appear on the council ballot via /runforcouncil
    councilSeats     = 3,     -- /election close seats this many top vote-getters (advisory only)
    maxCandidates    = 6,     -- ballot size cap per election

    taxMin           = 0,     -- /settaxrate lower bound (percent)
    taxMax           = 25,    -- /settaxrate upper bound (percent)

    pardonCooldown   = 86400, -- seconds between /mayorpardon uses (24h, persisted)
    announceCooldown = 600,   -- seconds between /mayorannounce uses (10 min)
    announceMaxLen   = 180,   -- character cap on /mayorannounce messages
}
