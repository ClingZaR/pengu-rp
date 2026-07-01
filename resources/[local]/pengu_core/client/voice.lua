-- Voice range adjust: cycle Whisper -> Normal -> Shout.
-- Bound to U (Ctrl+Z conflicted with another menu). Rebindable in FiveM key settings.
RegisterCommand('pengu_voicerange', function()
    ExecuteCommand('cycleproximity')
end, false)

RegisterKeyMapping('pengu_voicerange', 'Voice: cycle range', 'keyboard', 'U')
