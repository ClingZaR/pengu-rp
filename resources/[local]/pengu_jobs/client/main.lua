-- PenguRP Civilian Gathering Jobs (pengu_jobs) - CLIENT. ox_target on each job point (rebuilt live on
-- pointsUpdated). Gather points run a skill check + progress then the gather callback; sell points open
-- a per-item sell menu. All economy is server-authoritative. ASCII only. luac clean.

local zoneIds = {}
local blips = {}
local busy = false

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

-- ---------- zones ----------
local function rebuild(points)
    clearZones()
    vizPoints = {} -- rebuilt below; the streaming thread reconciles spawned entities against this
    if type(points) ~= 'table' then return end
    for _, point in ipairs(points) do
        local gdef = Config.gatherTypes[point.ptype]
        local sdef = Config.sellTypes[point.ptype]
        local shdef = Config.shopTypes and Config.shopTypes[point.ptype]
        local def = gdef or sdef or shdef
        if def then
            local ref = point

            -- visible ped/prop on the point (interaction still handled by the sphere zone below)
            local viz = Config.visuals and Config.visuals[point.ptype]
            if viz and viz.model and viz.model ~= '' then
                vizPoints[point.id] = { x = point.x + 0.0, y = point.y + 0.0, z = point.z + 0.0, model = viz.model, isPed = viz.ped == true }
            end
            local label = gdef and ('Work (' .. def.label .. ')')
                or sdef and ('Sell (' .. def.label .. ')')
                or ('Shop (' .. def.label .. ')')

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
                            else openShop(ref, shdef) end
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

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearZones(); clearAllViz() end
end)

TriggerEvent('chat:addSuggestion', '/jobloc', 'Manage job points (admin)', {
    { name = 'subcommand', help = 'add <type> [label] | remove <id> | list' },
})
