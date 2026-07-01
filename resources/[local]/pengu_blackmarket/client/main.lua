-- PenguRP Black Market (pengu_blackmarket) - CLIENT. The weapon CATALOG + buy now live in pengu_dealers
-- (a placeable, gang-controllable "weapons" Arms Dealer); THIS resource owns the CRATE DROP a weapon
-- order produces. Dropped crates render from GlobalState.penguCrates via a 1s reconcile loop (does NOT
-- rely on the statebag handler): a ground-snapped prop with the ox_target eye ON THE PROP, plus a
-- sphere-zone fallback if the model fails. You PICK UP the crate (carry it), can /dropcrate it anywhere,
-- then PRY it open with a crowbar to recover the weapon. ASCII only. luac clean.

local busy = false

-- crate tracking (DROPPED crates only; the one you carry is tracked in `carrying`)
local crates     = {} -- id -> { id, ownerCid, x, y, z, label }
local crateProps = {} -- id -> object handle (visual + ox_target host)
local crateZones = {} -- id -> ox_target zone id (fallback when no prop model)
local crateBlips = {} -- id -> blip (owner only)
local carrying   = nil -- { id, prop } while you are carrying a crate
local startCarry       -- forward-declared (defined after the dropped-crate helpers; used by doPickup)

local function isCriminal()
    local pd = exports.qbx_core:GetPlayerData()
    local g = pd and pd.gang
    return g and g.name and g.name ~= 'none' and Factions.isCriminal(g.name) and true or false
end

local function myCid()
    local pd = exports.qbx_core:GetPlayerData()
    return pd and pd.citizenid
end

local function hasCrowbar()
    return (exports.ox_inventory:Search('count', Config.crowbarItem) or 0) > 0
end

-- ===================== crate model =====================
local function loadCrateModel()
    for _, name in ipairs({ Config.crateModel, Config.crateModelFallback }) do
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

-- ===================== dropped-crate interaction =====================
local function doPickup(id)
    if busy or carrying then return end
    busy = true
    local ok = lib.progressCircle({
        label = 'Hoisting the crate', duration = 1800, position = 'bottom',
        useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'anim@heists@box_carry@', clip = 'idle' },
    })
    if ok and lib.callback.await('pengu_blackmarket:pickup', false, id) then
        startCarry(id) -- forward-declared below
    end
    busy = false
end

local function doOpen(id)
    if busy then return end
    if not hasCrowbar() then
        lib.notify({ title = 'Black Market', description = 'You need a crowbar to pry it open.', type = 'error' }); return
    end
    busy = true
    local ok = lib.progressCircle({
        label = 'Prying the crate open', duration = 4000, position = 'bottom',
        useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'amb@world_human_hammering@male@base', clip = 'base' },
    })
    if ok then lib.callback.await('pengu_blackmarket:retrieve', false, id) end
    busy = false
end

local function doIntercept(id)
    if busy then return end
    if not hasCrowbar() then
        lib.notify({ title = 'Black Market', description = 'You need a crowbar to crack a rival crate.', type = 'error' }); return
    end
    busy = true
    -- stake the claim server-side BEFORE doing the work, so the difficulty/timing is authoritative
    if not lib.callback.await('pengu_blackmarket:beginIntercept', false, id) then busy = false; return end
    lib.notify({ title = 'Black Market', description = 'Cracking a rival crate - do not get caught...', type = 'inform' })
    local passed = lib.skillCheck({ 'hard', 'hard', 'medium' })
    if not passed then
        lib.notify({ title = 'Black Market', description = 'You fumbled it. Back off.', type = 'error' })
        busy = false; return
    end
    local ok = lib.progressCircle({
        label = 'Intercepting rival shipment', duration = 6000, position = 'bottom',
        useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'amb@world_human_hammering@male@base', clip = 'base' },
    })
    if ok then lib.callback.await('pengu_blackmarket:stealCrate', false, id) end
    busy = false
end

local function crateOptions(id)
    return {
        {
            name = 'pengu_crate_pickup_' .. id,
            icon = 'fa-solid fa-box',
            label = 'Pick up crate',
            distance = (Config.crateDist or 2.5) + 1.0,
            canInteract = function() local c = crates[id]; return c and c.ownerCid == myCid() and not carrying end,
            onSelect = function() doPickup(id) end,
        },
        {
            name = 'pengu_crate_open_' .. id,
            icon = 'fa-solid fa-screwdriver-wrench',
            label = 'Pry open with crowbar',
            distance = (Config.crateDist or 2.5) + 1.0,
            canInteract = function() local c = crates[id]; return c and c.ownerCid == myCid() and hasCrowbar() end,
            onSelect = function() doOpen(id) end,
        },
        {
            name = 'pengu_crate_steal_' .. id,
            icon = 'fa-solid fa-mask',
            label = 'Intercept (crowbar)',
            distance = (Config.crateDist or 2.5) + 1.0,
            canInteract = function() local c = crates[id]; return c and c.ownerCid ~= myCid() and isCriminal() end,
            onSelect = function() doIntercept(id) end,
        },
    }
end

-- wait until static collision has streamed in AROUND THE GIVEN ENTITY (not around the player, which can
-- be tens of metres away from a distant drop and still report loaded). Without this the ground snap below
-- no-ops and the crate is left at the approximate config Z - underground or floating, i.e. invisible.
local function waitCollisionAround(entity, x, y, z)
    RequestCollisionAtCoord(x + 0.0, y + 0.0, z + 0.0)
    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() - t < 3000 do
        RequestCollisionAtCoord(x + 0.0, y + 0.0, z + 0.0)
        Wait(50)
    end
end

local function spawnCrateProp(id, c)
    local model = loadCrateModel() -- yields (model load)
    -- if the crate was collected/picked up during the load, do not commit an orphaned prop/zone
    -- (the reconcile loop only despawns ids still present in `crates`).
    if not crates[id] then
        if model then SetModelAsNoLongerNeeded(model) end
        return
    end
    if model then
        -- create at the approximate coords, stream collision around THE OBJECT, then snap it to the ground.
        -- this works no matter how wrong the config Z is, as long as the X/Y sits over solid ground.
        local obj = CreateObject(model, c.x + 0.0, c.y + 0.0, c.z + 0.0, false, false, false)
        if obj and obj ~= 0 then
            SetEntityAsMissionEntity(obj, true, true) -- prevent GC + pull collision in around it
            waitCollisionAround(obj, c.x, c.y, c.z)
            PlaceObjectOnGroundProperly(obj) -- collision is now loaded at the drop, so this actually snaps
            FreezeEntityPosition(obj, true)
            if not crates[id] then -- collected during the collision wait
                DeleteEntity(obj); SetModelAsNoLongerNeeded(model); return
            end
            exports.ox_target:addLocalEntity(obj, crateOptions(id))
            crateProps[id] = obj
            SetModelAsNoLongerNeeded(model)
            return
        end
    end
    -- fallback (no valid model): generous sphere zone, ground-probed from high above the config Z
    waitCollisionAround(PlayerPedId(), c.x, c.y, c.z)
    if not crates[id] then return end
    local z = c.z
    local found, gz = GetGroundZFor_3dCoord(c.x + 0.0, c.y + 0.0, c.z + 50.0, false)
    if found then z = gz end
    crateZones[id] = exports.ox_target:addSphereZone({
        coords = vector3(c.x + 0.0, c.y + 0.0, z + 0.0),
        radius = (Config.crateDist or 2.5) + 1.0,
        debug = false,
        options = crateOptions(id),
    })
end

local function despawnProp(id)
    if crateProps[id] then
        if DoesEntityExist(crateProps[id]) then
            exports.ox_target:removeLocalEntity(crateProps[id])
            DeleteEntity(crateProps[id])
        end
        crateProps[id] = nil
    end
    if crateZones[id] then
        exports.ox_target:removeZone(crateZones[id])
        crateZones[id] = nil
    end
end

local function removeBlip(id)
    if crateBlips[id] and DoesBlipExist(crateBlips[id]) then RemoveBlip(crateBlips[id]) end
    crateBlips[id] = nil
end

local function addBlip(id, c)
    local b = AddBlipForCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
    SetBlipSprite(b, Config.dropBlip.sprite or 478)
    SetBlipColour(b, Config.dropBlip.colour or 5)
    SetBlipScale(b, Config.dropBlip.scale or 0.9)
    SetBlipRoute(b, true)
    SetBlipRouteColour(b, Config.dropBlip.colour or 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Config.dropBlip.label or 'Weapon Drop')
    EndTextCommandSetBlipName(b)
    crateBlips[id] = b
end

local function despawnCrate(id)
    despawnProp(id)
    removeBlip(id)
    crates[id] = nil
end

local function clearAllCrates()
    for id in pairs(crateProps) do despawnProp(id) end
    for id in pairs(crateZones) do despawnProp(id) end
    for id in pairs(crateBlips) do removeBlip(id) end
    crates, crateProps, crateZones, crateBlips = {}, {}, {}, {}
end

-- single source of truth: reconcile world crates from GlobalState every second + stream by distance.
CreateThread(function()
    while not exports.qbx_core:GetPlayerData() do Wait(250) end
    while true do
        local mine = myCid()
        local incoming = GlobalState.penguCrates or {}
        local now = {}
        for k, c in pairs(incoming) do now[tonumber(k)] = c end

        -- remove crates that no longer exist (collected, expired, picked up, cleared)
        for id in pairs(crates) do
            if not now[id] then despawnCrate(id) end
        end

        -- upsert + owner-only blips
        for id, c in pairs(now) do
            crates[id] = { id = id, ownerCid = c.ownerCid, x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0, label = c.label }
            if c.ownerCid == mine and not crateBlips[id] then
                addBlip(id, crates[id])
            elseif c.ownerCid ~= mine and crateBlips[id] then
                removeBlip(id)
            end
        end

        -- stream props/zones by distance
        local pc = GetEntityCoords(PlayerPedId())
        for id, c in pairs(crates) do
            local d = #(pc - vector3(c.x, c.y, c.z))
            if d < (Config.streamIn or 60.0) and not crateProps[id] and not crateZones[id] then
                spawnCrateProp(id, c)
            elseif d > (Config.streamOut or 75.0) and (crateProps[id] or crateZones[id]) then
                despawnProp(id)
            end
        end

        Wait(1000)
    end
end)

RegisterNetEvent('pengu_blackmarket:shipmentOrdered', function(drop)
    if not drop then return end
    SetNewWaypoint(drop.x + 0.0, drop.y + 0.0)
    lib.notify({ title = 'Black Market', description = ('Shipment dropping at %s. GPS set.'):format(drop.label or 'the drop'), type = 'success' })
end)

-- ===================== carrying a crate =====================
local function stopCarry()
    if not carrying then return end
    if carrying.prop and DoesEntityExist(carrying.prop) then
        DetachEntity(carrying.prop, true, true)
        DeleteEntity(carrying.prop)
    end
    local ped = PlayerPedId()
    StopAnimTask(ped, Config.carry.animDict, Config.carry.animClip, 1.0)
    carrying = nil
end

-- defined here (forward-declared near the top); used by doPickup above
startCarry = function(id)
    if carrying then return end
    despawnCrate(id) -- remove the world prop/blip now instead of waiting for the next reconcile tick
    local model = loadCrateModel()
    local ped = PlayerPedId()
    local prop
    if model then
        local pc = GetEntityCoords(ped)
        prop = CreateObject(model, pc.x, pc.y, pc.z + 0.2, true, true, false)
        if prop and prop ~= 0 then
            SetEntityAsMissionEntity(prop, true, true) -- so DetachEntity+DeleteEntity always cleans up
            local cc = Config.carry
            AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, cc.bone),
                cc.px, cc.py, cc.pz, cc.rx, cc.ry, cc.rz, true, true, false, true, 1, true)
        end
        SetModelAsNoLongerNeeded(model)
    end
    carrying = { id = id, prop = prop }
    lib.notify({ title = 'Black Market', description = 'Crate hoisted. (( /dropcrate to set it down, then pry it open with a crowbar ))', type = 'inform' })

    CreateThread(function()
        RequestAnimDict(Config.carry.animDict)
        local t = GetGameTimer()
        while not HasAnimDictLoaded(Config.carry.animDict) and GetGameTimer() - t < 2000 do Wait(10) end
        while carrying do
            local p = PlayerPedId()
            if IsEntityDead(p) then
                -- dropped on death: hand the crate back to the server at the death spot
                local cid = carrying.id
                stopCarry()
                lib.callback.await('pengu_blackmarket:dropCarried', false, cid)
                break
            end
            if HasAnimDictLoaded(Config.carry.animDict)
                and not IsEntityPlayingAnim(p, Config.carry.animDict, Config.carry.animClip, 3) then
                TaskPlayAnim(p, Config.carry.animDict, Config.carry.animClip, 8.0, 8.0, -1, 49, 0.0, false, false, false)
            end
            DisableControlAction(0, 21, true) -- sprint
            DisableControlAction(0, 22, true) -- jump
            DisableControlAction(0, 23, true) -- enter vehicle
            Wait(0)
        end
    end)
end

-- /dropcrate - set the carried crate down at your feet
RegisterCommand('dropcrate', function()
    if not carrying then
        lib.notify({ title = 'Black Market', description = 'You are not carrying a crate.', type = 'error' }); return
    end
    local id = carrying.id
    if lib.callback.await('pengu_blackmarket:dropCarried', false, id) then
        stopCarry() -- the reconcile loop will respawn the world crate at the new spot
        lib.notify({ title = 'Black Market', description = 'Crate set down.', type = 'inform' })
    end
end, false)

TriggerEvent('chat:addSuggestion', '/dropcrate', 'Set down the weapon crate you are carrying', {})

-- server can force a carrier to drop the visual (e.g. admin /clearcrates)
RegisterNetEvent('pengu_blackmarket:cancelCarry', function() stopCarry() end)

-- ===================== wiring =====================
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then stopCarry(); clearAllCrates() end
end)
