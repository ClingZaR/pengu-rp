-- PenguRP - Jail & Court (Phase 2.5) :: SERVER HUB
-- Authoritative logic for prison labor (sentence reduction), bail, and judicial
-- court powers. All jail state changes go through the pengu_core custom jail. ASCII only.
--
-- pengu_core jail contract (server/jail.lua):
--   read    : exports['pengu_core']:GetJailMinutes(src)        (minutes; 0 if not jailed)
--   reduce  : exports['pengu_core']:ReduceJailMinutes(src, n)  (returns new remaining; releases at 0)
--   release : exports['pengu_core']:ReleasePlayerCustom(src)
--   client  : LocalPlayer.state.penguJailMinutes  (replicated; > 0 means jailed)

-- ===================== HELPERS =====================

local function getP(src)
    return exports.qbx_core:GetPlayer(src)
end

-- Remaining minutes from the REAL jail (pengu_core custom jail), not xt-prison.
local function jailTime(src)
    return exports['pengu_core']:GetJailMinutes(src) or 0
end

local function isJailed(src)
    return jailTime(src) > 0
end

-- Server-side notify -> qbx_chat_theme 'pengu:admin' template. kind in 'ok'|'err'|'info'.
local function notify(src, msg, kind, tag)
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { tag or 'PRISON', msg, kind or 'info' },
    })
end

-- Look up the GetPlayer job.name against a set table (e.g. Config.judgeJobs).
local function hasJob(src, set)
    local p = getP(src)
    if not p then return false end
    local job = p.PlayerData and p.PlayerData.job and p.PlayerData.job.name
    return job ~= nil and set[job] == true
end

-- 'First Last' from charinfo.
local function charName(p)
    local ci = p and p.PlayerData and p.PlayerData.charinfo
    if not ci then return 'Unknown' end
    return tostring(ci.firstname) .. ' ' .. tostring(ci.lastname)
end

-- ===================== STATE =====================

local customBail = {} -- [citizenid] = amount (judge/lawyer set; cleared on release)
local laborCd    = {} -- [src..':'..key] = os.time() of last completion

-- Clear any custom bail the instant the prisoner is released by ANY path (served, labor
-- worked to 0, /release, /unjail, pardon, or bail) so a stale amount can never carry into
-- a later sentence and bypass the maxSelfMinutes gate / pricing.
AddEventHandler('pengu_jail:server:released', function(_, cid)
    if cid then customBail[cid] = nil end
end)

-- Compute the effective bail amount for a jailed player.
-- Returns: amount (number) OR nil + reason ('toolong') when self bail is disallowed.
local function computeBail(src, cid)
    local amount = customBail[cid]
    if amount then return amount end
    local cur = jailTime(src)
    if cur > Config.bail.maxSelfMinutes then
        return nil, 'toolong'
    end
    return math.max(Config.bail.minAmount, math.min(Config.bail.maxAmount, math.floor(Config.bail.perMinute * cur)))
end

-- ===================== PRISON LABOR =====================

RegisterNetEvent('pengu_prison:labor', function(key)
    local src = source
    if not isJailed(src) then return end

    local station
    for _, st in ipairs(Config.labor.stations) do
        if st.key == key then
            station = st
            break
        end
    end
    if not station then return end

    -- Server-side proximity: the event must come from someone actually AT the station
    -- (the client progress bar is not trusted; this blocks remote labor spam).
    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - station.coords) > 3.5 then return end

    local cdKey = src .. ':' .. key
    local last = laborCd[cdKey]
    if last and (os.time() - last) < station.cooldown then
        notify(src, 'That work station is still on cooldown.', 'err')
        return
    end
    laborCd[cdKey] = os.time()

    -- [pengu_core prison_riot hook] labor works off DOUBLE time while a riot world event is
    -- live (GlobalState.penguPrisonRiot set by pengu_core). pcall-safe, sane defaults, and the
    -- endsAt check makes a stale flag harmless if pengu_core is off.
    local reduceMin = station.reduceMin
    local okR, riot = pcall(function() return GlobalState.penguPrisonRiot end)
    if okR and type(riot) == 'table' and os.time() < (tonumber(riot.endsAt) or 0) then
        reduceMin = reduceMin * (tonumber(riot.mult) or 2)
    end

    local newTime = exports['pengu_core']:ReduceJailMinutes(src, reduceMin)

    if Config.labor.cashItem and station.rewardMax > 0 then
        local reward = math.random(station.rewardMin, station.rewardMax)
        local p = getP(src)
        if p then
            p.Functions.AddMoney(Config.labor.cashItem, reward, 'prison-labor')
        end
    end

    if newTime > 0 then
        notify(src, 'You worked it off. ' .. newTime .. ' minute(s) of your sentence remain.', 'ok')
    else
        notify(src, 'You worked off the last of your sentence.', 'ok')
    end
end)

-- ===================== BAIL =====================

lib.addCommand('bail', { help = 'Pay bail to be released early' }, function(source)
    local p = getP(source)
    if not p then return end
    if not isJailed(source) then
        notify(source, 'You are not jailed.', 'err')
        return
    end

    local cid = p.PlayerData.citizenid
    local amount, reason = computeBail(source, cid)
    if not amount then
        if reason == 'toolong' then
            notify(source, 'Your sentence is too long for self bail; a judge must set your bail.', 'err')
        end
        return
    end

    local bank = (p.PlayerData.money and p.PlayerData.money.bank) or 0
    if bank < amount then
        notify(source, 'Bail is $' .. amount .. ' - insufficient bank funds.', 'err')
        return
    end
    if not p.Functions.RemoveMoney(Config.bail.payFromAccount, amount, 'bail') then
        notify(source, 'Payment failed.', 'err')
        return
    end

    exports['pengu_core']:ReleasePlayerCustom(source)
    customBail[cid] = nil
    notify(source, 'Released on $' .. amount .. ' bail.', 'ok')
end)

lib.addCommand('bailinfo', { help = 'Check your current bail amount' }, function(source)
    local p = getP(source)
    if not p then return end
    if not isJailed(source) then
        notify(source, 'You are not jailed.', 'err')
        return
    end

    local cid = p.PlayerData.citizenid
    local amount, reason = computeBail(source, cid)
    if not amount then
        if reason == 'toolong' then
            notify(source, 'Your sentence is too long for self bail; a judge must set your bail.', 'info')
        end
        return
    end
    notify(source, 'Your bail is $' .. amount .. '. Use /bail to post it.', 'info')
end)

-- ===================== JUDICIAL COMMANDS =====================

lib.addCommand('pardon', {
    help = 'Judge: pardon and release a jailed player',
    params = { { name = 'id', type = 'playerId', help = 'Target player server id' } },
}, function(source, args)
    if not hasJob(source, Config.judgeJobs) then
        notify(source, 'Judges only.', 'err')
        return
    end
    local target = args.id
    if not isJailed(target) then
        notify(source, 'Target is not jailed.', 'err')
        return
    end

    local tp = getP(target)
    exports['pengu_core']:ReleasePlayerCustom(target)
    if tp then
        customBail[tp.PlayerData.citizenid] = nil
    end

    notify(target, 'You have been pardoned and released.', 'ok')
    notify(source, 'Pardoned and released ' .. (tp and charName(tp) or ('player ' .. target)) .. '.', 'ok')
    print(('[pengu_prison] PARDON: judge %s released player %s'):format(source, target))
end)

lib.addCommand('reducetime', {
    help = 'Judge: reduce a jailed player sentence by minutes',
    params = {
        { name = 'id', type = 'playerId', help = 'Target player server id' },
        { name = 'minutes', type = 'number', help = 'Minutes to subtract' },
    },
}, function(source, args)
    if not hasJob(source, Config.judgeJobs) then
        notify(source, 'Judges only.', 'err')
        return
    end
    local target = args.id
    if not isJailed(target) then
        notify(source, 'Target is not jailed.', 'err')
        return
    end

    local minutes = math.max(0, math.floor(args.minutes))
    local newTime = exports['pengu_core']:ReduceJailMinutes(target, minutes)

    local tp = getP(target)
    notify(target, 'A judge reduced your sentence. ' .. newTime .. ' minute(s) remain.', 'info')
    notify(source, 'Reduced ' .. (tp and charName(tp) or ('player ' .. target)) .. ' to ' .. newTime .. ' minute(s).', 'ok')
end)

lib.addCommand('setbail', {
    help = 'Judge/Lawyer: set a custom bail amount for a jailed player',
    params = {
        { name = 'id', type = 'playerId', help = 'Target player server id' },
        { name = 'amount', type = 'number', help = 'Bail amount in dollars' },
    },
}, function(source, args)
    if not (hasJob(source, Config.judgeJobs) or hasJob(source, Config.lawyerJobs)) then
        notify(source, 'Only judges and lawyers can set bail.', 'err')
        return
    end
    local target = args.id
    if not isJailed(target) then
        notify(source, 'Target is not jailed.', 'err')
        return
    end
    local tp = getP(target)
    if not tp then
        notify(source, 'Target player unavailable.', 'err')
        return
    end

    local amount = math.max(0, math.floor(args.amount))
    customBail[tp.PlayerData.citizenid] = amount

    notify(target, 'Your bail has been set to $' .. amount .. '. Use /bail to post it.', 'info')
    notify(source, 'Set bail for ' .. charName(tp) .. ' to $' .. amount .. '.', 'ok')
end)

-- ===================== CLEANUP =====================

-- Best-effort: clear any custom bail for a dropping player while they are still resolvable.
AddEventHandler('playerDropped', function()
    local src = source
    local p = getP(src)
    if p and p.PlayerData and p.PlayerData.citizenid then
        customBail[p.PlayerData.citizenid] = nil
    end
    for k in pairs(laborCd) do
        if k:sub(1, #tostring(src) + 1) == (src .. ':') then
            laborCd[k] = nil
        end
    end
end)
