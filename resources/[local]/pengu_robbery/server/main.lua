-- PenguRP Safe Cracking (pengu_robbery) - SERVER.
-- Register robbery is delegated to qbx_storerobbery (coord-based, keypad flow).
-- This resource only handles the safecracker minigame on v_ilev_gangsafedoor MODEL.
-- Location key = 5m-grid coord string; server recomputes from ped to prevent spoof.
-- Cooldowns are in-memory (reset on restart).

local inv = exports.ox_inventory

-- In-memory cooldowns (register handlers removed; only safe remains)
local safeStoreCd = {}   -- locKey -> expiry
local safePlyerCd = {}   -- src    -> expiry

local function cooled(tbl, key)
    return not tbl[key] or os.time() > tbl[key]
end

local function notify(src, msg, ok)
    TriggerClientEvent('ox_lib:notify', src, {
        type        = ok and 'success' or 'error',
        description = msg,
    })
end

local function dispatchAlert(src, msg, code)
    local ped    = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    pcall(function()
        exports['ps-dispatch']:CustomAlert({
            coords       = coords,
            message      = msg,
            dispatchCode = code,
            description  = msg,
            radius       = 0,
            sprite       = 51,
            color        = 1,
            scale        = 1.0,
            length       = 3,
        })
    end)
end

local function awardXP(src, amount)
    pcall(function() exports.pengu_xp:Award(src, 'criminal', amount) end)
end

-- Recompute the 5m-grid key from the player's actual server-side coords.
-- If client's key doesn't match we know they spoofed the location.
local function serverLocKey(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return ('%d_%d_%d'):format(
        math.floor(c.x / 5) * 5,
        math.floor(c.y / 5) * 5,
        math.floor(c.z / 5) * 5
    )
end

----------------------------------------------------------------------
-- Safe cracking
----------------------------------------------------------------------

RegisterNetEvent('pengu_robbery:crackSafe', function(clientKey)
    local src = source
    if type(clientKey) ~= 'string' then return end

    local srvKey = serverLocKey(src)
    if srvKey ~= clientKey then
        notify(src, 'Invalid position.', false)
        return
    end

    if not cooled(safeStoreCd, clientKey) then
        local rem = math.ceil((safeStoreCd[clientKey] - os.time()) / 60)
        notify(src, ('This safe was cracked recently. Try again in %d min.'):format(rem), false)
        return
    end
    if not cooled(safePlyerCd, src) then
        local rem = math.ceil((safePlyerCd[src] - os.time()) / 60)
        notify(src, ('Wait %d min before another safe job.'):format(rem), false)
        return
    end

    -- Consume drill server-side
    if not inv:RemoveItem(src, Config.safeToolItem, 1) then
        notify(src, 'You need a drill.', false)
        return
    end

    local amount = math.random(Config.safeMin, Config.safeMax)
    if not inv:AddItem(src, 'black_money', amount) then
        inv:AddItem(src, Config.safeToolItem, 1)  -- refund drill if pockets full
        notify(src, 'Your pockets are full.', false)
        return
    end

    safeStoreCd[clientKey] = os.time() + Config.safeStoreCd
    safePlyerCd[src]       = os.time() + Config.safePlayerCd

    notify(src, ('Safe cracked. Took $%d.'):format(amount), true)
    dispatchAlert(src, 'Silent Alarm - Burglary in Progress - 10-16', '10-16')
    awardXP(src, Config.safeXP)
end)

----------------------------------------------------------------------
-- Cleanup cooldowns on drop
----------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    safePlyerCd[source] = nil
end)
