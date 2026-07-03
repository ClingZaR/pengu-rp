-- PenguRP Safe Cracking (pengu_robbery) - CLIENT.
-- Register robbery is handled by qbx_storerobbery (coord-based zones, keypad flow).
-- This resource only adds the SAFECRACKER minigame on the v_ilev_gangsafedoor MODEL
-- so any back-room safe in the world can be cracked (not just the pre-defined qbx zones).
-- All cooldowns, payouts, and dispatch are server-authoritative.

local function notify(msg, ok)
    lib.notify({ description = msg, type = ok and 'success' or 'error' })
end

local function locKey(entity)
    local c = GetEntityCoords(entity)
    return ('%d_%d_%d'):format(
        math.floor(c.x / 5) * 5,
        math.floor(c.y / 5) * 5,
        math.floor(c.z / 5) * 5
    )
end

----------------------------------------------------------------------
-- safecracker promise wrapper
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
-- ox_target: safecracker on back-room safe model
----------------------------------------------------------------------

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
