-- PenguRP: stress mechanic SERVER, revived from the (stopped) qbx_hud.
-- The HUD bar is drawn by pengu_hud/client/main.lua (reads metadata.stress); what went missing
-- when qbx_hud was stopped was the GAIN/RELIEVE logic. MANY resources fire these exact events --
-- qbx_medical, qbx_ambulancejob, qbx_smallresources (consumables), qbx_storerobbery,
-- qbx_vehiclekeys -- so re-registering the handlers under the SAME names revives the whole
-- mechanic for free, no edits to those resources. ASCII only. luac clean.

-- Stress applies to EVERYONE, including on-duty police. (Was true, which made on-duty LEO immune to
-- all stress - that is why running people over / no seatbelt / crashing did nothing while testing as
-- a cop. Flip back to true if you want trained officers to be stress-exempt on duty.)
local DISABLE_FOR_LEO = false
local lastNotify = {}        -- [src] = GetGameTimer() ms, to throttle the "stress rising" feedback

local function adjustStress(src, delta)
    if delta == 0 then return end
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local job = player.PlayerData.job
    if DISABLE_FOR_LEO and job and job.type == 'leo' and job.onduty then return end
    local cur = tonumber(player.PlayerData.metadata.stress) or 0
    local new = cur + delta
    if new < 0 then new = 0 elseif new > 100 then new = 100 end
    if new == cur then return end
    player.Functions.SetMetaData('stress', new)
    TriggerClientEvent('hud:client:UpdateStress', src, new)

    -- Feedback so the player actually SEES stress moving (the HUD bar hides at low stress). Relief
    -- is occasional (item/medic) so it always shows; gains are throttled so continuous speeding /
    -- shooting doesn't spam a notify every tick.
    if delta < 0 then
        exports.qbx_core:Notify(src, 'You feel calmer.', 'inform')
    else
        local now = GetGameTimer()
        if not lastNotify[src] or (now - lastNotify[src]) > 12000 then
            lastNotify[src] = now
            exports.qbx_core:Notify(src, 'Your stress is rising.', 'inform')
        end
    end
end

AddEventHandler('playerDropped', function() lastNotify[source] = nil end)

-- amount is always treated as a magnitude (callers pass a positive number); clamp per-call so a
-- spoofed value can't overshoot, the 0..100 result clamp does the rest.
RegisterNetEvent('hud:server:GainStress', function(amount)
    adjustStress(source, math.min(100, math.abs(tonumber(amount) or 0)))
end)

RegisterNetEvent('hud:server:RelieveStress', function(amount)
    adjustStress(source, -math.min(100, math.abs(tonumber(amount) or 0)))
end)
