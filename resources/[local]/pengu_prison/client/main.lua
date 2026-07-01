PP = PP or {}

-- The real jail (pengu_core/server/jail.lua) publishes the replicated statebag
-- `penguJailMinutes` on the jailed player; > 0 means they are serving time.
function PP.isJailed()
    return (LocalPlayer.state.penguJailMinutes or 0) > 0
end

function PP.notify(msg, ntype)
    lib.notify({
        title = 'Prison',
        description = msg,
        type = ntype or 'inform',
        position = 'top',
        iconColor = '#E1C7F9',
    })
end
