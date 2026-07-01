-- PenguRP Drug Supply Chain (pengu_drugs) - CLIENT lab interaction.
-- Builds an ox_target sphere per lab (rebuilt live on labsUpdated). Interacting opens an ox_lib
-- context menu of the lab type's recipes; choosing one runs an ox_lib skill-check, and ONLY on
-- success calls the server-authoritative process callback (which re-validates proximity + items).
-- ASCII only. luac clean.

local zoneIds = {} -- lab id -> ox_target zone id
local busy = false

-- world visuals: a relevant ped/prop placed AT each lab so the spot is visible (these labs have no map
-- blip by design, so the on-site entity is the only locator). Distance-streamed so collision is loaded
-- on spawn (correct ground placement) and far labs cost nothing. Populated from Config.visuals[type].
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
    for _, zid in pairs(zoneIds) do
        if zid then exports.ox_target:removeZone(zid) end
    end
    zoneIds = {}
end

-- one item-need line, e.g. "5x weed_og-kush"
local function needLine(map)
    local parts = {}
    for item, qty in pairs(map or {}) do parts[#parts + 1] = ('%dx %s'):format(qty, item) end
    return table.concat(parts, ', ')
end

local function runRecipe(lab, idx, recipe)
    if busy then return end
    busy = true

    -- ox_lib skill check (single difficulty string or an array of stages)
    local ok = lib.skillCheck(recipe.skill or 'medium', { 'w', 'a', 's', 'd' })
    if not ok then
        lib.notify({ title = 'Processing', description = 'You botched it.', type = 'error' })
        busy = false
        return
    end

    if lib.progressCircle then
        local okBar = lib.progressCircle({
            label = recipe.label or 'Processing',
            duration = recipe.time or 5000,
            position = 'bottom',
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = { dict = 'mini@repair', clip = 'fixing_a_player' },
        })
        if not okBar then busy = false; return end -- cancelled = no processing
    end

    local done = lib.callback.await('pengu_drugs:process', false, lab.id, idx)
    if not done then
        lib.notify({ title = 'Processing', description = 'Could not process here.', type = 'error' })
    end
    busy = false
end

local function openLab(lab)
    if not lab.active then
        lib.notify({ title = lab.label or 'Drug Lab', description = 'This lab is currently closed.', type = 'error' })
        return
    end
    local def = Config.labTypes[lab.type]
    if not def then return end
    local options = {}
    for idx, recipe in ipairs(def.recipes or {}) do
        local inLine = needLine(recipe.input)
        local desc = (inLine ~= '' and ('Needs ' .. inLine .. '  ->  ') or 'Gather  ->  ') .. needLine(recipe.output)
        options[#options + 1] = {
            title = recipe.label or ('Recipe ' .. idx),
            description = desc,
            icon = def.icon or 'fa-solid fa-flask',
            onSelect = function() runRecipe(lab, idx, recipe) end,
        }
    end
    if #options == 0 then
        lib.notify({ title = lab.label or 'Lab', description = 'No recipes configured.', type = 'inform' })
        return
    end
    lib.registerContext({ id = 'pengu_drugs_lab_' .. lab.id, title = lab.label or def.label or 'Drug Lab', options = options })
    lib.showContext('pengu_drugs_lab_' .. lab.id)
end

local function rebuild(labs)
    clearZones()
    vizPoints = {} -- rebuilt below; the streaming thread reconciles spawned entities against this
    if type(labs) ~= 'table' then return end
    for _, lab in ipairs(labs) do
        local def = Config.labTypes[lab.type]
        -- field types (coca_field/weed_field) have no anchor sphere/prop - they render as live PLANT
        -- NODES via client/fields.lua. Skip them here.
        if def and not def.field then
            local labRef = lab

            -- visible ped/prop on the lab (interaction still handled by the sphere zone below)
            local viz = Config.visuals and Config.visuals[lab.type]
            if viz and viz.model and viz.model ~= '' then
                vizPoints[lab.id] = { x = lab.x + 0.0, y = lab.y + 0.0, z = lab.z + 0.0, model = viz.model, isPed = viz.ped == true }
            end
            zoneIds[lab.id] = exports.ox_target:addSphereZone({
                coords = vector3(lab.x + 0.0, lab.y + 0.0, lab.z + 0.0),
                radius = Config.interactDist or 2.5,
                debug = false,
                options = {
                    {
                        name = 'pengu_drugs_lab_' .. lab.id,
                        icon = def.icon or 'fa-solid fa-flask',
                        label = lab.active and ('Use ' .. (def.label or 'Lab')) or ((def.label or 'Lab') .. ' [Closed]'),
                        onSelect = function() openLab(labRef) end,
                    },
                },
            })
        end
    end
end

RegisterNetEvent('pengu_drugs:labsUpdated', function(labs) rebuild(labs) end)

CreateThread(function()
    local labs = lib.callback.await('pengu_drugs:getLabs', false)
    rebuild(labs)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local labs = lib.callback.await('pengu_drugs:getLabs', false)
    rebuild(labs)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearZones(); clearAllViz() end
end)

TriggerEvent('chat:addSuggestion', '/labenable',  'Enable a lab group (admin)',   { { name = 'group_name', help = 'group key e.g. weed_backwoods' } })
TriggerEvent('chat:addSuggestion', '/labdisable', 'Disable a lab group (admin)',  { { name = 'group_name', help = 'group key' } })
TriggerEvent('chat:addSuggestion', '/labadd',     'Add a table to a lab (admin)', { { name = 'type', help = 'lab type' }, { name = 'group_name', help = 'group key' }, { name = 'label', help = 'optional label' } })
TriggerEvent('chat:addSuggestion', '/labremove',  'Remove a lab table (admin)',   { { name = 'id', help = 'table ID from /lablist' } })
TriggerEvent('chat:addSuggestion', '/lablist',    'List all lab groups (admin)',   {})
