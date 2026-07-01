-- PenguRP - Traffic & Pursuit : AUTOMATED SPEED CAMERAS
-- Spawns fixed camera props at each Config.cameras entry and lets the local
-- player's own client report whenever the vehicle it occupies passes a camera
-- zone over the posted limit. The server (cameraFine handler) resolves the
-- plate owner, clamps and cooldowns per plate@label, so a duplicate report
-- from a passenger is harmless. ASCII only. luac clean.

local cams   = Config.cameras or {}
local spawned = {} -- created camera prop entity handles (non-networked locals)
local blips   = {} -- created map blip handles

-- ---------- model helper (timeout-guarded, never hard-blocks) ----------
local function loadModel(model)
    local hash = (type(model) == 'number') and model or GetHashKey(model)
    if not IsModelValid(hash) then return nil end
    -- pcall so a bad/missing model can't error out the whole setup pass.
    local ok = pcall(lib.requestModel, hash, 5000)
    if ok and HasModelLoaded(hash) then return hash end
    return nil
end

-- ---------- setup: spawn props + blips ----------
local function spawnCameraAt(cam)
    local c = cam.coords
    local heading = cam.heading or 0.0

    -- Pole at the base.
    local poleHash = loadModel(Config.cameraPoleModel)
    if poleHash then
        local pole = CreateObject(poleHash, c.x, c.y, c.z, false, false, false)
        if pole and pole ~= 0 then
            SetEntityHeading(pole, heading)
            FreezeEntityPosition(pole, true)
            SetEntityInvincible(pole, true)
            spawned[#spawned + 1] = pole
        end
        SetModelAsNoLongerNeeded(poleHash)
    end

    -- Camera head mounted near the top of the pole.
    local camHash = loadModel(Config.cameraPropModel)
    if camHash then
        local head = CreateObject(camHash, c.x, c.y, c.z + 3.2, false, false, false)
        if head and head ~= 0 then
            SetEntityHeading(head, heading)
            FreezeEntityPosition(head, true)
            SetEntityInvincible(head, true)
            spawned[#spawned + 1] = head
        end
        SetModelAsNoLongerNeeded(camHash)
    end

    -- Small short-range map blip.
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, 184)
    SetBlipScale(blip, 0.7)
    SetBlipColour(blip, 0)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(cam.label or 'Speed Camera')
    EndTextCommandSetBlipName(blip)
    blips[#blips + 1] = blip
end

CreateThread(function()
    if not Config.spawnCameraProps then return end
    for i = 1, #cams do
        spawnCameraAt(cams[i])
    end
end)

-- ---------- detection ----------
CreateThread(function()
    local radius       = Config.cameraRadius or 22.0
    local dispatchOver = Config.cameraDispatchOver or 35

    -- Per-camera "already fired this pass" flags; cleared once we leave the zone.
    local fired = {}
    for i = 1, #cams do fired[i] = false end

    while true do
        Wait(400)
        local veh = cache.vehicle
        if veh and veh ~= 0 then
            local vc  = GetEntityCoords(cache.ped)
            local spd = PT.speed(veh)
            for i = 1, #cams do
                local cam = cams[i]
                local d = #(vc - cam.coords)
                if d <= radius then
                    if not fired[i] and spd > cam.limit then
                        fired[i] = true
                        TriggerServerEvent('pengu_traffic:cameraFine', {
                            plate = PT.plate(veh),
                            speed = spd,
                            limit = cam.limit,
                            label = cam.label,
                        })
                        PT.notify('Speed camera flash - ' .. (cam.label or 'zone'), 'error')
                        if (spd - cam.limit) >= dispatchOver then
                            pcall(function() exports['ps-dispatch']:SpeedingVehicle() end)
                        end
                    end
                elseif fired[i] then
                    -- Left the zone: allow a fresh fire on re-entry.
                    fired[i] = false
                end
            end
        end
    end
end)

-- ---------- cleanup ----------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for i = 1, #spawned do
        local obj = spawned[i]
        if obj and DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
    end
    for i = 1, #blips do
        local b = blips[i]
        if b and DoesBlipExist(b) then
            RemoveBlip(b)
        end
    end
    spawned = {}
    blips = {}
end)
