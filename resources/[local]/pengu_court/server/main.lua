-- PenguRP Court Sessions (pengu_court) - SERVER.
-- Judge-run trials against defendants with outstanding pengu_mdt_charges rows.
-- Guilty verdicts jail via xt-prison JailPlayerById (caps at 60), record a
-- pengu_mdt_imprisonments conviction row (officer = the court, plea = the
-- defendant's plea), flip the outstanding rows to 'processed' stamped with that
-- case id (same semantics as pengu_mdt /jail, so the MDT rap sheet shows the
-- outcome), then force the fine from bank LAST. Not-guilty clears the rows with
-- no penalty and NO imprisonment row - acquittals are not convictions.
-- Verdict execution is pcall-guarded: a DB/export fault unlocks the session so
-- the judge can retry; /courtend can override a lock older than 60s.
-- One active session max, replicated via GlobalState.penguCourtSession.
-- Optional jury: random online non-LEO citizens vote; majority decides, ties acquit.
-- ASCII only. luac clean.

local qbx = exports.qbx_core

----------------------------------------------------------------------
-- SQL (charge queries mirror pengu_mdt's; the UPDATE is its exact semantics)
----------------------------------------------------------------------

local SUM_OUTSTANDING_SQL = [[
SELECT
  COALESCE(SUM(months),0) AS months,
  COALESCE(SUM(fine),0)   AS fine,
  COUNT(*)                AS charges
FROM pengu_mdt_charges
WHERE citizenid = ? AND status = 'outstanding'
]]

local DOCKET_SQL = [[
SELECT citizenid,
  COUNT(*)                AS charges,
  COALESCE(SUM(months),0) AS months,
  COALESCE(SUM(fine),0)   AS fine
FROM pengu_mdt_charges
WHERE status = 'outstanding'
GROUP BY citizenid
]]

-- Acquittal flip (no case link): clears the person from outstanding + warrants
-- while leaving case_id = 0, so the rap sheet shows NO conviction/plea for them.
local MARK_PROCESSED_SQL = [[
UPDATE pengu_mdt_charges SET status = 'processed'
WHERE citizenid = ? AND status = 'outstanding'
]]

-- Conviction path - the exact pengu_mdt /jail semantics: record the imprisonment
-- (rap-sheet case row), then flip the rows AND stamp the case id so the MDT
-- Person tab joins plea/outcome per charge (HISTORY_FOR_PERSON_SQL in pengu_mdt).
local INSERT_IMPRISONMENT_SQL = [[
INSERT INTO pengu_mdt_imprisonments (citizenid, officer, months, fine, charges, plea, charge_list)
VALUES (?, ?, ?, ?, ?, ?, ?)
]]

local MARK_PROCESSED_CASE_SQL = [[
UPDATE pengu_mdt_charges SET status = 'processed', case_id = ?
WHERE citizenid = ? AND status = 'outstanding'
]]

-- Charge titles for the imprisonment's charge_list (captured BEFORE the flip).
local OUTSTANDING_TITLES_SQL = [[
SELECT title FROM pengu_mdt_charges
WHERE citizenid = ? AND status = 'outstanding'
ORDER BY created_at DESC
]]

local LOG_SQL = [[
INSERT INTO pengu_court_log (defendant_cid, judge_cid, verdict, months, fine)
VALUES (?, ?, ?, ?, ?)
]]

CreateThread(function()
    MySQL.query.await([[
CREATE TABLE IF NOT EXISTS pengu_court_log (
  id INT AUTO_INCREMENT PRIMARY KEY,
  defendant_cid VARCHAR(64) NOT NULL,
  judge_cid VARCHAR(64) DEFAULT '',
  verdict VARCHAR(16) DEFAULT '',
  months INT DEFAULT 0,
  fine INT DEFAULT 0,
  ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_court_cid (defendant_cid)
)
]])
    GlobalState.penguCourtSession = false
end)

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function chat(src, msg, kind)
    if not src or src <= 0 then print('[pengu_court] ' .. tostring(msg)) return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { 'COURT', msg, KIND[kind or 'inform'] or 'info' },
    })
end

local function toast(src, msg, ntype)
    if not src or src <= 0 then return end
    TriggerClientEvent('ox_lib:notify', src, { title = 'Court', description = msg, type = ntype or 'inform' })
end

local function fullName(ci)
    ci = ci or {}
    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return 'Unknown' end
    return name
end

-- Judge gate: job 'judge' (qbx_core/shared/jobs.lua), on duty (defaultDuty = true).
local function getJudge(src)
    local p = qbx:GetPlayer(src)
    if not p or not p.PlayerData then return nil end
    local job = p.PlayerData.job
    if not job or job.name ~= 'judge' or not job.onduty then return nil end
    return p
end

local function getLawyer(src)
    local p = qbx:GetPlayer(src)
    if not p or not p.PlayerData then return nil end
    local job = p.PlayerData.job
    if not job or job.name ~= 'lawyer' or not job.onduty then return nil end
    return p
end

----------------------------------------------------------------------
-- Session state (one active session max; token invalidates stale timers)
----------------------------------------------------------------------

local session = nil
local token = 0

local seatJury, finalizeJuryVote -- forward declarations

local function publishSession()
    if session then
        GlobalState.penguCourtSession = {
            defendant = session.defName,
            judge = session.judgeName,
            stage = session.stage,
        }
    else
        GlobalState.penguCourtSession = false
    end
end

-- judge + defendant + seated jurors + anyone still holding a summons
local function sessionParticipants()
    local list, seen = {}, {}
    if not session then return list end
    local function add(src)
        if src and src > 0 and not seen[src] then seen[src] = true; list[#list + 1] = src end
    end
    add(session.judgeSrc)
    add(session.defSrc)
    if session.jury then
        for src in pairs(session.jury.jurors) do add(src) end
        for src in pairs(session.jury.invited) do add(src) end
    end
    return list
end

local function clearSession(reason, ntype)
    if not session then return end
    token = token + 1
    local parts = sessionParticipants()
    session = nil
    publishSession()
    if reason then
        for _, src in ipairs(parts) do toast(src, reason, ntype or 'inform') end
    end
end

----------------------------------------------------------------------
-- Verdict execution (shared by /verdict guilty|notguilty and the jury tally)
----------------------------------------------------------------------

-- Body of the verdict pipeline. Runs with s.locked already set and is ALWAYS
-- invoked via pcall from executeVerdict: any DB/export error here is caught
-- there, which unlocks the session (never a permanent lock) and tells the
-- judge to retry. Early returns that unlock themselves are fine too.
local function runVerdictLocked(s, verdict, judgePct)
    local def = qbx:GetPlayer(s.defSrc)
    if not def or not def.PlayerData or def.PlayerData.citizenid ~= s.defCid then
        chat(s.judgeSrc, 'Defendant is no longer available. Session aborted, nothing processed.', 'err')
        if session == s then clearSession('Court session aborted.', 'error') end
        return
    end

    -- Re-sum at execution (mdt /jail semantics): charges placed mid-session count,
    -- and if someone else already processed the person there is nothing to rule on.
    local sums = MySQL.single.await(SUM_OUTSTANDING_SQL, { s.defCid })
    local months = sums and tonumber(sums.months) or 0
    local fine = sums and tonumber(sums.fine) or 0
    local charges = sums and tonumber(sums.charges) or 0
    if charges == 0 then
        chat(s.judgeSrc, 'The defendant no longer has outstanding charges. Session closed.', 'err')
        if session == s then clearSession('Court session closed: no outstanding charges remain.', 'inform') end
        return
    end

    if verdict == 'notguilty' then
        -- Acquittal: clear the rows WITHOUT an imprisonment row (case_id stays 0),
        -- so the MDT rap sheet never shows an acquittal as a conviction.
        MySQL.update.await(MARK_PROCESSED_SQL, { s.defCid })
        MySQL.insert.await(LOG_SQL, { s.defCid, s.judgeCid, 'notguilty', 0, 0 })
        -- charges are gone, so the wanted level derived from them clears too (mdt /jail parity)
        pcall(function() exports.pengu_mdt:SetWantedLevel(s.defCid, 0, 'court acquittal') end)
        chat(s.judgeSrc, ('Verdict: NOT GUILTY. %s acquitted, %d charge(s) cleared.'):format(s.defName, charges), 'ok')
        toast(s.defSrc, 'Verdict: NOT GUILTY. You are acquitted and your charges are cleared.', 'success')
        if session == s and s.jury then
            for src in pairs(s.jury.jurors) do
                toast(src, ('Verdict delivered: %s found NOT GUILTY. Jury dismissed.'):format(s.defName), 'inform')
            end
        end
        if session == s then clearSession(nil) end
        return
    end

    -- GUILTY: plea cut first, then any judge-ordered percentage, capped at maxSentence.
    if s.plea == 'guilty' then
        months = months - math.floor(months * Config.pleaReduction)
    end
    judgePct = tonumber(judgePct) or 0
    if judgePct < 0 then judgePct = 0 elseif judgePct > 100 then judgePct = 100 end
    if judgePct > 0 then
        months = months - math.floor(months * (judgePct / 100))
    end
    if months < 0 then months = 0 end
    local served = math.min(months, Config.maxSentence)

    -- Jail first (mdt /jail order); if this fails nothing has been processed.
    -- pcall'd explicitly so an export fault (resource stopped, script error)
    -- unlocks the session instead of leaving it stuck.
    if served > 0 then
        local okJail, jailed = pcall(function()
            return exports['xt-prison']:JailPlayerById(s.defSrc, served)
        end)
        if not okJail then
            s.locked = false
            s.stage = 'arguments'
            publishSession()
            chat(s.judgeSrc, 'Court systems failed - verdict not executed, try again.', 'err')
            return
        end
        if not jailed then
            s.locked = false
            s.stage = 'arguments'
            publishSession()
            chat(s.judgeSrc, 'Could not jail the defendant. Nothing was processed; retry or /courtend.', 'err')
            return
        end
    end

    -- Rap sheet (mirrors pengu_mdt /jail): capture the charge titles BEFORE the
    -- flip, record the conviction as an imprisonment row (officer = the court,
    -- plea = the defendant's plea in mdt vocabulary), then stamp its id onto the
    -- processed rows so the MDT Person tab shows plea/outcome per charge.
    local chargeRows = MySQL.query.await(OUTSTANDING_TITLES_SQL, { s.defCid }) or {}
    local titles = {}
    for _, r in ipairs(chargeRows) do titles[#titles + 1] = r.title end
    local mdtPlea = (s.plea == 'guilty') and 'guilty' or 'not_guilty'
    local caseId = MySQL.insert.await(INSERT_IMPRISONMENT_SQL, {
        s.defCid, 'Court: ' .. s.judgeName, served, fine, charges, mdtPlea, table.concat(titles, ', '),
    })
    MySQL.update.await(MARK_PROCESSED_CASE_SQL, { caseId or 0, s.defCid })
    MySQL.insert.await(LOG_SQL, { s.defCid, s.judgeCid, 'guilty', served, fine })
    -- conviction processed: clear the wanted level like mdt /jail does
    pcall(function() exports.pengu_mdt:SetWantedLevel(s.defCid, 0, 'court conviction') end)

    -- Fine LAST, after the rows are processed: if a money move failed AFTER
    -- processing the defendant merely keeps $fine (lesser harm), whereas a fine
    -- taken BEFORE a failed UPDATE would leave them paid but still charged.
    -- Note: on this server dontAllowMinus covers cash only, so RemoveMoney('bank')
    -- never comes back short - it drives bank negative (a forced debt) and returns
    -- true. The failure branch below is defensive only; nothing to roll back.
    if fine > 0 then
        local paid = def.Functions and def.Functions.RemoveMoney
            and def.Functions.RemoveMoney('bank', fine, 'court-fine')
        if not paid then
            chat(s.judgeSrc, ('Defendant could not pay the $%d fine.'):format(fine), 'err')
        end
    end

    chat(s.judgeSrc, ('Verdict: GUILTY. %s - %d charge(s) processed, %d min, $%d fined.'):format(
        s.defName, charges, served, fine), 'ok')
    toast(s.defSrc, ('Verdict: GUILTY. Sentence: %d minute(s), $%d fine.'):format(served, fine), 'error')
    if session == s and s.jury then
        for src in pairs(s.jury.jurors) do
            toast(src, ('Verdict delivered: %s found GUILTY. Jury dismissed.'):format(s.defName), 'inform')
        end
    end
    if session == s then clearSession(nil) end
end

local function executeVerdict(verdict, judgePct)
    local s = session
    if not s or s.locked then return end
    s.locked = true -- blocks /courtend + a second /verdict while the awaits run
    s.lockAt = os.time() -- lets /courtend override a lock stuck for over 60s
    s.stage = 'verdict'
    publishSession()

    -- pcall guard: MySQL awaits (and anything else in the pipeline) can raise on
    -- a DB fault. Without this the session would stay locked forever, bricking
    -- /verdict AND /courtend. On failure: unlock, keep the session intact (no
    -- clearSession - nothing was necessarily processed), and tell the judge.
    local ok, err = pcall(runVerdictLocked, s, verdict, judgePct)
    if not ok then
        print(('[pengu_court] verdict pipeline error: %s'):format(tostring(err)))
        if session == s then
            s.locked = false
            s.stage = 'arguments'
            publishSession()
            chat(s.judgeSrc, 'Court systems failed - verdict not executed, try again.', 'err')
        end
    end
end

----------------------------------------------------------------------
-- /docket - online citizens with outstanding charges (judge only)
----------------------------------------------------------------------

RegisterCommand('docket', function(source)
    if not getJudge(source) then chat(source, 'Judges only.', 'err') return end
    local rows = MySQL.query.await(DOCKET_SQL) or {}
    local entries = {}
    for _, r in ipairs(rows) do
        local p = qbx:GetPlayerByCitizenId(r.citizenid) -- online only
        if p and p.PlayerData then
            entries[#entries + 1] = {
                id = p.PlayerData.source,
                name = fullName(p.PlayerData.charinfo),
                charges = tonumber(r.charges) or 0,
                months = tonumber(r.months) or 0,
                fine = tonumber(r.fine) or 0,
            }
        end
    end
    if #entries == 0 then
        chat(source, 'No online citizens have outstanding charges.', 'info')
        return
    end
    table.sort(entries, function(a, b) return a.months > b.months end)
    TriggerClientEvent('pengu_court:showDocket', source, entries)
end, false)

----------------------------------------------------------------------
-- /courtstart [id] - open a session against an online defendant
----------------------------------------------------------------------

RegisterCommand('courtstart', function(source, args)
    local judge = getJudge(source)
    if not judge then chat(source, 'Judges only.', 'err') return end
    if session then chat(source, 'A court session is already in progress.', 'err') return end
    local id = tonumber(args and args[1])
    if not id then chat(source, 'Usage: /courtstart [player id] (see /docket)', 'err') return end
    if id == source then chat(source, 'You cannot preside over your own trial.', 'err') return end
    local target = qbx:GetPlayer(id)
    if not target or not target.PlayerData then chat(source, 'Invalid player id.', 'err') return end
    local cid = target.PlayerData.citizenid

    local sums = MySQL.single.await(SUM_OUTSTANDING_SQL, { cid })
    local charges = sums and tonumber(sums.charges) or 0
    if charges == 0 then chat(source, 'That citizen has no outstanding charges.', 'err') return end
    if session then chat(source, 'A court session is already in progress.', 'err') return end -- re-check post-await

    token = token + 1
    session = {
        judgeSrc = source,
        judgeCid = judge.PlayerData.citizenid,
        judgeName = fullName(judge.PlayerData.charinfo),
        defSrc = target.PlayerData.source,
        defCid = cid,
        defName = fullName(target.PlayerData.charinfo),
        stage = 'plea',
        plea = nil,
        charges = charges,
        months = tonumber(sums.months) or 0,
        fine = tonumber(sums.fine) or 0,
        jury = nil,
        locked = false,
        lockAt = 0, -- os.time() of the last lock; /courtend can override after 60s
    }
    publishSession()

    chat(source, ('Session opened: %s - %d charge(s), %d month(s), $%d fine. Awaiting plea.'):format(
        session.defName, charges, session.months, session.fine), 'ok')
    toast(session.defSrc, ('Judge %s has called you before the court. Enter your plea.'):format(session.judgeName), 'inform')
    TriggerClientEvent('pengu_court:pleaPrompt', session.defSrc, {
        judge = session.judgeName,
        charges = charges,
        months = session.months,
        fine = session.fine,
        pct = math.floor(Config.pleaReduction * 100),
    })
end, false)

----------------------------------------------------------------------
-- Plea (defendant only, plea stage only) -> arguments stage
----------------------------------------------------------------------

RegisterNetEvent('pengu_court:submitPlea', function(plea)
    local src = source
    if not session or session.stage ~= 'plea' or src ~= session.defSrc then return end
    if plea ~= 'guilty' and plea ~= 'notguilty' then return end
    session.plea = plea
    session.stage = 'arguments'
    publishSession()
    local pct = math.floor(Config.pleaReduction * 100)
    if plea == 'guilty' then
        chat(session.judgeSrc, ('%s pleads GUILTY (%d%% sentence cut applies on conviction). Arguments may begin.'):format(session.defName, pct), 'info')
        toast(src, ('Guilty plea entered (%d%% sentence reduction). The court proceeds to arguments.'):format(pct), 'inform')
    else
        chat(session.judgeSrc, ('%s pleads NOT GUILTY. Arguments may begin; rule with /verdict.'):format(session.defName), 'info')
        toast(src, 'Not-guilty plea entered. The court proceeds to arguments.', 'inform')
    end
end)

-- Re-offer the plea dialog if the defendant lost it (other UI open, etc.).
RegisterCommand('courtplea', function(source)
    if not session or session.stage ~= 'plea' or source ~= session.defSrc then
        chat(source, 'You have no pending plea.', 'err')
        return
    end
    TriggerClientEvent('pengu_court:pleaPrompt', source, {
        judge = session.judgeName,
        charges = session.charges,
        months = session.months,
        fine = session.fine,
        pct = math.floor(Config.pleaReduction * 100),
    })
end, false)

----------------------------------------------------------------------
-- Jury: /jury summons, seating, deliberation
----------------------------------------------------------------------

seatJury = function()
    local j = session and session.jury
    if not j or j.closedInvites then return end
    j.closedInvites = true
    local count = 0
    for _ in pairs(j.jurors) do count = count + 1 end
    if count < Config.jury.min then
        for src in pairs(j.jurors) do toast(src, 'The jury could not be seated. You are dismissed.', 'inform') end
        session.jury = nil
        chat(session.judgeSrc, ('Jury unavailable: %d of %d needed accepted. Rule yourself or retry /jury.'):format(count, Config.jury.min), 'err')
        return
    end
    j.seated = true
    for src in pairs(j.jurors) do toast(src, 'You are seated on the jury. Await the call to deliberate.', 'success') end
    chat(session.judgeSrc, ('Jury seated with %d juror(s). Use /verdict jury when arguments conclude.'):format(count), 'ok')
end

RegisterCommand('jury', function(source)
    local judge = getJudge(source)
    if not judge then chat(source, 'Judges only.', 'err') return end
    if not Config.jury.enabled then chat(source, 'Jury trials are disabled.', 'err') return end
    if not session or session.judgeSrc ~= source then chat(source, 'You have no active court session.', 'err') return end
    if session.stage == 'plea' then chat(source, 'Wait for the plea before summoning a jury.', 'err') return end
    if session.jury then chat(source, 'A jury has already been summoned this session.', 'err') return end

    local cands = {}
    for psrc, p in pairs(qbx:GetQBPlayers() or {}) do
        psrc = tonumber(psrc)
        local pd = p and p.PlayerData
        local job = pd and pd.job
        local jn = job and job.name or ''
        if psrc and pd and psrc ~= session.judgeSrc and psrc ~= session.defSrc
            and (not job or job.type ~= 'leo') and jn ~= 'judge' and jn ~= 'lawyer' then
            cands[#cands + 1] = psrc
        end
    end
    if #cands < Config.jury.min then
        chat(source, ('Not enough eligible citizens online for a jury (%d needed).'):format(Config.jury.min), 'err')
        return
    end
    for i = #cands, 2, -1 do
        local k = math.random(i)
        cands[i], cands[k] = cands[k], cands[i]
    end

    local j = { invited = {}, pending = 0, jurors = {}, votes = {}, seated = false, voting = false, done = false, closedInvites = false, expected = 0 }
    session.jury = j
    local n = math.min(Config.jury.size, #cands)
    for i = 1, n do
        local jsrc = cands[i]
        j.invited[jsrc] = true
        j.pending = j.pending + 1
        TriggerClientEvent('pengu_court:juryInvite', jsrc, { judge = session.judgeName })
    end
    chat(source, ('Jury summons sent to %d citizen(s). Waiting for responses...'):format(n), 'info')

    local myToken = token
    SetTimeout(Config.jury.inviteTimeout, function()
        if token == myToken and session and session.jury == j and not j.closedInvites then
            seatJury()
        end
    end)
end, false)

RegisterNetEvent('pengu_court:juryReply', function(accept)
    local src = source
    local j = session and session.jury
    if not j or j.closedInvites or not j.invited[src] then return end
    j.invited[src] = nil -- one reply per summons
    j.pending = j.pending - 1
    if accept == true then
        local count = 0
        for _ in pairs(j.jurors) do count = count + 1 end
        if count < Config.jury.size then
            j.jurors[src] = true
            toast(src, 'Summons accepted. You may be called to deliberate.', 'success')
        end
    end
    if j.pending <= 0 then seatJury() end
end)

finalizeJuryVote = function()
    local j = session and session.jury
    if not j or not j.voting then return end
    j.voting = false
    j.done = true
    local g, ng = 0, 0
    for _, v in pairs(j.votes) do
        if v == 'guilty' then g = g + 1 else ng = ng + 1 end
    end
    -- Majority decides; ties (and no votes) acquit. Timed-out jurors are simply excluded.
    local verdict = (g > ng) and 'guilty' or 'notguilty'
    chat(session.judgeSrc, ('Jury verdict: %s (%d guilty / %d not guilty, %d excluded).'):format(
        verdict == 'guilty' and 'GUILTY' or 'NOT GUILTY', g, ng, math.max(0, j.expected - g - ng)), 'info')
    executeVerdict(verdict, 0)
end

local function startJuryVote()
    local j = session.jury
    j.voting = true
    session.stage = 'verdict'
    publishSession()
    j.expected = 0
    for src in pairs(j.jurors) do
        j.expected = j.expected + 1
        TriggerClientEvent('pengu_court:juryVotePrompt', src, { defendant = session.defName })
    end
    chat(session.judgeSrc, ('The jury (%d) is deliberating. Verdict within %d seconds.'):format(
        j.expected, math.floor(Config.jury.voteTimeout / 1000)), 'info')
    toast(session.defSrc, 'The jury is deliberating your verdict.', 'inform')
    local myToken = token
    SetTimeout(Config.jury.voteTimeout, function()
        if token == myToken and session and session.jury == j and j.voting then
            finalizeJuryVote()
        end
    end)
end

RegisterNetEvent('pengu_court:juryVote', function(vote)
    local src = source
    local j = session and session.jury
    if not j or not j.voting or not j.jurors[src] or j.votes[src] then return end
    if vote ~= 'guilty' and vote ~= 'notguilty' then return end
    j.votes[src] = vote
    local p = qbx:GetPlayer(src)
    if p and p.Functions and p.Functions.AddMoney
        and p.Functions.AddMoney('bank', Config.jury.pay, 'jury-duty') then
        toast(src, ('Vote recorded. $%d jury pay deposited to your bank.'):format(Config.jury.pay), 'success')
    else
        toast(src, 'Vote recorded.', 'success')
    end
    local cast = 0
    for _ in pairs(j.votes) do cast = cast + 1 end
    if cast >= j.expected then finalizeJuryVote() end
end)

----------------------------------------------------------------------
-- /verdict guilty [pct] | notguilty | jury (presiding judge only)
----------------------------------------------------------------------

RegisterCommand('verdict', function(source, args)
    if not getJudge(source) then chat(source, 'Judges only.', 'err') return end
    if not session or session.judgeSrc ~= source then chat(source, 'You have no active court session.', 'err') return end
    if session.locked then chat(source, 'The verdict is already being processed.', 'err') return end
    if session.stage == 'plea' then chat(source, 'Waiting on the defendant\'s plea (/courtplea re-offers it).', 'err') return end
    if session.jury and session.jury.voting then chat(source, 'The jury is deliberating; await their verdict.', 'err') return end

    local mode = (args and args[1] or ''):lower()
    if mode == 'guilty' then
        local pct = tonumber(args[2]) or 0
        executeVerdict('guilty', pct)
    elseif mode == 'notguilty' then
        executeVerdict('notguilty')
    elseif mode == 'jury' then
        if not Config.jury.enabled then chat(source, 'Jury trials are disabled.', 'err') return end
        local j = session.jury
        if not j or not j.seated then chat(source, 'No jury is seated. Summon one with /jury first.', 'err') return end
        if j.done then chat(source, 'The jury already returned a verdict.', 'err') return end
        startJuryVote()
    else
        chat(source, 'Usage: /verdict guilty [reduction pct] | notguilty | jury', 'err')
    end
end, false)

----------------------------------------------------------------------
-- /objection (lawyer, arguments stage) - RP flavor to all participants
----------------------------------------------------------------------

RegisterCommand('objection', function(source)
    local lawyer = getLawyer(source)
    if not lawyer then chat(source, 'Lawyers only.', 'err') return end
    if not session then chat(source, 'There is no court session in progress.', 'err') return end
    if session.stage ~= 'arguments' then chat(source, 'You can only object during arguments.', 'err') return end
    local line = ('%s: OBJECTION!'):format(fullName(lawyer.PlayerData.charinfo))
    local sent = {}
    local function say(src)
        if src and src > 0 and not sent[src] then sent[src] = true; chat(src, line, 'info') end
    end
    say(source)
    for _, src in ipairs(sessionParticipants()) do say(src) end
end, false)

----------------------------------------------------------------------
-- /courtend - abort, nothing processed
----------------------------------------------------------------------

RegisterCommand('courtend', function(source)
    if not getJudge(source) then chat(source, 'Judges only.', 'err') return end
    if not session then chat(source, 'There is no court session in progress.', 'err') return end
    if session.judgeSrc ~= source then chat(source, 'Only the presiding judge can end the session.', 'err') return end
    if session.locked then
        -- Escape hatch: a healthy verdict pipeline finishes (or unlocks itself)
        -- in seconds. A lock older than 60s means it died mid-flight, so let the
        -- judge close the session manually - a stuck trial must never need a
        -- resource restart.
        local age = os.time() - (session.lockAt or 0)
        if age < 60 then
            chat(source, 'The verdict is already being processed.', 'err')
            return
        end
        chat(source, ('Overriding a stale verdict lock (%ds old).'):format(age), 'info')
    end
    chat(source, 'Session ended. Nothing was processed.', 'ok')
    clearSession('Court session ended by the judge. Nothing was processed.', 'inform')
end, false)

----------------------------------------------------------------------
-- Disconnect handling: judge/defendant drop aborts; jurors are excused
----------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source
    if not session then return end
    if src == session.judgeSrc then
        clearSession('The judge left the city. Court session aborted; nothing was processed.', 'error')
        return
    end
    if src == session.defSrc then
        clearSession('The defendant left the city. Session aborted; nothing was processed.', 'error')
        return
    end
    local j = session.jury
    if not j then return end
    if j.invited[src] then
        j.invited[src] = nil
        j.pending = j.pending - 1
        if not j.closedInvites and j.pending <= 0 then seatJury() end
    end
    if j.jurors[src] and not j.votes[src] then
        j.jurors[src] = nil
        if j.voting then
            j.expected = j.expected - 1
            local cast = 0
            for _ in pairs(j.votes) do cast = cast + 1 end
            if cast >= j.expected then finalizeJuryVote() end
        elseif j.seated then
            local count = 0
            for _ in pairs(j.jurors) do count = count + 1 end
            if count < Config.jury.min then
                for jsrc in pairs(j.jurors) do toast(jsrc, 'The jury lost too many members and is dismissed.', 'inform') end
                session.jury = nil
                chat(session.judgeSrc, 'The jury lost too many members and was dismissed. Rule yourself or retry /jury.', 'err')
            end
        end
    end
end)
