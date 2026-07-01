-- PenguRP - Traffic & Pursuit  [CLIENT SPINE]
-- Shared helpers in the global table `PT` used by every feature module
-- (spikes/radar/cones/speedcam/carjack/parking), plus the /fines pay UI.
-- ASCII only. luac clean.

PT = PT or {}
PT.cfg = Config

local QBX = exports.qbx_core

-- ---------- job / duty ----------
function PT.isLeoOnDuty()
    local d = QBX:GetPlayerData()
    local job = d and d.job
    return job ~= nil and job.type == 'leo' and job.onduty == true
end

-- ---------- speed / plate ----------
-- Returns vehicle speed in the configured unit (mph/kph), rounded.
function PT.speed(veh)
    if not veh or veh == 0 then return 0 end
    local mps = GetEntitySpeed(veh)
    local mult = (Config.speedUnit == 'kph') and 3.6 or 2.23694
    return math.floor(mps * mult + 0.5)
end

function PT.plate(veh)
    if not veh or veh == 0 then return '' end
    local p = GetVehicleNumberPlateText(veh) or ''
    return (p:gsub('%s+$', ''):gsub('^%s+', '')):upper()
end

-- ---------- raycasts ----------
local function rotToDir(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vec3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

-- Vehicle the officer is aiming at (camera ray). 0 if none within maxDist.
function PT.getVehicleAhead(maxDist)
    maxDist = maxDist or 90.0
    local cam = GetGameplayCamCoord()
    local dir = rotToDir(GetGameplayCamRot(2))
    local dest = cam + dir * maxDist
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, 10, cache.ped, 0)
    local _, hit, _, _, ent = GetShapeTestResult(ray) -- hit is a BOOLEAN in CfxLua, not 0/1
    if hit and ent and ent > 0 and IsEntityAVehicle(ent) then return ent end
    return 0
end

-- Nearest vehicle to a world coord within radius. 0 if none.
function PT.getClosestVehicle(coords, radius)
    radius = radius or 5.0
    local handle, veh = FindFirstVehicle()
    local best, bestD = 0, radius + 1.0
    local success
    repeat
        if veh and veh ~= 0 and DoesEntityExist(veh) then
            local d = #(GetEntityCoords(veh) - coords)
            if d < bestD then best, bestD = veh, d end
        end
        success, veh = FindNextVehicle(handle)
    until not success
    EndFindVehicle(handle)
    if bestD <= radius then return best end
    return 0
end

-- Server-id of the player driving `veh`, or nil if NPC / empty.
function PT.driverServerId(veh)
    if not veh or veh == 0 then return nil end
    local ped = GetPedInVehicleSeat(veh, -1)
    if ped == 0 or not IsPedAPlayer(ped) then return nil end
    local pl = NetworkGetPlayerIndexFromPed(ped)
    if pl == -1 then return nil end
    return GetPlayerServerId(pl)
end

-- ---------- notify (lavender ox_lib toast) ----------
function PT.notify(msg, ntype)
    lib.notify({
        title = 'Traffic',
        description = msg,
        type = ntype or 'inform',
        position = 'top',
        iconColor = '#E1C7F9',
    })
end

-- ---------- /fines : view + pay your outstanding fines ----------
RegisterCommand('fines', function()
    local fines = lib.callback.await('pengu_traffic:getMyFines', false) or {}
    if #fines == 0 then
        PT.notify('You have no outstanding fines.', 'success')
        return
    end
    local options = {}
    local total = 0
    for _, f in ipairs(fines) do
        total = total + (tonumber(f.amount) or 0)
        options[#options + 1] = {
            title = ('$%d - %s'):format(f.amount, f.reason or 'Fine'),
            description = ('%s - tap to pay'):format(f.kind or 'traffic'),
            icon = 'money-bill',
            onSelect = function()
                TriggerServerEvent('pengu_traffic:payFine', f.id)
            end,
        }
    end
    lib.registerContext({
        id = 'pengu_traffic_fines',
        title = ('Outstanding Fines ($%d)'):format(total),
        options = options,
    })
    lib.showContext('pengu_traffic_fines')
end, false)

TriggerEvent('chat:addSuggestion', '/fines', 'View and pay your outstanding traffic fines')
