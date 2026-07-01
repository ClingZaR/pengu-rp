-- PenguRP Business Ownership (pengu_business) - SERVER. Each business is a dynamically-created qbx job
-- + a Renewed-Banking account + a qbx_management boss menu, all (re)built on boot from our DB. Admins
-- register businesses live with /bizloc (pdloc recipe); players buy ownership at the management point.
-- ASCII only. luac clean.

local qbx = exports.qbx_core
local ACE = 'pengu.business'

BUSINESSES = {} -- id -> { id, job_key, label, owner_cid, owner_name, price, x, y, z }

local KIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, msg, kind, tag)
    if not src or src <= 0 then print('[pengu_business] ' .. tostring(msg)); return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { tag or 'BUSINESS', msg, KIND[kind or 'inform'] or 'info' },
    })
end

local function getCid(src)
    local p = qbx:GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function charName(p)
    local ci = p and p.PlayerData and p.PlayerData.charinfo
    if not ci then return 'Unknown' end
    return ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
end

-- ===================== compose a business out of qbx + banking + management =====================
-- (Re)create the dynamic job, its bank account, and its boss-menu zone. Idempotent.
local function ensureBusiness(b)
    -- 1) the qbx job (in-memory only; not committed to jobs.lua). Must exist before any SetJob/login.
    pcall(function()
        qbx:CreateJobs({ [b.job_key] = { label = b.label, type = Config.jobType, grades = Config.grades } })
    end)
    -- 2) the Renewed-Banking society account (id == job_key). Returns cached if it already exists.
    pcall(function()
        exports['Renewed-Banking']:CreateJobAccount({ name = b.job_key, label = b.label }, 0)
    end)
    -- 3) the qbx_management boss-menu zone at the management point (owner/isboss only, client-gated).
    pcall(function()
        exports.qbx_management:RegisterBossMenu({ groupName = b.job_key, type = 'job', coords = vec3(b.x, b.y, b.z) })
    end)
end

-- ===================== persistence + replication =====================
local function ensureColumn(tbl, col, ddl)
    local ex = MySQL.scalar.await(
        'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tbl, col })
    if not ex then MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(tbl, ddl)) end
end

local function loadBusinesses()
    local rows = MySQL.query.await(
        'SELECT id, job_key, label, owner_cid, owner_name, price, x, y, z FROM pengu_businesses ORDER BY id') or {}
    local t = {}
    for _, r in ipairs(rows) do
        t[r.id] = {
            id = r.id, job_key = r.job_key, label = r.label,
            owner_cid = r.owner_cid, owner_name = r.owner_name,
            price = tonumber(r.price) or Config.defaultPrice,
            x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0,
        }
    end
    BUSINESSES = t
    return t
end

-- client-facing list (no citizenids - owner shown by NAME only).
local function publicList()
    local arr = {}
    for _, b in pairs(BUSINESSES) do
        arr[#arr + 1] = {
            id = b.id, label = b.label, price = b.price,
            x = b.x, y = b.y, z = b.z,
            owned = b.owner_cid ~= nil and b.owner_cid ~= '',
            owner = (b.owner_cid and b.owner_cid ~= '') and (b.owner_name or 'Someone') or nil,
        }
    end
    return arr
end

local function broadcast() TriggerClientEvent('pengu_business:updated', -1, publicList()) end
lib.callback.register('pengu_business:getBusinesses', function(_) return publicList() end)

-- ===================== boot =====================
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_businesses (
                id         INT AUTO_INCREMENT PRIMARY KEY,
                job_key    VARCHAR(40) NOT NULL,
                label      VARCHAR(64) NOT NULL DEFAULT '',
                owner_cid  VARCHAR(64) NULL,
                owner_name VARCHAR(64) NULL,
                price      INT         NOT NULL DEFAULT 250000,
                x          FLOAT       NOT NULL,
                y          FLOAT       NOT NULL,
                z          FLOAT       NOT NULL,
                created_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uniq_job_key (job_key)
            )
        ]])
        ensureColumn('pengu_businesses', 'owner_name', '`owner_name` VARCHAR(64) NULL')
        loadBusinesses()
    end)
    if not ok then print('[pengu_business] BOOT FAILED: ' .. tostring(err)) end
    -- compose every business (jobs/accounts/boss-menus) so owners' persisted jobs resolve on login.
    for _, b in pairs(BUSINESSES) do ensureBusiness(b) end
    broadcast()
    local n = 0; for _ in pairs(BUSINESSES) do n = n + 1 end
    print(('[pengu_business] %s (%d businesses).'):format(ok and 'ready' or 'DEGRADED', n))
end)

-- ===================== buy (server-authoritative) =====================
local busy = {}    -- src -> true (one buy at a time per player)
local bizBusy = {} -- bizId -> true (one buy at a time per BUSINESS - blocks two players racing the same one)

local function setOwner(b, cid, name)
    b.owner_cid = cid
    b.owner_name = name
    MySQL.update.await('UPDATE pengu_businesses SET owner_cid = ?, owner_name = ? WHERE id = ?', { cid, name, b.id })
end

-- Fire b's current owner (if online) back to unemployed - so a replaced/cleared owner loses the job,
-- its boss menu, and bankAuth to the society account. cid optionally excludes a no-op self-reassign.
local function fireOwner(b, exceptCid)
    if not b.owner_cid or b.owner_cid == '' or b.owner_cid == exceptCid then return end
    for _, pid in ipairs(GetPlayers()) do
        local pp = qbx:GetPlayer(tonumber(pid))
        if pp and pp.PlayerData and pp.PlayerData.citizenid == b.owner_cid then
            qbx:SetJob(tonumber(pid), 'unemployed', 0)
        end
    end
end

lib.callback.register('pengu_business:buy', function(src, bizId)
    local id = tonumber(bizId) or -1
    -- lock BOTH the player AND the business across the whole critical section (the owner-nil check +
    -- RemoveMoney + SetJob span a DB round-trip; without the per-business lock two players could both
    -- pass the unowned check and both pay + both get the job).
    if busy[src] or bizBusy[id] then return false end
    busy[src] = true; bizBusy[id] = true
    local result = false
    pcall(function()
        local b = BUSINESSES[id]
        if not b then return end
        if b.owner_cid and b.owner_cid ~= '' then notify(src, 'That business is already owned.', 'error'); return end

        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return end
        if #(GetEntityCoords(ped) - vector3(b.x, b.y, b.z)) > (Config.interactDist + 2.0) then
            notify(src, 'You must be at the business to buy it.', 'error'); return
        end

        local p = qbx:GetPlayer(src)
        if not p then return end
        local bankBal = (p.Functions.GetMoney and p.Functions.GetMoney('bank')) or 0
        if bankBal < b.price then notify(src, ('You need $%d in the bank.'):format(b.price), 'error'); return end

        if not p.Functions.RemoveMoney('bank', b.price, 'business-purchase') then
            notify(src, 'Payment failed.', 'error'); return
        end
        -- make the buyer the owner (boss grade) of the business job
        local okJob = qbx:SetJob(src, b.job_key, Config.ownerGrade)
        if not okJob then
            p.Functions.AddMoney('bank', b.price, 'business-refund') -- refund if the job assignment failed
            notify(src, 'Could not transfer ownership - you were refunded.', 'error'); return
        end
        -- Persist ownership; if the DB write throws, fully roll back (refund + revert job + in-memory
        -- owner) so the buyer never loses money for a purchase the database didn't record.
        local prevCid, prevName = b.owner_cid, b.owner_name
        if not pcall(setOwner, b, p.PlayerData.citizenid, charName(p)) then
            b.owner_cid, b.owner_name = prevCid, prevName
            p.Functions.AddMoney('bank', b.price, 'business-refund')
            qbx:SetJob(src, 'unemployed', 0)
            notify(src, 'Purchase failed (database) - you were refunded.', 'error'); return
        end
        broadcast()
        notify(src, ('You bought %s for $%d. Manage it at the front desk.'):format(b.label, b.price), 'success')
        result = true
    end)
    busy[src] = nil; bizBusy[id] = nil
    return result
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)

-- ===================== /bizloc admin (pdloc recipe) =====================
local function cmdRegister(src, args)
    if src <= 0 then notify(src, 'run this in-game (it needs your position).', 'error'); return end
    local key = tostring(args[2] or ''):lower():gsub('[^%w_]', ''):sub(1, 28)
    if key == '' then notify(src, 'usage: /bizloc register <key> <price> [label]', 'error'); return end
    local job_key = Config.keyPrefix .. key
    for _, b in pairs(BUSINESSES) do
        if b.job_key == job_key then notify(src, ('a business "%s" already exists.'):format(key), 'error'); return end
    end
    local price = math.floor(tonumber(args[3]) or Config.defaultPrice)
    if price < 0 then price = 0 end
    local label = (#args >= 4) and table.concat({ table.unpack(args, 4) }, ' '):sub(1, 64)
        or (key:gsub('^%l', string.upper))
    local c = GetEntityCoords(GetPlayerPed(src))
    local okIns = pcall(MySQL.insert.await,
        'INSERT INTO pengu_businesses (job_key, label, price, x, y, z) VALUES (?, ?, ?, ?, ?, ?)',
        { job_key, label, price, c.x + 0.0, c.y + 0.0, c.z + 0.0 })
    if not okIns then notify(src, 'could not register business (db error).', 'error'); return end
    loadBusinesses()
    local b = nil
    for _, v in pairs(BUSINESSES) do if v.job_key == job_key then b = v break end end
    if b then ensureBusiness(b) end
    broadcast()
    notify(src, ('registered "%s" (%s) for $%d at your position.'):format(label, job_key, price), 'success')
end

local function findBiz(arg)
    local id = tonumber(arg)
    if id and BUSINESSES[id] then return BUSINESSES[id] end
    local key = tostring(arg or ''):lower()
    for _, b in pairs(BUSINESSES) do
        if b.job_key == key or b.job_key == (Config.keyPrefix .. key) then return b end
    end
    return nil
end

local function cmdSetOwner(src, args)
    local b = findBiz(args[2])
    if not b then notify(src, 'usage: /bizloc setowner <id|key> <playerid|none>', 'error'); return end
    local who = tostring(args[3] or ''):lower()
    if who == 'none' or who == 'clear' then
        fireOwner(b)
        setOwner(b, nil, nil)
        broadcast()
        notify(src, ('cleared ownership of "%s".'):format(b.label), 'success'); return
    end
    local tid = tonumber(args[3])
    local tp = tid and qbx:GetPlayer(tid)
    if not tp then notify(src, 'target player must be online (give a server id), or "none".', 'error'); return end
    -- strip the PREVIOUS owner first (unless it is the same person), then assign the new one.
    fireOwner(b, tp.PlayerData.citizenid)
    if not qbx:SetJob(tid, b.job_key, Config.ownerGrade) then notify(src, 'could not set owner job.', 'error'); return end
    setOwner(b, tp.PlayerData.citizenid, charName(tp))
    broadcast()
    notify(src, ('%s now owns "%s".'):format(charName(tp), b.label), 'success')
end

local function cmdSetPrice(src, args)
    local b = findBiz(args[2])
    local price = tonumber(args[3])
    if not b or not price or price < 0 then notify(src, 'usage: /bizloc setprice <id|key> <price>', 'error'); return end
    price = math.floor(price)
    b.price = price
    MySQL.update.await('UPDATE pengu_businesses SET price = ? WHERE id = ?', { price, b.id })
    broadcast()
    notify(src, ('price for "%s" set to $%d.'):format(b.label, price), 'success')
end

local function cmdRemove(src, args)
    local b = findBiz(args[2])
    if not b then notify(src, 'usage: /bizloc remove <id|key>', 'error'); return end
    fireOwner(b)
    MySQL.update.await('DELETE FROM pengu_businesses WHERE id = ?', { b.id })
    loadBusinesses(); broadcast()
    notify(src, ('removed business "%s". (the in-memory job stays until a server restart)'):format(b.label), 'success')
end

local function cmdList(src)
    local any = false
    for _, b in pairs(BUSINESSES) do
        any = true
        notify(src, ('#%d %s "%s" $%d owner=%s (%.0f,%.0f,%.0f)'):format(
            b.id, b.job_key, b.label, b.price, b.owner_name or 'none', b.x, b.y, b.z), 'inform')
    end
    if not any then notify(src, 'no businesses registered.', 'inform') end
end

RegisterCommand('bizloc', function(src, args)
    if not IsPlayerAceAllowed(src, ACE) then notify(src, 'you are not allowed to manage businesses.', 'error'); return end
    if not exports.qbx_core:IsOptin(src) then notify(src, 'you must /aduty before using /bizloc.', 'error'); return end
    local sub = tostring(args[1] or ''):lower()
    if     sub == 'register' or sub == 'add' then cmdRegister(src, args)
    elseif sub == 'setowner' then cmdSetOwner(src, args)
    elseif sub == 'setprice' then cmdSetPrice(src, args)
    elseif sub == 'remove' or sub == 'delete' then cmdRemove(src, args)
    elseif sub == 'list'   then cmdList(src)
    else
        notify(src, '/bizloc register <key> <price> [label] - register a business at your position', 'inform')
        notify(src, '/bizloc setowner <id|key> <playerid|none> | setprice <id|key> <price>', 'inform')
        notify(src, '/bizloc remove <id|key> | list', 'inform')
    end
end, false)

-- ===================== passive income tick =====================
-- Every 30 min, deposit $Config.passiveIncome into each owned business's society account.
-- The owner can withdraw it via Renewed-Banking on their phone.
CreateThread(function()
    Wait(Config.passiveIntervalMs) -- skip first tick (let DB load)
    while true do
        for _, b in pairs(BUSINESSES) do
            if b.owner_cid and b.owner_cid ~= '' then
                local ok = pcall(function()
                    exports['Renewed-Banking']:addAccountMoney(b.job_key, Config.passiveIncome)
                end)
                if ok then
                    -- notify the owner if they are online
                    for _, pid in ipairs(GetPlayers()) do
                        local p2 = qbx:GetPlayer(tonumber(pid))
                        if p2 and p2.PlayerData.citizenid == b.owner_cid then
                            TriggerClientEvent('ox_lib:notify', tonumber(pid), {
                                title = b.label,
                                description = ('Your business earned $%d (deposited to business account).'):format(Config.passiveIncome),
                                type = 'success',
                                duration = 7000,
                            })
                        end
                    end
                end
            end
        end
        Wait(Config.passiveIntervalMs)
    end
end)
