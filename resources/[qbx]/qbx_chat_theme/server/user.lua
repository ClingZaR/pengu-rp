-- PenguRP - PROXIMITY text chat (independent of the U voice-range control).
--   normal (just type)   -> "says"          ~22m
--   /low <text>          -> "says quietly"   ~8m
--   /shout, /s <text>    -> "shouts"         ~45m
--   /whisper [id] <text> -> "whispers"       direct to one player right next to you (~3m)
--   /carwhisper, /cw     -> "says in the car" everyone in your vehicle
-- All routed through the rp:say template: "[ts] Name (id) <verb>: text". ASCII only.

local RANGE = { low = 8.0, normal = 22.0, shout = 45.0 }

local function getCharName(source)
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(source) end)
    if ok and player and player.PlayerData and player.PlayerData.charinfo then
        local ci = player.PlayerData.charinfo
        local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$')
        if name ~= '' then return name end
    end
    return GetPlayerName(source) or 'Unknown'
end

local function coordsOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function sayTo(pid, ts, name, src, verb, text)
    TriggerClientEvent('chat:addMessage', pid, {
        templateId = 'rp:say',
        args = { ts, name, tostring(src), verb, text },
        multiline = true,
    })
end

-- Send a line to every player within `range` of the speaker (always includes the speaker).
local function sendProximity(src, text, range, verb)
    local sp = coordsOf(src)
    local ts, name = os.date('%H:%M:%S'), getCharName(src)
    if not sp then sayTo(src, ts, name, src, verb, text); return end
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        local pp = coordsOf(pid)
        if pid == src or (pp and #(pp - sp) <= range) then
            sayTo(pid, ts, name, src, verb, text)
        end
    end
end

-- Normal chat: intercept the default GLOBAL broadcast and re-route it as proximity speech.
exports.chat:registerMessageHook(function(source, outMessage, hookRef)
    if not source or source == 0 then return end -- console/system messages broadcast normally
    local text = outMessage.args[#outMessage.args]
    if not text or text == '' then hookRef.cancel(); return end
    hookRef.cancel()
    sendProximity(source, text, RANGE.normal, 'says')
end)

local function joined(args) return (table.concat(args, ' ')):match('^%s*(.-)%s*$') end

RegisterCommand('low', function(src, args)
    local text = joined(args)
    if src > 0 and text ~= '' then sendProximity(src, text, RANGE.low, 'says quietly') end
end, false)

local function shoutCmd(src, args)
    local text = joined(args)
    if src > 0 and text ~= '' then sendProximity(src, text, RANGE.shout, 'shouts') end
end
RegisterCommand('shout', shoutCmd, false)
RegisterCommand('s', shoutCmd, false)

-- /whisper [id] <text> - direct to one player who must be right next to you.
RegisterCommand('whisper', function(src, args)
    if src <= 0 then return end
    local target = tonumber(args[1])
    if not target then return end
    table.remove(args, 1)
    local text = joined(args)
    if text == '' then return end
    local sp, tp = coordsOf(src), coordsOf(target)
    if not sp or not tp or #(sp - tp) > 3.0 then return end
    local ts, name = os.date('%H:%M:%S'), getCharName(src)
    sayTo(target, ts, name, src, 'whispers', text)
    if src ~= target then sayTo(src, ts, name, src, 'whispers', text) end
end, false)

-- /carwhisper, /cw <text> - to everyone sharing your vehicle.
local function carCmd(src, args)
    if src <= 0 then return end
    local text = joined(args)
    if text == '' then return end
    local veh = GetVehiclePedIsIn(GetPlayerPed(src), false)
    if not veh or veh == 0 then return end
    local ts, name = os.date('%H:%M:%S'), getCharName(src)
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        if GetVehiclePedIsIn(GetPlayerPed(pid), false) == veh then
            sayTo(pid, ts, name, src, 'says in the car', text)
        end
    end
end
RegisterCommand('carwhisper', carCmd, false)
RegisterCommand('cw', carCmd, false)
