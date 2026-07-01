-- PenguRP Civilian Gathering Jobs (pengu_jobs) - CLIENT. ox_target on each job point (rebuilt live on
-- pointsUpdated). Gather points run a skill check + progress then the gather callback; sell points open
-- a per-item sell menu. All economy is server-authoritative. ASCII only. luac clean.

local zoneIds = {}
local blips = {}
local busy = false

-- perk tables for pengu_xp's /myxp display (keeps Config.perks as the single source of truth)
exports('GetPerks', function() return Config.perks end)

-- world visuals: a relevant ped/prop placed AT each point so the spot is visible up close (a blip alone
-- only helps on the map). Distance-streamed so collision is loaded when it spawns (correct ground
-- placement) and far points cost nothing. Populated by rebuild() from Config.visuals[ptype].
local vizPoints = {} -- id -> { x, y, z, model, isPed }
local vizEnts   = {} -- id -> entity handle

local function deleteViz(id)
    local e = vizEnts[id]
    if e and DoesEntityExist(e) then DeleteEntity(e) end
    vizEnts[id] = nil
end

local function clearAllViz()
    for id in pairs(vizEnts) do deleteViz(id) end
    vizEnts = {}
end

CreateThread(function()
    while true do
        local pc = GetEntityCoords(PlayerPedId())
        for id, v in pairs(vizPoints) do
            local d = #(pc - vector3(v.x, v.y, v.z))
            if d < 60.0 and not vizEnts[id] then
                local hash = joaat(v.model)
                if IsModelValid(hash) then
                    RequestModel(hash)
                    local t = GetGameTimer()
                    while not HasModelLoaded(hash) and GetGameTimer() - t < 3000 do Wait(10) end
                    if HasModelLoaded(hash) and vizPoints[id] then
                        local ent
                        if v.isPed then
                            ent = CreatePed(4, hash, v.x, v.y, v.z - 1.0, 0.0, false, false)
                            SetBlockingOfNonTemporaryEvents(ent, true)
                            SetEntityInvincible(ent, true)
                            FreezeEntityPosition(ent, true)
                        else
                            ent = CreateObject(hash, v.x, v.y, v.z - 1.0, false, false, false)
                            PlaceObjectOnGroundProperly(ent)
                            FreezeEntityPosition(ent, true)
                        end
                        vizEnts[id] = ent
                    end
                    SetModelAsNoLongerNeeded(hash)
                end
            elseif d > 80.0 and vizEnts[id] then
                deleteViz(id)
            end
        end
        for id in pairs(vizEnts) do
            if not vizPoints[id] then deleteViz(id) end
        end
        Wait(1500)
    end
end)

local function clearZones()
    for _, zid in pairs(zoneIds) do if zid then exports.ox_target:removeZone(zid) end end
    zoneIds = {}
    for _, b in pairs(blips) do if b and DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end

-- ---------- gather ----------
local function runGather(point, idx, recipe)
    if busy then return end
    busy = true
    local ok = lib.skillCheck(recipe.skill or 'easy', { 'w', 'a', 's', 'd' })
    if not ok then
        lib.notify({ title = 'Work', description = 'You fumbled it.', type = 'error' }); busy = false; return
    end
    local animDict = (recipe.anim and recipe.anim.dict) or 'melee@large_wpn@streamed_core'
    local animClip = (recipe.anim and recipe.anim.clip) or 'ground_attack_on_spot'
    local prog = lib.progressCircle({
        label = recipe.label or 'Working',
        duration = recipe.time or 6000,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = animDict, clip = animClip },
    })
    if not prog then busy = false; return end
    local done = lib.callback.await('pengu_jobs:gather', false, point.id, idx)
    if not done then lib.notify({ title = 'Work', description = 'Could not work here.', type = 'error' }) end
    busy = false
end

local function openGather(point, def)
    local recipes = def.recipes or {}
    if #recipes == 1 then runGather(point, 1, recipes[1]); return end
    local options = {}
    for i, r in ipairs(recipes) do
        options[#options + 1] = {
            title = r.label or ('Task ' .. i),
            icon = def.icon or 'fa-solid fa-gem',
            onSelect = function() runGather(point, i, r) end,
        }
    end
    if #options == 0 then return end
    lib.registerContext({ id = 'pengu_jobs_gather_' .. point.id, title = point.label or def.label or 'Work', options = options })
    lib.showContext('pengu_jobs_gather_' .. point.id)
end

-- ---------- sell ----------
local function openSell(point, def)
    local options = {}
    for item, price in pairs(def.prices or {}) do
        options[#options + 1] = {
            title = ('Sell %s'):format(item),
            description = ('$%d each (sells your whole stack)'):format(price),
            icon = def.icon or 'fa-solid fa-coins',
            onSelect = function()
                local ok = lib.callback.await('pengu_jobs:sell', false, point.id, item)
                if not ok then lib.notify({ title = 'Dealer', description = 'Nothing to sell.', type = 'inform' }) end
            end,
        }
    end
    if #options == 0 then return end
    lib.registerContext({ id = 'pengu_jobs_sell_' .. point.id, title = point.label or def.label or 'Dealer', options = options })
    lib.showContext('pengu_jobs_sell_' .. point.id)
end

-- ---------- shop (buy items, e.g. tools) ----------
local function openShop(point, def)
    local options = {}
    for item, price in pairs(def.items or {}) do
        options[#options + 1] = {
            title = ('Buy %s'):format(item),
            description = ('$%d'):format(price),
            icon = def.icon or 'fa-solid fa-screwdriver-wrench',
            onSelect = function()
                local ok = lib.callback.await('pengu_jobs:shopBuy', false, point.id, item)
                if not ok then lib.notify({ title = 'Shop', description = 'Could not buy that.', type = 'error' }) end
            end,
        }
    end
    if #options == 0 then return end
    lib.registerContext({ id = 'pengu_jobs_shop_' .. point.id, title = point.label or def.label or 'Shop', options = options })
    lib.showContext('pengu_jobs_shop_' .. point.id)
end

-- ---------- delivery (depot -> courier route) ----------
-- server owns the route (stop list, pay, expiry); the client only draws GPS/marker for the
-- CURRENT stop and runs the hand-over progress. One ox_target zone tracks the current stop.
local route = nil -- { stops = { {x,y,z,label} }, idx }
local stopZone = nil
local markerActive = false
local buildStopZone -- forward-declared (runDeliver advances the zone)

local function clearStopZone()
    if stopZone then exports.ox_target:removeZone(stopZone); stopZone = nil end
end

local function clearRoute()
    route = nil
    clearStopZone()
end

local function pointStop()
    local s = route and route.stops[route.idx]
    if s then SetNewWaypoint(s.x + 0.0, s.y + 0.0) end
    return s
end

local function runDeliver()
    if busy or not route then return end
    busy = true
    local prog = lib.progressCircle({
        label = 'Handing over the package',
        duration = (Config.delivery and Config.delivery.deliverTime) or 5000,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'anim@heists@box_carry@', clip = 'idle' },
    })
    if prog then
        local res = lib.callback.await('pengu_jobs:deliverStop', false)
        if res and res.ok and route then
            if res.finished then
                clearRoute()
                lib.notify({ title = 'Delivery', description = 'Route complete.', type = 'success' })
            else
                route.idx = res.nextIdx or (route.idx + 1)
                buildStopZone()
                local s = pointStop()
                if s then lib.notify({ title = 'Delivery', description = ('Next stop: %s'):format(s.label or 'stop'), type = 'inform' }) end
            end
        elseif route then
            lib.notify({ title = 'Delivery', description = 'Could not deliver here.', type = 'error' })
        end
    end
    busy = false
end

buildStopZone = function()
    clearStopZone()
    local s = route and route.stops[route.idx]
    if not s then return end
    local ddef = Config.deliveryTypes and Config.deliveryTypes.depot
    stopZone = exports.ox_target:addSphereZone({
        coords = vector3(s.x + 0.0, s.y + 0.0, s.z + 0.0),
        radius = (Config.delivery and Config.delivery.deliverDist) or 5.0,
        debug = false,
        options = {
            {
                name = 'pengu_jobs_deliver',
                icon = (ddef and ddef.icon) or 'fa-solid fa-box',
                label = 'Deliver Package',
                onSelect = runDeliver,
            },
        },
    })
end

local function startMarkerThread()
    if markerActive then return end
    markerActive = true
    CreateThread(function()
        local ddef = Config.deliveryTypes and Config.deliveryTypes.depot
        local m = (ddef and ddef.marker) or { r = 230, g = 190, b = 90 }
        while route do
            local s = route.stops[route.idx]
            if s then
                local d = #(GetEntityCoords(PlayerPedId()) - vector3(s.x, s.y, s.z))
                if d < 60.0 then
                    DrawMarker(1, s.x, s.y, s.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        2.5, 2.5, 1.2, m.r, m.g, m.b, 110, false, false, 2, false, nil, nil, false)
                    Wait(0)
                else
                    Wait(500)
                end
            else
                Wait(500)
            end
        end
        markerActive = false
    end)
end

local function startRoute(point)
    if busy or route then return end
    busy = true
    local prog = lib.progressCircle({
        label = 'Loading packages',
        duration = (Config.delivery and Config.delivery.loadTime) or 3000,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'anim@heists@box_carry@', clip = 'idle' },
    })
    if prog then
        local res = lib.callback.await('pengu_jobs:startDelivery', false, point.id)
        if res and type(res) == 'table' and res.stops and #res.stops > 0 then
            route = { stops = res.stops, idx = 1 }
            buildStopZone()
            startMarkerThread()
            local s = pointStop()
            lib.notify({ title = 'Delivery', description = ('%d stops. First: %s'):format(#res.stops, (s and s.label) or 'stop'), type = 'success' })
        else
            lib.notify({ title = 'Delivery', description = 'Could not start a route.', type = 'error' })
        end
    end
    busy = false
end

local function openDepot(point, def)
    local dcfg = Config.delivery or {}
    local options = {}
    if route then
        options[#options + 1] = {
            title = 'Abandon Delivery Route',
            description = 'Remaining packages are taken back.',
            icon = 'fa-solid fa-ban',
            onSelect = function() lib.callback.await('pengu_jobs:abandonDelivery', false) end,
        }
    else
        options[#options + 1] = {
            title = 'Start Delivery Route',
            description = ('%d-%d stops. $%d base + distance pay per delivery.'):format(dcfg.minStops or 3, dcfg.maxStops or 5, dcfg.basePay or 120),
            icon = def.icon or 'fa-solid fa-truck-fast',
            onSelect = function() startRoute(point) end,
        }
    end
    lib.registerContext({ id = 'pengu_jobs_depot_' .. point.id, title = point.label or def.label or 'Depot', options = options })
    lib.showContext('pengu_jobs_depot_' .. point.id)
end

RegisterNetEvent('pengu_jobs:routeClosed', function(reason)
    if not route then return end
    clearRoute()
    local msg = 'Delivery route ended.'
    if reason == 'expired' then msg = 'Your delivery route expired - remaining packages were taken back.'
    elseif reason == 'abandoned' then msg = 'Delivery route abandoned - remaining packages were taken back.' end
    lib.notify({ title = 'Delivery', description = msg, type = 'inform' })
end)

-- ---------- zones ----------
local function rebuild(points)
    clearZones()
    vizPoints = {} -- rebuilt below; the streaming thread reconciles spawned entities against this
    if type(points) ~= 'table' then return end
    for _, point in ipairs(points) do
        local gdef = Config.gatherTypes[point.ptype]
        local sdef = Config.sellTypes[point.ptype]
        local shdef = Config.shopTypes and Config.shopTypes[point.ptype]
        local ddef = Config.deliveryTypes and Config.deliveryTypes[point.ptype]
        local def = gdef or sdef or shdef or ddef
        if def then
            local ref = point

            -- visible ped/prop on the point (interaction still handled by the sphere zone below)
            local viz = Config.visuals and Config.visuals[point.ptype]
            if viz and viz.model and viz.model ~= '' then
                vizPoints[point.id] = { x = point.x + 0.0, y = point.y + 0.0, z = point.z + 0.0, model = viz.model, isPed = viz.ped == true }
            end
            local label = gdef and ('Work (' .. def.label .. ')')
                or sdef and ('Sell (' .. def.label .. ')')
                or shdef and ('Shop (' .. def.label .. ')')
                or ('Deliveries (' .. def.label .. ')')

            -- discoverable map blip
            local bc = (Config.blips and Config.blips[point.ptype]) or Config.blipDefault or { sprite = 1, colour = 0 }
            local blip = AddBlipForCoord(point.x + 0.0, point.y + 0.0, point.z + 0.0)
            SetBlipSprite(blip, bc.sprite or 1)
            SetBlipColour(blip, bc.colour or 0)
            SetBlipScale(blip, Config.blipScale or 0.85)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(point.label or bc.name or def.label or 'Job')
            EndTextCommandSetBlipName(blip)
            blips[point.id] = blip

            zoneIds[point.id] = exports.ox_target:addSphereZone({
                coords = vector3(point.x + 0.0, point.y + 0.0, point.z + 0.0),
                radius = Config.interactDist or 2.5,
                debug = false,
                options = {
                    {
                        name = 'pengu_jobs_' .. point.id,
                        icon = def.icon or 'fa-solid fa-briefcase',
                        label = label,
                        onSelect = function()
                            if gdef then openGather(ref, gdef)
                            elseif sdef then openSell(ref, sdef)
                            elseif shdef then openShop(ref, shdef)
                            else openDepot(ref, ddef) end
                        end,
                    },
                },
            })
        end
    end
end

RegisterNetEvent('pengu_jobs:pointsUpdated', function(points) rebuild(points) end)

CreateThread(function()
    local points = lib.callback.await('pengu_jobs:getPoints', false)
    rebuild(points)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local points = lib.callback.await('pengu_jobs:getPoints', false)
    rebuild(points)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() clearRoute() end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearZones(); clearAllViz(); clearRoute() end
end)

TriggerEvent('chat:addSuggestion', '/jobloc', 'Manage job points (admin)', {
    { name = 'subcommand', help = 'add <type> [label] | remove <id> | list' },
})
