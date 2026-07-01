-- PenguRP Government (pengu_gov) - CLIENT.
-- Renders the /vote ballot (ox_lib context) and registers chat suggestions. The server
-- validates everything (open election, candidate, one vote per citizen). ASCII only.

RegisterNetEvent('pengu_gov:client:voteMenu', function(data)
    if type(data) ~= 'table' or type(data.candidates) ~= 'table' then return end
    local label = (Config.offices and Config.offices[data.office]) or tostring(data.office or 'Office')
    local options = {
        {
            title = ('%s Election - Official Ballot'):format(label),
            description = 'Cast your vote. You can only vote ONCE per election.',
            icon = 'check-to-slot',
            disabled = true,
        },
    }
    for i = 1, #data.candidates do
        local c = data.candidates[i]
        if type(c) == 'table' and c.id and c.name then
            options[#options + 1] = {
                title = tostring(c.name),
                description = ('Vote for %s'):format(tostring(c.name)),
                icon = 'user-tie',
                onSelect = function()
                    TriggerServerEvent('pengu_gov:server:vote', c.id)
                end,
            }
        end
    end
    lib.registerContext({
        id = 'pengu_gov_vote',
        title = 'City Election',
        colorScheme = 'blue',
        options = options,
    })
    lib.showContext('pengu_gov_vote')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    lib.hideContext(false)
end)

-- chat suggestions
TriggerEvent('chat:addSuggestion', '/election', 'City elections: status for everyone; open/close for gov admins', {
    { name = 'action', help = 'open | close | status' },
    { name = 'office', help = 'mayor (only used with open)' },
})
TriggerEvent('chat:addSuggestion', '/runformayor', ('Register as a mayoral candidate ($%d bank fee)'):format(Config.registrationFee), {})
TriggerEvent('chat:addSuggestion', '/vote', 'Vote in the open city election (one vote per citizen)', {})
TriggerEvent('chat:addSuggestion', '/settaxrate', 'MAYOR ONLY: set the city tax rate', {
    { name = 'percent', help = ('%d-%d'):format(Config.taxMin, Config.taxMax) },
})
TriggerEvent('chat:addSuggestion', '/mayorpardon', 'MAYOR ONLY: pardon a prisoner (24h cooldown)', {
    { name = 'id', help = 'server id of the prisoner' },
})
TriggerEvent('chat:addSuggestion', '/mayorannounce', 'MAYOR ONLY: city-wide announcement (10 min cooldown)', {
    { name = 'message', help = 'the announcement' },
})
