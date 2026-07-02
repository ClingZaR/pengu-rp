-- PenguRP Character Bio (pengu_core) - SERVER. Player-chosen PUBLIC backstory line
-- stored in the qbx metadata key 'bio' (same SetMetaData persistence path as
-- marriage.lua). /setbio -> pengu_core:setBio (sanitize: printable ASCII only,
-- whitespace collapsed, trimmed, hard 280 cap). /bio [id] -> pengu_core:getBio;
-- reading someone ELSE requires them within 5m (server-side GetEntityCoords
-- proximity) - RP 'sizing someone up'. No admin gate: bios are player-chosen
-- public info. ASCII only. luac clean.

local qbx = exports.qbx_core

local MAX_LEN = 280
local RANGE = 5.0

-- printable ASCII only (newlines/tabs become spaces), collapse runs, trim, cap
local function sanitize(text)
    if type(text) ~= 'string' then return '' end
    text = text:gsub('[^\32-\126]', ' ')
    text = text:gsub('%s+', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    if #text > MAX_LEN then
        text = text:sub(1, MAX_LEN):gsub('%s+$', '')
    end
    return text
end

lib.callback.register('pengu_core:setBio', function(src, text)
    local p = qbx:GetPlayer(src)
    if not p then return false, 'Not found.' end
    local bio = sanitize(text)
    p.Functions.SetMetaData('bio', bio)
    if bio == '' then return true, 'Bio cleared.' end
    return true, ('Bio saved (%d/%d characters).'):format(#bio, MAX_LEN)
end)

-- Returns name, rawBio ('' when unset; client shows the fallback line).
-- Failure -> nil, message. No id = your own bio (no proximity needed).
lib.callback.register('pengu_core:getBio', function(src, targetId)
    local target
    if targetId then
        local tSrc = tonumber(targetId)
        if not tSrc then return nil, 'Invalid id.' end
        target = qbx:GetPlayer(tSrc)
        if not target then return nil, 'That player is not online.' end
        if tSrc ~= src then
            -- server-authoritative proximity: size someone up face to face
            local myPed, tPed = GetPlayerPed(src), GetPlayerPed(tSrc)
            if myPed == 0 or tPed == 0 then return nil, 'They are not around.' end
            if #(GetEntityCoords(myPed) - GetEntityCoords(tPed)) > RANGE then
                return nil, 'They are too far away to size up.'
            end
        end
    else
        target = qbx:GetPlayer(src)
        if not target then return nil, 'Not found.' end
    end

    local c = target.PlayerData.charinfo
    local name = c and (c.firstname .. ' ' .. c.lastname) or 'Unknown'
    local meta = target.PlayerData.metadata or {}
    local bio = type(meta.bio) == 'string' and meta.bio or ''
    return name, bio
end)
