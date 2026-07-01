-- PenguRP Marriage System (pengu_core) - SERVER. Stores marriage state in player metadata
-- (marriedTo = citizenid, marriedName = full name). Proposal uses a lib.callback pair
-- so one player proposes -> target gets an accept/reject prompt -> result saved on both.
-- ASCII only. luac clean.

local qbx = exports.qbx_core

local function playerByCid(cid)
    for src, p in pairs(qbx:GetQBPlayers() or {}) do
        if p.PlayerData and p.PlayerData.citizenid == cid then return src, p end
    end
end

local function fullName(p)
    local c = p.PlayerData.charinfo
    return c and (c.firstname .. ' ' .. c.lastname) or 'Unknown'
end

-- pending[targetSrc] = { proposerSrc, proposerCid, proposerName }
local pending = {}

lib.callback.register('pengu_core:propose', function(proposerSrc, targetId)
    local proposer = qbx:GetPlayer(proposerSrc)
    if not proposer then return false, 'Not found.' end
    local meta = proposer.PlayerData.metadata or {}
    if meta.marriedTo and meta.marriedTo ~= '' then return false, 'You are already married.' end

    local targetSrc = tonumber(targetId)
    if not targetSrc or targetSrc == proposerSrc then return false, 'Invalid target.' end
    local target = qbx:GetPlayer(targetSrc)
    if not target then return false, 'That player is not online.' end
    local tmeta = target.PlayerData.metadata or {}
    if tmeta.marriedTo and tmeta.marriedTo ~= '' then return false, 'They are already married.' end

    pending[targetSrc] = {
        proposerSrc  = proposerSrc,
        proposerCid  = proposer.PlayerData.citizenid,
        proposerName = fullName(proposer),
    }
    TriggerClientEvent('pengu_core:proposalReceived', targetSrc, fullName(proposer))
    return true, 'Proposal sent.'
end)

lib.callback.register('pengu_core:respondProposal', function(targetSrc, accepted)
    local data = pending[targetSrc]
    if not data then return false, 'No proposal pending.' end
    pending[targetSrc] = nil

    local target   = qbx:GetPlayer(targetSrc)
    local proposer = qbx:GetPlayer(data.proposerSrc)
    if not target or not proposer then return false, 'A player went offline.' end

    if not accepted then
        TriggerClientEvent('pengu_core:proposalResult', data.proposerSrc, false, fullName(target))
        return true, 'Declined.'
    end

    local tCid  = target.PlayerData.citizenid
    local pCid  = proposer.PlayerData.citizenid
    local tName = fullName(target)
    local pName = fullName(proposer)

    target.Functions.SetMetaData('marriedTo',   pCid)
    target.Functions.SetMetaData('marriedName', pName)
    proposer.Functions.SetMetaData('marriedTo',   tCid)
    proposer.Functions.SetMetaData('marriedName', tName)

    TriggerClientEvent('pengu_core:proposalResult', data.proposerSrc, true, tName)
    return true, 'Accepted.'
end)

lib.callback.register('pengu_core:divorce', function(src)
    local p = qbx:GetPlayer(src)
    if not p then return false end
    local meta = p.PlayerData.metadata or {}
    local partnerCid = meta.marriedTo
    if not partnerCid or partnerCid == '' then return false, 'You are not married.' end

    local partnerName = meta.marriedName or 'your spouse'
    p.Functions.SetMetaData('marriedTo',   '')
    p.Functions.SetMetaData('marriedName', '')

    local pSrc, partner = playerByCid(partnerCid)
    if partner then
        partner.Functions.SetMetaData('marriedTo',   '')
        partner.Functions.SetMetaData('marriedName', '')
        TriggerClientEvent('pengu_core:divorced', pSrc, fullName(p))
    end
    return true, ('You divorced %s.'):format(partnerName)
end)

lib.callback.register('pengu_core:getMarriageStatus', function(src)
    local p = qbx:GetPlayer(src)
    if not p then return nil end
    local meta = p.PlayerData.metadata or {}
    return { marriedTo = meta.marriedTo or '', marriedName = meta.marriedName or '' }
end)

-- clean up pending proposals when a player drops
AddEventHandler('playerDropped', function()
    local src = source
    pending[src] = nil
    -- also clean any proposal they sent (find by proposerSrc)
    for t, d in pairs(pending) do
        if d.proposerSrc == src then pending[t] = nil end
    end
end)
