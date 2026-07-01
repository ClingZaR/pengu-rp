local isEscorting = false

---@param bool boolean
---TODO: this event name should be changed within qb-policejob to be generic
AddEventHandler('hospital:client:SetEscortingState', function(bool)
    isEscorting = bool
end)

---Use first aid pack on nearest player.
lib.callback.register('hospital:client:UseFirstAid', function()
    if isEscorting then
        exports.qbx_core:Notify(locale('error.impossible'), 'error')
        return
    end

    local player = GetClosestPlayer()
    if player then
        local playerId = GetPlayerServerId(player)
        TriggerServerEvent('hospital:server:UseFirstAid', playerId)
    end
end)

lib.callback.register('hospital:client:canHelp', function()
    return exports.qbx_medical:IsLaststand() and exports.qbx_medical:GetLaststandTime() <= 300
end)

-- PenguRP: medikit = stronger firstaid. Server decides the heal target and removes the
-- item (hospital:server:UseMedikit); callback intentionally returns nothing so
-- triggerItemEventOnPlayer does not remove the item a second time.
lib.callback.register('hospital:client:UseMedikit', function()
    if isEscorting then
        exports.qbx_core:Notify(locale('error.impossible'), 'error')
        return
    end

    if lib.progressCircle({
        duration = 5000,
        position = 'bottom',
        label = 'Using medikit...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            combat = true,
            mouse = false,
        },
        anim = {
            dict = HealAnimDict,
            clip = HealAnim,
        },
    })
    then
        local player = GetClosestPlayer()
        local playerId = player and GetPlayerServerId(player) or nil
        TriggerServerEvent('hospital:server:UseMedikit', playerId)
    else
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
    end
end)

-- PenguRP: unlike canHelp, medikit revives dead or laststand players with no timer cap
lib.callback.register('hospital:client:medikitCanRevive', function()
    return exports.qbx_medical:IsDead() or exports.qbx_medical:IsLaststand()
end)

---@param targetId number playerId
RegisterNetEvent('hospital:client:HelpPerson', function(targetId)
    if GetInvokingResource() then return end
    if lib.progressCircle({
        duration = math.random(30000, 60000),
        position = 'bottom',
        label = locale('progress.revive'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            combat = true,
            mouse = false,
        },
        anim = {
            dict = HealAnimDict,
            clip = HealAnim,
        },
    })
    then
        exports.qbx_core:Notify(locale('success.revived'), 'success')
        TriggerServerEvent('hospital:server:RevivePlayer', targetId)
    else
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
    end
end)
