-- Client-side command registration.
-- Intercepts /me /do before GTA's native handler (which shows floating text).
-- /ooc, /o, /b are all routed to the OOC channel.

local function rpCmd(cmd, args)
    if #args == 0 then return end
    TriggerServerEvent('qbx_chat_theme:rpcmd', cmd, table.concat(args, ' '))
end

RegisterCommand('me',  function(_, args) rpCmd('me',  args) end, false)
RegisterCommand('do',  function(_, args) rpCmd('do',  args) end, false)
RegisterCommand('ooc', function(_, args) rpCmd('ooc', args) end, false)
RegisterCommand('o',   function(_, args) rpCmd('ooc', args) end, false)
RegisterCommand('b',   function(_, args) rpCmd('ooc', args) end, false)

local function addSuggestions()
    TriggerEvent('chat:addSuggestion', '/me',  'RP action - visible within 30m', {
        { name = 'action', help = 'What your character does' }
    })
    TriggerEvent('chat:addSuggestion', '/do',  'Scene description - visible within 30m', {
        { name = 'description', help = 'Environmental detail or fact' }
    })
    TriggerEvent('chat:addSuggestion', '/ooc', 'Out-of-character (server-wide)', {
        { name = 'message', help = 'OOC message' }
    })
    TriggerEvent('chat:addSuggestion', '/o',   'Out-of-character shorthand', {
        { name = 'message', help = 'OOC message' }
    })
    TriggerEvent('chat:addSuggestion', '/b',   'Out-of-character shorthand', {
        { name = 'message', help = 'OOC message' }
    })
    -- proximity speech (independent of the U voice range)
    TriggerEvent('chat:addSuggestion', '/low',     'Speak quietly (short range)', { { name = 'message', help = 'What you say quietly' } })
    TriggerEvent('chat:addSuggestion', '/shout',   'Shout (long range)',          { { name = 'message', help = 'What you shout' } })
    TriggerEvent('chat:addSuggestion', '/s',       'Shout (shorthand)',           { { name = 'message', help = 'What you shout' } })
    TriggerEvent('chat:addSuggestion', '/whisper', 'Whisper directly to a player right next to you', { { name = 'id', help = 'their server id' }, { name = 'message', help = 'what to whisper' } })
    TriggerEvent('chat:addSuggestion', '/cw',      'Talk to everyone in your vehicle', { { name = 'message', help = 'what to say in the car' } })
    TriggerEvent('chat:addSuggestion', '/carwhisper', 'Talk to everyone in your vehicle', { { name = 'message', help = 'what to say in the car' } })
end

AddEventHandler('onClientResourceStart', function(resName)
    if resName == GetCurrentResourceName() or resName == 'chat' then
        Wait(600)
        addSuggestions()
    end
end)

-- -- above-head 3D text for /me and /do ---------------------------------------

local HEAD_R, HEAD_G, HEAD_B = 225, 199, 249  -- #E1C7F9

local function drawText3D(x, y, z, text)
    SetDrawOrigin(x, y, z, 0)
    SetTextScale(0.0, 0.28)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextColour(HEAD_R, HEAD_G, HEAD_B, 220)
    SetTextOutline()
    SetTextCentre(1)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

-- Active above-head messages per actor, rendered STACKED by a single loop per actor so multiple
-- /me /do never draw on top of each other. Newest sits just above the head; older lines float up.
local headMsgs  = {} -- [actorId] = { { label, endTime }, ... } (oldest first, newest last)
local headLoops = {} -- [actorId] = true while that actor's render loop is alive

RegisterNetEvent('qbx_chat_theme:drawAboveHead')
AddEventHandler('qbx_chat_theme:drawAboveHead', function(actorId, cmd, uname, sid, text)
    local label = (cmd == 'do') and ('(( ' .. text .. ' ))') or ('* ' .. text)
    local duration = math.min(3000 + (#text * 50), 8000)

    local list = headMsgs[actorId]
    if not list then list = {}; headMsgs[actorId] = list end
    list[#list + 1] = { label = label, endTime = GetGameTimer() + duration }
    while #list > 4 do table.remove(list, 1) end -- cap the stack so it can't tower

    if headLoops[actorId] then return end -- a loop is already rendering this actor's stack
    headLoops[actorId] = true
    CreateThread(function()
        while true do
            local msgs = headMsgs[actorId]
            local now = GetGameTimer()
            if msgs then
                for i = #msgs, 1, -1 do
                    if now >= msgs[i].endTime then table.remove(msgs, i) end
                end
            end
            -- No Wait between this check and the clears below, so no event can interleave + leak.
            if not msgs or #msgs == 0 then
                headMsgs[actorId] = nil
                headLoops[actorId] = nil
                return
            end
            local player = GetPlayerFromServerId(actorId)
            if player and player ~= -1 then
                local ped = GetPlayerPed(player)
                if DoesEntityExist(ped) then
                    local pos = GetEntityCoords(ped, true)
                    for i = 1, #msgs do
                        drawText3D(pos.x, pos.y, pos.z + 1.05 + (#msgs - i) * 0.25, msgs[i].label)
                    end
                end
            end
            Wait(0)
        end
    end)
end)
