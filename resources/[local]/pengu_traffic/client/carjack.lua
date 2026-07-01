-- PenguRP - Traffic & Pursuit: Carjacking (pull driver out)
-- Registers ONE global-vehicle ox_target option that yanks the driver
-- (NPC fled, or player ejected server-side) and optionally pings dispatch.
-- ASCII only. Reuses PT.* helpers; do NOT reimplement them.

-- Global vehicle target option (registered ONCE at file load).
exports.ox_target:addGlobalVehicle({
    {
        name = 'pengu_carjack',
        icon = 'fas fa-car-burst',
        label = 'Pull Driver Out',
        distance = 2.0,
        canInteract = function(entity)
            local me = cache.vehicle
            if me == entity then return false end
            if Config.carjack.requireWeapon and GetSelectedPedWeapon(cache.ped) == GetHashKey('WEAPON_UNARMED') then
                return false
            end
            local drv = GetPedInVehicleSeat(entity, -1)
            return drv ~= 0 and drv ~= cache.ped
        end,
        onSelect = function(d)
            local veh = d.entity
            local drv = GetPedInVehicleSeat(veh, -1)
            if drv ~= 0 and IsPedAPlayer(drv) then
                local tsrc = PT.driverServerId(veh)
                if tsrc then
                    TriggerServerEvent('pengu_traffic:ejectDriver', tsrc)
                end
            else
                SetPedFleeAttributes(drv, 0, true)
                TaskLeaveVehicle(drv, veh, 4096)
                CreateThread(function()
                    Wait(250)
                    TaskSmartFleePed(drv, cache.ped, 100.0, -1, false, false)
                end)
            end
            if Config.carjack.dispatch then
                pcall(function()
                    exports['ps-dispatch']:CarJacking(veh)
                end)
            end
        end,
    },
})

-- Victim side: server tells the targeted player to bail out of their seat.
RegisterNetEvent('pengu_traffic:forceExit', function()
    local veh = cache.vehicle ~= 0 and cache.vehicle or GetVehiclePedIsIn(cache.ped, false)
    if veh and veh ~= 0 then
        TaskLeaveVehicle(cache.ped, veh, 4096)
    end
end)
