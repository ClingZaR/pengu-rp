-- PenguRP: stress mechanic CLIENT, revived from the (stopped) qbx_hud.
-- Triggers stress GAIN from COLLISIONS (hitting other cars/objects, or running people over) and from
-- shooting a non-whitelisted weapon. The stress LEVEL is pushed into the shared impairment pipeline
-- (client/effects.lua), which applies the actual consequences (blur, drunk sway, stumble, grip loss)
-- both on foot AND while driving. Later-phase DRUG effects feed the SAME pipeline.
-- NOTE: seatbelt stress was removed on purpose - seatbelt consequences come in a later phase
-- (qbx_seatbelt already ejects you through the windscreen on a hard crash). ASCII only.

local stress = 0
local hasWeapon = false
local speedMultiplier = 3.6 -- km/h (matches the pengu_hud speedometer)

local CHANCE_SHOOT = 0.1
local WHITELISTED_WEAPONS = { -- no stress from these
    [`WEAPON_UNARMED`] = true,
    [`WEAPON_SNOWBALL`] = true,
    [`WEAPON_STUNGUN`] = true,
    [`WEAPON_FLASHLIGHT`] = true,
    [`WEAPON_FIREEXTINGUISHER`] = true,
    [`WEAPON_PETROLCAN`] = true,
    [`WEAPON_NIGHTSTICK`] = true,
}

-- Set the local stress value AND push it into the shared impairment pipeline (effects.lua) so the
-- consequences (blur / sway / stumble / grip loss) react to it. Drug effects use the same API.
local function setStress(v)
    stress = tonumber(v) or 0
    exports.pengu_hud:SetImpairment('stress', stress)
end

RegisterNetEvent('hud:client:UpdateStress', function(newStress)
    setStress(newStress)
end)

-- Keep local stress in sync with metadata (covers relog / admin set / first load).
CreateThread(function()
    while true do
        local pd = exports.qbx_core:GetPlayerData()
        if pd and pd.metadata and pd.metadata.stress ~= nil then setStress(pd.metadata.stress) end
        Wait(5000)
    end
end)

local function isDriving()
    local veh = cache.vehicle
    if not veh or cache.seat ~= -1 then return nil end -- must be the DRIVER
    local vc = GetVehicleClass(veh)
    if vc == 13 or vc == 14 or vc == 15 or vc == 16 or vc == 21 then return nil end -- skip bike/boat/heli/plane/train
    return veh
end

-- GAIN: collision - a sudden drop in body health means you hit another car, a wall, or an object.
CreateThread(function()
    local lastBody
    while true do
        Wait(250)
        local veh = isDriving()
        if veh then
            local bh = GetVehicleBodyHealth(veh)
            if lastBody and bh < (lastBody - 12) then -- moderate+ impact (incl. car-to-car bumps)
                local dmg = lastBody - bh
                TriggerServerEvent('hud:server:GainStress', math.min(15, math.max(2, math.floor(dmg / 12))))
            end
            lastBody = bh
        else
            lastBody = nil
        end
    end
end)

-- GAIN: running people over - a nearby ped/player damaged by your moving vehicle.
CreateThread(function()
    while true do
        Wait(600)
        local veh = isDriving()
        if veh and (GetEntitySpeed(veh) * speedMultiplier) > 12 then
            local vpos = GetEntityCoords(veh)
            for _, ped in ipairs(GetGamePool('CPed')) do
                if ped ~= cache.ped and DoesEntityExist(ped)
                    and #(GetEntityCoords(ped) - vpos) < 7.0
                    and HasEntityBeenDamagedByEntity(ped, veh, true) then
                    TriggerServerEvent('hud:server:GainStress', math.random(4, 8))
                    ClearEntityLastDamageEntity(ped)
                end
            end
        end
    end
end)

-- GAIN: shooting a non-whitelisted weapon.
local function startWeaponStressThread(hash)
    if WHITELISTED_WEAPONS[hash] then return end
    hasWeapon = true
    CreateThread(function()
        while hasWeapon do
            if IsPedShooting(cache.ped) and math.random() <= CHANCE_SHOOT then
                TriggerServerEvent('hud:server:GainStress', math.random(1, 5))
            end
            Wait(0)
        end
    end)
end

AddEventHandler('ox_inventory:currentWeapon', function(currentWeapon)
    hasWeapon = false
    Wait(0)
    if currentWeapon and currentWeapon.hash then startWeaponStressThread(currentWeapon.hash) end
end)
