-- PenguRP: shared IMPAIRMENT effects pipeline (pengu_hud CLIENT).
-- A single 0-100 "impairment" level drives context-aware consequences:
--   on foot -> screen blur, a drunk camera sway, and an occasional stumble/fall at extreme levels
--   driving -> screen blur, a drunk camera sway, and brief grip loss (twitchy handling) at high levels
-- MULTIPLE named sources contribute and the STRONGEST one wins, so later-phase DRUG effects plug into
-- the SAME pipeline without duplicating any effect code:
--   exports.pengu_hud:SetImpairment('weed', 70)   -- set/raise a source by key (0 or nil clears it)
--   exports.pengu_hud:GetImpairment()             -- current combined level (0-100)
-- Stress feeds it via SetImpairment('stress', <stress>) from client/stress.lua.
-- Drug-specific VISUALS (e.g. a weed timecycle tint) can be layered by the drug script itself; this
-- module owns the SHARED physical/visual consequences common to any impaired state. ASCII only.

local sources = {} -- key -> level 0..100

local function combined()
    local m = 0
    for _, v in pairs(sources) do if v > m then m = v end end
    return m
end

-- Public API (used by stress now, by drug effects later).
exports('SetImpairment', function(key, level)
    if type(key) ~= 'string' then return end
    level = math.max(0, math.min(100, tonumber(level) or 0))
    sources[key] = (level > 0) and level or nil
end)
exports('GetImpairment', combined)

local MIN_FX = 50 -- below this combined level, no effects at all
local shaking = false
local nextBlur, nextHit, nextShake = 0, 0, 0

CreateThread(function()
    while true do
        local lvl = combined()
        if lvl < MIN_FX then
            if shaking then StopGameplayCamShaking(true); shaking = false end
            Wait(800)
        else
            local t = (lvl - MIN_FX) / (100 - MIN_FX) -- 0..1 ramp above the threshold
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            local driving = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
            local now = GetGameTimer()

            -- shared sway: a drunk camera shake, refreshed periodically (it persists between refreshes)
            -- with amplitude scaling on impairment, so it is harder to walk AND drive.
            if now >= nextShake then
                nextShake = now + 1500
                ShakeGameplayCam('DRUNK_SHAKE', 0.10 + t * 0.45)
                shaking = true
            end

            -- shared: periodic screen-blur pulses, more frequent the higher the impairment.
            if now >= nextBlur then
                nextBlur = now + math.floor(6500 - t * 4000)
                TriggerScreenblurFadeIn(800.0)
                CreateThread(function()
                    Wait(1200 + math.floor(t * 1400))
                    TriggerScreenblurFadeOut(900.0)
                end)
            end

            -- context consequence (higher impairment only, on a cooldown so it is not constant).
            if t >= 0.6 and now >= nextHit then
                if driving then
                    -- DRIVING: brief grip loss makes the car twitchy / hard to control.
                    nextHit = now + math.floor(8000 - t * 4000)
                    local v = veh
                    SetVehicleReduceGrip(v, true)
                    CreateThread(function()
                        Wait(500 + math.floor(t * 700))
                        if DoesEntityExist(v) then SetVehicleReduceGrip(v, false) end
                    end)
                elseif t >= 0.9 and IsPedOnFoot(ped) and not IsPedRagdoll(ped)
                    and not IsPedSwimming(ped) and not IsPedInAnyVehicle(ped, false) then
                    -- ON FOOT (extreme): stumble / fall.
                    nextHit = now + 10000
                    local fwd = GetEntityForwardVector(ped)
                    SetPedToRagdollWithFall(ped, 2200, 2200, 1, fwd.x, fwd.y, fwd.z, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
                end
            end

            Wait(250)
        end
    end
end)

-- Never leave a shake/blur stuck if the resource stops.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    StopGameplayCamShaking(true)
    TriggerScreenblurFadeOut(0.0)
end)
