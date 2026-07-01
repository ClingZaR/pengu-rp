-- PenguRP Petty Crime (pengu_pettycrime) CONFIG. Low-end crime layer against WORLD PROPS - no
-- placement needed, ox_target binds to the prop MODELS directly:
--   ATM HACK    : trojan_usb consumed when the hack STARTS (no refund on a failed skillcheck),
--                 pays dirty money (black_money item) on success. Dispatch pings EVERY attempt.
--   METER THEFT : needs a lockpick (chance it snaps per attempt), pays small clean CASH.
-- Every tunable number lives here. ASCII only. luac clean.

Config = {}

Config.interactDist = 2.0  -- ox_target interaction distance on the props
Config.maxDistance  = 4.0  -- server-side proximity re-check: player must be within this of the prop

-- A begun attempt expires this many seconds AFTER its expected duration (progress + skillcheck
-- headroom). A finish arriving later than that is rejected server-side.
Config.sessionSlackS = 60

-- ===================== 1) ATM HACKING =====================
Config.atm = {
    -- world ATM prop models (same set Renewed-Banking targets for legit banking)
    models = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' },

    item       = 'trojan_usb',   -- consumed at START; deliberately NOT refunded on failure (the risk)
    payoutItem = 'black_money',  -- dirty money on success
    payoutMin  = 300,
    payoutMax  = 700,

    skill      = { 'medium', 'medium', 'medium' },  -- lib.skillCheck, 3 rounds
    progressMs = 25000,                             -- lib.progressCircle duration

    minElapsedS     = 20,    -- server pays only if at least this many seconds passed since begin
    propCooldownS   = 1800,  -- 30 min per ATM (keyed by rounded prop coords)
    playerCooldownS = 600,   -- 10 min per player across ALL ATMs

    minCops        = 0,      -- on-duty police/bcso/sasp required online (owner can raise)
    dispatchChance = 1.0,    -- ALWAYS ping dispatch on an ATM hack attempt

    xp = 25,                 -- criminal XP on a successful hack (0 = off)
}

-- ===================== 2) PARKING METER THEFT =====================
Config.meter = {
    models = { 'prop_parkingmeter_01', 'prop_parkingmeter_02' },

    item        = 'lockpick',
    breakChance = 0.25,      -- chance per attempt the lockpick snaps (removed); attempt continues
    payoutMin   = 40,
    payoutMax   = 120,       -- paid as CASH via AddMoney('cash') - the same clean-cash channel
                             -- pengu_launder/pengu_turf already pay into (verified working)

    skill      = { 'easy' },
    progressMs = 8000,

    minElapsedS     = 6,
    propCooldownS   = 3600,  -- 60 min per meter
    playerCooldownS = 300,   -- 5 min per player across ALL meters

    minCops        = 0,
    dispatchChance = 0.30,   -- 30% of attempts ping dispatch

    xp = 10,
}
