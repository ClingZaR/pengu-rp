-- PenguRP Drug Supply Chain (pengu_drugs) - CLIENT: renders the respawning PLANT NODES for field-type
-- labs (coca_field/weed_field) from GlobalState.penguDrugNodes via a 1s reconcile loop. Each node = a
-- ground-snapped plant prop with an ox_target "Harvest" option (skill check -> server harvestNode, which
-- gives the yield and despawns the plant). Mirrors the crate-drop renderer (collision-aware ground snap,
-- eye on the prop, sphere-zone fallback, distance streaming). ASCII only. luac clean.

local nodes     = {} -- id -> { id, type, x, y, z }
local nodeProps = {} -- id -> entity handle
local nodeZones = {} -- id -> ox_target zone id (fallback when the model fails)
local busy = false

local STREAM_IN  = 50.0
local STREAM_OUT = 65.0

local function loadPlantModel(ltype)
    local def = Config.labTypes[ltype]
    if not def then return nil end
    for _, name in ipairs({ def.plantModel, def.plantModelFallback }) do
        local hash = name and joaat(name)
        if hash and IsModelValid(hash) then
            RequestModel(hash)
            local t = GetGameTimer()
            while not HasModelLoaded(hash) and GetGameTimer() - t < 3000 do Wait(10) end
            if HasModelLoaded(hash) then return hash end
        end
    end
    return nil
end

local function harvest(id)
    if busy then return end
    local n = nodes[id]; if not n then return end
    local def = Config.labTypes[n.type]; if not def then return end
    busy = true
    local ok = lib.skillCheck(def.skill or 'easy', { 'w', 'a', 's', 'd' })
    if ok then
        if lib.progressCircle then
            local okBar = lib.progressCircle({
                label = 'Harvesting',
                duration = def.harvestTime or 5000,
                position = 'bottom',
                useWhileDead = false,
                canCancel = true,
                disable = { move = true, car = true, combat = true },
                anim = { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base' },
            })
            if not okBar then busy = false; return end -- cancelled = no harvest
        end
        local done = lib.callback.await('pengu_drugs:harvestNode', false, id)
        if not done then lib.notify({ title = 'Harvest', description = 'Could not harvest that plant.', type = 'error' }) end
    else
        lib.notify({ title = 'Harvest', description = 'You damaged the plant.', type = 'error' })
    end
    busy = false
end

local function nodeOptions(id, ltype)
    local def = Config.labTypes[ltype]
    return {
        {
            name     = 'pengu_node_' .. id,
            icon     = (def and def.icon) or 'fa-solid fa-seedling',
            label    = 'Harvest',
            distance = (Config.interactDist or 2.5) + 1.0,
            onSelect = function() harvest(id) end,
        },
    }
end

-- wait until static collision is loaded AROUND THE GIVEN ENTITY so the ground snap actually works
local function waitCollisionAround(entity, x, y, z)
    RequestCollisionAtCoord(x + 0.0, y + 0.0, z + 0.0)
    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() - t < 3000 do
        RequestCollisionAtCoord(x + 0.0, y + 0.0, z + 0.0)
        Wait(50)
    end
end

local function spawnNodeProp(id, n)
    local model = loadPlantModel(n.type)
    if not nodes[id] then -- harvested/removed during the model load
        if model then SetModelAsNoLongerNeeded(model) end
        return
    end
    if model then
        local obj = CreateObject(model, n.x + 0.0, n.y + 0.0, n.z + 0.0, false, false, false)
        if obj and obj ~= 0 then
            SetEntityAsMissionEntity(obj, true, true)
            waitCollisionAround(obj, n.x, n.y, n.z)
            PlaceObjectOnGroundProperly(obj)
            FreezeEntityPosition(obj, true)
            if not nodes[id] then DeleteEntity(obj); SetModelAsNoLongerNeeded(model); return end
            exports.ox_target:addLocalEntity(obj, nodeOptions(id, n.type))
            nodeProps[id] = obj
            SetModelAsNoLongerNeeded(model)
            return
        end
    end
    -- fallback: no prop model, but harvesting still works via a sphere zone on the ground
    waitCollisionAround(PlayerPedId(), n.x, n.y, n.z)
    if not nodes[id] then return end
    local z = n.z
    local found, gz = GetGroundZFor_3dCoord(n.x + 0.0, n.y + 0.0, n.z + 50.0, false)
    if found then z = gz end
    nodeZones[id] = exports.ox_target:addSphereZone({
        coords = vector3(n.x + 0.0, n.y + 0.0, z + 0.0),
        radius = (Config.interactDist or 2.5) + 1.0,
        debug = false,
        options = nodeOptions(id, n.type),
    })
end

local function despawnNode(id)
    if nodeProps[id] then
        if DoesEntityExist(nodeProps[id]) then
            exports.ox_target:removeLocalEntity(nodeProps[id])
            DeleteEntity(nodeProps[id])
        end
        nodeProps[id] = nil
    end
    if nodeZones[id] then
        exports.ox_target:removeZone(nodeZones[id])
        nodeZones[id] = nil
    end
end

local function clearAll()
    for id in pairs(nodeProps) do despawnNode(id) end
    for id in pairs(nodeZones) do despawnNode(id) end
    nodes, nodeProps, nodeZones = {}, {}, {}
end

-- single source of truth: reconcile world plant nodes from GlobalState every second + stream by distance
CreateThread(function()
    while true do
        local incoming = GlobalState.penguDrugNodes or {}
        local now = {}
        for k, n in pairs(incoming) do now[tonumber(k)] = n end

        -- remove nodes that no longer exist (harvested, regrown elsewhere, field disabled)
        for id in pairs(nodes) do
            if not now[id] then despawnNode(id); nodes[id] = nil end
        end

        -- upsert
        for id, n in pairs(now) do
            nodes[id] = { id = id, type = n.type, x = n.x + 0.0, y = n.y + 0.0, z = n.z + 0.0 }
        end

        -- stream props/zones by distance
        local pc = GetEntityCoords(PlayerPedId())
        for id, n in pairs(nodes) do
            local d = #(pc - vector3(n.x, n.y, n.z))
            if d < STREAM_IN and not nodeProps[id] and not nodeZones[id] then
                spawnNodeProp(id, n)
            elseif d > STREAM_OUT and (nodeProps[id] or nodeZones[id]) then
                despawnNode(id)
            end
        end

        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearAll() end
end)
