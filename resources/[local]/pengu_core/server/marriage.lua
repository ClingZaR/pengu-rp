-- PenguRP Marriage System (pengu_core) - SERVER. Stores marriage state in player metadata
-- (marriedTo = citizenid, marriedName = full name, marriageAccount = joint bank id).
-- Proposal uses a lib.callback pair so one player proposes -> target gets an
-- accept/reject prompt -> result saved on both. On acceptance a joint shared bank
-- account is opened via Renewed-Banking exports (pcall-guarded, never blocks marriage).
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

-- ===================== joint bank account (Renewed-Banking) ===================== -- PenguRP
-- On marriage a shared account 'marriage_<cidA>_<cidB>' (cids sorted -> deterministic)
-- is created via Renewed-Banking exports and both spouses are added as members.
-- Every banking call is pcall-guarded: a banking failure never blocks the marriage.

local BANK = 'Renewed-Banking'

local function jointAccountId(cidA, cidB)
    if cidB < cidA then cidA, cidB = cidB, cidA end
    return ('marriage_%s_%s'):format(cidA, cidB)
end

-- Returns the account id on success, nil on any banking failure.
local function setupJointAccount(playerA, playerB)
    local cidA = playerA.PlayerData.citizenid
    local cidB = playerB.PlayerData.citizenid
    local acctId = jointAccountId(cidA, cidB)
    local label = ('Joint Account - %s & %s'):format(fullName(playerA), fullName(playerB))
    local ok = pcall(function()
        local bank = exports[BANK]
        bank:CreateJobAccount({ name = acctId, label = label }, 0) -- returns existing account if already created
        local acct = bank:GetJobAccount(acctId)
        if not acct then error('joint account missing after create') end
        -- addAccountMember appends blindly, so skip cids already authorized (remarriage case)
        local auth = acct.auth or {}
        if not auth[cidA] then bank:addAccountMember(acctId, cidA) end
        if not auth[cidB] then bank:addAccountMember(acctId, cidB) end
    end)
    if not ok then
        print(('[pengu_core] joint bank account setup failed for %s (marriage completed anyway)'):format(acctId))
        return nil
    end
    return acctId
end

-- Divorce policy: NEVER delete the account (funds must not vanish).
-- Empty account  -> revoke access for every online spouse (nothing to lose; the
--                   removeAccountMember export only resolves ONLINE players, so an
--                   offline ex keeps a harmless auth entry on an empty account).
-- Funded account -> leave both members on it so the ex-couple split the money in RP.
-- Returns true when access was kept because funds remain to be split.
local function releaseJointAccount(acctId, onlineCids)
    local keepAccess = false
    pcall(function()
        local bank = exports[BANK]
        local balance = bank:getAccountMoney(acctId)
        if type(balance) ~= 'number' then return end -- account not found; nothing to release
        if balance > 0 then
            keepAccess = true
            return
        end
        for i = 1, #onlineCids do
            pcall(function() bank:removeAccountMember(acctId, onlineCids[i]) end)
        end
    end)
    return keepAccess
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

    -- PenguRP: open the joint bank account (failure never blocks the marriage)
    local acctId = setupJointAccount(proposer, target)
    if acctId then
        target.Functions.SetMetaData('marriageAccount', acctId)
        proposer.Functions.SetMetaData('marriageAccount', acctId)
        TriggerClientEvent('pengu_core:jointAccount', targetSrc, acctId)
        TriggerClientEvent('pengu_core:jointAccount', data.proposerSrc, acctId)
    end

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
    local acctId = meta.marriageAccount or '' -- PenguRP joint bank account
    p.Functions.SetMetaData('marriedTo',   '')
    p.Functions.SetMetaData('marriedName', '')
    p.Functions.SetMetaData('marriageAccount', '')

    local pSrc, partner = playerByCid(partnerCid)
    if partner then
        partner.Functions.SetMetaData('marriedTo',   '')
        partner.Functions.SetMetaData('marriedName', '')
        partner.Functions.SetMetaData('marriageAccount', '')
    end

    -- PenguRP: handle the joint account (never deleted - funds must not vanish)
    local acctNote = ''
    if acctId ~= '' then
        local onlineCids = { p.PlayerData.citizenid }
        if partner then onlineCids[#onlineCids + 1] = partner.PlayerData.citizenid end
        if releaseJointAccount(acctId, onlineCids) then
            acctNote = (' Joint account %s remains at the bank - split the funds yourselves.'):format(acctId)
        end
    end

    if partner then
        TriggerClientEvent('pengu_core:divorced', pSrc, fullName(p), acctNote)
    end
    return true, ('You divorced %s.%s'):format(partnerName, acctNote)
end)

lib.callback.register('pengu_core:getMarriageStatus', function(src)
    local p = qbx:GetPlayer(src)
    if not p then return nil end
    local meta = p.PlayerData.metadata or {}
    -- PenguRP: include joint account id (and balance when the bank answers)
    local acctId = meta.marriageAccount or ''
    local balance
    if acctId ~= '' then
        local ok, bal = pcall(function() return exports[BANK]:getAccountMoney(acctId) end)
        if ok and type(bal) == 'number' then balance = bal end
    end
    return {
        marriedTo      = meta.marriedTo or '',
        marriedName    = meta.marriedName or '',
        account        = acctId,
        accountBalance = balance,
    }
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
