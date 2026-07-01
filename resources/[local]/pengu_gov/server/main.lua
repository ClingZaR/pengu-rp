-- PenguRP Government (pengu_gov) - SERVER.
-- Owns: pengu_gov_settings / pengu_elections / pengu_election_voters tables, the election
-- lifecycle (/election open|close|status, /runformayor, /vote) and the mayor powers
-- (/settaxrate, /mayorpardon, /mayorannounce). Everything is server-authoritative: the ace
-- gate, the mayor citizenid check, one-vote-per-citizen (DB primary key) and all money flows
-- (return-checked, refunded on failure, per-player busy lock) are enforced HERE - the client
-- only renders the ballot menu. Replication contracts other resources read:
--   GlobalState.penguMayor   = { cid, name }  (nil while the office is vacant)
--   GlobalState.penguTaxRate = fraction (e.g. 0.05) - pengu_finance reads this, 0.05 default
-- ASCII only. luac clean.

local QBX = exports.qbx_core

-- ---------- chat feedback (qbx_chat_theme 'pengu:admin' template, house pattern) ----------
local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, msg, kind, tag)
    if not src or src <= 0 then print('[pengu_gov] ' .. tostring(msg)); return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { tag or 'GOV', msg, KIND[kind or 'inform'] or 'info' },
    })
end

-- server-wide styled announcement: chat template + ox_lib toast for everyone online
local function announce(tag, msg, kind)
    TriggerClientEvent('chat:addMessage', -1, {
        templateId = 'pengu:admin',
        args = { tag or 'GOV', msg, KIND[kind or 'inform'] or 'info' },
    })
    TriggerClientEvent('ox_lib:notify', -1, {
        title = tag or 'GOV', description = msg, type = kind or 'inform',
    })
end

-- ---------- helpers ----------
local function getPlayer(src) return QBX:GetPlayer(src) end

local function cidOf(p)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function charName(p)
    local ci = p and p.PlayerData and p.PlayerData.charinfo
    if not ci then return 'Unknown' end
    local name = ('%s %s'):format(ci.firstname or '', ci.lastname or '')
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then name = 'Unknown' end
    return name
end

-- admin gate for /election open|close: NEW ace pengu.gov + the qbx admin-duty opt-in
-- (the /aduty pattern). Console (src 0) is always allowed.
local ACE = 'pengu.gov'
local function adminOk(src)
    if not src or src <= 0 then return true end
    if not IsPlayerAceAllowed(src, ACE) then
        notify(src, 'You are not allowed.', 'error')
        return false
    end
    if not QBX:IsOptin(src) then
        notify(src, 'You must /aduty before using this command.', 'error')
        return false
    end
    return true
end

-- silent variant for /election status (players may run status; no error spam)
local function isAdmin(src)
    if not src or src <= 0 then return true end
    return IsPlayerAceAllowed(src, ACE) and QBX:IsOptin(src) or false
end

-- ---------- settings (pengu_gov_settings k/v) ----------
local function setSetting(k, v)
    local aff = MySQL.update.await(
        'INSERT INTO pengu_gov_settings (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)',
        { k, tostring(v) })
    return aff ~= nil
end

local function getSetting(k)
    return MySQL.scalar.await('SELECT v FROM pengu_gov_settings WHERE k = ?', { k })
end

-- ---------- state ----------
local MAYOR = { cid = nil, name = nil }
local ELECTION = nil -- { raceId, office, candidates = { {rowId,cid,name,votes}... }, byCid = {} }
local busy = {}      -- src -> true (one money/vote flow at a time per player)
local lastAnnounce = 0

local function publishMayor()
    if MAYOR.cid then
        GlobalState.penguMayor = { cid = MAYOR.cid, name = MAYOR.name or 'Unknown' }
    else
        GlobalState.penguMayor = nil
    end
end

-- ---------- boot: tables + resume persisted state ----------
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_gov_settings (
                k VARCHAR(48)  NOT NULL PRIMARY KEY,
                v VARCHAR(128) NOT NULL
            )
        ]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_elections (
                id             INT         NOT NULL AUTO_INCREMENT PRIMARY KEY,
                office         VARCHAR(24) NOT NULL,
                candidate_cid  VARCHAR(64) NOT NULL,
                candidate_name VARCHAR(64) NOT NULL,
                votes          INT         NOT NULL DEFAULT 0,
                status         VARCHAR(8)  NOT NULL DEFAULT 'open',
                opened_at      TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_election_voters (
                election_id INT         NOT NULL,
                voter_cid   VARCHAR(64) NOT NULL,
                PRIMARY KEY (election_id, voter_cid)
            )
        ]])

        local cid = getSetting('mayor_cid')
        if cid and cid ~= '' then
            MAYOR.cid  = cid
            MAYOR.name = getSetting('mayor_name') or 'Unknown'
        end

        local tax = tonumber(getSetting('tax_rate'))
        if tax then GlobalState.penguTaxRate = tax / 100 end

        -- resume an election that was open when the server last stopped
        local openId = tonumber(getSetting('election_open_mayor')) or 0
        if openId > 0 then
            local rows = MySQL.query.await(
                'SELECT id, candidate_cid, candidate_name, votes FROM pengu_elections WHERE office = ? AND status = ? ORDER BY id ASC',
                { 'mayor', 'open' }) or {}
            ELECTION = { raceId = openId, office = 'mayor', candidates = {}, byCid = {} }
            for _, r in ipairs(rows) do
                local c = { rowId = r.id, cid = r.candidate_cid, name = r.candidate_name, votes = tonumber(r.votes) or 0 }
                ELECTION.candidates[#ELECTION.candidates + 1] = c
                ELECTION.byCid[c.cid] = c
            end
        else
            -- hygiene: no race marked open in settings -> close any stray open rows
            MySQL.update.await('UPDATE pengu_elections SET status = ? WHERE status = ?', { 'closed', 'open' })
        end
    end)
    if not ok then print('[pengu_gov] BOOT FAILED: ' .. tostring(err)) end
    publishMayor()
    print('[pengu_gov] ready.')
end)

-- ---------- election lifecycle ----------
local function openElection(src, office)
    if ELECTION then
        notify(src, ('An election is already open (#%d %s). Close it first.'):format(ELECTION.raceId, ELECTION.office), 'error')
        return
    end
    local seq = (tonumber(getSetting('election_seq')) or 0) + 1
    if not setSetting('election_seq', seq) or not setSetting('election_open_mayor', seq) then
        notify(src, 'Database error - election not opened.', 'error')
        return
    end
    ELECTION = { raceId = seq, office = office, candidates = {}, byCid = {} }
    announce('ELECTION',
        ('The polls are OPEN for %s of Los Santos! Register with /runformayor ($%d fee, %d slots) and vote with /vote.')
        :format(Config.offices[office], Config.registrationFee, Config.maxCandidates))
    notify(src, ('Election #%d (%s) opened.'):format(seq, office), 'success')
end

local function closeElection(src)
    if not ELECTION then
        notify(src, 'No election is open.', 'error')
        return
    end
    local race = ELECTION
    -- winner straight from the DB (most votes; ties broken by earliest registration)
    local winner
    local ok, err = pcall(function()
        winner = MySQL.single.await(
            'SELECT candidate_cid, candidate_name, votes FROM pengu_elections WHERE office = ? AND status = ? ORDER BY votes DESC, id ASC LIMIT 1',
            { race.office, 'open' })
        MySQL.update.await('UPDATE pengu_elections SET status = ? WHERE office = ? AND status = ?',
            { 'closed', race.office, 'open' })
        setSetting('election_open_mayor', 0)
        if winner then
            setSetting('mayor_cid', winner.candidate_cid)
            setSetting('mayor_name', winner.candidate_name)
        end
    end)
    if not ok then
        print('[pengu_gov] close error: ' .. tostring(err))
        notify(src, 'Database error - election NOT closed.', 'error')
        return
    end
    ELECTION = nil
    if winner then
        MAYOR.cid, MAYOR.name = winner.candidate_cid, winner.candidate_name
        publishMayor()
        local v = tonumber(winner.votes) or 0
        announce('ELECTION', ('The polls are CLOSED. Your new Mayor of Los Santos: %s (%d vote%s)!')
            :format(winner.candidate_name, v, v == 1 and '' or 's'), 'success')
    else
        announce('ELECTION', 'The polls are CLOSED. Nobody ran for office - the seat is unchanged.')
    end
    notify(src, 'Election closed.', 'success')
end

local function electionStatus(src)
    local admin = isAdmin(src)
    if MAYOR.cid then
        notify(src, ('Current mayor: %s.'):format(MAYOR.name or 'Unknown'), 'inform')
    else
        notify(src, 'Current mayor: none (office vacant).', 'inform')
    end
    if not ELECTION then
        notify(src, 'No election is open.', 'inform')
        return
    end
    notify(src, ('Election #%d (%s) is OPEN - %d candidate%s on the ballot:')
        :format(ELECTION.raceId, ELECTION.office, #ELECTION.candidates, #ELECTION.candidates == 1 and '' or 's'), 'inform')
    for i, c in ipairs(ELECTION.candidates) do
        if admin then
            notify(src, ('%d. %s - %d vote%s'):format(i, c.name, c.votes, c.votes == 1 and '' or 's'), 'inform')
        else
            notify(src, ('%d. %s'):format(i, c.name), 'inform')
        end
    end
end

RegisterCommand('election', function(src, args)
    local action = tostring(args[1] or ''):lower()
    if action == 'status' then
        electionStatus(src) -- open to everyone; counts shown to admins only
        return
    end
    if not adminOk(src) then return end
    if action == 'open' then
        local office = tostring(args[2] or 'mayor'):lower()
        if not Config.offices[office] then
            notify(src, 'Unknown office. Available: mayor.', 'error')
            return
        end
        openElection(src, office)
    elseif action == 'close' then
        closeElection(src)
    else
        notify(src, 'Usage: /election <open|close|status> [office]', 'error')
    end
end, false)

-- ---------- candidacy ----------
RegisterCommand('runformayor', function(src)
    if not src or src <= 0 then return end
    if busy[src] then return end
    busy[src] = true
    local ok, err = pcall(function()
        local race = ELECTION
        if not race or race.office ~= 'mayor' then
            notify(src, 'There is no open mayoral election.', 'error')
            return
        end
        local p = getPlayer(src)
        local cid = cidOf(p)
        if not cid then return end
        if race.byCid[cid] then
            notify(src, 'You are already on the ballot.', 'error')
            return
        end
        if #race.candidates >= Config.maxCandidates then
            notify(src, ('The ballot is full (%d candidates max).'):format(Config.maxCandidates), 'error')
            return
        end

        -- reserve the slot in memory BEFORE any await so two players cannot overfill the ballot
        local name = charName(p)
        local cand = { rowId = nil, cid = cid, name = name, votes = 0 }
        race.candidates[#race.candidates + 1] = cand
        race.byCid[cid] = cand

        local function unreserve()
            race.byCid[cid] = nil
            for i = #race.candidates, 1, -1 do
                if race.candidates[i] == cand then table.remove(race.candidates, i); break end
            end
        end

        -- charge the fee (return-checked; refunded on any later failure)
        if not p.Functions.RemoveMoney('bank', Config.registrationFee, 'mayor-candidacy') then
            unreserve()
            notify(src, ('You need $%d in the bank to register.'):format(Config.registrationFee), 'error')
            return
        end

        local rowId = MySQL.insert.await(
            'INSERT INTO pengu_elections (office, candidate_cid, candidate_name, votes, status) VALUES (?, ?, ?, 0, ?)',
            { race.office, cid, name, 'open' })
        if not rowId or ELECTION ~= race then
            -- insert failed, or the race closed while we were writing: roll everything back
            if rowId then
                MySQL.update.await('UPDATE pengu_elections SET status = ? WHERE id = ?', { 'closed', rowId })
            end
            unreserve()
            p.Functions.AddMoney('bank', Config.registrationFee, 'mayor-candidacy-refund')
            notify(src, 'Registration failed - your fee was refunded.', 'error')
            return
        end
        cand.rowId = rowId
        announce('ELECTION', ('%s has entered the mayoral race! Cast your vote with /vote.'):format(name))
    end)
    busy[src] = nil
    if not ok then print('[pengu_gov] runformayor error: ' .. tostring(err)) end
end, false)

-- ---------- voting ----------
RegisterCommand('vote', function(src)
    if not src or src <= 0 then return end
    local race = ELECTION
    if not race then
        notify(src, 'There is no open election.', 'error')
        return
    end
    local list = {}
    for _, c in ipairs(race.candidates) do
        -- wire format uses the DB row id, not the citizenid (no cids leak to clients)
        if c.rowId then list[#list + 1] = { id = c.rowId, name = c.name } end
    end
    if #list == 0 then
        notify(src, 'Nobody is on the ballot yet. Run yourself with /runformayor!', 'error')
        return
    end
    TriggerClientEvent('pengu_gov:client:voteMenu', src, { office = race.office, candidates = list })
end, false)

RegisterNetEvent('pengu_gov:server:vote', function(candidateRowId)
    local src = source
    candidateRowId = tonumber(candidateRowId)
    if not src or src <= 0 or not candidateRowId then return end
    if busy[src] then return end
    busy[src] = true
    local ok, err = pcall(function()
        local race = ELECTION
        if not race then
            notify(src, 'The election has closed.', 'error')
            return
        end
        local cand
        for _, c in ipairs(race.candidates) do
            if c.rowId == candidateRowId then cand = c break end
        end
        if not cand then
            notify(src, 'Invalid candidate.', 'error')
            return
        end
        local voterCid = cidOf(getPlayer(src))
        if not voterCid then return end

        -- one vote per citizenid per election: PRIMARY KEY (election_id, voter_cid)
        local aff = MySQL.update.await(
            'INSERT IGNORE INTO pengu_election_voters (election_id, voter_cid) VALUES (?, ?)',
            { race.raceId, voterCid })
        if not aff or aff < 1 then
            notify(src, 'You have already voted in this election.', 'error')
            return
        end

        local upd = MySQL.update.await(
            'UPDATE pengu_elections SET votes = votes + 1 WHERE id = ? AND status = ?',
            { cand.rowId, 'open' })
        if not upd or upd < 1 then
            -- race closed under us: give the citizen their vote back (row is history anyway)
            MySQL.update.await('DELETE FROM pengu_election_voters WHERE election_id = ? AND voter_cid = ?',
                { race.raceId, voterCid })
            notify(src, 'The election closed before your vote was counted.', 'error')
            return
        end
        cand.votes = cand.votes + 1
        notify(src, ('Vote cast for %s. Democracy thanks you.'):format(cand.name), 'success')
    end)
    busy[src] = nil
    if not ok then print('[pengu_gov] vote error: ' .. tostring(err)) end
end)

-- ---------- mayor powers (every command re-checks citizenid == mayor_cid server-side) ----------
local function mayorOk(src)
    if not src or src <= 0 then return nil end
    if not MAYOR.cid then
        notify(src, 'There is no elected mayor.', 'error', 'MAYOR')
        return nil
    end
    local p = getPlayer(src)
    local cid = cidOf(p)
    if not cid or cid ~= MAYOR.cid then
        notify(src, 'Only the Mayor may use this command.', 'error', 'MAYOR')
        return nil
    end
    return p
end

-- a. /settaxrate <0-25> -> pengu_gov_settings tax_rate + GlobalState.penguTaxRate (fraction).
--    Contract: pengu_finance reads GlobalState.penguTaxRate with a 0.05 default.
RegisterCommand('settaxrate', function(src, args)
    if not mayorOk(src) then return end
    local pct = tonumber(args[1])
    if not pct or pct < Config.taxMin or pct > Config.taxMax then
        notify(src, ('Usage: /settaxrate <%d-%d>'):format(Config.taxMin, Config.taxMax), 'error', 'MAYOR')
        return
    end
    pct = math.floor(pct * 10 + 0.5) / 10 -- one decimal place
    if not setSetting('tax_rate', pct) then
        notify(src, 'Database error - tax rate unchanged.', 'error', 'MAYOR')
        return
    end
    GlobalState.penguTaxRate = pct / 100
    announce('MAYOR', ('Mayor %s has set the city tax rate to %s%%.'):format(MAYOR.name or 'Unknown', tostring(pct)))
end, false)

-- b. /mayorpardon <playerid> -> release from prison (pengu_core pdloc jail first, then the
--    legacy xt-prison Bolingbroke flow). 24h cooldown persisted in pengu_gov_settings.
RegisterCommand('mayorpardon', function(src, args)
    if not mayorOk(src) then return end
    if busy[src] then return end
    busy[src] = true
    local ok, err = pcall(function()
        local target = tonumber(args[1])
        if not target or target <= 0 then
            notify(src, 'Usage: /mayorpardon <playerid>', 'error', 'MAYOR')
            return
        end
        local tp = getPlayer(target)
        if not tp then
            notify(src, 'Invalid id (player must be online).', 'error', 'MAYOR')
            return
        end
        local last = tonumber(getSetting('last_pardon')) or 0
        local now = os.time()
        if now - last < Config.pardonCooldown then
            local left = Config.pardonCooldown - (now - last)
            notify(src, ('Pardon power on cooldown - %dh %dm left.'):format(
                math.floor(left / 3600), math.floor((left % 3600) / 60)), 'error', 'MAYOR')
            return
        end

        local released = false
        -- the pdloc self-contained jail (pengu_core) is the primary jail on this server
        local okc, resc = pcall(function() return exports.pengu_core:ReleasePlayerCustom(target) end)
        if okc and resc == true then released = true end
        if not released then
            -- legacy Bolingbroke flow (xt-prison); UnjailPlayerById added for this pardon
            local okx, resx = pcall(function() return exports['xt-prison']:UnjailPlayerById(target) end)
            if okx and resx == true then released = true end
        end
        if not released then
            notify(src, 'That player is not in prison.', 'error', 'MAYOR')
            return
        end

        if not setSetting('last_pardon', now) then
            print('[pengu_gov] WARNING: last_pardon not persisted')
        end
        announce('MAYOR', ('Mayor %s has granted a full pardon to %s.'):format(MAYOR.name or 'Unknown', charName(tp)), 'success')
        notify(target, 'You have been pardoned by the Mayor. You are free to go.', 'success', 'MAYOR')
    end)
    busy[src] = nil
    if not ok then print('[pengu_gov] pardon error: ' .. tostring(err)) end
end, false)

-- c. /mayorannounce <msg> -> server-wide styled announcement (10 min cooldown)
RegisterCommand('mayorannounce', function(src, args)
    if not mayorOk(src) then return end
    local msg = table.concat(args, ' ')
    msg = msg:gsub('^%s+', ''):gsub('%s+$', ''):sub(1, Config.announceMaxLen)
    if msg == '' then
        notify(src, 'Usage: /mayorannounce <message>', 'error', 'MAYOR')
        return
    end
    local now = os.time()
    if now - lastAnnounce < Config.announceCooldown then
        notify(src, ('Announcement on cooldown - %ds left.'):format(Config.announceCooldown - (now - lastAnnounce)), 'error', 'MAYOR')
        return
    end
    lastAnnounce = now
    announce('MAYOR', ('Mayor %s: %s'):format(MAYOR.name or 'Unknown', msg))
end, false)

-- ---------- cleanup ----------
AddEventHandler('playerDropped', function()
    busy[source] = nil
end)
