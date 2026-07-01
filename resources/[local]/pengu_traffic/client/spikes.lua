-- PenguRP - Traffic & Pursuit : SPIKE STRIPS
-- Usable item 'spikestrip' deploys a stinger in front of the officer.
-- A distributed burst loop pops the LOCAL player's tyres over any networked
-- spike. ox_target lets on-duty LEO pick spikes back up.
-- Reuses PT.* helpers (client/main.lua). ASCII only. luac clean.

local SPIKE_MODEL = Config.spikes.model
local SPIKE_HASH  = GetHashKey(SPIKE_MODEL)

-- Spikes this client deployed (so we can clean them up on resource stop).
local deployed = {}

-- Forget a (possibly picked-up) spike object from our deploy list.
local function forgetSpike(obj)
    for i = #deployed, 1, -1 do
        if deployed[i] == obj then
            table.remove(deployed, i)
            return
        end
    end
end

-- ============================== DEPLOY (usable item) ==============================
exports('spikestrip', function(data, slot)
    if not PT.isLeoOnDuty() then
        PT.notify('You must be an on-duty officer to deploy a spike strip.', 'error')
        return
    end
    if not lib.requestModel(SPIKE_HASH, 5000) then
        PT.notify('Failed to load the spike strip model.', 'error')
        return
    end
    local ped     = cache.ped
    local coords  = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local rad     = math.rad(heading)
    -- ~1.8m in front of the ped, aligned to ped heading.
    local pos = vec3(
        coords.x - math.sin(rad) * 1.8,
        coords.y + math.cos(rad) * 1.8,
        coords.z
    )
    local obj = CreateObject(SPIKE_HASH, pos.x, pos.y, pos.z, true, true, false)
    SetEntityHeading(obj, heading)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(SPIKE_HASH)

    -- Resolve the network id (retry a few frames if it is not ready yet).
    local netId = NetworkGetNetworkIdFromEntity(obj)
    local tries = 0
    while (not netId or netId == 0) and tries < 10 do
        Wait(0); netId = NetworkGetNetworkIdFromEntity(obj); tries = tries + 1
    end
    if not netId or netId == 0 then
        DeleteEntity(obj)
        PT.notify('Deploy failed, try again.', 'error')
        return
    end

    -- Server CONSUMES one spike strip and registers the placement (authoritative).
    -- If the officer has none, nothing is consumed and we remove the object.
    local ok = lib.callback.await('pengu_traffic:spikeDeploy', false, netId, 'spikestrip')
    if not ok then
        DeleteEntity(obj)
        PT.notify('You have no spike strips.', 'error')
        return
    end
    deployed[#deployed + 1] = obj
    PT.notify('Spike strip deployed.', 'success')
end)

-- ============================== BURST LOOP ==============================
-- Each client pops its OWN tyres over any networked spike within range.
local lastBurstVeh = 0
local lastBurstAt  = 0

CreateThread(function()
    while true do
        local sleep = 500
        local veh = cache.vehicle
        if veh and veh ~= 0 then
            -- Gate the expensive object scan behind the speed check: below burstSpeedMin the tyres can't
            -- pop anyway, so don't run GetClosestObjectOfType every frame while parked/cruising. At/above
            -- burst speed we still tight-loop (Wait 0) so a fast car never skips the small 2.6m spike.
            if PT.speed(veh) > Config.spikes.burstSpeedMin then
                sleep = 0
                local vc = GetEntityCoords(veh)
                local spike = GetClosestObjectOfType(vc.x, vc.y, vc.z, Config.spikes.triggerRadius, SPIKE_HASH, false, false, false)
                if spike and spike ~= 0 then
                    local now = GetGameTimer()
                    if veh ~= lastBurstVeh or (now - lastBurstAt) > 5000 then
                        for i = 0, 5 do
                            SetVehicleTyreBurst(veh, i, true, 1000.0)
                        end
                        lastBurstVeh = veh
                        lastBurstAt  = now
                    end
                end
            else
                sleep = 250 -- below burst speed: skip the per-frame object scan
            end
        else
            lastBurstVeh = 0
        end
        Wait(sleep)
    end
end)

-- ============================== PICKUP (ox_target) ==============================
exports.ox_target:addModel(SPIKE_HASH, {
    {
        name = 'pengu_spike_pickup',
        icon = 'fas fa-hand',
        label = 'Pick up Spike Strip',
        canInteract = function()
            return PT.isLeoOnDuty()
        end,
        onSelect = function(d)
            local e = d.entity
            local netId = NetworkGetNetworkIdFromEntity(e)
            -- Server returns the item and deletes the object for everyone.
            local ok = lib.callback.await('pengu_traffic:pickupDeployable', false, netId)
            if not ok then
                PT.notify('Could not retrieve that spike strip.', 'error')
                return
            end
            forgetSpike(e)
            PT.notify('Spike strip retrieved.', 'success')
        end,
    },
})

-- ============================== CLEANUP ==============================
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for i = 1, #deployed do
        local obj = deployed[i]
        if obj and DoesEntityExist(obj) then
            SetEntityAsMissionEntity(obj, true, true)
            DeleteEntity(obj)
        end
    end
end)
