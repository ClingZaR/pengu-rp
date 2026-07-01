-- PenguRP Character XP (pengu_xp) - SHARED config. ASCII only. luac clean.
Config = {}

-- XP thresholds[i] = total XP needed to be at level i (1-indexed; level 1 = 0 xp)
Config.categories = {
    criminal   = { label = 'Criminal',   icon = 'fa-solid fa-skull',       thresholds = {0, 500,  1500, 3500, 7500} },
    drugs      = { label = 'Drug Trade', icon = 'fa-solid fa-flask',       thresholds = {0, 400,  1200, 3000, 6500} },
    mining     = { label = 'Mining',     icon = 'fa-solid fa-hammer',      thresholds = {0, 300,  1000, 2500, 5500} },
    fishing    = { label = 'Fishing',    icon = 'fa-solid fa-fish',        thresholds = {0, 300,  1000, 2500, 5500} },
    farming    = { label = 'Farming',    icon = 'fa-solid fa-seedling',    thresholds = {0, 300,  1000, 2500, 5500} },
    hunting    = { label = 'Hunting',    icon = 'fa-solid fa-crosshairs',  thresholds = {0, 400,  1200, 3000, 6500} },
    cooking    = { label = 'Cooking',    icon = 'fa-solid fa-utensils',    thresholds = {0, 300,  1000, 2500, 5500} },
    lumberjack = { label = 'Lumberjack', icon = 'fa-solid fa-tree',       thresholds = {0, 300,  1000, 2500, 5500} },
    fitness    = { label = 'Fitness',    icon = 'fa-solid fa-dumbbell',    thresholds = {0, 300,  1000, 2500, 5500} },
}

-- Maps pengu_jobs ptype -> { category, xp per gather }
Config.jobsXP = {
    mine       = { category = 'mining',     amount = 20 },
    smelter    = { category = 'mining',     amount = 25 },
    metaldealer = { category = 'mining',    amount = 10 },
    fish       = { category = 'fishing',    amount = 15 },
    fishmarket = { category = 'fishing',    amount = 5  },
    farm       = { category = 'farming',    amount = 15 },
    farmmarket = { category = 'farming',    amount = 5  },
    hunt       = { category = 'hunting',    amount = 25 },
    butcher    = { category = 'hunting',    amount = 15 },
    grill      = { category = 'cooking',    amount = 20 },
    tree       = { category = 'lumberjack', amount = 15 },
    sawmill    = { category = 'lumberjack', amount = 20 },
    lumberyard = { category = 'lumberjack', amount = 10 },
    gym        = { category = 'fitness',    amount = 20 },
}

-- Maps pengu_jobs sell ptype -> { category, xp per sell action }
Config.sellXP = {
    fishmarket     = { category = 'fishing',    amount = 8  },
    metaldealer    = { category = 'mining',     amount = 10 },
    farmmarket     = { category = 'farming',    amount = 8  },
    butcher_market = { category = 'hunting',    amount = 10 },
    foodmarket     = { category = 'cooking',    amount = 8  },
    lumberyard     = { category = 'lumberjack', amount = 8  },
    smelter        = { category = 'mining',     amount = 12 },
}

-- Daily playtime bonus (gang member, >=1h per day, first time each day)
Config.playtime = {
    min_seconds = 3600,
    xp_category = 'criminal',
    xp_amount   = 100,
    gang_rep    = 75,
}
