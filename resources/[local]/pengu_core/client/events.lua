-- PenguRP World Events (pengu_core) - CLIENT. Reads GlobalState.penguWorldEvent to show a
-- blip + a corner notification when an event starts/ends. ev.show gates visibility:
-- 'all' (everyone) | 'leo' (LEO jobs) | 'gang' (criminal gang members) | 'none'.
-- Also renders the event crate (GlobalState.penguEventCrate) for vip_transport / arms_deal
-- via the pengu_blackmarket 1s reconcile-loop pattern, and the delayed offset LEO tip blip
-- for arms_deal. ASCII only. luac clean.

local eventBlips = {}
local tipBlip = nil

local function isCriminalGang()
    local pd = exports.qbx_core:GetPlayerData()
    local g = pd and pd.gang
    return (g and g.name and g.name ~= 'none' and Factions.isCriminal(g.name)) or false
end

local function isLeo()
    local pd = exports.qbx_core:GetPlayerData()
    local job = pd and pd.job
    return (job and job.type == 'leo') or false
end

local function isOnDutyLeo()
    local pd = exports.qbx_core:GetPlayerData()
    local job = pd and pd.job
    return (job and job.type == 'leo' and job.onduty) or false
end

local function clearBlips()
    for _, b in ipairs(eventBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    eventBlips = {}
end

local function clearTip()
    if tipBlip and DoesBlipExist(tipBlip) then RemoveBlip(tipBlip) end
    tipBlip = nil
end

local function canSee(ev)
    local show = ev.show or 'all'
    if show == 'none' then return false end
    if show == 'leo'  then return isLeo() end
    if show == 'gang' then return isCriminalGang() end
    return true
end

local function applyEvent(ev)
    clearBlips()
    if not ev then clearTip() return end
    if not canSee(ev) then return end

    if (ev.radius or 0) > 0 then
        local rb = AddBlipForRadius(ev.x + 0.0, ev.y + 0.0, ev.z + 0.0, ev.radius + 0.0)
        SetBlipColour(rb, ev.colour or 1)
        SetBlipAlpha(rb, 100)
        eventBlips[#eventBlips + 1] = rb
    end

    local b2 = AddBlipForCoord(ev.x + 0.0, ev.y + 0.0, ev.z + 0.0)
    SetBlipSprite(b2, ev.sprite or 161)
    SetBlipColour(b2, ev.colour or 1)
    SetBlipScale(b2, 1.1)
    SetBlipRoute(b2, true)
    SetBlipRouteColour(b2, ev.colour or 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('[EVENT] %s'):format(ev.title or 'World Event'))
    EndTextCommandSetBlipName(b2)
    eventBlips[#eventBlips + 1] = b2

    lib.notify({
        title       = ev.title or 'World Event',
        description = ('%s - %s'):format(ev.label or '', ev.desc or ''),
        type        = 'inform',
        duration    = 12000,
        position    = 'top',
    })
end

AddStateBagChangeHandler('penguWorldEvent', 'global', function(_, _, value)
    applyEvent(value)
end)

-- ===================== LEO tip blip (arms_deal: delayed + offset, 150m circle) =====================
RegisterNetEvent('pengu_core:events:leoTip', function(data)
    if not data then return end
    clearTip()
    tipBlip = AddBlipForRadius(data.x + 0.0, data.y + 0.0, (data.z or 0.0) + 0.0, (data.radius or 150.0) + 0.0)
    SetBlipColour(tipBlip, 3)
    SetBlipAlpha(tipBlip, 90)
    lib.notify({
        title = 'Dispatch Tip-Off',
        description = 'An arms deal is going down somewhere in the marked area.',
        type = 'inform', duration = 12000, position = 'top',
    })
end)

-- ===================== event crate (vip_transport / arms_deal) =====================
local CRATE_MODELS = { 'prop_mil_crate_02', 'prop_box_ammo07a' }
local CRATE_DIST   = 3.0
local STREAM_IN    = 40.0
local STREAM_OUT   = 55.0

local crate = nil -- { key, kind, x, y, z, label }
local crateProp, crateZone = nil, nil
local crateBusy = false

local function loadCrateModel()
    for _, name in ipairs(CRATE_MODELS) do
        local hash = joaat(name)
        if hash and IsModelValid(hash) then
            RequestModel(hash)
            local t = GetGameTimer()
            while not HasModelLoaded(hash) and GetGameTimer() - t < 3000 do Wait(10) end
            if HasModelLoaded(hash) then return hash end
        end
    end
    return nil
end

local function waitCollisionAround(entity, x, y, z)
    RequestCollisionAtCoord(x + 0.0, y + 0.0, z + 0.0)
    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() - t < 3000 do
        RequestCollisionAtCoord(x + 0.0, y + 0.0, z + 0.0)
        Wait(50)
    end
end

local function doCrate(kind, key)
    if crateBusy then return end
    crateBusy = true
    if lib.callback.await('pengu_core:events:crateBegin', false, key) then
        if kind == 'convoy' then
            if lib.skillCheck({ 'medium', 'medium', 'hard' }) then
                local ok = lib.progressCircle({
                    label = 'Breaking into the convoy crate', duration = 60000, position = 'bottom',
                    useWhileDead = false, canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = 'amb@world_human_hammering@male@base', clip = 'base' },
                })
                if ok then lib.callback.await('pengu_core:events:crateFinish', false, key) end
            else
                lib.notify({ title = 'World Event', description = 'You fumbled it. Back off.', type = 'error' })
            end
        else
            local ok = lib.progressCircle({
                label = 'Cracking the crate open', duration = 15000, position = 'bottom',
                useWhileDead = false, canCancel = true,
                disable = { move = true, car = true, combat = true },
                anim = { dict = 'amb@world_human_hammering@male@base', clip = 'base' },
            })
            if ok then lib.callback.await('pengu_core:events:crateFinish', false, key) end
        end
    end
    crateBusy = false
end

local function crateOptions(kind, key)
    local label = (kind == 'convoy') and 'Loot the convoy crate' or 'Crack open the arms crate'
    return {
        {
            name = 'pengu_event_crate',
            icon = 'fa-solid fa-box-open',
            label = label,
            distance = CRATE_DIST,
            canInteract = function()
                if not crate or crate.key ~= key then return false end
                if kind == 'convoy' then return not isOnDutyLeo() end
                return isCriminalGang()
            end,
            onSelect = function() doCrate(kind, key) end,
        },
    }
end

local function despawnCrateProp()
    if crateProp then
        if DoesEntityExist(crateProp) then
            exports.ox_target:removeLocalEntity(crateProp)
            DeleteEntity(crateProp)
        end
        crateProp = nil
    end
    if crateZone then
        exports.ox_target:removeZone(crateZone)
        crateZone = nil
    end
end

local function spawnCrateProp(c)
    local key = c.key
    local model = loadCrateModel() -- yields; re-check the crate is still the same afterwards
    if not (crate and crate.key == key) then
        if model then SetModelAsNoLongerNeeded(model) end
        return
    end
    if model then
        local obj = CreateObject(model, c.x + 0.0, c.y + 0.0, c.z + 0.0, false, false, false)
        if obj and obj ~= 0 then
            SetEntityAsMissionEntity(obj, true, true)
            waitCollisionAround(obj, c.x, c.y, c.z)
            PlaceObjectOnGroundProperly(obj)
            FreezeEntityPosition(obj, true)
            if not (crate and crate.key == key) then
                DeleteEntity(obj); SetModelAsNoLongerNeeded(model); return
            end
            exports.ox_target:addLocalEntity(obj, crateOptions(c.kind, key))
            crateProp = obj
            SetModelAsNoLongerNeeded(model)
            return
        end
        SetModelAsNoLongerNeeded(model)
    end
    -- fallback (no valid model): sphere zone, ground-probed
    waitCollisionAround(PlayerPedId(), c.x, c.y, c.z)
    if not (crate and crate.key == key) then return end
    local z = c.z
    local found, gz = GetGroundZFor_3dCoord(c.x + 0.0, c.y + 0.0, c.z + 50.0, false)
    if found then z = gz end
    crateZone = exports.ox_target:addSphereZone({
        coords = vector3(c.x + 0.0, c.y + 0.0, z + 0.0),
        radius = CRATE_DIST + 1.0,
        debug = false,
        options = crateOptions(c.kind, key),
    })
end

-- reconcile the crate from GlobalState every second + stream the prop by distance
-- (pengu_blackmarket pattern; a single crate at a time, keyed so convoy moves respawn it)
CreateThread(function()
    while not exports.qbx_core:GetPlayerData() do Wait(250) end
    applyEvent(GlobalState.penguWorldEvent)
    while true do
        local incoming = GlobalState.penguEventCrate
        if incoming and incoming.key then
            if not crate or crate.key ~= incoming.key then
                despawnCrateProp()
                crate = {
                    key = incoming.key, kind = incoming.kind or 'convoy',
                    x = incoming.x + 0.0, y = incoming.y + 0.0, z = incoming.z + 0.0,
                    label = incoming.label,
                }
            end
        elseif crate then
            crate = nil
            despawnCrateProp()
        end

        if crate then
            local d = #(GetEntityCoords(PlayerPedId()) - vector3(crate.x, crate.y, crate.z))
            if d < STREAM_IN and not crateProp and not crateZone then
                spawnCrateProp(crate)
            elseif d > STREAM_OUT and (crateProp or crateZone) then
                despawnCrateProp()
            end
        end

        Wait(1000)
    end
end)

-- ===================== wiring =====================
AddEventHandler('onClientResourceStart', function(rsc)
    if rsc ~= GetCurrentResourceName() then return end
    applyEvent(GlobalState.penguWorldEvent)
end)

AddEventHandler('onResourceStop', function(rsc)
    if rsc ~= GetCurrentResourceName() then return end
    clearBlips()
    clearTip()
    crate = nil
    despawnCrateProp()
end)
