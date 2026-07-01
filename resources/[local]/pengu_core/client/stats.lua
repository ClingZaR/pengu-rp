RegisterCommand('stats', function()
    TriggerServerEvent('pengu_core:requestStats')
end, false)

TriggerEvent('chat:addSuggestion', '/stats', 'View your character statistics')
