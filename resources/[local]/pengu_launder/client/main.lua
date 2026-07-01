-- PenguRP Money Laundering (pengu_launder) - CLIENT. Each laundromat has ox_target with THREE
-- contextual actions gated by the live GlobalState.penguLaunderActive wash state:
--   Launder money       - when the machine is free: pick an amount, your dirty money goes in, it runs.
--   Collect laundered $  - when YOUR wash is in this machine: pull the clean CASH (server checks it is done).
--   Rob the wash         - when SOMEONE ELSE's wash is running: skillcheck to skim their clean cash.
-- ASCII only. luac clean.

local zoneIds = {}
local busy = false

-- world visuals: a relevant ped/prop placed AT each point so the spot is visible. Distance-streamed so
-- collision is loaded when it spawns (correct ground placement) and far-away points cost nothing.
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

-- rebuild the desired-visuals map from the live point list (a washing-machine prop per laundromat)
local function rebuildViz(points)
    local vp = {}
    local v = Config.visual or {}
    local model = v.model
    if model and model ~= '' and type(points) == 'table' then
        for _, p in ipairs(points) do
            vp[p.id] = { x = p.x + 0.0, y = p.y + 0.0, z = p.z + 0.0, model = model, isPed = v.ped == true }
        end
    end
    vizPoints = vp
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
end

-- live wash state for a point (or nil if the machine is free)
local function stateOf(pointId)
    local active = GlobalState.penguLaunderActive
    return active and active[tostring(pointId)] or nil
end

local function myCid()
    local d = exports.qbx_core:GetPlayerData()
    return d and d.citizenid
end

-- ===================== actions =====================
local function washStart(point)
    if busy then return end
    busy = true
    local input = lib.inputDialog('Launder Money', {
        {
            type = 'number',
            label = 'Dirty money to wash',
            description = ('Min $%d, max $%d. %.0f%% fee. The MORE you wash, the LONGER it takes - leave it and come back to collect CLEAN CASH (others can rob it while it runs).')
                :format(Config.minWash, Config.maxWash, Config.fee * 100),
            min = Config.minWash,
            max = Config.maxWash,
            required = true,
            icon = 'soap',
        },
    })
    if not input or not input[1] then busy = false; return end
    local amount = math.floor(tonumber(input[1]) or 0)
    if amount < Config.minWash then busy = false; return end

    local ok = lib.progressCircle({
        label = 'Loading the machine',
        duration = Config.startTime or 3000,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mp_arresting', clip = 'a_uncuff' },
    })
    if not ok then busy = false; return end

    local started = lib.callback.await('pengu_launder:start', false, point.id, amount)
    if not started then
        lib.notify({ title = 'Laundromat', description = 'Could not start a wash here.', type = 'error' })
    end
    busy = false
end

local function washCollect(point)
    if busy then return end
    busy = true
    -- server pays out on success and notifies "still washing" / "not yours" otherwise
    lib.callback.await('pengu_launder:collect', false, point.id)
    busy = false
end

local function washRob(point)
    if busy then return end
    busy = true
    local st = stateOf(point.id)
    if not st then busy = false; return end
    local payout = math.floor((st.amount or 0) * (1 - Config.fee) * (Config.robCutPct or 0.5))
    lib.notify({ title = 'Laundromat', description = ('Crack the machine to skim ~$%d...'):format(payout), type = 'inform' })
    local ok = lib.skillCheck(Config.robSkill or { 'medium', 'hard' })
    if not ok then
        lib.notify({ title = 'Laundromat', description = 'You botched it and walked off.', type = 'error' })
        busy = false; return
    end
    lib.callback.await('pengu_launder:rob', false, point.id)
    busy = false
end

-- ===================== targets =====================
local function rebuild(points)
    clearZones()
    rebuildViz(points)
    if type(points) ~= 'table' then return end
    for _, point in ipairs(points) do
        local ref = point
        local id = point.id
        zoneIds[id] = exports.ox_target:addSphereZone({
            coords = vector3(point.x + 0.0, point.y + 0.0, point.z + 0.0),
            radius = Config.interactDist or 2.5,
            debug = false,
            options = {
                {
                    name = 'pengu_launder_wash_' .. id,
                    icon = 'fa-solid fa-soap',
                    label = 'Launder money',
                    canInteract = function() return stateOf(id) == nil end,
                    onSelect = function() washStart(ref) end,
                },
                {
                    name = 'pengu_launder_collect_' .. id,
                    icon = 'fa-solid fa-sack-dollar',
                    label = 'Collect laundered cash',
                    canInteract = function() local s = stateOf(id); return s ~= nil and s.ownerCid == myCid() end,
                    onSelect = function() washCollect(ref) end,
                },
                {
                    name = 'pengu_launder_rob_' .. id,
                    icon = 'fa-solid fa-user-ninja',
                    label = 'Rob the wash',
                    canInteract = function() local s = stateOf(id); return s ~= nil and s.ownerCid ~= myCid() end,
                    onSelect = function() washRob(ref) end,
                },
            },
        })
    end
end

RegisterNetEvent('pengu_launder:pointsUpdated', function(points) rebuild(points) end)

CreateThread(function()
    local points = lib.callback.await('pengu_launder:getPoints', false)
    rebuild(points)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local points = lib.callback.await('pengu_launder:getPoints', false)
    rebuild(points)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearZones(); clearAllViz() end
end)

TriggerEvent('chat:addSuggestion', '/washloc', 'Manage laundromats (admin)', {
    { name = 'subcommand', help = 'add [label] | remove <id> | list' },
})
