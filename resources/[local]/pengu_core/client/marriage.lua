-- PenguRP Marriage System (pengu_core) - CLIENT. /propose, /divorce, /marriagestatus commands.
-- Receives proposal-received net event, shows an accept/reject dialog, sends response back.
-- ASCII only. luac clean.

local function notify(msg, kind)
    lib.notify({ title = 'Marriage', description = msg, type = kind or 'inform', duration = 6000 })
end

-- ===================== commands =====================
RegisterCommand('propose', function(_, args)
    local targetId = tonumber(args[1])
    if not targetId then
        notify('Usage: /propose [server-id]', 'error'); return
    end
    local ok, msg = lib.callback.await('pengu_core:propose', false, targetId)
    notify(msg or (ok and 'Proposal sent!' or 'Could not propose.'), ok and 'success' or 'error')
end, false)

RegisterCommand('divorce', function()
    local ok, msg = lib.callback.await('pengu_core:divorce', false)
    notify(msg or (ok and 'Divorced.' or 'You are not married.'), ok and 'inform' or 'error')
end, false)

RegisterCommand('marriagestatus', function()
    local s = lib.callback.await('pengu_core:getMarriageStatus', false)
    if not s then return end
    if s.marriedTo and s.marriedTo ~= '' then
        notify(('Married to %s'):format(s.marriedName or s.marriedTo), 'success')
    else
        notify('You are not married.', 'inform')
    end
end, false)

TriggerEvent('chat:addSuggestion', '/propose',       'Propose marriage to a nearby player', {{ name='id', help='Server ID' }})
TriggerEvent('chat:addSuggestion', '/divorce',       'Divorce your spouse', {})
TriggerEvent('chat:addSuggestion', '/marriagestatus','Check your marriage status', {})

-- ===================== incoming proposal =====================
RegisterNetEvent('pengu_core:proposalReceived', function(proposerName)
    CreateThread(function()
        local input = lib.alertDialog({
            header  = 'Marriage Proposal',
            content = (('%s has proposed to you. Do you accept?'):format(proposerName)),
            centered = true,
            cancel  = true,
            labels  = { confirm = 'Accept', cancel = 'Decline' },
        })
        local accepted = (input == 'confirm')
        local ok, msg = lib.callback.await('pengu_core:respondProposal', false, accepted)
        if accepted then
            notify(ok and ('You said YES to %s!'):format(proposerName) or (msg or 'Something went wrong.'),
                ok and 'success' or 'error')
        else
            notify('You declined the proposal.', 'inform')
        end
    end)
end)

RegisterNetEvent('pengu_core:proposalResult', function(accepted, partnerName)
    if accepted then
        notify(('Congratulations! %s said YES!'):format(partnerName), 'success')
    else
        notify(('%s declined your proposal.'):format(partnerName), 'error')
    end
end)

RegisterNetEvent('pengu_core:divorced', function(exName)
    notify(('%s has divorced you.'):format(exName or 'Your spouse'), 'error')
end)
