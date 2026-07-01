local config    = require 'configs.server'
local utils     = require 'modules.server.utils'

-- Check Jail Time -- PenguRP: renamed 'jailtime' -> 'xtjailtime'. The real jail is pengu_core
-- (penguJailMinutes), so xt-prison's checkJailTime always read 0; pengu_core owns /jailtime now.
lib.addCommand('xtjailtime', {
    help = locale('commands.check_time'),
    params = {},
    restricted = false
}, function(source, args, raw)
    utils.checkJailTime(source)
end)

-- Jail Roster --
lib.addCommand('prisoners', {
    help = locale('commands.prisoners_roster'),
    params = {},
    restricted = false
}, function(source, args, raw)
    if not utils.isCop(source) then
        lib.notify(source, {
            title = locale('notify.no_access'),
            type = 'info'
        })
        return
    end

    local jailRoster = utils.generateJailRoster()

    TriggerClientEvent('xt-prison:client:openPrivateJailRoster', source, jailRoster)
end)


-- Jail/Unjail Player Commands --
if config.EnableJailCommand then
    -- PenguRP: renamed from 'jail' to 'xtjail' so pengu_mdt owns /jail (the DOC-processing command
    -- that imprisons by summing outstanding MDT charges). This stays as an admin manual-jail menu;
    -- /unjail below is unchanged.
    lib.addCommand('xtjail', {
        help = locale('commands.jail'),
        params = {},
        restricted = false
    }, function(source, args, _)
        local player = getPlayer(source)
        if not player then return end

        if utils.isCop(source) then
            local nearbyPlayers = lib.getNearbyPlayers(GetEntityCoords(GetPlayerPed(source)), 5.0)
            local formattedPlayers = {}

            for i = 1, #nearbyPlayers do
                local pid = nearbyPlayers[i].id

                formattedPlayers[#formattedPlayers + 1] = {
                    label = getCharName(pid) .. ' (' .. pid .. ')',
                    value = pid,
                    distance = #(GetEntityCoords(GetPlayerPed(source)) - nearbyPlayers[i].coords)
                }
            end

            table.sort(formattedPlayers, function(a, b)
                return a.distance < b.distance
            end)

            local jailInput = lib.callback.await('xt-prison:client:jailPlayerInput', source, formattedPlayers)
            if not jailInput then return end

            local targetSource = tonumber(jailInput[1])
            local setTime = tonumber(jailInput[2])

            local targetPlayer = getPlayer(targetSource)
            if not targetPlayer then
                return lib.notify(source, {
                    title = locale('notify.invalid_player'),
                    type = 'error'
                })
            end

            local dist = utils.playerDistanceCheck(source, targetSource)
            if not dist then return end

            local notifyTitle = (locale('notify.player_sent')):format(getCharName(targetSource), setTime)
            local state = Player(targetSource).state
            if state?.jailTime and state?.jailTime > 0 then
                if setTime < 0 then
                    setTime = 0
                end

                setJailTime(targetSource, setTime)

                lib.notify(targetSource, {
                    title = locale('notify.time_updated'),
                    description = (locale('notify.time_updated_description')):format(setTime),
                    icon = 'fas fa-lock',
                    type = 'success',
                    duration = 5000
                })
                notifyTitle = (locale('notify.updated_players_times')):format(getCharName(targetSource), setTime)
            else
                lib.callback.await('xt-prison:client:enterJail', targetSource, setTime)
            end

            lib.notify(source, {
                title = notifyTitle,
                icon = 'fas fa-lock',
                type = 'success',
                duration = 5000
            })
        else
            lib.notify(source, {
                title = locale('notify.no_access'),
                type = 'info'
            })
        end
    end)

    -- PenguRP: renamed from 'unjail' to 'xtunjail' so pengu_core owns /unjail (the ADMIN-only
    -- release for the pdloc self-contained jail). This stays as the cop-gated release for the
    -- legacy /xtjail (Bolingbroke) flow.
    lib.addCommand('xtunjail', {
        help = locale('commands.unjail'),
        params = {{
            name = 'id',
            type = 'playerId',
            help = locale('commands.playerid')
        }}
    }, function(source, args)
        if not utils.isCop(source) then return end

        local targetPlayer = getPlayer(args.id)
        if not targetPlayer then
            return lib.notify(source, {
                title = locale('notify.invalid_player'),
                type = 'error'
            })
        end

        local state = Player(args.id).state
        if state and state.jailTime <= 0 then
            return
        end

        local released = lib.callback.await('xt-prison:client:exitJail', args.id, true)
        if released then
            lib.notify(source, {
                title = (locale('notify.player_released')):format(getCharName(args.id)),
                icon = 'fas fa-lock',
                type = 'success',
                duration = 5000
            })
        end
    end)
end

-- PenguRP: external jail API for the MDT (ps-mdt) sentencing flow.
-- Jails an ONLINE player by server id for `minutes` real minutes (xt-prison's jailTime
-- unit: 1 = 60s). Mirrors the /jail handler's branch but without the cop/proximity/dialog
-- gating, since the MDT already authorises the officer and resolves the target. Registered
-- outside the EnableJailCommand block so it works even if the /jail command is disabled.
-- PenguRP: hard cap on any MDT-issued sentence. Penal-code charge months sum 1:1 into real
-- minutes; this clamps the total so the longest possible sentence is 1 hour, no matter how
-- many charges an officer stacks. Raise/lower this single number to retune.
local MAX_JAIL_MINUTES = 60

exports('JailPlayerById', function(targetSource, minutes)
    targetSource = tonumber(targetSource)
    if not targetSource then return false end
    minutes = tonumber(minutes) or 0
    if minutes < 0 then minutes = 0 end
    if minutes > MAX_JAIL_MINUTES then minutes = MAX_JAIL_MINUTES end

    local targetPlayer = getPlayer(targetSource)
    if not targetPlayer then return false end

    local state = Player(targetSource).state
    if state?.jailTime and state?.jailTime > 0 then
        -- already serving: update remaining time instead of re-entering
        setJailTime(targetSource, minutes)
        lib.notify(targetSource, {
            title = locale('notify.time_updated'),
            description = (locale('notify.time_updated_description')):format(minutes),
            icon = 'fas fa-lock',
            type = 'success',
            duration = 5000
        })
        return true
    end

    -- fresh sentence: teleport + book into Bolingbroke Penitentiary
    lib.callback.await('xt-prison:client:enterJail', targetSource, minutes)
    return true
end)

-- PenguRP: external release API for the pengu_gov mayor pardon. Mirrors the /xtunjail
-- handler above minus the cop gating (the caller has already authorised the release).
-- Returns true only if the target was actually serving time and got released. Registered
-- outside the EnableJailCommand block, same precedent as JailPlayerById.
exports('UnjailPlayerById', function(targetSource)
    targetSource = tonumber(targetSource)
    if not targetSource then return false end

    local targetPlayer = getPlayer(targetSource)
    if not targetPlayer then return false end

    local state = Player(targetSource).state
    if not state or not state.jailTime or state.jailTime <= 0 then return false end

    local released = lib.callback.await('xt-prison:client:exitJail', targetSource, true)
    return released and true or false
end)