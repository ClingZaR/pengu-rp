-- PenguRP Petty Crime (pengu_pettycrime) - SERVER. Low-end crime against WORLD PROPS:
--   ATM HACK    : trojan_usb consumed at BEGIN (deliberately no refund on a failed skillcheck),
--                 pays black_money on success. Dispatch pings EVERY attempt.
--   METER THEFT : requires a lockpick (breakChance it snaps per attempt), pays small clean CASH.
-- Server-authoritative: the client only reports which prop it targeted (model + coords) and whether
-- the minigame passed. EVERYTHING that matters is enforced here: model hash validated against the
-- allowed set, player proximity to the prop re-checked (<= Config.maxDistance), per-prop cooldown
-- (keyed by rounded coords) + per-player cooldown (keyed by citizenid), cops-online gate, item
-- consumption return-checked, CanCarry checked BEFORE the irreversible step, payout only after a
-- plausible elapsed time (a finish that arrives faster than the progress bar allows is spoofed and
-- rejected). Cooldowns are in-memory by design (no DB). ASCII only. luac clean.

local qbx = exports.qbx_core
local ox  = exports.ox_inventory

-- ===================== allowed model hash sets =====================
-- joaat()/GetEntityModel() may disagree on 32-bit signedness across runtimes, so BOTH the set keys
-- and the client-supplied model are normalized to unsigned 32-bit before comparing.
local function u32(n) return n % 4294967296 end

local HASHES = { atm = {}, meter = {} }
for _, m in ipairs(Config.atm.models or {}) do HASHES.atm[u32(joaat(m))] = true end
for _, m in ipairs(Config.meter.models or {}) do HASHES.meter[u32(joaat(m))] = true end

math.randomseed(os.time())

-- ===================== state (all in-memory) =====================
local propCd   = {}                       -- 'kind:x:y:z' -> os.time() the prop is free again
local playerCd = { atm = {}, meter = {} } -- citizenid -> os.time() the player may go again
local PENDING  = {}                       -- src -> { kind, x, y, z, startedAt, expiresAt }

local function notify(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Petty Crime', description = msg, type = kind or 'inform',
    })
end

local function cidOf(src)
    local p = qbx:GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

-- per-prop cooldown key from ROUNDED prop coords (stable across clients for the same world prop)
local function propKey(kind, x, y, z)
    return ('%s:%d:%d:%d'):format(kind, math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5))
end

-- player must actually be standing at the prop coords the client claimed
local function nearCoords(src, x, y, z)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(x, y, z)) <= (Config.maxDistance or 4.0)
end

-- on-duty LEO count (same job set as the pengu_core dispatch relay)
local LAW = { police = true, bcso = true, sasp = true }
local function copsOnline()
    local n = 0
    for _, p in pairs(qbx:GetQBPlayers() or {}) do
        local job = p.PlayerData and p.PlayerData.job
        if job and job.onduty and LAW[job.name] then n = n + 1 end
    end
    return n
end

local function sendDispatch(kind, x, y, z)
    pcall(function()
        local d
        if kind == 'atm' then
            d = { message = 'ATM Tampering', code = '10-31', icon = 'fas fa-credit-card', priority = 2 }
        else
            d = { message = 'Parking Meter Theft', code = '10-66', icon = 'fas fa-coins', priority = 3 }
        end
        d.jobs = { 'police', 'bcso', 'sasp' }
        exports.pengu_core:Dispatch(vector3(x, y, z), d)
    end)
end

-- sanitize a client-supplied coordinate (reject nil/NaN/off-map junk)
local function num(v)
    v = tonumber(v)
    if not v or v ~= v or v < -20000.0 or v > 20000.0 then return nil end
    return v + 0.0
end

-- ===================== BEGIN an attempt =====================
-- Validates everything, consumes/wears the tool, sets ALL cooldowns and fires dispatch NOW (the
-- attempt is committed the moment it starts - aborting the minigame does not undo any of it).
lib.callback.register('pengu_pettycrime:begin', function(src, kind, model, x, y, z)
    kind = (kind == 'atm' or kind == 'meter') and kind or nil
    if not kind then return false end
    local cfg = Config[kind]

    x, y, z = num(x), num(y), num(z)
    model = tonumber(model)
    if not x or not y or not z or not model then return false end

    local now = os.time()

    -- per-player busy lock (one attempt at a time; expired sessions are swept here)
    local s = PENDING[src]
    if s then
        if now <= s.expiresAt then notify(src, 'You are already in the middle of something.', 'error'); return false end
        PENDING[src] = nil
    end

    local cid = cidOf(src)
    if not cid then return false end

    -- the claimed prop must be a real allowed model for this activity, and the player must be at it
    if not HASHES[kind][u32(model)] then return false end
    if not nearCoords(src, x, y, z) then notify(src, 'You are too far away.', 'error'); return false end

    -- cops-online gate
    if (cfg.minCops or 0) > 0 and copsOnline() < cfg.minCops then
        notify(src, 'Not enough police in the city for that right now.', 'error'); return false
    end

    -- cooldowns (server-side only; both checked before anything is consumed)
    local key = propKey(kind, x, y, z)
    if (propCd[key] or 0) > now then
        notify(src, 'This one was hit recently - come back later.', 'error'); return false
    end
    local pcd = playerCd[kind][cid] or 0
    if pcd > now then
        notify(src, ('Lay low for another %d min before trying that again.'):format(math.ceil((pcd - now) / 60)), 'error')
        return false
    end

    -- tool check
    if (ox:Search(src, 'count', cfg.item) or 0) < 1 then
        notify(src, ('You need a %s for this.'):format(cfg.item == 'trojan_usb' and 'trojan USB' or 'lockpick'), 'error')
        return false
    end

    if kind == 'atm' then
        -- CanCarry the MAX payout BEFORE burning the USB (never consume it into a full inventory)
        if not ox:CanCarryItem(src, cfg.payoutItem, cfg.payoutMax) then
            notify(src, 'Your pockets are too full to carry the take - make space first.', 'error'); return false
        end
        -- consume the trojan at start; deliberately NOT refunded if the hack fails (the risk)
        if not ox:RemoveItem(src, cfg.item, 1) then return false end
    else
        -- lockpick wear: it snaps on breakChance of attempts (the attempt still proceeds)
        if math.random() < (cfg.breakChance or 0) then
            if not ox:RemoveItem(src, cfg.item, 1) then return false end
            notify(src, 'Your lockpick snapped in the coin slot.', 'error')
        end
    end

    -- the attempt is now committed: cooldowns start and dispatch rolls regardless of the outcome
    propCd[key] = now + (cfg.propCooldownS or 0)
    playerCd[kind][cid] = now + (cfg.playerCooldownS or 0)
    if math.random() < (cfg.dispatchChance or 0) then sendDispatch(kind, x, y, z) end

    PENDING[src] = {
        kind = kind, x = x, y = y, z = z,
        startedAt = now,
        expiresAt = now + math.ceil((cfg.progressMs or 0) / 1000) + (Config.sessionSlackS or 60),
    }
    return true
end)

-- ===================== FINISH an attempt =====================
lib.callback.register('pengu_pettycrime:finish', function(src, success)
    local s = PENDING[src]
    if not s then return false end
    PENDING[src] = nil -- consume the session first: a double finish can never double pay

    local cfg = Config[s.kind]
    if success ~= true then
        notify(src, s.kind == 'atm' and 'The hack failed - the trojan USB is burned.' or 'You could not crack the meter open.', 'error')
        return false
    end

    local now = os.time()
    -- a success reported faster than the minigame allows, or after the session window, is spoofed
    if (now - s.startedAt) < (cfg.minElapsedS or 0) then return false end
    if now > s.expiresAt then return false end
    if not nearCoords(src, s.x, s.y, s.z) then return false end

    local p = qbx:GetPlayer(src)
    if not p then return false end

    local amount = math.random(cfg.payoutMin or 1, cfg.payoutMax or 1)
    if s.kind == 'atm' then
        if not ox:CanCarryItem(src, cfg.payoutItem, amount) then
            notify(src, 'Your pockets are too full to grab the take.', 'error'); return false
        end
        if not ox:AddItem(src, cfg.payoutItem, amount) then
            notify(src, 'You fumbled the take.', 'error'); return false
        end
        notify(src, ('The ATM spits out $%d in marked bills.'):format(amount), 'success')
    else
        if not p.Functions.AddMoney('cash', amount, 'pettycrime-parking-meter') then return false end
        notify(src, ('You shake $%d in coins out of the meter.'):format(amount), 'success')
    end

    if (cfg.xp or 0) > 0 then
        pcall(function() exports.pengu_xp:Award(src, 'criminal', cfg.xp) end)
    end
    return true
end)

AddEventHandler('playerDropped', function() PENDING[source] = nil end)
