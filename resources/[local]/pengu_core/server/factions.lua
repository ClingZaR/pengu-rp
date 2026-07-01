-- PenguRP - FACTION chat + ranking (server). Works identically for LEGAL (jobs) and
-- CRIMINAL (gangs) factions - this is the "faction chat + ranking like the rest" that
-- EVERY faction gets. The legal-only feature set (loc/fleet/clothing/armoury) lives in
-- server/pd.lua; nothing here is police-specific.
--
--   /f <message>            - send to your faction's members only (rp:faction chat line)
--   pengu_faction:getRoster - callback: faction label + online members + ranks + canManage
--   pengu_faction:promote   - boss-only: bump a same-faction member up one grade
--   pengu_faction:demote    - boss-only: drop a same-faction member down one grade
--
-- Faction is resolved from the player: a CRIMINAL gang takes precedence (it is the player's
-- crew), else a LEGAL job. ASCII only. luac clean.

local qbx = exports.qbx_core

-- chat feedback via the qbx_chat_theme 'pengu:admin' template (ok=green/err=red/info=lavender).
local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, msg, kind, tag)
    if not src or src <= 0 then print('[pengu_faction] ' .. msg); return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { tag or 'FACTION', msg, KIND[kind or 'inform'] or 'info' },
    })
end

local function charName(p)
    local ci = p and p.PlayerData and p.PlayerData.charinfo
    if not ci then return 'Unknown' end
    return ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
end

-- Authoritative boss flag for a job/gang group (mirrors pd.lua isBoss): the group-level
-- isboss wins, with grade.isboss as the fallback. Avoids depending on either alone.
local function bossFlag(group)
    if not group then return false end
    if group.isboss ~= nil then return group.isboss == true end
    return (group.grade and group.grade.isboss == true) or false
end

-- Resolve a player's faction: { scope='legal'|'criminal', key, label, grade={name,level}, isboss }
-- or nil if they belong to no registered faction. Precedence: an ON-DUTY legal job wins (so an
-- officer's /f + /faction follow their agency and legal rank management stays reachable, matching
-- the loc/fleet/armoury subsystems which key off the job); else the gang (the player's crew); else
-- an off-duty legal job. This keeps a dual job+gang member's identity consistent across the system.
local function resolveFaction(p)
    local pd = p and p.PlayerData
    if not pd then return nil end
    local job  = pd.job
    local gang = pd.gang
    local legalJob = job and job.name and Factions.isLegal(job.name)

    if legalJob and job.onduty then
        return { scope = 'legal', key = job.name, label = Factions.labelOf('legal', job.name), grade = job.grade or {}, isboss = bossFlag(job) }
    end
    if gang and gang.name and Factions.isCriminal(gang.name) then
        return { scope = 'criminal', key = gang.name, label = Factions.labelOf('criminal', gang.name), grade = gang.grade or {}, isboss = bossFlag(gang) }
    end
    if legalJob then
        return { scope = 'legal', key = job.name, label = Factions.labelOf('legal', job.name), grade = job.grade or {}, isboss = bossFlag(job) }
    end
    return nil
end

-- The qbx grades table for a faction key, e.g. { [0]={name=...}, [1]={...,isboss=true} }.
local function gradesFor(scope, key)
    local ok, set = pcall(function()
        return scope == 'criminal' and qbx:GetGangs() or qbx:GetJobs()
    end)
    local def = ok and set and set[key]
    return def and def.grades or nil
end

-- Highest defined grade level for a faction (integer key), default 0.
local function maxGrade(scope, key)
    local grades = gradesFor(scope, key)
    if not grades then return 0 end
    local hi = 0
    for lvl in pairs(grades) do
        local n = tonumber(lvl)
        if n and n > hi then hi = n end
    end
    return hi
end

-- Name for a grade level within a faction, default 'Grade N'.
local function gradeName(scope, key, level)
    local grades = gradesFor(scope, key)
    local g = grades and grades[level]
    return (g and g.name) or ('Grade ' .. tostring(level))
end

-- Online members of the SAME faction as the given resolved-faction descriptor.
-- Returns { { src, name, level, rank, isboss } }, sorted by grade desc then name.
local function membersOf(myF)
    local players = qbx:GetQBPlayers() or {}
    local out = {}
    -- GetQBPlayers() is keyed by source (table<Source, Player>), so the key is authoritative.
    for src, target in pairs(players) do
        local tf = resolveFaction(target)
        if tf and tf.scope == myF.scope and tf.key == myF.key then
            local level = tonumber(tf.grade.level) or 0
            out[#out + 1] = {
                src    = tonumber(src) or target.PlayerData.source,
                name   = charName(target),
                level  = level,
                rank   = tf.grade.name or gradeName(tf.scope, tf.key, level),
                isboss = tf.isboss,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- ============================ faction chat ============================
-- Registered as /f (primary) + /fc + /factionchat aliases. scully_emotemenu's facial-expression
-- command was moved OFF /f to /face + /exp (server.cfg sets scully_emotemenu:expressionCommands),
-- so /f is now free for faction chat with no collision.

local function factionChatCommand(src, args)
    if src <= 0 then return end
    local p = qbx:GetPlayer(src)
    if not p then return end
    local myF = resolveFaction(p)
    if not myF then
        notify(src, 'You are not in a faction.', 'error', 'FACTION')
        return
    end

    local text = table.concat(args, ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then
        notify(src, 'Usage: /f <message>', 'inform', 'FACTION')
        return
    end

    -- Faction chat is OOC -> "[LSPD | Chief] Name: (( text ))". sendFactionOOC adds the (( )) brackets
    -- itself and tints the colon + brackets with the faction colour, so we pass the RAW text.
    -- tag = "Label | Rank"; sent to faction members only.
    local lvl = tonumber(myF.grade.level) or 0
    local tag = myF.label .. ' | ' .. (myF.grade.name or gradeName(myF.scope, myF.key, lvl))
    local name = charName(p)
    local members = membersOf(myF)
    local ts = os.date('%H:%M:%S')
    -- Criminal gangs get a per-gang colour; legal factions use the standard lavender.
    if myF.scope == 'criminal' then
        local col = (Factions.criminal[myF.key] and Factions.criminal[myF.key].chatColour) or '#4488ff'
        for i = 1, #members do
            TriggerClientEvent('chat:addMessage', members[i].src, {
                templateId = 'pengu:gang:ooc',
                args       = { ts, tag, name, text, col },
                multiline  = true,
            })
        end
    else
        for i = 1, #members do
            exports.qbx_chat_theme:sendFactionOOC(members[i].src, tag, name, text)
        end
    end
end

RegisterCommand('f', factionChatCommand, false)
RegisterCommand('fc', factionChatCommand, false)          -- short alias
RegisterCommand('factionchat', factionChatCommand, false) -- long alias
-- /f autocomplete is provided client-side via chat:addSuggestion (client/factions.lua).

-- ============================ rank customization + permissions ============================
-- Ranks ARE the faction's qbx grade levels (0..maxGrade). This layer lets a leader RENAME each
-- rank and grant it PERMISSIONS, stored per-faction in pengu_faction_ranks (overriding the static
-- config name). The BOSS grade implicitly holds every permission.

-- Permission keys a rank can be granted. 'members' = hire/fire/promote/demote; 'ranks' = rename
-- ranks + set their permissions; 'loadout' = manage the legal-faction armoury/fleet/wardrobe.
local PERMS = { members = true, ranks = true, loadout = true }
local rankCache = {} -- [factionKey] = { [grade] = { label, perms = {k=true} } }

local function permsToSet(str)
    local set = {}
    if type(str) == 'string' then
        for k in str:gmatch('[^,]+') do if PERMS[k] then set[k] = true end end
    end
    return set
end

local function permsToStr(set)
    local out = {}
    for k in pairs(PERMS) do if set[k] then out[#out + 1] = k end end
    return table.concat(out, ',')
end

local function loadRanks(facKey)
    if rankCache[facKey] then return rankCache[facKey] end
    local rows = MySQL.query.await('SELECT grade, label, perms FROM pengu_faction_ranks WHERE faction = ?', { facKey }) or {}
    local t = {}
    for _, r in ipairs(rows) do
        t[tonumber(r.grade)] = { label = r.label, perms = permsToSet(r.perms) }
    end
    rankCache[facKey] = t
    return t
end

-- Effective rank info (custom label + permissions) for a faction grade level.
local function rankInfo(scope, key, level)
    local o = loadRanks(key)[level]
    return {
        level = level,
        label = (o and o.label and o.label ~= '') and o.label or gradeName(scope, key, level),
        perms = (o and o.perms) or {},
    }
end

-- Effective permissions a member has (the BOSS grade always has all of them).
local function playerPerms(myF)
    if myF.isboss then return { members = true, ranks = true, loadout = true } end
    return rankInfo(myF.scope, myF.key, tonumber(myF.grade.level) or 0).perms
end

-- Guard: caller's faction if they hold `perm` (or are the boss), else nil (+ notify).
local function requirePerm(source, perm)
    local p = qbx:GetPlayer(source)
    local myF = p and resolveFaction(p)
    if not myF then return nil end
    if myF.isboss or playerPerms(myF)[perm] then return myF end
    notify(source, 'You do not have permission to do that.', 'error', 'FACTION')
    return nil
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS pengu_faction_ranks (
            faction VARCHAR(24) NOT NULL,
            grade   INT         NOT NULL,
            label   VARCHAR(40) NULL,
            perms   VARCHAR(64) NOT NULL DEFAULT '',
            PRIMARY KEY (faction, grade)
        )
    ]])
end)

-- ============================ roster + ranking ============================

lib.callback.register('pengu_faction:getRoster', function(source)
    local p = qbx:GetPlayer(source)
    if not p then return nil end
    local myF = resolveFaction(p)
    if not myF then return nil end

    local iAmBoss = myF.isboss
    local cap = maxGrade(myF.scope, myF.key)
    local members = membersOf(myF)
    for i = 1, #members do
        members[i].isSelf = (members[i].src == source)
    end
    return {
        scope    = myF.scope,
        label    = myF.label,
        rank     = myF.grade.name or gradeName(myF.scope, myF.key, tonumber(myF.grade.level) or 0),
        canManage = iAmBoss,
        maxGrade = cap,
        members  = members,
    }
end)

-- Shared guard for member actions (promote/demote/fire). Requires the 'members' permission, the
-- target in the same faction, and (unless boss) the target ranked BELOW the actor. Returns
-- myFaction, targetPlayer, targetFaction, targetLevel - or nil (+ notify).
local function authChange(source, targetSrc)
    targetSrc = tonumber(targetSrc)
    if not targetSrc then return end
    local p = qbx:GetPlayer(source)
    if not p then return end
    local myF = resolveFaction(p)
    if not myF or not (myF.isboss or playerPerms(myF).members) then
        notify(source, 'You do not have permission to manage members.', 'error')
        return
    end
    if targetSrc == source then
        notify(source, 'You cannot change your own rank.', 'error')
        return
    end
    local t = qbx:GetPlayer(targetSrc)
    if not t then notify(source, 'That member is not online.', 'error'); return end
    local tf = resolveFaction(t)
    if not tf or tf.scope ~= myF.scope or tf.key ~= myF.key then
        notify(source, 'That player is not in your faction.', 'error')
        return
    end
    local tLevel = tonumber(tf.grade.level) or 0
    if not myF.isboss and tLevel >= (tonumber(myF.grade.level) or 0) then
        notify(source, 'You cannot manage someone at or above your own rank.', 'error')
        return
    end
    return myF, t, tf, tLevel
end

local function applyGrade(scope, key, targetSrc, newLevel)
    if scope == 'criminal' then
        return qbx:SetGang(targetSrc, key, newLevel)
    end
    -- SetJob rebuilds job.onduty from job.defaultDuty (true for all LEO/EMS), which would
    -- force an off-duty officer ON duty on a mere rank change (and pd.lua would then treat
    -- them as an active LEO). Preserve their duty state across the grade change.
    local cur = qbx:GetPlayer(targetSrc)
    local wasOnDuty = cur and cur.PlayerData and cur.PlayerData.job and cur.PlayerData.job.onduty == true
    local ok = qbx:SetJob(targetSrc, key, newLevel)
    if ok then qbx:SetJobDuty(targetSrc, wasOnDuty) end
    return ok
end

RegisterNetEvent('pengu_faction:promote', function(targetSrc)
    local src = source -- capture before any awaiting call (applyGrade yields -> source clobber)
    local myF, t, _, level = authChange(src, targetSrc)
    if not myF then return end
    local cap = maxGrade(myF.scope, myF.key)
    if level >= cap then
        notify(src, ('%s is already at the top rank.'):format(charName(t)), 'inform')
        return
    end
    local newLevel = level + 1
    if applyGrade(myF.scope, myF.key, t.PlayerData.source, newLevel) then
        local rank = rankInfo(myF.scope, myF.key, newLevel).label
        notify(src, ('Promoted %s to %s.'):format(charName(t), rank), 'success')
        notify(t.PlayerData.source, ('You were promoted to %s in %s.'):format(rank, myF.label), 'success')
    else
        notify(src, 'Promotion failed.', 'error')
    end
end)

RegisterNetEvent('pengu_faction:demote', function(targetSrc)
    local src = source -- capture before any awaiting call (applyGrade yields -> source clobber)
    local myF, t, _, level = authChange(src, targetSrc)
    if not myF then return end
    if level <= 0 then
        notify(src, ('%s is already at the lowest rank.'):format(charName(t)), 'inform')
        return
    end
    local newLevel = level - 1
    if applyGrade(myF.scope, myF.key, t.PlayerData.source, newLevel) then
        local rank = rankInfo(myF.scope, myF.key, newLevel).label
        notify(src, ('Demoted %s to %s.'):format(charName(t), rank), 'success')
        notify(t.PlayerData.source, ('You were demoted to %s in %s.'):format(rank, myF.label), 'inform')
    else
        notify(src, 'Demotion failed.', 'error')
    end
end)

-- ============================ comprehensive management (NUI-driven) ============================

-- Rich faction snapshot for the management UI: my rank + permissions, all ranks (custom label +
-- perms), and the online roster (with custom rank labels).
lib.callback.register('pengu_faction:getData', function(source)
    local p = qbx:GetPlayer(source)
    local myF = p and resolveFaction(p)
    if not myF then return nil end
    local cap = maxGrade(myF.scope, myF.key)

    local ranks = {}
    for lvl = 0, cap do
        local ri = rankInfo(myF.scope, myF.key, lvl)
        ranks[#ranks + 1] = { level = lvl, label = ri.label, perms = ri.perms, isBoss = (lvl == cap) }
    end

    local members = membersOf(myF)
    for i = 1, #members do
        members[i].isSelf = (members[i].src == source)
        members[i].label  = rankInfo(myF.scope, myF.key, members[i].level).label
    end

    return {
        scope    = myF.scope,
        key      = myF.key,
        label    = myF.label,
        myLevel  = tonumber(myF.grade.level) or 0,
        myPerms  = playerPerms(myF),
        isBoss   = myF.isboss,
        maxGrade = cap,
        permKeys = { 'members', 'ranks', 'loadout' },
        ranks    = ranks,
        members  = members,
    }
end)

-- Rename a rank ('ranks' perm). Empty label clears the override (back to the config name).
RegisterNetEvent('pengu_faction:setRankLabel', function(grade, label)
    local myF = requirePerm(source, 'ranks')
    if not myF then return end
    grade = tonumber(grade)
    if not grade or grade < 0 or grade > maxGrade(myF.scope, myF.key) then return end
    label = type(label) == 'string' and label:gsub('[^%w%s%-/]', ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 32) or ''
    MySQL.query.await(
        'INSERT INTO pengu_faction_ranks (faction, grade, label) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE label = VALUES(label)',
        { myF.key, grade, label ~= '' and label or nil })
    rankCache[myF.key] = nil
    notify(source, 'Rank renamed.', 'success', 'FACTION')
end)

-- Set a rank's permissions ('ranks' perm). The top (boss) rank always has all permissions.
RegisterNetEvent('pengu_faction:setRankPerms', function(grade, permList)
    local myF = requirePerm(source, 'ranks')
    if not myF then return end
    grade = tonumber(grade)
    if not grade or grade < 0 or grade >= maxGrade(myF.scope, myF.key) then return end
    local set = {}
    if type(permList) == 'table' then
        for _, k in ipairs(permList) do if PERMS[k] then set[k] = true end end
    end
    MySQL.query.await(
        'INSERT INTO pengu_faction_ranks (faction, grade, perms) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE perms = VALUES(perms)',
        { myF.key, grade, permsToStr(set) })
    rankCache[myF.key] = nil
    notify(source, 'Rank permissions updated.', 'success', 'FACTION')
end)

-- Remove a member from the faction ('members' perm + rank hierarchy via authChange).
RegisterNetEvent('pengu_faction:fire', function(targetSrc)
    local src = source
    local myF, t = authChange(src, targetSrc)
    if not myF then return end
    local tsrc = t.PlayerData.source
    if myF.scope == 'criminal' then qbx:SetGang(tsrc, 'none', 0) else qbx:SetJob(tsrc, 'unemployed', 0) end
    notify(src, ('Removed %s from %s.'):format(charName(t), myF.label), 'success')
    notify(tsrc, ('You were removed from %s.'):format(myF.label), 'inform')
end)

-- ============================ invite / accept / quit ============================
-- One faction per player. A leader (or a rank with the 'members' perm) INVITES by server id or
-- character name; the invite is held in-memory and the target must /factionaccept (within
-- INVITE_TTL) to actually join. /quitfaction leaves the current faction.
local pendingInvites = {} -- [targetSrc] = { scope, key, label, fromName, expires }
local INVITE_TTL = 60     -- seconds an invite stays valid

-- Resolve a name-or-id string to an online qbx Player (or nil). Numeric = server id; otherwise a
-- case-insensitive character-name match (exact wins over substring).
local function resolveTarget(input)
    input = ((type(input) == 'string' and input) or tostring(input or '')):gsub('^%s+', ''):gsub('%s+$', '')
    if input == '' then return nil end
    local asId = tonumber(input)
    if asId then return qbx:GetPlayer(asId) end
    local want = input:lower()
    local exact, partial
    for _, target in pairs(qbx:GetQBPlayers() or {}) do
        local nm = charName(target):lower()
        if nm == want then exact = target; break end
        if not partial and nm:find(want, 1, true) then partial = target end
    end
    return exact or partial
end

RegisterNetEvent('pengu_faction:invite', function(nameOrId)
    local src = source
    local myF = requirePerm(src, 'members')
    if not myF then return end
    local t = resolveTarget(nameOrId)
    if not t then notify(src, ('No online player matches "%s".'):format(tostring(nameOrId)), 'error'); return end
    local tsrc = t.PlayerData.source
    if tsrc == src then notify(src, 'You cannot invite yourself.', 'error'); return end
    if resolveFaction(t) then
        notify(src, ('%s is already in a faction (they must /quitfaction first).'):format(charName(t)), 'error')
        return
    end
    local me = qbx:GetPlayer(src)
    pendingInvites[tsrc] = {
        scope = myF.scope, key = myF.key, label = myF.label,
        fromName = me and charName(me) or 'Someone', expires = os.time() + INVITE_TTL,
    }
    notify(src, ('Invited %s to %s. They have %ds to /factionaccept.'):format(charName(t), myF.label, INVITE_TTL), 'success')
    notify(tsrc, ('%s invited you to join %s. Type /factionaccept to join (1 faction max).'):format(pendingInvites[tsrc].fromName, myF.label), 'inform')
end)

RegisterCommand('factionaccept', function(source)
    local src = source
    if src <= 0 then return end
    local inv = pendingInvites[src]
    if not inv then notify(src, 'You have no pending faction invite.', 'error'); return end
    if os.time() > inv.expires then
        pendingInvites[src] = nil
        notify(src, 'That faction invite has expired.', 'error'); return
    end
    local p = qbx:GetPlayer(src)
    if not p then return end
    if resolveFaction(p) then
        pendingInvites[src] = nil
        notify(src, 'You are already in a faction. Use /quitfaction first.', 'error'); return
    end
    pendingInvites[src] = nil
    if inv.scope == 'criminal' then qbx:SetGang(src, inv.key, 0) else qbx:SetJob(src, inv.key, 0) end
    notify(src, ('You joined %s.'):format(inv.label), 'success')
end, false)

RegisterCommand('quitfaction', function(source)
    local src = source
    if src <= 0 then return end
    local p = qbx:GetPlayer(src)
    local myF = p and resolveFaction(p)
    if not myF then notify(src, 'You are not in a faction.', 'error'); return end
    if myF.scope == 'criminal' then qbx:SetGang(src, 'none', 0) else qbx:SetJob(src, 'unemployed', 0) end
    notify(src, ('You left %s.'):format(myF.label), 'inform')
end, false)

AddEventHandler('playerDropped', function() pendingInvites[source] = nil end)
