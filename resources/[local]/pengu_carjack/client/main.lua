-- PenguRP Carjack (pengu_carjack) - CLIENT.
-- ox_target on all vehicles:
--   Unoccupied -> "Hotwire" (lockpick required): skillcheck + progress, then server event.
--   Occupied   -> "Carjack" (no item): immediate server event (driver ejected server-side).
-- The server re-validates everything; the client only runs UX.

local function notify(msg, ok)
    lib.notify({ description = msg, type = ok and 'success' or 'error' })
end

----------------------------------------------------------------------
-- Hotwire action (unoccupied vehicle)
----------------------------------------------------------------------

local function doHotwire(vehicle)
    -- Quick client-side check: has lockpick?
    local lpCount = exports.ox_inventory:GetItemCount('lockpick')
    if (lpCount or 0) < 1 then
        notify('You need a lockpick.', false)
        return
    end

    -- Skillcheck: medium difficulty x2
    local sc = lib.skillCheck({'medium', 'medium'}, {'w', 'a', 's', 'd'})
    if not sc then
        notify('Failed to pick the lock.', false)
        return
    end

    -- Progress bar: hotwiring animation
    local ok = lib.progressBar({
        duration     = 20000,
        label        = 'Hotwiring...',
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, car = true, combat = true },
        anim         = { dict = 'veh@break_in@0h@p_m_one@', clip = 'low_stance_ds' },
    })

    if ok then
        TriggerServerEvent('pengu_carjack:hotwire', NetworkGetNetworkIdFromEntity(vehicle))
    end
end

----------------------------------------------------------------------
-- Carjack action (occupied vehicle)
----------------------------------------------------------------------

local function doCarjack(vehicle)
    local ok = lib.progressBar({
        duration     = 3000,
        label        = 'Carjacking...',
        useWhileDead = false,
        canCancel    = false,
        disable      = { move = false, car = false, combat = false },
        anim         = { dict = 'missfam1_crsatk1', clip = 'crs_plyr_run_atk_loop' },
    })

    if ok then
        TriggerServerEvent('pengu_carjack:carjack', NetworkGetNetworkIdFromEntity(vehicle))
    end
end

----------------------------------------------------------------------
-- ox_target on all vehicles
----------------------------------------------------------------------

exports.ox_target:addGlobalVehicle({
    {
        name     = 'pengu_hotwire',
        icon     = 'fa-solid fa-car-burst',
        label    = 'Hotwire Vehicle',
        distance = 2.5,
        onSelect = function(data)
            local vehicle = data.entity
            if not vehicle or vehicle == 0 then return end

            -- Only show for unoccupied vehicles
            local driver = GetPedInVehicleSeat(vehicle, -1)
            if driver ~= 0 and driver ~= cache.ped then
                notify('Vehicle is occupied. Use Carjack instead.', false)
                return
            end

            doHotwire(vehicle)
        end,
    },
    {
        name     = 'pengu_carjack',
        icon     = 'fa-solid fa-hand-fist',
        label    = 'Carjack Driver',
        distance = 2.5,
        onSelect = function(data)
            local vehicle = data.entity
            if not vehicle or vehicle == 0 then return end

            local driver = GetPedInVehicleSeat(vehicle, -1)
            if driver == 0 then
                notify('No driver to carjack. Use Hotwire instead.', false)
                return
            end
            if driver == cache.ped then
                notify('That\'s your own vehicle.', false)
                return
            end

            doCarjack(vehicle)
        end,
    },
})

----------------------------------------------------------------------
-- Eject handler (fired by server when this player's vehicle is carjacked)
----------------------------------------------------------------------

RegisterNetEvent('pengu_carjack:eject', function()
    local ped = cache.ped
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle and vehicle ~= 0 then
        TaskLeaveVehicle(ped, vehicle, 4160) -- 4160 = instant exit
    end
end)
