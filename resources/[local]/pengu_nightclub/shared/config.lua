-- PenguRP - Nightclub (pengu_nightclub) CONFIG.
-- DJ booths stream a URL through xsound at the booth position with distance falloff; bars sell
-- drinks for CLEAN money (cash first, bank fallback). Default locations sit inside the Galaxy
-- afterhours underground club (bob74_ipl loads it; interior anchor -1604.66, -3012.58, -78.0).
-- These are SCRIPT DEFAULTS, not live content - move/add points freely, then restart later.
-- VIP doors are NOT handled here: add them in-game with the ox_doorlock UI. ASCII only.

Config = {}

Config.interactDist = 2.5

-- DJ booth access gate. Default OPEN TO ALL (both lists empty). To restrict, add names as keys:
--   jobs  = { nightclub = true }, gangs = { ballas = true }
Config.djAccess = {
    jobs  = {},
    gangs = {},
}

Config.trackCooldownMs = 20000 -- one track change per booth per 20s (anti URL-spam)
Config.maxUrlLen       = 512   -- longest accepted track URL
Config.maxVolume       = 1.0   -- hard ceiling for the 5-100 volume slider (1.0 = xsound max)
Config.staleTrackSecs  = 900   -- stop re-syncing a track to late joiners after this many seconds

-- DJ booths. coords = center of the ox_target box (the Galaxy DJ stage is at the west end of the
-- main dancefloor area; the game's own 'main_area' audio emitter sits at -1601.2, -3012.6, -77.0).
Config.booths = {
    {
        id            = 'galaxy_stage',
        label         = 'Galaxy DJ Booth',
        coords        = vec3(-1604.5, -3012.5, -78.0),
        targetSize    = vec3(4.0, 4.0, 3.5),
        rotation      = 0.0,
        musicDistance = 40.0, -- falloff radius in meters
    },
}

-- Bars selling drinks for CLEAN money. Default = the Galaxy main bar (the game's own
-- 'se_ba_dlc_int_01_bars' audio emitter sits at -1579.0, -3012.1, -78.0).
-- All items below exist in ox_inventory data/items.lua (beer/whiskey/vodka/cola verified).
Config.bars = {
    {
        id         = 'galaxy_bar',
        label      = 'Galaxy Bar',
        coords     = vec3(-1579.0, -3012.1, -78.5),
        targetSize = vec3(6.0, 4.0, 3.5),
        rotation   = 0.0,
        drinks = {
            { item = 'beer',    label = 'Beer',    price = 40, icon = 'fa-solid fa-beer-mug-empty' },
            { item = 'whiskey', label = 'Whiskey', price = 90, icon = 'fa-solid fa-whiskey-glass' },
            { item = 'vodka',   label = 'Vodka',   price = 75, icon = 'fa-solid fa-martini-glass' },
            { item = 'cola',    label = 'eCola',   price = 15, icon = 'fa-solid fa-bottle-water' },
        },
    },
}

-- Pulse lights ('Pulse Lights' toggle at the booth). Client-side DrawLightWithRange color cycle
-- around the booth while music is playing; auto-stops when the track ends. offsets are relative
-- to the booth coords (one light drawn per offset, colors phase-shifted per light).
Config.lights = {
    colors = { -- RGB
        { 255, 0,   128 },
        { 0,   128, 255 },
        { 128, 0,   255 },
        { 0,   255, 128 },
        { 255, 128, 0   },
    },
    offsets = {
        vec3(0.0, 0.0, 3.0),   -- above the booth
        vec3(4.0, -2.0, 2.0),  -- over the dancefloor, left
        vec3(4.0, 2.0, 2.0),   -- over the dancefloor, right
    },
    range     = 12.0, -- light radius (m)
    intensity = 2.0,
    cycleMs   = 450,  -- color swap interval
    drawDist  = 60.0, -- stop drawing (and slow the loop) beyond this distance from the booth
}
