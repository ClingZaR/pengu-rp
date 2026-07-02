-- PenguRP Character Bio (pengu_core) - CLIENT. /setbio opens a textarea dialog
-- (280 chars; the server sanitizes and caps authoritatively). /bio [id] shows a
-- player's bio in an alert dialog - the target must be within 5m (checked
-- server-side); no id = your own. Empty bio -> 'They keep to themselves.'
-- ASCII only. luac clean.

local MAX_LEN = 280
local EMPTY_LINE = 'They keep to themselves.'

local function notify(msg, kind)
    lib.notify({ title = 'Bio', description = msg, type = kind or 'inform', duration = 6000 })
end

RegisterCommand('setbio', function()
    -- prefill with the current bio so /setbio edits instead of restarting
    local name, current = lib.callback.await('pengu_core:getBio', false)
    if not name then current = '' end

    local input = lib.inputDialog('Character Bio', {
        {
            type = 'textarea',
            label = 'Backstory / notes',
            description = ('Public - anyone close enough can read it. Max %d characters. Leave empty to clear.'):format(MAX_LEN),
            placeholder = 'Grew up on Grove Street...',
            default = current,
            autosize = true,
            max = 6, -- textarea rows (ox_lib), not length; length enforced below + server-side
        },
    })
    if not input then return end

    local text = input[1] or ''
    if #text > MAX_LEN then
        notify(('Too long: %d characters (max %d).'):format(#text, MAX_LEN), 'error')
        return
    end

    local ok, msg = lib.callback.await('pengu_core:setBio', false, text)
    notify(msg or (ok and 'Bio saved.' or 'Could not save bio.'), ok and 'success' or 'error')
end, false)

RegisterCommand('bio', function(_, args)
    local targetId
    if args[1] then
        targetId = tonumber(args[1])
        if not targetId then
            notify('Usage: /bio [server-id]', 'error')
            return
        end
    end

    local name, bio = lib.callback.await('pengu_core:getBio', false, targetId)
    if not name then
        notify(bio or 'Could not read their bio.', 'error')
        return
    end
    if bio == '' then bio = EMPTY_LINE end

    lib.alertDialog({
        header = name,
        content = bio,
        centered = true,
    })
end, false)

TriggerEvent('chat:addSuggestion', '/setbio', 'Write your public character bio (280 chars)', {})
TriggerEvent('chat:addSuggestion', '/bio', 'Size up a nearby player (no id = your own bio)',
    {{ name = 'id', help = 'Server ID (optional)' }})
