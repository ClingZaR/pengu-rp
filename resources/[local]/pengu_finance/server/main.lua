-- PenguRP Finance (pengu_finance) - SERVER.
-- 1) CREDIT SCORE: pengu_credit row per citizen (default 600, clamped 300-850). Moves:
--    +5 on-time loan installment, -25 missed installment, +2 to a business owner per
--    fully-paid payroll cycle. Updates are a single atomic UPSERT (no read-modify-write race).
-- 2) LOANS: pengu_loans. Tiers gated by credit score, ONE active loan per citizen.
--    Principal is paid to the bank FIRST (return-checked) and the DB row committed after;
--    if the insert fails the principal is clawed back. A 30-min thread charges the
--    installment from ONLINE borrowers only - offline borrowers accrue NOTHING and are
--    never charged or penalized while away (documented design choice: the timer only
--    exists while you play). 3 CONSECUTIVE misses = garnish mode: every subsequent pass
--    attempts a DOUBLE installment (the paycheck-garnish equivalent, implemented inside
--    this same thread); each successful double charge catches up one missed installment.
--    Missing never shrinks the debt - `remaining` only falls when money actually moves.
-- 3) INCOME TAX: the qbx_core paycheck deduction lives in a tagged "PenguRP edit" inside
--    [qbx]/qbx_core/server/loops.lua. THIS resource creates the 'government'
--    Renewed-Banking society account on boot so the deposit always has a destination.
--    Rate = GlobalState.penguTaxRate (pengu_gov owns setting it; default 0.05).
-- 4) BUSINESS PAYROLL: every 60 min, each owned pengu_businesses row pays its ONLINE
--    biz_ job holders a wage out of the business society account (removeAccountMoney ->
--    qbx AddMoney bank, return-checked with re-deposit rollback). Insufficient balance
--    skips that business and warns the owner if online. Owner credit +2 when everyone
--    online got paid.
-- Server-authoritative: every client event/callback re-validates; per-citizen busy locks
-- guard all money flows. ASCII only. luac clean.

local qbx = exports.qbx_core
local banking = exports['Renewed-Banking']

-- ===================== helpers =====================
local function notify(src, msg, kind)
    if not src or src <= 0 then print('[pengu_finance] ' .. tostring(msg)) return end
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Finance',
        description = msg,
        type = kind or 'inform',
        duration = 8000,
    })
end

local function getCid(src)
    local p = qbx:GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil, p
end

-- pcall wrapper around Renewed-Banking exports: (ok, value) -> value or nil on throw
local function bankCall(fn, ...)
    local args = { ... }
    local ok, res = pcall(function() return banking[fn](banking, table.unpack(args)) end)
    if not ok then
        print(('[pengu_finance] Renewed-Banking %s failed: %s'):format(fn, tostring(res)))
        return nil
    end
    return res
end

-- ===================== busy locks (one money flow per citizen at a time) =====================
local busy = {} -- citizenid -> true
local function lock(cid)
    if not cid or busy[cid] then return false end
    busy[cid] = true
    return true
end
local function unlock(cid) if cid then busy[cid] = nil end end

-- ===================== credit score =====================
local function getCredit(cid)
    local ok, score = pcall(MySQL.scalar.await, 'SELECT score FROM pengu_credit WHERE citizenid = ?', { cid })
    if ok and score ~= nil then return tonumber(score) or Config.creditDefault end
    -- no row yet (or read failed): seed the default. INSERT IGNORE keeps this idempotent.
    pcall(MySQL.insert.await,
        'INSERT IGNORE INTO pengu_credit (citizenid, score) VALUES (?, ?)', { cid, Config.creditDefault })
    return Config.creditDefault
end

-- Atomic clamped adjustment - one statement, safe against concurrent bumps.
local function bumpCredit(cid, delta)
    if not cid or not delta or delta == 0 then return end
    local seeded = math.max(Config.creditMin, math.min(Config.creditMax, Config.creditDefault + delta))
    local ok, err = pcall(MySQL.query.await, [[
        INSERT INTO pengu_credit (citizenid, score) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE score = LEAST(?, GREATEST(?, score + ?)), updated_at = CURRENT_TIMESTAMP
    ]], { cid, seeded, Config.creditMax, Config.creditMin, delta })
    if not ok then print('[pengu_finance] bumpCredit failed for ' .. tostring(cid) .. ': ' .. tostring(err)) end
end

-- ===================== loans: data =====================
local function getActiveLoan(cid)
    local ok, row = pcall(MySQL.single.await,
        "SELECT id, citizenid, principal, remaining, installment, interest_pct, missed, status, created_at " ..
        "FROM pengu_loans WHERE citizenid = ? AND status = 'active' LIMIT 1", { cid })
    if not ok then return nil end
    return row
end

local function eligibleTiers(score)
    local out = {}
    for i, t in ipairs(Config.loanTiers) do
        if score >= t.minScore then
            local total = math.floor(t.amount * (1 + t.interest))
            out[#out + 1] = {
                idx = i, amount = t.amount, interest = t.interest,
                total = total, installment = math.ceil(total / Config.loanInstallments),
            }
        end
    end
    return out
end

-- ===================== /credit + /loan commands (server-registered, client draws UI) =====================
RegisterCommand('credit', function(src)
    if not src or src <= 0 then return end
    local cid = getCid(src)
    if not cid then return end
    local score = getCredit(cid)
    local loan = getActiveLoan(cid)
    TriggerClientEvent('pengu_finance:showCredit', src, {
        score = score,
        loan = loan and {
            principal = loan.principal, remaining = loan.remaining,
            installment = loan.installment, missed = loan.missed,
            interest_pct = loan.interest_pct,
        } or nil,
    })
end, false)

local function cmdLoanApply(src, cid)
    if getActiveLoan(cid) then
        notify(src, 'You already have an active loan. Pay it off first (/loan status).', 'error')
        return
    end
    local score = getCredit(cid)
    local tiers = eligibleTiers(score)
    if #tiers == 0 then
        notify(src, ('Your credit score (%d) is too low for any loan. Minimum is %d.')
            :format(score, Config.loanTiers[1].minScore), 'error')
        return
    end
    TriggerClientEvent('pengu_finance:showLoanOffers', src, { score = score, tiers = tiers })
end

local function cmdLoanStatus(src, cid)
    local loan = getActiveLoan(cid)
    if not loan then
        notify(src, 'You have no active loan.', 'inform')
        return
    end
    TriggerClientEvent('pengu_finance:showLoanStatus', src, {
        principal = loan.principal, remaining = loan.remaining,
        installment = loan.installment, missed = loan.missed,
        interest_pct = loan.interest_pct, garnished = (tonumber(loan.missed) or 0) >= Config.garnishAfterMisses,
        intervalMin = math.floor(Config.loanIntervalMs / 60000),
    })
end

-- Early repayment. Server clamps to [1, remaining]; RemoveMoney return-checked; the DB
-- write is awaited and the money refunded if it fails.
local function payLoan(src, amount)
    local cid, p = getCid(src)
    if not cid or not p then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then
        notify(src, 'Enter a valid amount, e.g. /loan pay 500', 'error')
        return
    end
    if not lock(cid) then
        notify(src, 'Another transaction is in progress - try again in a moment.', 'error')
        return
    end
    local okFlow, errFlow = pcall(function()
        local loan = getActiveLoan(cid)
        if not loan then notify(src, 'You have no active loan.', 'error') return end
        local remaining = tonumber(loan.remaining) or 0
        if amount > remaining then amount = remaining end
        if amount < 1 then notify(src, 'Nothing left to pay.', 'inform') return end

        if not p.Functions.RemoveMoney('bank', amount, 'loan-early-repayment') then
            notify(src, ('You need $%d in the bank.'):format(amount), 'error')
            return
        end
        local newRemaining = remaining - amount
        local newStatus = newRemaining <= 0 and 'paid' or 'active'
        local okDb = pcall(MySQL.update.await,
            "UPDATE pengu_loans SET remaining = ?, status = ? WHERE id = ? AND status = 'active'",
            { math.max(0, newRemaining), newStatus, loan.id })
        if not okDb then
            -- refund: the payment was taken but never recorded
            if not p.Functions.AddMoney('bank', amount, 'loan-repayment-refund') then
                print(('[pengu_finance] CRITICAL: refund of $%d to %s failed after DB error'):format(amount, cid))
            end
            notify(src, 'Payment failed (database) - you were refunded.', 'error')
            return
        end
        if newStatus == 'paid' then
            notify(src, ('Loan PAID OFF! Final payment: $%d.'):format(amount), 'success')
        else
            notify(src, ('Paid $%d toward your loan. Remaining: $%d.'):format(amount, newRemaining), 'success')
        end
    end)
    unlock(cid)
    if not okFlow then print('[pengu_finance] payLoan error: ' .. tostring(errFlow)) end
end

RegisterCommand('loan', function(src, args)
    if not src or src <= 0 then return end
    local cid = getCid(src)
    if not cid then return end
    local sub = tostring(args[1] or ''):lower()
    if sub == 'apply' then
        cmdLoanApply(src, cid)
    elseif sub == 'pay' then
        if args[2] then
            payLoan(src, args[2])
        else
            local loan = getActiveLoan(cid)
            if not loan then notify(src, 'You have no active loan.', 'error') return end
            TriggerClientEvent('pengu_finance:promptPayAmount', src, tonumber(loan.remaining) or 0)
        end
    elseif sub == 'status' then
        cmdLoanStatus(src, cid)
    else
        notify(src, '/loan apply | /loan pay [amount] | /loan status', 'inform')
    end
end, false)

-- client picked a tier from the offers menu. UNTRUSTED: everything is re-validated here
-- (score, single active loan, tier index), inside the citizen's busy lock.
RegisterNetEvent('pengu_finance:applyLoan', function(tierIdx)
    local src = source
    local cid, p = getCid(src)
    if not cid or not p then return end
    local tier = Config.loanTiers[math.floor(tonumber(tierIdx) or -1)]
    if not tier then return end
    if not lock(cid) then
        notify(src, 'Another transaction is in progress - try again in a moment.', 'error')
        return
    end
    local okFlow, errFlow = pcall(function()
        if getActiveLoan(cid) then
            notify(src, 'You already have an active loan.', 'error')
            return
        end
        local score = getCredit(cid)
        if score < tier.minScore then
            notify(src, ('Your credit score (%d) does not qualify for that loan.'):format(score), 'error')
            return
        end
        local total = math.floor(tier.amount * (1 + tier.interest))
        local installment = math.ceil(total / Config.loanInstallments)

        -- principal FIRST (return-checked), row committed only after it landed
        if not p.Functions.AddMoney('bank', tier.amount, 'loan-principal') then
            notify(src, 'The bank could not deposit your loan. Try again.', 'error')
            return
        end
        local okDb, insertId = pcall(MySQL.insert.await, [[
            INSERT INTO pengu_loans (citizenid, principal, remaining, installment, interest_pct, missed, status)
            VALUES (?, ?, ?, ?, ?, 0, 'active')
        ]], { cid, tier.amount, total, installment, tier.interest * 100 })
        if not okDb or not insertId then
            -- claw the principal back: no recorded loan means no free money
            if not p.Functions.RemoveMoney('bank', tier.amount, 'loan-rollback') then
                print(('[pengu_finance] CRITICAL: loan rollback of $%d from %s failed'):format(tier.amount, cid))
            end
            notify(src, 'Loan failed (database) - the deposit was reversed.', 'error')
            return
        end
        notify(src, ('Loan approved! $%d deposited. You owe $%d in %d installments of $%d, charged every %d min while you are online.')
            :format(tier.amount, total, Config.loanInstallments, installment,
                math.floor(Config.loanIntervalMs / 60000)), 'success')
    end)
    unlock(cid)
    if not okFlow then print('[pengu_finance] applyLoan error: ' .. tostring(errFlow)) end
end)

-- client typed an amount into the pay dialog. UNTRUSTED: payLoan clamps and re-validates.
RegisterNetEvent('pengu_finance:payLoanAmount', function(amount)
    payLoan(source, amount)
end)

-- ===================== loan installment collection (every 30 min, ONLINE only) =====================
-- Design note: ONLY online borrowers are charged. Offline borrowers accrue nothing - no
-- installments, no misses, no interest growth. The clock on a loan effectively only ticks
-- while the borrower plays, so nobody logs back in to a wrecked score.
--
-- Garnish semantics: `missed` counts consecutive missed installments. At 3+ the borrower is
-- garnished: each pass attempts installment * 2 (this is the "50% of your paycheck" bite,
-- implemented in this thread as a double charge). Each successful double charge catches up
-- one arrear (missed - 1). A successful NORMAL charge (below the garnish threshold) resets
-- the consecutive-miss streak to 0. The debt itself never shrinks from missing - `remaining`
-- only moves when a charge actually lands.
local function collectFrom(src, p, cid)
    local loan = getActiveLoan(cid)
    if not loan then return end
    if not lock(cid) then return end -- player mid-transaction; catch them next pass
    local okFlow, errFlow = pcall(function()
        local remaining = tonumber(loan.remaining) or 0
        local installment = tonumber(loan.installment) or 0
        local missed = tonumber(loan.missed) or 0
        if remaining <= 0 or installment <= 0 then
            pcall(MySQL.update.await, "UPDATE pengu_loans SET status = 'paid' WHERE id = ?", { loan.id })
            return
        end
        local garnishing = missed >= Config.garnishAfterMisses
        local charge = installment * (garnishing and Config.garnishMultiplier or 1)
        if charge > remaining then charge = remaining end

        if p.Functions.RemoveMoney('bank', charge, garnishing and 'loan-garnish' or 'loan-installment') then
            local newRemaining = remaining - charge
            local newMissed = garnishing and math.max(0, missed - 1) or 0
            local newStatus = newRemaining <= 0 and 'paid' or 'active'
            local okDb = pcall(MySQL.update.await,
                'UPDATE pengu_loans SET remaining = ?, missed = ?, status = ? WHERE id = ?',
                { math.max(0, newRemaining), newMissed, newStatus, loan.id })
            if not okDb then
                -- unrecorded charge: give it back rather than double-bill next pass
                if not p.Functions.AddMoney('bank', charge, 'loan-installment-refund') then
                    print(('[pengu_finance] CRITICAL: installment refund of $%d to %s failed'):format(charge, cid))
                end
                return
            end
            bumpCredit(cid, Config.creditOnTime)
            if newStatus == 'paid' then
                notify(src, ('Final loan payment of $%d collected. Loan PAID OFF!'):format(charge), 'success')
            elseif garnishing then
                notify(src, ('WAGE GARNISH: $%d seized (double installment). Remaining: $%d. Missed payments left to catch up: %d.')
                    :format(charge, newRemaining, newMissed), 'error')
            else
                notify(src, ('Loan installment of $%d collected. Remaining: $%d.'):format(charge, newRemaining), 'inform')
            end
        else
            local newMissed = missed + 1
            local okDb = pcall(MySQL.update.await,
                'UPDATE pengu_loans SET missed = ? WHERE id = ?', { newMissed, loan.id })
            if okDb then
                bumpCredit(cid, Config.creditMissed)
                if newMissed >= Config.garnishAfterMisses then
                    notify(src, ('MISSED loan installment of $%d (%d in a row). Your wages are now GARNISHED - double installments will be seized. Credit %d.')
                        :format(charge, newMissed, Config.creditMissed), 'error')
                else
                    notify(src, ('MISSED loan installment of $%d. Credit %d. %d more consecutive misses and your wages get garnished.')
                        :format(charge, Config.creditMissed, Config.garnishAfterMisses - newMissed), 'error')
                end
            end
        end
    end)
    unlock(cid)
    if not okFlow then print('[pengu_finance] collect error for ' .. tostring(cid) .. ': ' .. tostring(errFlow)) end
end

CreateThread(function()
    Wait(Config.loanIntervalMs) -- skip first tick (let DB/boot settle; nobody is charged at startup)
    while true do
        for _, pid in ipairs(GetPlayers()) do
            local src = tonumber(pid)
            local p = src and qbx:GetPlayer(src)
            if p and p.PlayerData and p.PlayerData.citizenid then
                collectFrom(src, p, p.PlayerData.citizenid)
            end
        end
        Wait(Config.loanIntervalMs)
    end
end)

-- ===================== business payroll (every 60 min) =====================
-- For each OWNED pengu_businesses row: pay every ONLINE holder of its biz_ job a wage
-- from the business society account. Wage = the qbx job grade `payment` when the grade
-- defines one, else Config.payrollFallbackWage (pengu_business grades define none).
-- The owner holds the biz_ job too and is paid like anyone else - it is their money
-- moving from the business account to their pocket. Insufficient balance = the whole
-- business is skipped this cycle and the owner warned if online. Owner credit +2 only
-- when at least one employee was paid and NOBODY failed.
local function ownerSrc(ownerCid)
    local op = qbx:GetPlayerByCitizenId(ownerCid)
    return op and op.PlayerData and op.PlayerData.source or nil
end

local function runPayroll()
    local okQ, rows = pcall(MySQL.query.await,
        "SELECT job_key, label, owner_cid FROM pengu_businesses WHERE owner_cid IS NOT NULL AND owner_cid <> ''")
    if not okQ or type(rows) ~= 'table' then return end

    -- one pass over online players: biz job name -> list of player objects
    local roster = {}
    for _, pid in ipairs(GetPlayers()) do
        local sp = qbx:GetPlayer(tonumber(pid))
        local job = sp and sp.PlayerData and sp.PlayerData.job
        if job and job.name and job.name:sub(1, #Config.bizPrefix) == Config.bizPrefix then
            roster[job.name] = roster[job.name] or {}
            roster[job.name][#roster[job.name] + 1] = sp
        end
    end

    for _, biz in ipairs(rows) do
        local emps = roster[biz.job_key]
        if emps and #emps > 0 then
            local jobData = qbx:GetJob(biz.job_key)
            local paidCount, failed = 0, false
            for _, sp in ipairs(emps) do
                local lvl = sp.PlayerData.job.grade and tonumber(sp.PlayerData.job.grade.level) or 0
                local gradeWage = jobData and jobData.grades and jobData.grades[lvl]
                    and tonumber(jobData.grades[lvl].payment) or nil
                local wage = math.floor(gradeWage or Config.payrollFallbackWage)
                if wage > 0 then
                    local bal = bankCall('getAccountMoney', biz.job_key)
                    if type(bal) ~= 'number' or bal < wage then
                        failed = true
                        notify(ownerSrc(biz.owner_cid),
                            ('%s: the business account cannot cover payroll ($%d needed). Employees went unpaid.')
                                :format(biz.label or biz.job_key, wage), 'error')
                        break -- nothing left in the pot; skip the rest of this business
                    end
                    if bankCall('removeAccountMoney', biz.job_key, wage) == true then
                        if sp.Functions.AddMoney('bank', wage, 'business-payroll') then
                            paidCount = paidCount + 1
                            notify(sp.PlayerData.source,
                                ('Payday: $%d wage from %s.'):format(wage, biz.label or biz.job_key), 'success')
                        else
                            -- employee could not receive it: put the money back in the account
                            if bankCall('addAccountMoney', biz.job_key, wage) ~= true then
                                print(('[pengu_finance] CRITICAL: payroll rollback of $%d to %s failed')
                                    :format(wage, biz.job_key))
                            end
                            failed = true
                        end
                    else
                        failed = true
                    end
                end
            end
            if paidCount > 0 and not failed then
                bumpCredit(biz.owner_cid, Config.creditPayroll)
                notify(ownerSrc(biz.owner_cid),
                    ('%s: payroll paid to %d employee(s). Credit +%d.')
                        :format(biz.label or biz.job_key, paidCount, Config.creditPayroll), 'success')
            end
        end
    end
end

CreateThread(function()
    Wait(Config.payrollIntervalMs) -- skip first tick
    while true do
        local ok, err = pcall(runPayroll)
        if not ok then print('[pengu_finance] payroll error: ' .. tostring(err)) end
        Wait(Config.payrollIntervalMs)
    end
end)

-- ===================== boot =====================
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_credit (
                citizenid  VARCHAR(64) PRIMARY KEY,
                score      INT NOT NULL DEFAULT 600,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            )
        ]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_loans (
                id           INT AUTO_INCREMENT PRIMARY KEY,
                citizenid    VARCHAR(64) NOT NULL,
                principal    INT NOT NULL,
                remaining    INT NOT NULL,
                installment  INT NOT NULL,
                interest_pct FLOAT NOT NULL DEFAULT 0,
                missed       INT NOT NULL DEFAULT 0,
                created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                status       VARCHAR(16) NOT NULL DEFAULT 'active',
                INDEX idx_loans_cid (citizenid),
                INDEX idx_loans_status (status)
            )
        ]])
    end)
    if not ok then print('[pengu_finance] BOOT FAILED (db): ' .. tostring(err)) end
    -- the 'government' society account income tax gets deposited into (qbx_core loops.lua
    -- "PenguRP edit"). CreateJobAccount returns the cached account if it already exists.
    local okGov = pcall(function()
        banking:CreateJobAccount({ name = Config.govAccount, label = Config.govLabel }, 0)
    end)
    if not okGov then print('[pengu_finance] WARNING: could not ensure the government bank account') end
    print(('[pengu_finance] %s.'):format(ok and 'ready' or 'DEGRADED'))
end)
