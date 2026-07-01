-- PenguRP - Jail & Court (Phase 2.5). Prison labor (sentence reduction), bail,
-- and judicial court powers. Integrates with the pengu_core custom jail via:
--   read    : exports['pengu_core']:GetJailMinutes(src)  / LocalPlayer.state.penguJailMinutes (client)
--   reduce  : exports['pengu_core']:ReduceJailMinutes(src, n)
--   release : exports['pengu_core']:ReleasePlayerCustom(src)
-- jailTime is in real MINUTES (pengu_core jail caps a sentence at 60). ASCII only.

Config = {}

-- Job sets, gated by job NAME (judge/lawyer have no reliable 'type' field in jobs.lua).
Config.judgeJobs  = { judge = true }                       -- pardon / reduce / set bail
Config.lawyerJobs = { lawyer = true }                      -- set bail (advocate for a client)
Config.leoJobs    = { police = true, bcso = true, sasp = true }

-- ===================== PRISON LABOR =====================
-- Work stations inside Bolingbroke (Sandy Shores). Only jailed players can use them;
-- each completes a progress action, reduces remaining time, and pays a small commissary
-- reward. Coords are inside the xt-prison yard (~x1745-1780 / y2467-2592 / z45.6-49.7).
Config.labor = {
    cashItem   = 'cash',   -- reward money type ('cash' commissary credit); set false for none
    stations = {
        { key = 'rocks',   label = 'Break Rocks',     coords = vec3(1751.0, 2483.0, 45.74), scenario = 'WORLD_HUMAN_HAMMERING',   reduceMin = 3, rewardMin = 20, rewardMax = 60, duration = 9000,  cooldown = 20 },
        { key = 'laundry', label = 'Do Laundry',      coords = vec3(1774.0, 2484.0, 45.74), scenario = 'WORLD_HUMAN_MAID_CLEAN',  reduceMin = 2, rewardMin = 15, rewardMax = 45, duration = 8000,  cooldown = 20 },
        { key = 'sweep',   label = 'Sweep the Yard',  coords = vec3(1765.0, 2490.0, 45.74), scenario = 'WORLD_HUMAN_JANITOR',     reduceMin = 2, rewardMin = 10, rewardMax = 35, duration = 7000,  cooldown = 20 },
        { key = 'plates',  label = 'Stamp Plates',    coords = vec3(1760.0, 2478.0, 45.74), scenario = 'WORLD_HUMAN_WELDING',     reduceMin = 3, rewardMin = 20, rewardMax = 55, duration = 9000,  cooldown = 20 },
        { key = 'kitchen', label = 'Kitchen Duty',    coords = vec3(1779.0, 2557.0, 45.62), scenario = 'WORLD_HUMAN_COP_IDLES',   reduceMin = 2, rewardMin = 15, rewardMax = 40, duration = 8000,  cooldown = 20 },
    },
    targetSize = vec3(1.6, 1.6, 2.0), -- ox_target box-zone size per station
}

-- ===================== BAIL =====================
Config.bail = {
    perMinute      = 250,   -- $ of bail per remaining unit of jailTime
    minAmount      = 500,   -- floor for any bail
    maxAmount      = 25000, -- ceiling for self-serve bail
    maxSelfMinutes = 30,    -- self /bail only allowed when remaining <= this (else a judge must set bail)
    allowLifer     = false, -- lifers can never bail out
    payFromAccount = 'bank',-- money type taken on /bail
}
