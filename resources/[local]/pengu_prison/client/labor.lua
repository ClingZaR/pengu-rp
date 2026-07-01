-- PenguRP - Prison Labor (client). ox_target work stations for jailed players.
-- Each station is a box zone; interacting plays a scenario + progress bar, and
-- only on completion fires pengu_prison:labor so the server reduces jail time.
-- Uses PP.* from client/main.lua (same resource, loaded first). ASCII only.

local zoneIds = {}

-- Run one labor action at a station. Guarded by jail state on both entry and
-- (server-side) on the event; the server is the source of truth for reduction.
local function doLabor(station)
    if not PP.isJailed() then return end
    if not cache.ped or cache.ped == 0 then return end -- guard: ped may be invalid mid-respawn

    TaskStartScenarioInPlace(cache.ped, station.scenario, 0, true)

    local ok = lib.progressBar({
        duration    = station.duration,
        label       = station.label .. '...',
        useWhileDead = false,
        canCancel   = true,
        disable     = { move = true, car = true, combat = true },
    })

    ClearPedTasksImmediately(cache.ped)

    if ok then
        TriggerServerEvent('pengu_prison:labor', station.key)
    end
end

-- Register a box zone per station once at load.
for _, station in ipairs(Config.labor.stations) do
    local id = exports.ox_target:addBoxZone({
        coords   = station.coords,
        size     = Config.labor.targetSize,
        rotation = 0,
        debug    = false,
        options  = {
            {
                name        = 'pengu_labor_' .. station.key,
                icon        = 'fas fa-hammer',
                label       = station.label,
                distance    = 1.6,
                canInteract = function()
                    return PP.isJailed()
                end,
                onSelect    = function()
                    doLabor(station)
                end,
            },
        },
    })
    zoneIds[#zoneIds + 1] = id
end

-- Clean up zones when this resource stops.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, id in ipairs(zoneIds) do
        exports.ox_target:removeZone(id)
    end
end)
