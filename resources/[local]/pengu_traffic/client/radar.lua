-- PenguRP - Traffic & Pursuit  [ANPR RADAR HUD]
-- Vehicle-mounted police ANPR radar. While an on-duty officer is in a
-- police-class vehicle, a HUD above the speedometer lists the plate + speed of
-- every vehicle in a forward cone. Arrow up/down move the selection; arrow
-- right runs the selected plate in the MDT. The HUD is a NUI panel (html/) -
-- this module only pushes SendNUIMessage data and NEVER takes NUI focus.
-- ASCII only. luac clean.

local active = false
local plates = {}   -- list of { plate = String, speed = Number }
local selected = 1
local lastScan = 0

-- Return the vehicle the player is driving IF they are an on-duty officer in a
-- police-class vehicle; otherwise nil.
local function inPoliceVehicle()
    if not PT.isLeoOnDuty() then return nil end
    local veh = cache.vehicle
    if not veh or veh == 0 then return nil end
    if GetVehicleClass(veh) ~= Config.radar.vehicleClass then return nil end
    return veh
end

-- Scan all nearby vehicles in the forward cone of 'veh'. Returns up to
-- Config.radar.maxPlates rows of { plate, speed }, sorted nearest-first.
local function scan(veh)
    local myCoords = GetEntityCoords(veh)
    local fwd = GetEntityForwardVector(veh)
    local near = lib.getNearbyVehicles(myCoords, Config.radar.range, false)
    local found = {}
    for i = 1, #near do
        local e = near[i]
        local ent = e.vehicle
        if ent ~= veh and DoesEntityExist(ent) then
            local dir = e.coords - myCoords
            local dist = #(dir)
            if dist > 1.0 then
                local nd = dir / dist
                local dot = fwd.x * nd.x + fwd.y * nd.y + fwd.z * nd.z
                if dot >= Config.radar.frontDot then
                    found[#found + 1] = {
                        plate = PT.plate(ent),
                        speed = PT.speed(ent),
                        dist = dist,
                    }
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.dist < b.dist end)
    local rows = {}
    local limit = Config.radar.maxPlates
    for i = 1, #found do
        if i > limit then break end
        rows[i] = { plate = found[i].plate, speed = found[i].speed }
    end
    return rows
end

-- Clamp the selection into range and push the current list to the NUI.
local function pushList()
    if #plates == 0 then
        selected = 1
    else
        if selected < 1 then selected = 1 end
        if selected > #plates then selected = #plates end
    end
    SendNUIMessage({
        action = 'radarList',
        plates = plates,
        selected = selected,
    })
end

-- Main loop: reveal/hide the panel with police-vehicle state, rescan on an
-- interval, and handle the selection / run-plate keys each frame.
CreateThread(function()
    while true do
        local veh = inPoliceVehicle()

        if veh and not active then
            active = true
            selected = 1
            SendNUIMessage({ action = 'radarShow' })
        elseif not veh and active then
            active = false
            plates = {}
            SendNUIMessage({ action = 'radarHide' })
        end

        if active then
            local now = GetGameTimer()
            if now - lastScan >= Config.radar.scanMs then
                lastScan = now
                plates = scan(veh)
                pushList()
            end

            if IsControlJustPressed(0, Config.radar.upKey) and #plates > 0 then
                selected = selected - 1
                if selected < 1 then selected = #plates end
                pushList()
            elseif IsControlJustPressed(0, Config.radar.downKey) and #plates > 0 then
                selected = selected + 1
                if selected > #plates then selected = 1 end
                pushList()
            elseif IsControlJustPressed(0, Config.radar.runKey) then
                if plates[selected] then
                    TriggerEvent('pengu_mdt:runPlate', plates[selected].plate)
                end
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- Tidy the HUD if the resource stops while the radar is open.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SendNUIMessage({ action = 'radarHide' })
end)
