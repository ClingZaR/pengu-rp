-- PenguRP - Money Laundering (pengu_launder) CONFIG. Phase 3.3 (reworked).
-- Laundering is now ASYNC + contestable: you START a wash (your black_money goes into the machine),
-- it takes time SCALED BY AMOUNT, then you COME BACK to collect CLEAN CASH on your person (which you
-- then deposit at a bank yourself). While a wash is running, a RIVAL can rob the machine and skim the
-- clean cash. `Config` is a per-resource global. ASCII only. luac clean.

Config = {}

Config.interactDist = 3.0  -- wider so the washing-machine prop at the point never blocks reach
Config.fee          = 0.30     -- laundering fee (keep 70%)
Config.minWash      = 100      -- minimum dirty money per batch
Config.maxWash      = 50000    -- maximum dirty money per batch (bigger batch -> longer wash)
Config.dirtyItem    = 'black_money'
Config.payType      = 'cash'   -- laundering returns CASH on the person (deposit it at a bank yourself)

-- wash time scales with the amount: the more dirty money, the longer it takes.
Config.baseSeconds  = 30       -- base time
Config.secondsPer1k = 4        -- + this many seconds per $1000 (e.g. $50k = 30 + 200 = 230s)
Config.startTime    = 3000     -- ms - the short "load the machine" interaction when starting a wash

-- contesting: a rival at the laundromat can rob an in-progress wash.
Config.robSkill   = { 'medium', 'hard' } -- ox_lib skillcheck to rob a wash
Config.robCutPct  = 0.60       -- a robber skims this fraction of the clean cash; the rest is lost

-- seed laundromats (admin re-places live with /washloc). Placeholder coords.
Config.seeds = {
    { label = 'Hawick Laundromat', x = 1133.0, y = -991.0, z = 46.2 },
}

Config.defaultLabel = 'Laundromat'

-- World visual at each laundromat so the interaction point is VISIBLE (it was an invisible ox_target
-- sphere before). A washing-machine prop sits on the point; the existing sphere still handles the
-- interaction. `ped = true` would spawn a ped instead. Set model to '' to disable. IsModelValid-guarded.
Config.visual = { model = 'prop_washer_01', ped = false }
