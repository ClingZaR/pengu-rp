-- PenguRP Gun Progression (pengu_gunrunning) - CLIENT.
-- Uses ox_target sphere zones for spot and bench interactions.
-- All validation (gang grade, proximity, cooldowns) is server-side.
-- ASCII only. luac clean.

local spots     = {}  -- id -> row
local benches   = {}  -- id -> row
local benchCfgs = {}  -- tier -> config block (from shared/config.lua)

----------------------------------------------------------------------
-- Bench craft menu
----------------------------------------------------------------------

local function openBenchMenu(benchId, tierCfg)
    local options = {}
    for idx, recipe in ipairs(tierCfg.recipes) do
        local parts = {}
        for item, count in pairs(recipe.ingredients) do
            parts[#parts+1] = count .. 'x ' .. item:gsub('_', ' ')
        end
        table.sort(parts)
        local desc = table.concat(parts, ', ')
        local ridx  = idx
        options[#options+1] = {
            title       = recipe.label,
            description = desc,
            icon        = 'gun',
            onSelect    = function()
                local ok = lib.progressBar({
                    duration     = recipe.duration,
                    label        = 'Assembling ' .. recipe.label .. '...',
                    useWhileDead = false,
                    canCancel    = true,
                    disable      = { move = true, car = true, combat = true },
                    anim         = { dict = 'mini@repair', clip = 'fixing_a_ped' },
                })
                if ok then
                    TriggerServerEvent('pengu_gunrunning:craft', benchId, ridx)
                end
            end,
        }
    end
    lib.registerContext({ id = 'gunbench_menu_' .. benchId, title = tierCfg.label, options = options })
    lib.showContext('gunbench_menu_' .. benchId)
end

----------------------------------------------------------------------
-- Zone registration
----------------------------------------------------------------------

local registeredSpots   = {}  -- id -> true
local registeredBenches = {}  -- id -> true

local function registerSpotZone(id, s)
    if registeredSpots[id] then exports.ox_target:removeZone('gunspot_' .. id) end
    exports.ox_target:addSphereZone({
        name     = 'gunspot_' .. id,
        coords   = vector3(s.x, s.y, s.z),
        radius   = 2.5,
        options  = {
            {
                name     = 'gunspot_gather_' .. id,
                icon     = 'fa-solid fa-magnifying-glass',
                label    = s.label or 'Scavenge Parts',
                onSelect = function()
                    local ok = lib.progressBar({
                        duration     = Config.gatherDurationMs,
                        label        = 'Searching for parts...',
                        useWhileDead = false,
                        canCancel    = true,
                        disable      = { move = true, car = true, combat = true },
                        anim         = { dict = 'amb@world_human_janitor@male@idle_a', clip = 'idle_a' },
                    })
                    if ok then TriggerServerEvent('pengu_gunrunning:gather', id) end
                end,
                distance = 3.0,
            },
        },
    })
    registeredSpots[id] = true
end

local function registerBenchZone(id, b)
    local tierCfg = benchCfgs[b.tier]
    if not tierCfg then return end
    if registeredBenches[id] then exports.ox_target:removeZone('gunbench_' .. id) end
    local bid = id
    exports.ox_target:addSphereZone({
        name    = 'gunbench_' .. bid,
        coords  = vector3(b.x, b.y, b.z),
        radius  = 2.5,
        options = {
            {
                name     = 'gunbench_craft_' .. bid,
                icon     = 'fa-solid fa-screwdriver-wrench',
                label    = tierCfg.label or 'Craft Weapon',
                onSelect = function() openBenchMenu(bid, tierCfg) end,
                distance = 3.0,
            },
        },
    })
    registeredBenches[id] = true
end

local function applyZones()
    for id, s in pairs(spots)   do registerSpotZone(id, s)  end
    for id, b in pairs(benches) do registerBenchZone(id, b) end
end

----------------------------------------------------------------------
-- Sync
----------------------------------------------------------------------

RegisterNetEvent('pengu_gunrunning:sync', function(s, b, cfgs)
    spots     = s    or {}
    benches   = b    or {}
    benchCfgs = cfgs or {}
    applyZones()
end)

----------------------------------------------------------------------
-- Admin placement position reporting
----------------------------------------------------------------------

RegisterNetEvent('pengu_gunrunning:requestPos', function(kind, extra)
    local ped     = cache.ped or PlayerPedId()
    local coords  = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    if kind == 'spot' then
        TriggerServerEvent('pengu_gunrunning:placeSpot', coords.x, coords.y, coords.z, heading, extra)
    elseif kind == 'bench' then
        TriggerServerEvent('pengu_gunrunning:placeBench', coords.x, coords.y, coords.z, heading, tonumber(extra))
    end
end)

----------------------------------------------------------------------
-- Gang stash command
----------------------------------------------------------------------

RegisterCommand('gangstash', function()
    local p = exports.qbx_core:GetPlayerData()
    if not p then return end
    local gang = p.gang
    if not gang or gang.name == 'none' or gang.name == '' then
        lib.notify({ description = 'You are not in a gang.', type = 'error' })
        return
    end
    TriggerServerEvent('pengu_gunrunning:openStash', gang.name)
end, false)

TriggerEvent('chat:addSuggestion', '/gangstash',   'Open your gang shared weapon stash.', {})
TriggerEvent('chat:addSuggestion', '/gunpartloc',  'Admin: manage gun part scavenge spots.', { { name='add|remove|list [label]', help='action' } })
TriggerEvent('chat:addSuggestion', '/gunbenchloc', 'Admin: manage gang weapon benches.',    { { name='add|remove|list', help='action' }, { name='tier', help='1/2/3' } })
