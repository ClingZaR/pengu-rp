-- PenguRP Store Robbery (pengu_robbery) - CLIENT.
-- Register targets: prop_till_01 (cash registers in convenience/liquor stores).
-- Safe targets: v_ilev_gangsafedoor (back-room safe doors).
-- Minigames:
--   mhacking  -> TriggerEvent 'mhacking:start'  (installed standalone)
--   safecracker -> TriggerEvent 'SafeCracker:StartMinigame' (installed standalone)
-- All cooldowns, payouts, and dispatch are server-authoritative.

local function notify(msg, ok)
    lib.notify({ description = msg, type = ok and 'success' or 'error' })
end

-- Round entity coords to 5m grid to produce a stable location key.
-- Server recomputes the same key from the player's server-side coords.
local function locKey(entity)
    local c = GetEntityCoords(entity)
    return ('%d_%d_%d'):format(
        math.floor(c.x / 5) * 5,
        math.floor(c.y / 5) * 5,
        math.floor(c.z / 5) * 5
    )
end

----------------------------------------------------------------------
-- mhacking promise wrapper
-- TriggerEvent 'mhacking:start' -> callback(success, remainingTime)
----------------------------------------------------------------------

local function runMhacking(codeLen, seconds)
    local p = promise.new()
    TriggerEvent('mhacking:start', codeLen, seconds, function(success, _rem)
        p:resolve(success)
    end)
    return Citizen.Await(p)
end

----------------------------------------------------------------------
-- safecracker promise wrapper
-- Fires TriggerEvent 'SafeCracker:StartMinigame' with a random combo,
-- then waits for the 'SafeCracker:EndMinigame' local event to resolve.
----------------------------------------------------------------------

local function runSafecracker()
    local p = promise.new()
    local handle
    handle = AddEventHandler('SafeCracker:EndMinigame', function(won)
        RemoveEventHandler(handle)
        p:resolve(won)
    end)
    local combo = { math.random(30, 120), math.random(150, 240), math.random(260, 340) }
    TriggerEvent('SafeCracker:StartMinigame', combo)
    return Citizen.Await(p)
end

----------------------------------------------------------------------
-- Register robbery flow
----------------------------------------------------------------------

local robbingRegister = false

local function doRobRegister(entity)
    if robbingRegister then return end
    robbingRegister = true

    local ok = lib.progressBar({
        duration     = 4000,
        label        = 'Demanding cash...',
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, car = true, combat = false },
    })

    if not ok then
        robbingRegister = false
        return
    end

    local success = runMhacking(6, 20)

    if success then
        TriggerServerEvent('pengu_robbery:robRegister', locKey(entity))
    else
        notify('Register hack failed.', false)
    end

    robbingRegister = false
end

----------------------------------------------------------------------
-- Safe crack flow
----------------------------------------------------------------------

local crackingSafe = false

local function doCrackSafe(entity)
    if crackingSafe then return end

    local drillCount = exports.ox_inventory:GetItemCount('drill')
    if (drillCount or 0) < 1 then
        notify('You need a drill.', false)
        return
    end

    crackingSafe = true

    local won = runSafecracker()

    if won then
        TriggerServerEvent('pengu_robbery:crackSafe', locKey(entity))
    else
        notify('Safe crack failed.', false)
    end

    crackingSafe = false
end

----------------------------------------------------------------------
-- ox_target model interactions
----------------------------------------------------------------------

exports.ox_target:addModel({ 'prop_till_01' }, {
    {
        name     = 'pengu_rob_register',
        icon     = 'fa-solid fa-cash-register',
        label    = 'Rob Register',
        distance = 2.0,
        onSelect = function(data)
            doRobRegister(data.entity)
        end,
    }
})

exports.ox_target:addModel({ 'v_ilev_gangsafedoor' }, {
    {
        name     = 'pengu_crack_safe',
        icon     = 'fa-solid fa-vault',
        label    = 'Crack Safe',
        distance = 1.5,
        onSelect = function(data)
            doCrackSafe(data.entity)
        end,
    }
})
