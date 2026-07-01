-- PenguRP - Traffic & Pursuit  [SERVER / integration hub]
-- Owns: pengu_traffic_fines table, fine application (online deduct / offline
-- unpaid), plate->owner resolution, all client-facing callbacks/events, the
-- carjack eject relay, and society payout. Client feature modules talk ONLY
-- to the endpoints defined here. ASCII only. luac clean.

local QBX = exports.qbx_core

-- ---------- chat notify (reuses the qbx_chat_theme 'pengu:admin' template) ----------
local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, msg, kind, tag)
    if src and src > 0 then
        TriggerClientEvent('chat:addMessage', src, {
            templateId = 'pengu:admin',
            args = { tag or 'TRAFFIC', msg, KIND[kind or 'inform'] or 'info' },
        })
    else
        print('[pengu_traffic] ' .. tostring(msg))
    end
end

-- ---------- helpers ----------
-- On-duty LEO guard -> player object or nil.
local function onDutyLeo(src)
    local p = QBX:GetPlayer(src)
    if not p or not p.PlayerData or not p.PlayerData.job then return nil end
    local job = p.PlayerData.job
    if job.type ~= 'leo' or not job.onduty then return nil end
    return p
end

local function trimPlate(plate)
    if type(plate) ~= 'string' then return '' end
    return (plate:gsub('%s+$', ''):gsub('^%s+', '')):upper()
end

-- Resolve a plate to its registered owner. Returns citizenid, "First Last" or nil.
local function ownerByPlate(plate)
    plate = trimPlate(plate)
    if plate == '' then return nil end
    local row = MySQL.single.await(
        'SELECT citizenid FROM player_vehicles WHERE TRIM(plate) = ? LIMIT 1', { plate })
    if not row or not row.citizenid then return nil end
    local cid = row.citizenid
    local prow = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { cid })
    local name = 'Unknown'
    if prow and prow.charinfo then
        local ci = type(prow.charinfo) == 'string' and json.decode(prow.charinfo) or prow.charinfo
        if ci then name = ('%s %s'):format(ci.firstname or '', ci.lastname or ''):gsub('%s+$', '') end
    end
    return cid, name
end

-- Pay a collected fine into the police society account (best effort, never fatal).
local function payToSociety(amount)
    if not Config.payToSociety or amount <= 0 then return end
    pcall(function()
        exports['Renewed-Banking']:addAccountMoney(Config.payToSociety, amount, 'Traffic fine collected')
    end)
end

-- Core: apply a fine. targetSrc (online driver) takes precedence over plate owner.
-- Returns ok(boolean), message(string).
local function applyFine(issuerSrc, data)
    local amount = math.floor(tonumber(data.amount) or 0)
    if amount <= 0 then return false, 'Invalid fine amount.' end
    amount = math.min(amount, 100000)
    local reason = type(data.reason) == 'string' and data.reason:sub(1, 96) or 'Traffic violation'
    local kind   = type(data.kind) == 'string' and data.kind or 'traffic'
    local plate  = trimPlate(data.plate)

    -- Determine the payer: live driver (targetSrc) or registered owner.
    local payer, cid, name
    local tsrc = tonumber(data.targetSrc)
    if tsrc and tsrc > 0 then
        payer = QBX:GetPlayer(tsrc)
        if payer then cid = payer.PlayerData.citizenid; name = ('%s %s'):format(
            payer.PlayerData.charinfo.firstname or '', payer.PlayerData.charinfo.lastname or '') end
    end
    if not cid then
        cid, name = ownerByPlate(plate)
        if cid then payer = QBX:GetPlayerByCitizenId(cid) end
    end
    if not cid then
        return false, ('No registered owner for plate %s.'):format(plate ~= '' and plate or '???')
    end

    -- Online + can afford -> deduct now (paid). Else record as unpaid.
    local paid = 0
    if payer and payer.PlayerData then
        local bank = (payer.PlayerData.money and payer.PlayerData.money.bank) or 0
        if bank >= amount and payer.Functions and payer.Functions.RemoveMoney then
            if payer.Functions.RemoveMoney('bank', amount, 'traffic-fine') then
                paid = 1
                payToSociety(amount)
                notify(payer.PlayerData.source,
                    ('You were fined $%d (%s).'):format(amount, reason), 'error', 'TRAFFIC')
            end
        end
        if paid == 0 then
            notify(payer.PlayerData.source,
                ('Unpaid fine added: $%d (%s). Pay with /fines.'):format(amount, reason), 'inform', 'TRAFFIC')
        end
    end

    MySQL.insert.await(
        'INSERT INTO pengu_traffic_fines (citizenid, plate, amount, reason, kind, issued_by, paid) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { cid, plate, amount, reason, kind, issuerSrc and tostring(issuerSrc) or 'system', paid })

    local tail = paid == 1 and 'charged' or 'billed (unpaid)'
    return true, ('%s %s $%d - %s.'):format(name ~= '' and name or 'Owner', tail, amount, reason)
end

-- ===================== CALLBACKS / EVENTS =====================

-- Radar / parking display: owner NAME only (NO citizenid out -> anti-metagaming).
lib.callback.register('pengu_traffic:getVehicleOwner', function(src, plate)
    if not onDutyLeo(src) then return { name = 'N/A', registered = false } end
    local cid, name = ownerByPlate(plate)
    if not cid then return { name = 'Unregistered', registered = false } end
    return { name = name, registered = true }
end)

-- Officer issues a fine (radar speeding / parking / reckless). Server authoritative.
lib.callback.register('pengu_traffic:issueFine', function(src, data)
    if not onDutyLeo(src) then return { ok = false, msg = 'Not an on-duty officer.' } end
    if type(data) ~= 'table' then return { ok = false, msg = 'Bad request.' } end
    local ok, msg = applyFine(src, data)
    notify(src, msg, ok and 'success' or 'error', 'TRAFFIC')
    return { ok = ok, msg = msg }
end)

-- Automated speed camera report (the passing vehicle's own client reports it).
local camCooldown = {} -- [plate..'@'..label] = os.time()
RegisterNetEvent('pengu_traffic:cameraFine', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    -- Server-authoritative: read the REPORTER's OWN vehicle plate + position (never a client-supplied
    -- plate), so a forged event can only ever fine the car the reporter is sitting in - not an arbitrary
    -- victim - and only when that car is actually at the named camera. Limit comes from the server config.
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return end
    local plate = trimPlate(GetVehicleNumberPlateText(veh))
    if plate == '' then return end
    local cam
    for _, c in ipairs(Config.cameras or {}) do
        if (c.label or '') == tostring(data.label or '') then cam = c break end
    end
    if not cam or not cam.coords then return end
    if #(GetEntityCoords(veh) - cam.coords) > (Config.cameraRadius or 22.0) + 10.0 then return end
    local limit = tonumber(cam.limit) or 0
    local speed = tonumber(data.speed) or 0
    if limit <= 0 or speed <= limit then return end
    speed = math.min(speed, 400) -- sanity clamp against spoofed values
    local key = plate .. '@' .. tostring(cam.label or '?')
    local now = os.time()
    if camCooldown[key] and (now - camCooldown[key]) < (Config.cameraCooldown or 60) then return end
    camCooldown[key] = now

    local over = speed - limit
    local amount = math.min(
        (Config.fines.speedingBase or 0) + over * (Config.fines.speedingPerOver or 0),
        Config.fines.speedingMax or 99999)
    applyFine(nil, {
        plate  = plate,
        amount = amount,
        reason = ('Speed camera: %d in a %d (%s)'):format(math.floor(speed), limit, data.label or 'zone'),
        kind   = 'speedcam',
    })
end)

-- A player views and pays their own outstanding fines.
lib.callback.register('pengu_traffic:getMyFines', function(src)
    local p = QBX:GetPlayer(src)
    if not p then return {} end
    local rows = MySQL.query.await(
        'SELECT id, amount, reason, kind, created FROM pengu_traffic_fines WHERE citizenid = ? AND paid = 0 ORDER BY id DESC',
        { p.PlayerData.citizenid }) or {}
    return rows
end)

RegisterNetEvent('pengu_traffic:payFine', function(id)
    local src = source
    id = tonumber(id)
    if not id then return end
    local p = QBX:GetPlayer(src)
    if not p then return end
    local row = MySQL.single.await(
        'SELECT amount FROM pengu_traffic_fines WHERE id = ? AND citizenid = ? AND paid = 0',
        { id, p.PlayerData.citizenid })
    if not row then notify(src, 'Fine not found or already paid.', 'error', 'FINES') return end
    local amount = math.floor(row.amount)
    local bank = (p.PlayerData.money and p.PlayerData.money.bank) or 0
    if bank < amount then notify(src, ('Insufficient bank funds ($%d needed).'):format(amount), 'error', 'FINES') return end
    if not (p.Functions and p.Functions.RemoveMoney and p.Functions.RemoveMoney('bank', amount, 'traffic-fine-paid')) then
        notify(src, 'Payment failed.', 'error', 'FINES') return
    end
    MySQL.update.await('UPDATE pengu_traffic_fines SET paid = 1 WHERE id = ?', { id })
    payToSociety(amount)
    notify(src, ('Paid fine $%d.'):format(amount), 'success', 'FINES')
end)

-- Carjack relay: jacker asks the server to eject a target player's driver. Server-authoritative
-- proximity: the jacker must REALLY be next to the target and the target must actually be in a vehicle -
-- without this any client could forge the event to eject any player anywhere on the map.
RegisterNetEvent('pengu_traffic:ejectDriver', function(targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc <= 0 or targetSrc == src then return end
    if not GetPlayerName(targetSrc) then return end
    local sp, tp = GetPlayerPed(src), GetPlayerPed(targetSrc)
    if not sp or sp == 0 or not tp or tp == 0 then return end
    if #(GetEntityCoords(sp) - GetEntityCoords(tp)) > 6.0 then return end -- jacker must be at the vehicle
    if GetVehiclePedIsIn(tp, false) == 0 then return end                  -- target must be in a vehicle
    TriggerClientEvent('pengu_traffic:forceExit', targetSrc)
end)

-- ===================== DEPLOYABLES (spike strips / cones) =====================
-- Server-authoritative: deploy CONSUMES one item server-side and only then tracks the
-- placement by network id; pickup gives EXACTLY one back, deletes the entity server-side,
-- and untracks. Both ends are LEO-gated. Because registration costs a real consumed item,
-- a faked netId can never mint a free item (the 1 item = 1 deployable invariant holds).
local liveDeployables = {} -- [netId] = itemName

-- Expected object model per item, so a forged netId can only ever delete a real spike/cone.
local DEPLOY_MODEL = {
    spikestrip  = GetHashKey(Config.spikes.model),
    trafficcone = GetHashKey(Config.cones.model),
}

-- Deploy: remove 1 of the item; on success track the placed object's net id.
lib.callback.register('pengu_traffic:spikeDeploy', function(src, netId, item)
    if not onDutyLeo(src) then return false end
    netId = tonumber(netId)
    if not netId or netId == 0 or (item ~= 'spikestrip' and item ~= 'trafficcone') then return false end
    if not exports.ox_inventory:RemoveItem(src, item, 1) then return false end -- they had none
    liveDeployables[netId] = item
    return true
end)

-- Pickup: give 1 back, delete the networked object server-side, untrack.
lib.callback.register('pengu_traffic:pickupDeployable', function(src, netId)
    if not onDutyLeo(src) then return false end
    netId = tonumber(netId)
    if not netId or netId == 0 then return false end
    local item = liveDeployables[netId]
    if not item then return false end
    if not exports.ox_inventory:AddItem(src, item, 1) then return false end -- inventory full: leave placed
    liveDeployables[netId] = nil
    -- Only delete the entity if it really is the tracked deployable model (a forged netId
    -- pointing at some other networked entity must NOT be deletable).
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and GetEntityModel(ent) == DEPLOY_MODEL[item] then
        DeleteEntity(ent)
    end
    return true
end)

-- Periodically drop tracking entries whose object no longer exists (disconnect, abandon,
-- manual delete) so liveDeployables cannot grow unbounded over server uptime.
CreateThread(function()
    while true do
        Wait(300000) -- 5 minutes
        for netId in pairs(liveDeployables) do
            local ent = NetworkGetEntityFromNetworkId(netId)
            if not ent or ent == 0 or not DoesEntityExist(ent) then
                liveDeployables[netId] = nil
            end
        end
    end
end)

-- ===================== DB BOOTSTRAP =====================
CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS pengu_traffic_fines (
            id        INT AUTO_INCREMENT PRIMARY KEY,
            citizenid VARCHAR(64) NOT NULL,
            plate     VARCHAR(16) NOT NULL DEFAULT '',
            amount    INT         NOT NULL DEFAULT 0,
            reason    VARCHAR(128) NOT NULL DEFAULT '',
            kind      VARCHAR(24) NOT NULL DEFAULT 'traffic',
            issued_by VARCHAR(32) NOT NULL DEFAULT 'system',
            paid      TINYINT     NOT NULL DEFAULT 0,
            created   TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_fines_cid (citizenid),
            INDEX idx_fines_paid (paid)
        )
    ]])
    print('[pengu_traffic] fines table ready')
end)
