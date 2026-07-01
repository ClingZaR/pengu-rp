-- PenguRP - Business Ownership (pengu_business) CONFIG. Phase 4.2.
-- A player can BUY an admin-registered business. Behind the scenes each business is a dynamically
-- created qbx JOB (owner = boss grade) + a Renewed-Banking society account, so employee management
-- (qbx_management boss menu) and the business bank (owner is bankAuth -> shows in their bank) come
-- for FREE. This resource owns: admin registration, the management POINT, and the purchase. Businesses
-- are ENTIRELY admin-placed live with /bizloc (no hardcoded locations). `Config` is per-resource global.

Config = {}

Config.interactDist = 2.5
Config.jobType      = 'business' -- qbx job type (not leo/ems/etc -> no special behavior)
Config.keyPrefix    = 'biz_'     -- namespaces business job keys so they never collide with real jobs
Config.ownerGrade   = 2          -- the boss grade a buyer is set to
Config.defaultPrice = 250000
Config.defaultLabel = 'Business'

-- Standard business grade ladder (the owner grade must have isboss + bankAuth).
Config.grades = {
    [0] = { name = 'Employee' },
    [1] = { name = 'Manager' },
    [2] = { name = 'Owner', isboss = true, bankAuth = true },
}

-- Passive income: deposited to each owned business's society account every 30 min.
-- The owner can withdraw from the business bank via Renewed-Banking on their phone.
Config.passiveIncome = 350   -- $ per 30-minute tick
Config.passiveIntervalMs = 1800000  -- 30 minutes

-- Businesses are admin-registered live (/bizloc register). No seeds - nothing hardcoded.
Config.seeds = {}
