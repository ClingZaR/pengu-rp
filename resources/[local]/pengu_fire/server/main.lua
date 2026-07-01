-- PenguRP - Fire Department mechanic SERVER. Authoritative active-fire registry, spawning
-- (random timer + /firecall), server-validated extinguishing, and reward payout. The fire JOB
-- itself + stations/fleet/gear/clothing come from the faction system (pengu_core). ASCII only.
local qbx = exports.qbx_core

local activeFires = {} -- [id] = { coords, hp, contributors = { [src]=true }, reporter = src|nil, reward = bool }
local nextFireId  = 0
local lastFirecall = {} -- [src] = GetGameTimer() ms
local lastSpray    = {} -- [src] = GetGameTimer() ms

-- On-duty firefighter -> player object (or nil).
local function onDutyFire(src)
    local p = qbx:GetPlayer(src)
    if not p then return nil end
    local job = p.PlayerData.job
    if job and Config.fireJobs[job.name] and job.onduty then return p end
    return nil
end

-- Sources of all on-duty firefighters.
local function firefightersOnline()
    local players = qbx:GetQBPlayers() or {}
    local out = {}
    for src, p in pairs(players) do
        local job = p.PlayerData.job
        if job and Config.fireJobs[job.name] and job.onduty then
            out[#out + 1] = tonumber(src) or p.PlayerData.source
        end
    end
    return out
end

local function chatTo(src, msg, kind)
    TriggerClientEvent('chat:addMessage', src, { templateId = 'pengu:admin', args = { 'LSFD', msg, kind or 'info' } })
end

-- ps-dispatch CustomAlert is a CLIENT export; fire it from exactly ONE client (the reporter,
-- else any online player) so the alert is created once. Coords are passed so the street lookup
-- is correct regardless of where that client stands.
local function sendDispatch(coords, reporterSrc)
    local target = reporterSrc
    if not target then
        local ps = GetPlayers()
        target = ps[1] and tonumber(ps[1]) or nil
    end
    if target then
        TriggerClientEvent('pengu_fire:client:dispatch', target, coords)
    end
end

-- Count active fires; pass true to count only player-REPORTED ones.
local function fireCount(reportedOnly)
    local n = 0
    for _, f in pairs(activeFires) do
        if not reportedOnly or f.reporter ~= nil then n = n + 1 end
    end
    return n
end

-- Put a fire out: tell everyone to clear the visual, and pay each firefighter who helped (never
-- the reporter, so a firefighter can't /firecall their own fire and farm it).
local function extinguishFire(id)
    local fire = activeFires[id]
    if not fire then return end
    activeFires[id] = nil
    TriggerClientEvent('pengu_fire:client:stop', -1, id)
    if not fire.reward then return end
    for src in pairs(fire.contributors) do
        if src ~= fire.reporter then
            local p = onDutyFire(src)
            if p then
                p.Functions.AddMoney('bank', Config.rewardPerFire, 'fire-extinguished')
                chatTo(src, ('Fire extinguished. +$%d'):format(Config.rewardPerFire), 'ok')
            end
        end
    end
end

-- Start a fire at coords. reporterSrc = the /firecall reporter (nil for a random fire). Only
-- RANDOM fires pay a reward - player-reported fires are RP/dispatch only, so a player cannot mint
-- a paid fire on demand (directly or via an accomplice reporter).
local function spawnFire(coords, reporterSrc)
    if fireCount() >= Config.maxActiveFires then return false end
    if reporterSrc and fireCount(true) >= Config.maxReportFires then return false end
    nextFireId = nextFireId + 1
    local id = nextFireId
    activeFires[id] = { coords = coords, hp = Config.fireHealth, contributors = {}, reporter = reporterSrc, reward = (reporterSrc == nil) }

    TriggerClientEvent('pengu_fire:client:start', -1, id, coords)
    sendDispatch(coords, reporterSrc)
    local ffs = firefightersOnline()
    for i = 1, #ffs do chatTo(ffs[i], 'Structure fire reported - respond and extinguish it.', 'info') end

    SetTimeout(reporterSrc and Config.reportExpireMs or Config.autoExpireMs, function()
        if activeFires[id] then
            activeFires[id] = nil
            TriggerClientEvent('pengu_fire:client:stop', -1, id)
        end
    end)
    return true
end

-- Backfill active fires to a (re)joining client so they can see + fight fires that spawned before
-- they connected/loaded. startFireVisual de-dupes, so re-sending a known fire is harmless.
RegisterNetEvent('pengu_fire:server:requestActive', function()
    local src = source
    for id, fire in pairs(activeFires) do
        TriggerClientEvent('pengu_fire:client:start', src, id, fire.coords)
    end
end)

-- A firefighter spraying an extinguisher near a fire. Server re-validates job + proximity +
-- rate-limit so it cannot be remote-spammed.
RegisterNetEvent('pengu_fire:server:damage', function(id)
    local src = source
    if not onDutyFire(src) then return end
    local fire = activeFires[id]
    if not fire then return end

    local now = GetGameTimer()
    if lastSpray[src] and (now - lastSpray[src]) < (Config.sprayIntervalMs - 50) then return end
    lastSpray[src] = now

    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    -- Server-authoritative weapon check (the client gate alone is spoofable): no extinguish without
    -- the extinguisher actually equipped. GetSelectedPedWeapon returns the ped's weapon hash server-side.
    if GetSelectedPedWeapon(ped) ~= Config.extinguishWeapon then return end
    if #(GetEntityCoords(ped) - fire.coords) > (Config.extinguishRadius + 3.0) then return end

    fire.contributors[src] = true
    fire.hp = fire.hp - Config.damagePerSpray
    if fire.hp <= 0 then extinguishFire(id) end
end)

-- /firecall: any player reports a fire at their location (RP). Cooldown-gated; firefighter
-- self-reports earn nothing (reporter is excluded from reward) so it can't be farmed.
RegisterCommand('firecall', function(src)
    if src <= 0 then return end
    local now = GetGameTimer()
    if lastFirecall[src] and (now - lastFirecall[src]) < Config.firecallCooldownMs then
        chatTo(src, 'You recently reported a fire. Please wait before reporting another.', 'err')
        return
    end
    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    if spawnFire(GetEntityCoords(ped), src) then
        lastFirecall[src] = now
        chatTo(src, 'Fire reported - the fire department has been dispatched.', 'ok')
    else
        chatTo(src, 'Dispatch is at capacity right now. Try again shortly.', 'err')
    end
end, false)

TriggerEvent('chat:addSuggestion', '/firecall', 'Report a structure fire at your location (LSFD)')

-- Random structure fires while firefighters are on duty.
if Config.randomFires then
    CreateThread(function()
        while true do
            Wait(math.random(Config.spawnIntervalMs.min, Config.spawnIntervalMs.max))
            if #firefightersOnline() > 0 and #Config.locations > 0 then
                spawnFire(Config.locations[math.random(#Config.locations)], nil)
            end
        end
    end)
end

AddEventHandler('playerDropped', function()
    local src = source
    lastFirecall[src] = nil
    lastSpray[src] = nil
    for _, fire in pairs(activeFires) do fire.contributors[src] = nil end
end)
