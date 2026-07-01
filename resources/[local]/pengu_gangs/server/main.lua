-- PenguRP Gang Reputation & Level (pengu_gangs) - SERVER. Persists per-gang rep + level, awards rep
-- (called by pengu_turf / imports / drug bonus), levels gangs up, and exposes exports other systems
-- read. Replicated to GlobalState.penguGangProgress for clients + other resources. ASCII only.

local qbx = exports.qbx_core

PROGRESS = {} -- gang -> { rep, level }

local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, msg, kind, tag)
    if not src or src <= 0 then print('[pengu_gangs] ' .. tostring(msg)); return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { tag or 'GANG', msg, KIND[kind or 'inform'] or 'info' },
    })
end

local function isGang(gang) return gang ~= nil and gang ~= '' and Factions.isCriminal(gang) == true end

-- message every ONLINE member of a gang
local function notifyGang(gang, msg, kind)
    for src, p in pairs(qbx:GetQBPlayers() or {}) do
        local g = p.PlayerData and p.PlayerData.gang
        if g and g.name == gang then notify(src, msg, kind, 'GANG') end
    end
end

-- ===================== rep / level math =====================
local function levelForRep(rep)
    local lvl = 1
    for l = 1, Config.maxLevel do
        if rep >= (Config.levels[l] or math.huge) then lvl = l else break end
    end
    return lvl
end

-- rep needed for the NEXT level (or nil if maxed)
local function nextThreshold(level)
    return Config.levels[level + 1]
end

-- ===================== persistence + replication =====================
local function persist(gang, p)
    MySQL.update('INSERT INTO pengu_gang_progress (gang, rep, level) VALUES (?, ?, ?) ' ..
        'ON DUPLICATE KEY UPDATE rep = VALUES(rep), level = VALUES(level)', { gang, p.rep, p.level })
end

local function publish()
    local out = {}
    for gang, p in pairs(PROGRESS) do out[gang] = { rep = p.rep, level = p.level } end
    GlobalState.penguGangProgress = out
end

-- ===================== boot =====================
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_gang_progress (
                gang  VARCHAR(24) NOT NULL PRIMARY KEY,
                rep   INT         NOT NULL DEFAULT 0,
                level INT         NOT NULL DEFAULT 1
            )
        ]])
        local rows = MySQL.query.await('SELECT gang, rep, level FROM pengu_gang_progress') or {}
        for _, r in ipairs(rows) do
            if isGang(r.gang) then PROGRESS[r.gang] = { rep = tonumber(r.rep) or 0, level = tonumber(r.level) or 1 } end
        end
        -- ensure a row for every known criminal gang
        for gang in pairs(Factions.criminal or {}) do
            if not PROGRESS[gang] then
                PROGRESS[gang] = { rep = 0, level = 1 }
                persist(gang, PROGRESS[gang])
            end
        end
    end)
    if not ok then print('[pengu_gangs] BOOT FAILED: ' .. tostring(err)) end
    publish()
    print('[pengu_gangs] ready.')
end)

-- ===================== exports (other resources award/read rep) =====================
local function addRep(gang, amount)
    if not isGang(gang) then return end
    local p = PROGRESS[gang]
    if not p then p = { rep = 0, level = 1 }; PROGRESS[gang] = p end
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then return end
    p.rep = math.max(0, p.rep + amount)
    local newLevel = levelForRep(p.rep)
    local leveledUp = newLevel > p.level
    p.level = newLevel
    persist(gang, p)
    publish()
    if leveledUp then
        notifyGang(gang, ('Your crew reached LEVEL %d - new contraband and perks unlocked.'):format(newLevel), 'success')
        TriggerEvent('pengu_gangs:levelUp', gang, newLevel)
    end
end

exports('AddRep', addRep)
exports('RepValue', function(key) return (Config.rep and Config.rep[key]) or 0 end) -- canonical rep amounts for callers
exports('GetRep', function(gang) local p = PROGRESS[gang]; return p and p.rep or 0 end)
exports('GetLevel', function(gang) local p = PROGRESS[gang]; return p and p.level or 1 end)
exports('GetLevelPerks', function(gang)
    local p = PROGRESS[gang]
    return Config.levelPerks[(p and p.level) or 1] or Config.levelPerks[1] or {}
end)

-- ===================== /gang (members) =====================
RegisterCommand('ganginfo', function(src)
    if src <= 0 then return end
    local pl = qbx:GetPlayer(src)
    local gang = pl and pl.PlayerData and pl.PlayerData.gang and pl.PlayerData.gang.name
    if not isGang(gang) then notify(src, 'You are not in a gang.', 'error'); return end
    local p = PROGRESS[gang] or { rep = 0, level = 1 }
    local nxt = nextThreshold(p.level)
    local label = Factions.labelOf('criminal', gang)
    if nxt then
        notify(src, ('%s - Level %d | Rep %d/%d (%d to next level).'):format(label, p.level, p.rep, nxt, nxt - p.rep), 'inform')
    else
        notify(src, ('%s - Level %d (MAX) | Rep %d.'):format(label, p.level, p.rep), 'inform')
    end
end, false)

-- ===================== admin =====================
local ACE = 'pengu.gang'
local function adminOk(src)
    if not IsPlayerAceAllowed(src, ACE) then notify(src, 'you are not allowed.', 'error'); return false end
    if not exports.qbx_core:IsOptin(src) then notify(src, 'you must /aduty.', 'error'); return false end
    return true
end

RegisterCommand('gangrep', function(src, args)
    if not adminOk(src) then return end
    local gang = tostring(args[1] or ''):lower()
    local amt = tonumber(args[2])
    if not isGang(gang) or not amt then notify(src, 'usage: /gangrep <gang> <amount(+/-)>', 'error'); return end
    addRep(gang, amt)
    local p = PROGRESS[gang]
    notify(src, ('%s now rep %d (level %d).'):format(gang, p.rep, p.level), 'success')
end, false)

-- /gangpenalty <gang> <amount>  — deduct rep (does not go below 0; may drop level)
RegisterCommand('gangpenalty', function(src, args)
    if not adminOk(src) then return end
    local gang = tostring(args[1] or ''):lower()
    local amt  = tonumber(args[2])
    if not isGang(gang) or not amt or amt <= 0 then
        notify(src, 'usage: /gangpenalty <gang> <positive_amount>', 'error'); return
    end
    addRep(gang, -amt) -- addRep handles math.max(0, ...) + level recalc
    local p = PROGRESS[gang] or { rep = 0, level = 1 }
    notifyGang(gang, ('Your crew lost %d rep due to an admin penalty. Current: %d rep (Level %d).'):format(amt, p.rep, p.level), 'error')
    notify(src, ('%s penalised -%d rep. Now %d rep Level %d.'):format(gang, amt, p.rep, p.level), 'success')
end, false)

-- /gangreset <gang>  — wipe rep to 0 and drop to level 1 (hard reset / ban punishment)
RegisterCommand('gangreset', function(src, args)
    if not adminOk(src) then return end
    local gang = tostring(args[1] or ''):lower()
    if not isGang(gang) then notify(src, 'usage: /gangreset <gang>', 'error'); return end
    local p = PROGRESS[gang] or { rep = 0, level = 1 }; PROGRESS[gang] = p
    p.rep   = 0
    p.level = 1
    persist(gang, p); publish()
    -- also reset dealer influence
    pcall(function() exports.pengu_dealers:ResetInfluence(gang) end)
    notifyGang(gang, 'Your gang rep and level have been RESET by administration. Read the rules.', 'error')
    notify(src, ('%s has been fully reset to 0 rep Level 1.'):format(gang), 'success')
end, false)

RegisterCommand('ganglevel', function(src, args)
    if not adminOk(src) then return end
    local gang = tostring(args[1] or ''):lower()
    local lvl = tonumber(args[2])
    if not isGang(gang) or not lvl or lvl < 1 or lvl > Config.maxLevel then
        notify(src, ('usage: /ganglevel <gang> <1-%d>'):format(Config.maxLevel), 'error'); return
    end
    local p = PROGRESS[gang] or { rep = 0, level = 1 }; PROGRESS[gang] = p
    p.level = math.floor(lvl)
    p.rep = math.max(p.rep, Config.levels[p.level] or p.rep) -- bump rep to at least the level threshold
    persist(gang, p); publish()
    notify(src, ('%s set to level %d.'):format(gang, p.level), 'success')
end, false)
