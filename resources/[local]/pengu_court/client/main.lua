-- PenguRP Court Sessions (pengu_court) - CLIENT.
-- Presentation only: docket context menu, plea/jury alert dialogs, jury vote menu.
-- Every decision is validated server-side (job, session state, juror identity).
-- No NUI of its own; ox_lib owns focus. ASCII only. luac clean.

----------------------------------------------------------------------
-- /docket - list of online citizens with outstanding charges (judge)
----------------------------------------------------------------------

RegisterNetEvent('pengu_court:showDocket', function(entries)
    if type(entries) ~= 'table' or #entries == 0 then return end
    local options = {}
    for _, e in ipairs(entries) do
        options[#options + 1] = {
            title = ('[ID %d] %s'):format(tonumber(e.id) or 0, tostring(e.name)),
            description = ('%d charge(s) | %d month(s) | $%d fine'):format(
                tonumber(e.charges) or 0, tonumber(e.months) or 0, tonumber(e.fine) or 0),
            icon = 'scale-balanced',
        }
    end
    options[#options + 1] = {
        title = 'Open a session',
        description = 'Use /courtstart [id] to bring a defendant before the court',
        icon = 'gavel',
        disabled = true,
    }
    lib.registerContext({
        id = 'pengu_court_docket',
        title = 'Court Docket - Outstanding Charges',
        colorScheme = 'grape',
        options = options,
    })
    lib.showContext('pengu_court_docket')
end)

----------------------------------------------------------------------
-- Plea prompt (defendant). ESC/cancel = not guilty; /courtplea re-offers.
----------------------------------------------------------------------

RegisterNetEvent('pengu_court:pleaPrompt', function(data)
    if type(data) ~= 'table' then return end
    local res = lib.alertDialog({
        header = 'Court of San Andreas',
        content = ('Judge %s has opened proceedings against you.\n\n**%d charge(s) | %d month(s) | $%d fine**\n\nPlead GUILTY for a %d%% sentence reduction, or NOT GUILTY to proceed to trial.'):format(
            tostring(data.judge or 'Unknown'), tonumber(data.charges) or 0,
            tonumber(data.months) or 0, tonumber(data.fine) or 0, tonumber(data.pct) or 25),
        centered = true,
        cancel = true,
        labels = { confirm = 'Plead GUILTY', cancel = 'Plead NOT GUILTY' },
    })
    if res == nil then return end -- another dialog was open; /courtplea re-offers
    TriggerServerEvent('pengu_court:submitPlea', res == 'confirm' and 'guilty' or 'notguilty')
end)

----------------------------------------------------------------------
-- Jury summons (candidate). No reply before the server timeout = declined.
----------------------------------------------------------------------

RegisterNetEvent('pengu_court:juryInvite', function(data)
    local judge = (type(data) == 'table' and data.judge) or 'the court'
    local res = lib.alertDialog({
        header = 'Jury Summons',
        content = ('You have been summoned for jury duty by Judge %s - accept?\n\nJurors are paid for casting their vote.'):format(tostring(judge)),
        centered = true,
        cancel = true,
        labels = { confirm = 'Accept', cancel = 'Decline' },
    })
    if res == nil then return end
    TriggerServerEvent('pengu_court:juryReply', res == 'confirm')
end)

----------------------------------------------------------------------
-- Jury vote (seated juror). Closing without choosing = excluded from tally.
----------------------------------------------------------------------

RegisterNetEvent('pengu_court:juryVotePrompt', function(data)
    local def = (type(data) == 'table' and data.defendant) or 'the defendant'
    lib.registerContext({
        id = 'pengu_court_vote',
        title = 'Jury Deliberation',
        colorScheme = 'grape',
        options = {
            {
                title = 'The People v. ' .. tostring(def),
                description = 'Cast your vote. Not voting excludes you from the tally.',
                icon = 'scroll',
                disabled = true,
            },
            {
                title = 'Vote GUILTY',
                icon = 'gavel',
                onSelect = function() TriggerServerEvent('pengu_court:juryVote', 'guilty') end,
            },
            {
                title = 'Vote NOT GUILTY',
                icon = 'scale-balanced',
                onSelect = function() TriggerServerEvent('pengu_court:juryVote', 'notguilty') end,
            },
        },
    })
    lib.showContext('pengu_court_vote')
end)

----------------------------------------------------------------------
-- Cleanup + chat suggestions
----------------------------------------------------------------------

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- no NUI of our own; close any ox_lib dialog we may have opened so focus is released
    lib.hideContext(false)
    lib.closeAlertDialog()
end)

TriggerEvent('chat:addSuggestion', '/docket', 'List online citizens with outstanding charges (judge)', {})
TriggerEvent('chat:addSuggestion', '/courtstart', 'Open a court session against a defendant (judge)', { { name = 'id', help = 'server id from /docket' } })
TriggerEvent('chat:addSuggestion', '/verdict', 'Deliver the verdict (judge)', { { name = 'ruling', help = 'guilty | notguilty | jury' }, { name = 'pct', help = 'optional sentence reduction 0-100 (guilty only)' } })
TriggerEvent('chat:addSuggestion', '/jury', 'Summon a jury for the active session (judge)', {})
TriggerEvent('chat:addSuggestion', '/courtend', 'End the session; nothing is processed (judge)', {})
TriggerEvent('chat:addSuggestion', '/courtplea', 'Re-open your pending court plea (defendant)', {})
TriggerEvent('chat:addSuggestion', '/objection', 'Object during arguments (lawyer)', {})
