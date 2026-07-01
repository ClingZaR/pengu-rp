-- PenguRP - Traffic & Pursuit : TRAFFIC CONES
-- Reusable LEO item 'trafficcone' deploys a networked cone ~1.2m ahead of the
-- officer. Pick up via ox_target on the cone model. ASCII only. luac clean.

local coneModel = GetHashKey(Config.cones.model)

-- Cones this client has deployed (so onResourceStop only cleans up ours).
local deployed = {}

-- ---------- deploy (usable item) ----------
exports('trafficcone', function(data, slot)
    if not PT.isLeoOnDuty() then
        PT.notify('You must be an on-duty officer to place cones.', 'error')
        return
    end
    if not lib.requestModel(coneModel, 5000) then
        PT.notify('Failed to load cone model.', 'error')
        return
    end
    local ped = cache.ped
    local fwd = GetEntityForwardVector(ped)
    local pos = GetEntityCoords(ped) + fwd * 1.2
    local obj = CreateObject(coneModel, pos.x, pos.y, pos.z, true, true, false)
    SetModelAsNoLongerNeeded(coneModel)
    if not obj or obj == 0 then
        PT.notify('Failed to place cone.', 'error')
        return
    end
    PlaceObjectOnGroundProperly(obj)
    SetEntityHeading(obj, GetEntityHeading(ped))
    FreezeEntityPosition(obj, true)

    -- Resolve the network id (retry a few frames if not ready yet).
    local netId = NetworkGetNetworkIdFromEntity(obj)
    local tries = 0
    while (not netId or netId == 0) and tries < 10 do
        Wait(0); netId = NetworkGetNetworkIdFromEntity(obj); tries = tries + 1
    end
    if not netId or netId == 0 then
        DeleteEntity(obj)
        PT.notify('Placement failed, try again.', 'error')
        return
    end

    -- Server CONSUMES one cone and registers the placement (authoritative).
    local ok = lib.callback.await('pengu_traffic:spikeDeploy', false, netId, 'trafficcone')
    if not ok then
        DeleteEntity(obj)
        PT.notify('You have no cones.', 'error')
        return
    end
    deployed[#deployed + 1] = obj
    PT.notify('Cone placed.', 'success')
end)

-- ---------- pickup (ox_target on the cone model, registered once) ----------
exports.ox_target:addModel(coneModel, {
    {
        name = 'pengu_cone_pickup',
        icon = 'fas fa-hand',
        label = 'Pick up Cone',
        canInteract = function()
            return PT.isLeoOnDuty()
        end,
        onSelect = function(d)
            local ent = d.entity
            local netId = NetworkGetNetworkIdFromEntity(ent)
            -- Server returns the item and deletes the object for everyone.
            local ok = lib.callback.await('pengu_traffic:pickupDeployable', false, netId)
            if not ok then
                PT.notify('Could not retrieve that cone.', 'error')
                return
            end
            for i = #deployed, 1, -1 do
                if deployed[i] == ent then
                    table.remove(deployed, i)
                    break
                end
            end
            PT.notify('Cone retrieved.', 'success')
        end,
    },
})

-- ---------- cleanup ----------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for i = 1, #deployed do
        local obj = deployed[i]
        if obj and DoesEntityExist(obj) then
            SetEntityAsMissionEntity(obj, true, true)
            DeleteEntity(obj)
        end
    end
    deployed = {}
end)
