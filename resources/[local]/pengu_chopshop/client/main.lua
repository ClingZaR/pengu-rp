-- PenguRP Chop Shop (pengu_chopshop) - CLIENT.
-- A global-vehicle ox_target "Strip Vehicle" inside each chop zone; the strip needs NO tool (the shop
-- has everything) and the server only allows WANTED models. Workshop PROPS + a map blip spawn at each
-- point. NO mechanic ped here - place a mechanic dealer separately with /dealeradd mechanic.
-- ASCII only. luac clean.

local chopPoints = {} -- flat array of { id, label, x, y, z }
local pointBlips = {} -- pointId -> map blip handle
local busy       = false

-- ===================== zone check =====================
local function nearChop(coords)
    for _, p in ipairs(chopPoints) do
        if #(coords - vector3(p.x + 0.0, p.y + 0.0, p.z + 0.0)) <= (Config.zoneRadius or 30.0) then
            return true
        end
    end
    return false
end

-- ===================== vehicle chop action =====================
local function chopVehicle(veh)
    if busy or not veh or veh == 0 then return end

    -- no tool required: the chop shop has everything. The server validates wanted-model + proximity.
    busy = true
    local ok = lib.skillCheck({ 'medium', 'medium', 'hard' }, { 'w', 'a', 's', 'd' })
    if not ok then
        lib.notify({ title = 'Chop Shop', description = 'You slipped - job botched.', type = 'error' })
        busy = false; return
    end

    local prog = lib.progressCircle({
        label = 'Stripping vehicle',
        duration = Config.chopTime or 12000,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_player' },
    })
    if not prog then busy = false; return end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    local done  = lib.callback.await('pengu_chop:chop', false, netId)
    if not done then
        lib.notify({ title = 'Chop Shop', description = 'Could not chop that here.', type = 'error' })
    end
    busy = false
end

-- ===================== workshop props (distance-streamed) =====================
local propEnts  = {} -- pointId -> list of entity handles
local pointsGen = 0  -- bumped on every applyPoints; in-flight spawns abort if it changes mid-load

local STREAM_IN  = 70.0
local STREAM_OUT = 90.0

local function spawnProps(point)
    if propEnts[point.id] ~= nil then return end
    local myGen = pointsGen
    propEnts[point.id] = {} -- claim the slot
    -- build into a LOCAL list (never index the shared table across a yield -> no nil-index crash if a
    -- re-sync rebinds it mid-load); commit only if we still own the slot.
    local built = {}
    for _, pc in ipairs(Config.chopProps or {}) do
        local hash = joaat(pc.model)
        if IsModelValid(hash) then
            RequestModel(hash)
            local t = GetGameTimer()
            while not HasModelLoaded(hash) and GetGameTimer() - t < 3000 do Wait(50) end
            if myGen ~= pointsGen then break end -- re-synced: stop building
            if HasModelLoaded(hash) then
                local ex = point.x + (pc.dx or 0.0) + 0.0
                local ey = point.y + (pc.dy or 0.0) + 0.0
                local obj = CreateObject(hash, ex, ey, point.z + (pc.dz or 0.0) - 1.0, false, false, false)
                PlaceObjectOnGroundProperly(obj)
                FreezeEntityPosition(obj, true)
                SetEntityAsMissionEntity(obj, true, true)
                built[#built + 1] = obj
                SetModelAsNoLongerNeeded(hash)
            end
        else
            print(('[pengu_chopshop] prop model "%s" is INVALID - skipped'):format(tostring(pc.model)))
        end
    end
    if myGen ~= pointsGen then
        for _, o in ipairs(built) do if DoesEntityExist(o) then DeleteEntity(o) end end
        return -- new gen owns the slot; don't touch propEnts
    end
    propEnts[point.id] = built
end

local function removeProps(id)
    for _, obj in ipairs(propEnts[id] or {}) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    propEnts[id] = nil
end

-- distance-stream the workshop props
CreateThread(function()
    while true do
        Wait(2000)
        local pc = GetEntityCoords(PlayerPedId())
        for _, point in ipairs(chopPoints) do
            local dist = #(pc - vector3(point.x + 0.0, point.y + 0.0, point.z + 0.0))
            if dist < STREAM_IN then
                if propEnts[point.id] == nil then CreateThread(function() spawnProps(point) end) end
            elseif dist > STREAM_OUT then
                removeProps(point.id)
            end
        end
    end
end)

-- ===================== global vehicle target =====================
local function buildGlobalTarget()
    exports.ox_target:addGlobalVehicle({
        {
            name      = 'pengu_chop_vehicle',
            icon      = 'fa-solid fa-screwdriver-wrench',
            label     = 'Strip Vehicle',
            distance  = Config.targetDist or 3.5,
            canInteract = function(entity)
                if busy or not entity or entity == 0 then return false end
                return nearChop(GetEntityCoords(entity))
            end,
            onSelect = function(data) chopVehicle(data.entity) end,
        },
    })
end

local function clearStreamed()
    -- clear keys IN PLACE (removeProps sets each entry to nil); do NOT rebind the table, or in-flight
    -- spawn threads holding the old table would crash / leak. The generation guard handles the rest.
    for id in pairs(propEnts) do removeProps(id) end
end

-- ===================== point sync =====================
local function clearPointBlips()
    for _, b in pairs(pointBlips) do if b and DoesBlipExist(b) then RemoveBlip(b) end end
    pointBlips = {}
end

-- persistent map blip per chop point so the location is visible on the map.
local function makePointBlip(p)
    local b = AddBlipForCoord(p.x + 0.0, p.y + 0.0, p.z + 0.0)
    SetBlipSprite(b, 446)            -- wrench / chop icon
    SetBlipColour(b, 5)              -- yellow
    SetBlipScale(b, 0.8)
    SetBlipAsShortRange(b, true)     -- only shows on the minimap when nearby (keeps the underworld low-key)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(p.label or 'Chop Shop')
    EndTextCommandSetBlipName(b)
    pointBlips[p.id] = b
end

local function applyPoints(pts)
    pointsGen = pointsGen + 1 -- invalidate any in-flight spawn threads from the previous point set
    clearStreamed()
    clearPointBlips()
    chopPoints = pts or {}
    for _, p in ipairs(chopPoints) do makePointBlip(p) end
end

RegisterNetEvent('pengu_chop:pointsUpdated', function(points) applyPoints(points) end)

CreateThread(function()
    local pts = lib.callback.await('pengu_chop:getPoints', false) or {}
    applyPoints(pts)
    buildGlobalTarget()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local pts = lib.callback.await('pengu_chop:getPoints', false) or {}
    applyPoints(pts)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    exports.ox_target:removeGlobalVehicle('pengu_chop_vehicle')
    clearStreamed()
    clearPointBlips()
end)

TriggerEvent('chat:addSuggestion', '/choploc', 'Manage chop points (admin)', {
    { name = 'subcommand', help = 'add [label] | remove <id> | list' },
})
