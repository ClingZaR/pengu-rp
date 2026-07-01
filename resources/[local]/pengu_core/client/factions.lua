-- PenguRP - FACTION management NUI controller (/faction). Opens the themed glass-lavender drawer
-- (html/faction.js + faction.css) and relays its actions to the server. Same UI for LEGAL (jobs)
-- and CRIMINAL (gangs); the server's getData snapshot decides what the viewer sees + can do.
-- /f (faction chat) is a pure server command. ASCII only.

local open = false

local function openFaction()
    local data = lib.callback.await('pengu_faction:getData', false)
    if not data then
        lib.notify({ title = 'Faction', description = 'You are not in a faction.', type = 'error' })
        return
    end
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'factionOpen', data = data })
end

-- Re-fetch + push fresh data so the drawer reflects a just-applied change.
local function refresh()
    if not open then return end
    local data = lib.callback.await('pengu_faction:getData', false)
    if data then
        SendNUIMessage({ action = 'factionData', data = data })
    else
        open = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'factionClose' })
    end
end

RegisterCommand('faction', function() openFaction() end, false)

RegisterNUICallback('factionClose', function(_, cb)
    open = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('factionAction', function(d, cb)
    cb('ok')
    if type(d) ~= 'table' then return end
    local k = d.kind
    if k == 'promote' then
        TriggerServerEvent('pengu_faction:promote', tonumber(d.src))
    elseif k == 'demote' then
        TriggerServerEvent('pengu_faction:demote', tonumber(d.src))
    elseif k == 'fire' then
        TriggerServerEvent('pengu_faction:fire', tonumber(d.src))
    elseif k == 'invite' then
        local v = tostring(d.value or ''):gsub('^%s+', ''):gsub('%s+$', '')
        if v == '' then
            lib.notify({ title = 'Faction', description = 'Enter a name or server ID to invite.', type = 'error' })
            return
        end
        TriggerServerEvent('pengu_faction:invite', v)
    elseif k == 'rankLabel' then
        TriggerServerEvent('pengu_faction:setRankLabel', tonumber(d.grade), tostring(d.label or ''))
    elseif k == 'rankPerms' then
        TriggerServerEvent('pengu_faction:setRankPerms', tonumber(d.grade), d.perms or {})
    else
        return
    end
    -- let the server state settle, then refresh the open drawer
    SetTimeout(350, refresh)
end)

-- Release NUI focus if the resource stops/restarts while the faction drawer is open - otherwise the
-- player's keyboard + cursor stay frozen (SetNuiFocus survives the resource stop) until they rejoin.
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and open then SetNuiFocus(false, false) end
end)

-- Chat autocomplete (T). /f is free (scully's facial-expression command moved to /face + /exp).
TriggerEvent('chat:addSuggestion', '/f', 'Faction chat - message your faction only', {
    { name = 'message', help = 'what to say to your faction' },
})
TriggerEvent('chat:addSuggestion', '/faction', 'Open your faction management menu', {})
TriggerEvent('chat:addSuggestion', '/factionaccept', 'Accept a pending faction invite', {})
TriggerEvent('chat:addSuggestion', '/quitfaction', 'Leave your current faction', {})
