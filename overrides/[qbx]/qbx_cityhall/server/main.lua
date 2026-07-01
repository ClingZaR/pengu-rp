local sharedConfig = require 'config.shared'

local function getClosestHall(pedCoords)
    local distance = #(pedCoords - sharedConfig.cityhalls[1].coords)
    local closest = 1
    for i = 1, #sharedConfig.cityhalls do
        local hall = sharedConfig.cityhalls[i]
        local dist = #(pedCoords - hall.coords)
        if dist < distance then
            distance = dist
            closest = i
        end
    end
    return closest
end

local function distanceCheck(source, job)
    local ped = GetPlayerPed(source)
    local pedCoords = GetEntityCoords(ped)
    local closestCityhall = getClosestHall(pedCoords)
    local cityhallCoords = sharedConfig.cityhalls[closestCityhall].coords
    if #(pedCoords - cityhallCoords) >= 20.0 or not sharedConfig.employment.jobs[job] then
        return false
    end
    return true
end

lib.callback.register('qbx_cityhall:server:requestId', function(source, item, hall)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return end
    local itemType = sharedConfig.cityhalls[hall].licenses[item]

    if itemType.item ~= 'id_card' and itemType.item ~= 'driver_license' and itemType.item ~= 'weaponlicense'
        and itemType.item ~= 'business_license' then -- PenguRP
        return exports.qbx_core:Notify(source, locale('error.invalid_type'), 'error')
    end

    if not player.Functions.RemoveMoney('cash', itemType.cost) then
        return exports.qbx_core:Notify(source, locale('error.not_enough_money'), 'error')
    end

    -- PenguRP: business license is a plain item (qbx_idcard has no card config for it,
    -- CreateMetaLicense would error). Refund if it cannot be carried.
    if itemType.item == 'business_license' then
        if not exports.ox_inventory:AddItem(source, itemType.item, 1) then
            player.Functions.AddMoney('cash', itemType.cost)
            return exports.qbx_core:Notify(source, 'You cannot carry the license.', 'error')
        end
        return exports.qbx_core:Notify(source, locale('success.item_recieved') .. itemType.label, 'success')
    end

    exports.qbx_idcard:CreateMetaLicense(source, itemType.item)
    exports.qbx_core:Notify(source, locale('success.item_recieved') .. itemType.label, 'success')
end)

lib.callback.register('qbx_cityhall:server:applyJob', function(source, job)
    if not sharedConfig.employment.enabled then
        lib.print.error((
            'Weird applyJob attempt while employment is disabled | source=%s | name=%s | requestedJob=%s'
        ):format(source, GetPlayerName(source), tostring(job)))
        return false
    end

    local player = exports.qbx_core:GetPlayer(source)
    if not player or not distanceCheck(source, job) then return end

    if not sharedConfig.employment.jobs[job] then
        exports.qbx_core:Notify(source, locale('error.invalid_job'), 'error')
        return false
    end
    
    player.Functions.SetJob(job, 0)
    exports.qbx_core:Notify(source, locale('success.new_job'), 'success')
end)
