-- PenguRP - consumable item effects (ox_inventory client.export handlers).
-- items.lua wires: steroid -> pengu_core.useSteroid, adrenaline_shot -> pengu_core.useAdrenaline.
-- ox_inventory calls the export(data, slot) and returns, so WE must call
-- exports.ox_inventory:useItem(data, cb) to actually consume the item; the item's anim/usetime
-- progress bar runs inside useItem and cb only fires on success. ASCII only. luac clean.

local SPRINT_MULT = 1.12
local STEROID_MS  = 120000

-- GetGameTimer() deadline; > now means the buff is active. Refreshing the deadline extends the
-- single running watcher thread, so the multiplier is applied once and never stacks.
local steroidExpires = 0

local function resetSprint()
    SetRunSprintMultiplierForPlayer(cache.playerId, 1.0)
end

exports('useSteroid', function(data, slot)
    exports.ox_inventory:useItem(data, function(slotData)
        if not slotData then return end
        RestorePlayerStamina(cache.playerId, 1.0)
        local wasActive = steroidExpires > GetGameTimer()
        steroidExpires = GetGameTimer() + STEROID_MS
        if wasActive then
            lib.notify({ title = 'Steroid', description = 'Effect refreshed.', type = 'inform' })
            return
        end
        SetRunSprintMultiplierForPlayer(cache.playerId, SPRINT_MULT)
        lib.notify({ title = 'Steroid', description = 'You feel a surge of energy.', type = 'success' })
        CreateThread(function()
            while GetGameTimer() < steroidExpires do
                Wait(1000)
            end
            steroidExpires = 0
            resetSprint()
            lib.notify({ title = 'Steroid', description = 'The effect wears off.', type = 'inform' })
        end)
    end)
end)

exports('useAdrenaline', function(data, slot)
    exports.ox_inventory:useItem(data, function(slotData)
        if not slotData then return end
        local ped = cache.ped
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        -- pengu_hud/server/stress.lua registers this exact event (positive magnitude, clamped there)
        TriggerServerEvent('hud:server:RelieveStress', 30)
        lib.notify({ title = 'Adrenaline', description = 'Your body surges back to full strength.', type = 'success' })
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then resetSprint() end
end)
