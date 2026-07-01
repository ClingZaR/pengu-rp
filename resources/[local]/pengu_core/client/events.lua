-- PenguRP World Events (pengu_core) - CLIENT. Reads GlobalState.penguWorldEvent to show a
-- blip + a corner notification when an event starts/ends. ASCII only. luac clean.

local eventBlip = nil

local function clearBlip()
    if eventBlip and DoesBlipExist(eventBlip) then RemoveBlip(eventBlip) end
    eventBlip = nil
end

local function applyEvent(ev)
    clearBlip()
    if not ev then return end
    eventBlip = AddBlipForRadius(ev.x + 0.0, ev.y + 0.0, ev.z + 0.0, ev.radius or 60.0)
    SetBlipColour(eventBlip, ev.colour or 1)
    SetBlipAlpha(eventBlip, 100)

    local b2 = AddBlipForCoord(ev.x + 0.0, ev.y + 0.0, ev.z + 0.0)
    SetBlipSprite(b2, ev.sprite or 161)
    SetBlipColour(b2, ev.colour or 1)
    SetBlipScale(b2, 1.1)
    SetBlipRoute(b2, true)
    SetBlipRouteColour(b2, ev.colour or 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('[EVENT] %s'):format(ev.title or 'World Event'))
    EndTextCommandSetBlipName(b2)

    lib.notify({
        title       = ev.title or 'World Event',
        description = ('%s — %s'):format(ev.label or '', ev.desc or ''),
        type        = 'inform',
        duration    = 12000,
        position    = 'top',
    })
end

AddStateBagChangeHandler('penguWorldEvent', 'global', function(_, _, value)
    applyEvent(value)
end)

CreateThread(function()
    while not exports.qbx_core:GetPlayerData() do Wait(250) end
    applyEvent(GlobalState.penguWorldEvent)
end)

AddEventHandler('onClientResourceStart', function(rsc)
    if rsc ~= GetCurrentResourceName() then return end
    applyEvent(GlobalState.penguWorldEvent)
end)

AddEventHandler('onResourceStop', function(rsc)
    if rsc == GetCurrentResourceName() then clearBlip() end
end)
