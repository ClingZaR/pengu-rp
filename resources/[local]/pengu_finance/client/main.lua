-- PenguRP Finance (pengu_finance) - CLIENT.
-- Presentation only: credit report dialog, loan offer menu, loan status dialog, pay prompt.
-- Every choice is sent back to the server, which re-validates everything (score, single
-- active loan, clamped amounts) - nothing here is trusted. No NUI; ox_lib owns focus.
-- ASCII only. luac clean.

----------------------------------------------------------------------
-- /credit - credit report
----------------------------------------------------------------------

RegisterNetEvent('pengu_finance:showCredit', function(data)
    if type(data) ~= 'table' then return end
    local score = tonumber(data.score) or 0
    local band = 'Poor'
    if score >= 750 then band = 'Excellent'
    elseif score >= 700 then band = 'Good'
    elseif score >= 600 then band = 'Fair'
    elseif score >= 500 then band = 'Shaky' end
    local lines = ('**Credit score: %d** (%s)\n\nRange 300 - 850. On-time loan installments raise it; missed ones sink it. Business owners gain a little every clean payroll.')
        :format(score, band)
    if type(data.loan) == 'table' then
        lines = lines .. ('\n\n**Active loan**\nBorrowed: $%d\nRemaining: $%d\nInstallment: $%d\nMissed payments: %d')
            :format(tonumber(data.loan.principal) or 0, tonumber(data.loan.remaining) or 0,
                tonumber(data.loan.installment) or 0, tonumber(data.loan.missed) or 0)
    else
        lines = lines .. '\n\nNo active loan. Use /loan apply at any time.'
    end
    lib.alertDialog({
        header = 'Credit Report',
        content = lines,
        centered = true,
        cancel = false,
    })
end)

----------------------------------------------------------------------
-- /loan apply - tier menu (server sends only the tiers this player qualifies for)
----------------------------------------------------------------------

RegisterNetEvent('pengu_finance:showLoanOffers', function(data)
    if type(data) ~= 'table' or type(data.tiers) ~= 'table' or #data.tiers == 0 then return end
    local options = {
        {
            title = ('Your credit score: %d'):format(tonumber(data.score) or 0),
            description = 'Pick a loan. Installments are auto-collected from your bank every 30 minutes while you are online. Missing payments hurts your credit; three in a row gets your wages garnished.',
            icon = 'file-invoice-dollar',
            disabled = true,
        },
    }
    for _, t in ipairs(data.tiers) do
        local idx = tonumber(t.idx)
        options[#options + 1] = {
            title = ('Borrow $%d'):format(tonumber(t.amount) or 0),
            description = ('%.0f%% interest | repay $%d total | $%d per installment'):format(
                (tonumber(t.interest) or 0) * 100, tonumber(t.total) or 0, tonumber(t.installment) or 0),
            icon = 'sack-dollar',
            onSelect = function()
                local res = lib.alertDialog({
                    header = 'Sign the loan?',
                    content = ('You will receive **$%d** now and owe **$%d**, collected as **$%d** installments from your bank every 30 minutes while online.')
                        :format(tonumber(t.amount) or 0, tonumber(t.total) or 0, tonumber(t.installment) or 0),
                    centered = true,
                    cancel = true,
                    labels = { confirm = 'Sign', cancel = 'Walk away' },
                })
                if res == 'confirm' then
                    TriggerServerEvent('pengu_finance:applyLoan', idx)
                end
            end,
        }
    end
    lib.registerContext({
        id = 'pengu_finance_offers',
        title = 'Bank Loans',
        options = options,
    })
    lib.showContext('pengu_finance_offers')
end)

----------------------------------------------------------------------
-- /loan status
----------------------------------------------------------------------

RegisterNetEvent('pengu_finance:showLoanStatus', function(d)
    if type(d) ~= 'table' then return end
    local garnish = d.garnished and '\n\n**WAGES GARNISHED** - double installments are being seized until you catch up.' or ''
    lib.alertDialog({
        header = 'Loan Status',
        content = ('Borrowed: **$%d** at %.0f%% interest\nRemaining: **$%d**\nInstallment: **$%d** every %d min (online only)\nMissed payments: **%d**%s\n\nPay early any time with /loan pay [amount].')
            :format(tonumber(d.principal) or 0, tonumber(d.interest_pct) or 0,
                tonumber(d.remaining) or 0, tonumber(d.installment) or 0,
                tonumber(d.intervalMin) or 30, tonumber(d.missed) or 0, garnish),
        centered = true,
        cancel = false,
    })
end)

----------------------------------------------------------------------
-- /loan pay (no amount) - input dialog
----------------------------------------------------------------------

RegisterNetEvent('pengu_finance:promptPayAmount', function(remaining)
    remaining = tonumber(remaining) or 0
    local input = lib.inputDialog('Loan Payment', {
        {
            type = 'number',
            label = 'Amount',
            description = ('Remaining balance: $%d'):format(remaining),
            required = true,
            min = 1,
            max = remaining > 0 and remaining or nil,
        },
    })
    if not input or not input[1] then return end
    TriggerServerEvent('pengu_finance:payLoanAmount', input[1])
end)

----------------------------------------------------------------------
-- Cleanup + chat suggestions
----------------------------------------------------------------------

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    lib.hideContext(false)
    lib.closeAlertDialog()
    lib.closeInputDialog()
end)

TriggerEvent('chat:addSuggestion', '/credit', 'View your credit score and active loan', {})
TriggerEvent('chat:addSuggestion', '/loan', 'Bank loans', {
    { name = 'action', help = 'apply | pay | status' },
    { name = 'amount', help = 'with pay: how much to repay early (optional)' },
})
