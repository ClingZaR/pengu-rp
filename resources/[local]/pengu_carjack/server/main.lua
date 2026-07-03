-- PenguRP Carjack (pengu_carjack) - SERVER.
-- Two actions:
--   HOTWIRE: unoccupied vehicle, consumes lockpick, skillcheck client-side,
--            server validates proximity + lockpick + per-vehicle/player cooldowns,
--            then gives vehicle keys via qbx_vehiclekeys.
--   CARJACK: occupied vehicle, no item, server ejects driver, gives attacker keys.
-- ps-dispatch alert on both. Awards Criminal XP via pengu_xp. ASCII only. luac clean.

local qbx  = exports.qbx_core
local inv   = exports.ox_inventory
local keys  = exports.qbx_vehiclekeys

-- In-memory cooldowns. Per-netId resets on server restart (vehicles are re-netId'd anyway).
local vehCooldown = {}  -- netId -> expiry os.time()
local plyCooldown = {}  -- src   -> expiry os.time()

local VEHICLE_CD = 30 * 60  -- 30 min same vehicle
local PLAYER_CD  = 10 * 60  -- 10 min per player

local function cooled(tbl, key)
    return not tbl[key] or os.time() > tbl[key]
end

----------------------------------------------------------------------
-- Dispatch helper
----------------------------------------------------------------------

local function dispatch(src, msg, code, vehicle)
    local ped    = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    pcall(function()
        exports['ps-dispatch']:CustomAlert({
            coords      = coords,
            message     = msg,
            dispatchCode = code,
            description = msg,
            radius      = 0,
            sprite      = 225,
            color       = 1,
            scale       = 1.0,
            length      = 3,
        })
    end)
end

----------------------------------------------------------------------
-- XP helper
----------------------------------------------------------------------

local function awardXP(src, amount)
    pcall(function() exports.pengu_xp:Award(src, 'criminal', amount) end)
end

----------------------------------------------------------------------
-- HOTWIRE (unoccupied)
----------------------------------------------------------------------

RegisterNetEvent('pengu_carjack:hotwire', function(netId)
    local src = source
    netId = tonumber(netId)
    if not netId then return end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Vehicle not found.' })
        return
    end

    -- Proximity check (anti-spoof)
    local ped = GetPlayerPed(src)
    local px, py, pz = table.unpack(GetEntityCoords(ped, true))
    local vx, vy, vz = table.unpack(GetEntityCoords(vehicle, true))
    if #(vector3(px,py,pz) - vector3(vx,vy,vz)) > 6.0 then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Too far from the vehicle.' })
        return
    end

    -- Vehicle must be unoccupied
    if GetVehicleNumberOfPassengers(vehicle) > 0 or GetPedInVehicleSeat(vehicle, -1) ~= 0 then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Vehicle is occupied.' })
        return
    end

    -- Lockpick in inventory
    local lpCount = inv:GetItemCount(src, 'lockpick')
    if (lpCount or 0) < 1 then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='You need a lockpick.' })
        return
    end

    -- Cooldowns
    if not cooled(vehCooldown, netId) then
        local rem = vehCooldown[netId] - os.time()
        TriggerClientEvent('ox_lib:notify', src, { type='error',
            description=('This vehicle was recently hotwired. %d min left.'):format(math.ceil(rem/60)) })
        return
    end
    if not cooled(plyCooldown, src) then
        local rem = plyCooldown[src] - os.time()
        TriggerClientEvent('ox_lib:notify', src, { type='error',
            description=('You need to wait %d min.'):format(math.ceil(rem/60)) })
        return
    end

    -- Consume lockpick
    local removed = inv:RemoveItem(src, 'lockpick', 1)
    if not removed then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Could not consume lockpick.' })
        return
    end

    -- Set cooldowns
    vehCooldown[netId] = os.time() + VEHICLE_CD
    plyCooldown[src]   = os.time() + PLAYER_CD

    -- Give keys
    keys:GiveKeys(src, vehicle, true)

    -- Unlock the vehicle doors
    SetVehicleDoorsLocked(vehicle, 1)

    TriggerClientEvent('ox_lib:notify', src, { type='success', description='Hotwired. Get moving.' })
    dispatch(src, 'Vehicle Break-In in Progress', '10-82', vehicle)
    awardXP(src, 15)
end)

----------------------------------------------------------------------
-- CARJACK (occupied — eject driver)
----------------------------------------------------------------------

RegisterNetEvent('pengu_carjack:carjack', function(netId)
    local src = source
    netId = tonumber(netId)
    if not netId then return end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Vehicle not found.' })
        return
    end

    -- Proximity check
    local ped = GetPlayerPed(src)
    local px, py, pz = table.unpack(GetEntityCoords(ped, true))
    local vx, vy, vz = table.unpack(GetEntityCoords(vehicle, true))
    if #(vector3(px,py,pz) - vector3(vx,vy,vz)) > 4.0 then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Too far from the vehicle.' })
        return
    end

    -- Must have a driver (seat -1)
    local driverPed = GetPedInVehicleSeat(vehicle, -1)
    if driverPed == 0 then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='No driver to carjack.' })
        return
    end

    -- Find the FiveM player source that owns the driver ped
    local driverSrc = nil
    for _, pid in ipairs(GetPlayers()) do
        local pidNum = tonumber(pid)
        if pidNum and pidNum ~= src then
            if GetPlayerPed(pidNum) == driverPed then
                driverSrc = pidNum
                break
            end
        end
    end

    -- Cooldown (per-player only for carjack; no per-vehicle since it's occupied)
    if not cooled(plyCooldown, src) then
        local rem = plyCooldown[src] - os.time()
        TriggerClientEvent('ox_lib:notify', src, { type='error',
            description=('Wait %d min before another carjack.'):format(math.ceil(rem/60)) })
        return
    end
    plyCooldown[src] = os.time() + PLAYER_CD

    -- Eject driver if they're a player
    if driverSrc then
        TriggerClientEvent('pengu_carjack:eject', driverSrc)
        TriggerClientEvent('ox_lib:notify', driverSrc, { type='error', description='You were carjacked!' })
    end

    -- Give carjacker the keys
    keys:GiveKeys(src, vehicle, true)

    TriggerClientEvent('ox_lib:notify', src, { type='success', description='Carjacked.' })
    dispatch(src, 'Carjacking in Progress - Armed Suspect', '10-37', vehicle)
    awardXP(src, 25)
end)

----------------------------------------------------------------------
-- Cleanup cooldowns on player drop
----------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    plyCooldown[source] = nil
end)
