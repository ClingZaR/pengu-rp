-- /me  /do  /ooc  /o  /b  RP commands with proximity and character names.
-- All RP templates receive args: {0}=timestamp  {1}=name  {2}=serverId  {3}=text
-- /me and /do use Firstname_Lastname (underscore) per RP convention.

local PROXIMITY_RADIUS = 30.0

local function getCharName(source)
    local ok, player = pcall(function()
        return exports.qbx_core:GetPlayer(source)
    end)
    if ok and player and player.PlayerData and player.PlayerData.charinfo then
        local ci = player.PlayerData.charinfo
        local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$')
        if name ~= '' then return name end
    end
    return GetPlayerName(source) or 'Unknown'
end

local function underName(name)
    return (name:gsub('%s+', '_'))
end

local function playerCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function nearbyPlayers(source, radius)
    local origin = playerCoords(source)
    local out = {}
    for _, pid in ipairs(GetPlayers()) do
        local id = tonumber(pid)
        if id then
            if not origin then
                table.insert(out, id)
            else
                local c = playerCoords(id)
                if c and #(origin - c) <= radius then
                    table.insert(out, id)
                end
            end
        end
    end
    return out
end

RegisterNetEvent('qbx_chat_theme:rpcmd')
AddEventHandler('qbx_chat_theme:rpcmd', function(cmd, text)
    local source = source
    if not source or source == 0 then return end
    if not text or text == '' then return end

    local name = getCharName(source)
    local sid  = tostring(source)
    local ts   = os.date('%H:%M:%S')

    if cmd == 'me' then
        -- [14:06:35] * Samuel_White (5) action
        local uname = underName(name)
        local msg = { templateId = 'rp:me', args = { ts, uname, sid, text }, multiline = true }
        for _, pid in ipairs(nearbyPlayers(source, PROXIMITY_RADIUS)) do
            TriggerClientEvent('chat:addMessage', pid, msg)
            TriggerClientEvent('qbx_chat_theme:drawAboveHead', pid, source, 'me', uname, sid, text)
        end
        print('[/me] ' .. name .. ' (' .. sid .. ') ' .. text)

    elseif cmd == 'do' then
        -- [14:06:35] * description (( Samuel_White (5) ))
        local uname = underName(name)
        local msg = { templateId = 'rp:do', args = { ts, uname, sid, text }, multiline = true }
        for _, pid in ipairs(nearbyPlayers(source, PROXIMITY_RADIUS)) do
            TriggerClientEvent('chat:addMessage', pid, msg)
            TriggerClientEvent('qbx_chat_theme:drawAboveHead', pid, source, 'do', uname, sid, text)
        end
        print('[/do] ' .. name .. ' (' .. sid .. '): ' .. text)

    elseif cmd == 'ooc' then
        -- [14:06:35] (( Samuel White (106): text ))  - server-wide
        TriggerClientEvent('chat:addMessage', -1, {
            templateId = 'rp:ooc',
            args       = { ts, name, sid, text },
            multiline  = true,
        })
        print('[/ooc] ' .. name .. ' (' .. sid .. '): ' .. text)
    end
end)

-- -- exports for other resources -----------------------------------------------
-- exports.qbx_chat_theme:sendLaw(source, "All units 10-4")
exports('sendLaw', function(source, text)
    local name = (source and source ~= 0) and getCharName(source) or 'DISPATCH'
    local sid  = (source and source ~= 0) and tostring(source) or '0'
    local ts   = os.date('%H:%M:%S')
    TriggerClientEvent('chat:addMessage', -1, {
        templateId = 'rp:law',
        args       = { ts, name, sid, text },
        multiline  = true,
    })
end)

-- exports.qbx_chat_theme:sendDispatch("Robbery at Maze Bank")
exports('sendDispatch', function(text)
    local ts = os.date('%H:%M:%S')
    TriggerClientEvent('chat:addMessage', -1, {
        templateId = 'rp:dispatch',
        args       = { ts, '', '', text },
        multiline  = true,
    })
end)

-- exports.qbx_chat_theme:sendSuccess(source, "[SUCCESS] Received ~g~$500~w~")
-- pass source=-1 to broadcast server-wide
exports('sendSuccess', function(source, text)
    local ts = os.date('%H:%M:%S')
    local targets = (source and source ~= 0) and { source } or GetPlayers()
    for _, pid in ipairs(targets) do
        TriggerClientEvent('chat:addMessage', tonumber(pid), {
            templateId = 'rp:success',
            args       = { ts, '', '', text },
            multiline  = true,
        })
    end
end)

-- exports.qbx_chat_theme:sendFaction(source, "Police | Officer III", "Samuel White", "All units code 2")
-- pass source=-1 to broadcast to all
exports('sendFaction', function(source, factionLabel, name, text)
    local ts = os.date('%H:%M:%S')
    TriggerClientEvent('chat:addMessage', source or -1, {
        templateId = 'rp:faction',
        args       = { ts, factionLabel, name, text },
        multiline  = true,
    })
end)

-- Faction OOC line for /f: the template wraps {text} in coloured (( )) brackets, so pass the RAW
-- message (no brackets). The colon + brackets are tinted with the faction colour.
-- exports.qbx_chat_theme:sendFactionOOC(source, "LSPD | Chief", "David Loan", "text")
exports('sendFactionOOC', function(source, factionLabel, name, text)
    local ts = os.date('%H:%M:%S')
    TriggerClientEvent('chat:addMessage', source or -1, {
        templateId = 'rp:faction:ooc',
        args       = { ts, factionLabel, name, text },
        multiline  = true,
    })
end)
