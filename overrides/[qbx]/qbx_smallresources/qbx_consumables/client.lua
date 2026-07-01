local alcoholCount = 0
local relieveCount = 0
local healing = false
local smokingWeed = false

-- PenguRP: drunk gameplay effect (session-only: drunk level intentionally does
-- not persist across relog/character switch). Tunables below.
local drunkConfig = {
    decaySeconds = 45,       -- seconds for 1 drunk level to wear off
    mildLevel = 2,           -- stage 1: swaying walk + light camera shake
    moderateLevel = 4,       -- stage 2: stumbling walk + stronger shake + occasional ragdoll
    heavyLevel = 6,          -- stage 3: very drunk walk + drunk screen effect
    maxLevel = 10,           -- drunk level cap
    ragdollSeconds = 90,     -- average seconds between random ragdolls (stage 2+)
    ragdollTimeMs = 2000,    -- how long a random ragdoll lasts
    shakeAmplitude = { 0.3, 0.9, 1.5 }, -- DRUNK_SHAKE amplitude per stage
    clipsets = {
        'move_m@drunk@slightlydrunk',
        'move_m@drunk@moderatedrunk',
        'move_m@drunk@verydrunk',
    },
    heavyTimecycle = 'spectator5', -- drunk screen fx at stage 3
}

local drunkLevel = 0
local drunkStage = 0 -- 0 = sober, 1 = mild, 2 = moderate, 3 = heavy
local drunkThreadActive = false

local function getDrunkStage()
    if drunkLevel >= drunkConfig.heavyLevel then return 3 end
    if drunkLevel >= drunkConfig.moderateLevel then return 2 end
    if drunkLevel >= drunkConfig.mildLevel then return 1 end
    return 0
end

local function clearDrunkEffects()
    ResetPedMovementClipset(cache.ped, 0.5)
    StopGameplayCamShaking(true)
    ClearTimecycleModifier()
end

local function applyDrunkStage(stage)
    if stage == 0 then
        clearDrunkEffects()
        return
    end

    local clipset = drunkConfig.clipsets[stage]
    RequestAnimSet(clipset)
    local timeout = 100
    while not HasAnimSetLoaded(clipset) and timeout > 0 do
        Wait(10)
        timeout -= 1
    end
    if HasAnimSetLoaded(clipset) then
        SetPedMovementClipset(cache.ped, clipset, 0.5)
        RemoveAnimSet(clipset)
    end

    ShakeGameplayCam('DRUNK_SHAKE', drunkConfig.shakeAmplitude[stage])

    if stage >= 3 then
        SetTimecycleModifier(drunkConfig.heavyTimecycle)
        SetTimecycleModifierStrength(1.0)
    else
        ClearTimecycleModifier()
    end
end

local function startDrunkThread()
    if drunkThreadActive then return end
    drunkThreadActive = true

    CreateThread(function()
        local decayMs = 0
        local lastPed = cache.ped

        while drunkLevel > 0 do
            Wait(1000)
            decayMs += 1000

            if decayMs >= drunkConfig.decaySeconds * 1000 then
                decayMs = 0
                drunkLevel = math.max(drunkLevel - 1, 0)
            end

            local newStage = getDrunkStage()
            if newStage ~= drunkStage or cache.ped ~= lastPed then
                drunkStage = newStage
                lastPed = cache.ped
                applyDrunkStage(newStage)
            end

            if drunkStage >= 2
                and not cache.vehicle
                and not IsPedRagdoll(cache.ped)
                and not IsEntityDead(cache.ped)
                and math.random(drunkConfig.ragdollSeconds) == 1
            then
                SetPedToRagdoll(cache.ped, drunkConfig.ragdollTimeMs, drunkConfig.ragdollTimeMs, 0, false, false, false)
            end
        end

        drunkStage = 0
        clearDrunkEffects()
        drunkThreadActive = false
    end)
end

local function addDrunkLevel(amount)
    drunkLevel = math.min(drunkLevel + amount, drunkConfig.maxLevel)
    startDrunkThread()
end

local function resetDrunk()
    drunkLevel = 0
    drunkStage = 0
    clearDrunkEffects()
end

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    resetDrunk()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    resetDrunk()
end)
-- PenguRP end drunk gameplay effect

local function healOxy()
    if not healing then
        healing = true
    else
        return
    end

    local count = 9
    while count > 0 do
        Wait(1000)
        count -= 1
        SetEntityHealth(cache.ped, GetEntityHealth(cache.ped) + 6)
    end
    healing = false
end

local function trevorEffect()
    AnimpostfxPlay('DrugsTrevorClownsFightIn', 3.0, false)
    Wait(3000)
    AnimpostfxPlay('DrugsTrevorClownsFight', 3.0, false)
    Wait(3000)
    AnimpostfxPlay('DrugsTrevorClownsFightOut', 3.0, false)
    AnimpostfxStop('DrugsTrevorClownsFight')
    AnimpostfxStop('DrugsTrevorClownsFightIn')
    AnimpostfxStop('DrugsTrevorClownsFightOut')
end
exports('TrevorEffect', trevorEffect)

local function methBagEffect()
    local startStamina = 8
    trevorEffect()
    SetRunSprintMultiplierForPlayer(cache.playerId, 1.49)
    while startStamina > 0 do
        Wait(1000)
        if math.random(5, 100) < 10 then
            RestorePlayerStamina(cache.playerId, 1.0)
        end
        startStamina -= 1
        if math.random(5, 100) < 51 then
            trevorEffect()
        end
    end
    SetRunSprintMultiplierForPlayer(cache.playerId, 1.0)
end
exports('MethBagEffect', methBagEffect)

local function ecstasyEffect()
    local startStamina = 30
    SetFlash(0, 0, 500, 7000, 500)
    while startStamina > 0 do
        Wait(1000)
        startStamina -= 1
        RestorePlayerStamina(cache.playerId, 1.0)
        if math.random(1, 100) < 51 then
            SetFlash(0, 0, 500, 7000, 500)
            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.08)
        end
    end
    if IsPedRunning(cache.ped) then
        SetPedToRagdoll(cache.ped, math.random(1000, 3000), math.random(1000, 3000), 3, false, false, false)
    end
end
exports('EcstasyEffect', ecstasyEffect)

local function alienEffect()
    AnimpostfxPlay('DrugsMichaelAliensFightIn', 3.0, false)
    Wait(math.random(5000, 8000))
    AnimpostfxPlay('DrugsMichaelAliensFight', 3.0, false)
    Wait(math.random(5000, 8000))
    AnimpostfxPlay('DrugsMichaelAliensFightOut', 3.0, false)
    AnimpostfxStop('DrugsMichaelAliensFightIn')
    AnimpostfxStop('DrugsMichaelAliensFight')
    AnimpostfxStop('DrugsMichaelAliensFightOut')
end
exports('AlienEffect', alienEffect)

local function crackBaggyEffect()
    local startStamina = 8
    alienEffect()
    SetRunSprintMultiplierForPlayer(cache.playerId, 1.3)
    while startStamina > 0 do
        Wait(1000)
        if math.random(1, 100) < 10 then
            RestorePlayerStamina(cache.playerId, 1.0)
        end
        startStamina -= 1
        if math.random(1, 100) < 60 and IsPedRunning(cache.ped) then
            SetPedToRagdoll(cache.ped, math.random(1000, 2000), math.random(1000, 2000), 3, false, false, false)
        end
        if math.random(1, 100) < 51 then
            alienEffect()
        end
    end
    if IsPedRunning(cache.ped) then
        SetPedToRagdoll(cache.ped, math.random(1000, 3000), math.random(1000, 3000), 3, false, false, false)
    end
    SetRunSprintMultiplierForPlayer(cache.playerId, 1.0)
end
exports('CrackBaggyEffect', crackBaggyEffect)

local function cokeBaggyEffect()
    local startStamina = 20
    alienEffect()
    SetRunSprintMultiplierForPlayer(cache.playerId, 1.1)
    while startStamina > 0 do
        Wait(1000)
        if math.random(1, 100) < 20 then
            RestorePlayerStamina(cache.playerId, 1.0)
        end
        startStamina -= 1
        if math.random(1, 100) < 10 and IsPedRunning(cache.ped) then
            SetPedToRagdoll(cache.ped, math.random(1000, 3000), math.random(1000, 3000), 3, false, false, false)
        end
        if math.random(1, 300) < 10 then
            alienEffect()
            Wait(math.random(3000, 6000))
        end
    end
    if IsPedRunning(cache.ped) then
        SetPedToRagdoll(cache.ped, math.random(1000, 3000), math.random(1000, 3000), 3, false, false, false)
    end
    SetRunSprintMultiplierForPlayer(cache.playerId, 1.0)
end
exports('CokeBaggyEffect', cokeBaggyEffect)

local function smokeWeed()
    if smokingWeed then return end
    smokingWeed = true
    CreateThread(function()
        while smokingWeed do
            Wait(10000)
            TriggerServerEvent('hud:server:RelieveStress', math.random(15, 18))
            relieveCount += 1
            if relieveCount == 6 then
                exports.scully_emotemenu:cancelEmote()
                if smokingWeed then
                    smokingWeed = false
                    relieveCount = 0
                end
            end
        end
    end)
end

lib.callback.register('consumables:client:Eat', function(anim, prop)
    if lib.progressBar({
        duration = 5000,
        label = locale('progress.eating'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            mouse = false,
            combat = true
        },
        anim = anim or {
            clip = 'mp_player_int_eat_burger',
            dict = 'mp_player_inteat@burger',
            flag = 49
        },
        prop = prop or {
            {
                model = 'prop_cs_burger_01',
                bone = 18905,
                pos = {x = 0.13, y = 0.05, z = 0.02},
                rot = {x = -50.0, y = 16.0, z = 60.0}
            }
        }
    }) then -- if completed
        return true
    else -- if canceled
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
        return false
    end
end)

lib.callback.register('consumables:client:Drink', function(anim, prop)
    if lib.progressBar({
        duration = 5000,
        label = locale('progress.drinking'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            mouse = false,
            combat = true
        },
        anim = anim or {
            clip = 'loop_bottle',
            dict = 'mp_player_intdrink',
            flag = 49
        },
        prop = prop or {
            {
                model = 'prop_ld_flow_bottle',
                bone = 18905,
                pos = {x = 0.12, y = 0.008, z = 0.03},
                rot = {x = 240.0, y = -60.0, z = 0.0}
            }
        }
    }) then -- if completed
        return true
    else -- if canceled
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
        return false
    end
end)

lib.callback.register('consumables:client:DrinkAlcohol', function(alcoholLevel, anim, prop)
    if lib.progressBar({
        duration = math.random(3000, 6000),
        label = locale('progress.drinking_liquor'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            mouse = false,
            combat = true
        },
        anim = anim or {
            clip = 'loop_bottle',
            dict = 'mp_player_intdrink',
            flag = 49
        },
        prop = prop or {
            {
                model = 'prop_amb_beer_bottle',
                bone = 18905,
                pos = {x = 0.12, y = 0.008, z = 0.03},
                rot = {x = 240.0, y = -60.0, z = 0.0}
            }
        }
    }) then -- if completed
        alcoholCount += alcoholLevel or 1
        addDrunkLevel(alcoholLevel or 1) -- PenguRP: drunk gameplay effect
        if alcoholCount > 1 and alcoholCount < 4 then
            TriggerEvent('evidence:client:SetStatus', 'alcohol', 200)
        elseif alcoholCount >= 4 then
            TriggerEvent('evidence:client:SetStatus', 'heavyalcohol', 200)
        end
        return true
    else -- if canceled
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
        return false
    end
end)

RegisterNetEvent('consumables:client:Cokebaggy', function()
    if lib.progressBar({
        duration = math.random(5000, 8000),
        label = locale('progress.popping_pills'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            mouse = false,
            combat = true
        },
        anim = {
            dict = 'switch@trevor@trev_smoking_meth',
            clip = 'trev_smoking_meth_loop',
            flag = 49
        }
    }) then -- if completed
        local used = lib.callback.await('consumables:server:usedItem', false, 'cokebaggy')
        if not used then return end

        TriggerEvent('evidence:client:SetStatus', 'widepupils', 200)
        cokeBaggyEffect()
    else -- if canceled
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
    end
end)

RegisterNetEvent('consumables:client:Crackbaggy', function()
    if lib.progressBar({
        duration = math.random(7000, 10000),
        label = locale('progress.smoking_crack'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            mouse = false,
            combat = true
        },
        anim = {
            dict = 'switch@trevor@trev_smoking_meth',
            clip = 'trev_smoking_meth_loop',
            flag = 49
        }
    }) then -- if completed
        local used = lib.callback.await('consumables:server:usedItem', false, 'crack_baggy')
        if not used then return end

        TriggerEvent('evidence:client:SetStatus', 'widepupils', 300)
        crackBaggyEffect()
    else -- if canceled
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
    end
end)

RegisterNetEvent('consumables:client:EcstasyBaggy', function()
    if lib.progressBar({
        duration = 3000,
        label = locale('progress.popping_pills'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            mouse = false,
            combat = true
        },
        anim = {
            dict = 'mp_suicide',
            clip = 'pill',
            flag = 49
        }
    }) then -- if completed
        local used = lib.callback.await('consumables:server:usedItem', false, 'xtcbaggy')
        if not used then return end

        ecstasyEffect()
    else -- if canceled
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
    end
end)

RegisterNetEvent('consumables:client:oxy', function()
    if lib.progressBar({
        duration = 2000,
        label = locale('progress.healing'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            mouse = false,
            combat = true
        },
        anim = {
            dict = 'mp_suicide',
            clip = 'pill',
            flag = 49
        }
    }) then -- if completed
        local used = lib.callback.await('consumables:server:usedItem', false, 'oxy')
        if not used then return end

        ClearPedBloodDamage(cache.ped)
        healOxy()
    else -- if canceled
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
    end
end)

RegisterNetEvent('consumables:client:meth', function()
    if lib.progressBar({
        duration = 1500,
        label = locale('progress.smoking_meth'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            mouse = false,
            combat = true
        },
        anim = {
            dict = 'switch@trevor@trev_smoking_meth',
            clip = 'trev_smoking_meth_loop',
            flag = 49
        }
    }) then -- if completed
        local used = lib.callback.await('consumables:server:usedItem', false, 'meth')
        if not used then return end

        TriggerEvent('evidence:client:SetStatus', 'widepupils', 300)
        TriggerEvent('evidence:client:SetStatus', 'agitated', 300)
        methBagEffect()
    else -- if canceled
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
    end
end)

RegisterNetEvent('consumables:client:UseJoint', function()
    if lib.progressBar({
        duration = 1500,
        label = locale('progress.lighting_joint'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            mouse = false,
            combat = true
        }
    }) then -- if completed
        local used = lib.callback.await('consumables:server:usedItem', false, 'joint')
        if not used then return end

        exports.scully_emotemenu:playEmoteByCommand('joint')
        TriggerEvent('evidence:client:SetStatus', 'weedsmell', 300)
        smokeWeed()
    else -- if canceled
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
    end
end)

--@TODO Rework this to only run when needed.
CreateThread(function()
    while true do
        Wait(10)
        if alcoholCount > 0 then
            Wait(1000 * 60 * 15)
            alcoholCount -= 1
        else
            Wait(2000)
        end
    end
end)
