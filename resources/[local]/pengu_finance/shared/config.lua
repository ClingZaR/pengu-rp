-- PenguRP - Finance (pengu_finance) CONFIG. Phase: economy.
-- Four systems in one resource: CREDIT SCORE (pengu_credit), LOANS (pengu_loans),
-- INCOME TAX (deposited to the 'government' Renewed-Banking society account; the RATE itself
-- lives in GlobalState.penguTaxRate and is owned by pengu_gov - we only read it), and
-- BUSINESS PAYROLL (pengu_business society accounts -> online employees' banks).
-- `Config` is per-resource global. ASCII only.

Config = {}

-- ===================== credit score =====================
Config.creditDefault = 600 -- starting score for a citizen with no pengu_credit row
Config.creditMin     = 300 -- hard clamp floor
Config.creditMax     = 850 -- hard clamp ceiling
Config.creditOnTime  = 5   -- + per on-time loan installment paid
Config.creditMissed  = -25 -- per missed loan installment
Config.creditPayroll = 2   -- + to the OWNER per fully-paid business payroll cycle

-- ===================== loans =====================
-- Tiers gated by credit score. A player is offered every tier whose minScore they meet.
-- total owed = amount * (1 + interest); installment = ceil(total / loanInstallments).
Config.loanTiers = {
    { minScore = 500, amount = 10000,  interest = 0.08 },
    { minScore = 600, amount = 25000,  interest = 0.06 },
    { minScore = 700, amount = 50000,  interest = 0.05 },
    { minScore = 750, amount = 100000, interest = 0.04 },
}
Config.loanInstallments   = 20      -- repayment is split into this many installments
Config.loanIntervalMs     = 1800000 -- 30 min between installment collection passes
Config.garnishAfterMisses = 3       -- consecutive missed installments before garnish mode
Config.garnishMultiplier  = 2       -- garnish = installment * this (double charge to catch up)

-- ----- loan eligibility gates (defaults preserve legacy behavior: no gates) -----
Config.loanRequireJob     = false   -- true = players on the 'unemployed' job cannot take a loan
Config.loanMinPlaytimeMin = 0       -- RESERVED, NOT ENFORCED. There is no playtime source on
                                    -- this server to read (pengu_core/server/daily.lua only
                                    -- tracks login-day streaks, not minutes played), so ONLY
                                    -- the job gate above is implemented. This key exists so a
                                    -- future playtime tracker can be wired in without a config
                                    -- migration; any value here is currently ignored.

-- ===================== income tax =====================
Config.taxDefault = 0.05         -- used when GlobalState.penguTaxRate is nil (pengu_gov not up yet)
Config.taxMax     = 0.25         -- hard ceiling on the read rate
Config.govAccount = 'government' -- Renewed-Banking society account taxes are deposited into
Config.govLabel   = 'Government'

-- ===================== business payroll =====================
Config.payrollIntervalMs   = 3600000 -- 60 min between payroll cycles
Config.payrollFallbackWage = 250     -- flat wage when the qbx job grade has no `payment` field
                                     -- (pengu_business grades define none, so this is the norm)
Config.bizPrefix           = 'biz_'  -- pengu_business Config.keyPrefix (business jobs are biz_<key>)
