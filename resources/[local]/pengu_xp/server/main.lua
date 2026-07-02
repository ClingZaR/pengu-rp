-- PenguRP Character XP (pengu_xp) - SERVER. DB-backed category XP, level-up toasts,
-- daily playtime bonus for gang members. ASCII only. luac clean.

local qbx = exports.qbx_core
local xpCache = {}       -- [citizenid][category] = xp (integer)
local joinTimes = {}     -- [src] = server time at login (for playtime tracking)

-- ===================== helpers =====================
local function calcLevel(xp, thresholds)
    local level = 1
    for i = #thresholds, 2, -1 do
        if xp >= thresholds[i] then level = i; break end
    end
    return level
end

local function notify(src, title, desc, kind, duration)
    TriggerClientEvent('ox_lib:notify', src, {
        title = title, description = desc,
        type = kind or 'success', duration = duration or 6000,
    })
end

local function pushXP(src, citizenid)
    local data = xpCache[citizenid]
    if not data then return end
    TriggerClientEvent('pengu_xp:sync', src, data)
end

local function todayStamp()
    local t = os.date('*t')
    return ('%04d-%02d-%02d'):format(t.year, t.month, t.mday)
end

-- ===================== DB =====================
MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS pengu_character_xp (
            citizenid VARCHAR(50) NOT NULL,
            category  VARCHAR(32) NOT NULL,
            xp        INT NOT NULL DEFAULT 0,
            PRIMARY KEY (citizenid, category)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

local function loadXP(citizenid, cb)
    MySQL.query('SELECT category, xp FROM pengu_character_xp WHERE citizenid = ?',
        { citizenid }, function(rows)
            local data = {}
            for _, r in ipairs(rows or {}) do
                data[r.category] = tonumber(r.xp) or 0
            end
            xpCache[citizenid] = data
            if cb then cb(data) end
        end)
end

local function saveXP(citizenid, category, newXP)
    MySQL.query([[
        INSERT INTO pengu_character_xp (citizenid, category, xp)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE xp = VALUES(xp)
    ]], { citizenid, category, newXP })
end

-- ===================== fitness carry-weight perk =====================
-- maxWeight = weightBase + weightPerFitnessLevel * (fitnessLevel - 1), applied
-- through ox_inventory's SetMaxWeight export (modules/inventory/server.lua,
-- signature SetMaxWeight(inv, maxWeight)). Config.weightBase is coupled to the
-- inventory:weight convar in ox.cfg - see shared/config.lua for the warning.
local function fitnessWeight(level)
    local cat = Config.categories.fitness
    if not cat then return nil end
    if type(level) ~= 'number' or level < 1 then level = 1 end
    if level > #cat.thresholds then level = #cat.thresholds end
    return Config.weightBase + Config.weightPerFitnessLevel * (level - 1)
end

local function applyWeightPerk(src, level)
    if not Config.weightPerk then return end
    local newWeight = fitnessWeight(level)
    -- guard rail: never shrink a player below the configured base weight
    if not newWeight or newWeight < Config.weightBase then return end
    pcall(function()
        exports.ox_inventory:SetMaxWeight(src, newWeight)
    end)
end

-- On login the qbx bridge builds the ox inventory only after the client sets
-- the loadInventory statebag, which can land AFTER PlayerLoaded + our DB read;
-- SetMaxWeight silently no-ops on a missing inventory, so retry briefly until
-- it exists. Fully pcall-guarded: never throws during player load.
local function applyWeightPerkOnLoad(src, cid, level)
    if not Config.weightPerk then return end
    local attempts = 0
    local function try()
        attempts = attempts + 1
        local p = qbx:GetPlayer(src)
        if not p or p.PlayerData.citizenid ~= cid then return end -- left / swapped
        local ok, inv = pcall(function() return exports.ox_inventory:GetInventory(src) end)
        if ok and inv then
            applyWeightPerk(src, level)
        elseif attempts < 10 then
            SetTimeout(1000, try)
        end
    end
    try()
end

-- ===================== core Award export =====================
exports('Award', function(src, category, amount)
    local p = qbx:GetPlayer(src)
    if not p then return end
    local cat = Config.categories[category]
    if not cat then return end

    local cid = p.PlayerData.citizenid
    if not xpCache[cid] then xpCache[cid] = {} end

    local oldXP   = xpCache[cid][category] or 0
    local newXP   = oldXP + math.abs(amount)
    local oldLvl  = calcLevel(oldXP, cat.thresholds)
    local newLvl  = calcLevel(newXP, cat.thresholds)

    xpCache[cid][category] = newXP
    saveXP(cid, category, newXP)
    pushXP(src, cid)

    if newLvl > oldLvl then
        notify(src,
            ('%s Level Up!'):format(cat.label),
            ('Reached level %d in %s.'):format(newLvl, cat.label),
            'success', 8000)
        -- re-apply carry-weight perk only on fitness level-ups
        if category == 'fitness' then
            applyWeightPerk(src, newLvl)
        end
    end
end)

-- ===================== level/xp lookup exports =====================
-- consumed by pengu_jobs perks; offline/invalid src -> level 1 / 0 xp
exports('GetLevel', function(src, category)
    local cat = Config.categories[category]
    if not cat then return 1 end
    src = tonumber(src)
    if not src then return 1 end
    local p = qbx:GetPlayer(src)
    if not p then return 1 end
    local data = xpCache[p.PlayerData.citizenid]
    return calcLevel((data and data[category]) or 0, cat.thresholds)
end)

exports('GetXP', function(src, category)
    if not Config.categories[category] then return 0 end
    src = tonumber(src)
    if not src then return 0 end
    local p = qbx:GetPlayer(src)
    if not p then return 0 end
    local data = xpCache[p.PlayerData.citizenid]
    return (data and data[category]) or 0
end)

-- ptype -> XP category maps (single source of truth stays in this config)
exports('GetGatherCategory', function(ptype)
    local m = Config.jobsXP[ptype]
    return m and m.category or nil
end)

exports('GetSellCategory', function(ptype)
    local m = Config.sellXP[ptype]
    return m and m.category or nil
end)

exports('GetDeliveryCategory', function()
    local m = Config.deliveryXP
    return m and m.category or nil
end)

-- ===================== playtime tracking =====================
AddEventHandler('QBCore:Server:PlayerLoaded', function()
    local src = source
    joinTimes[src] = os.time()
    local p = qbx:GetPlayer(src)
    if p then
        local cid = p.PlayerData.citizenid
        loadXP(cid, function(data)
            pushXP(src, cid)
            -- fitness carry-weight perk on load (retries until inv exists)
            local cat = Config.categories.fitness
            if cat then
                applyWeightPerkOnLoad(src, cid,
                    calcLevel((data and data.fitness) or 0, cat.thresholds))
            end
        end)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local joinAt = joinTimes[src]
    if not joinAt then return end
    joinTimes[src] = nil

    local elapsed = os.time() - joinAt
    local p = qbx:GetPlayer(src)
    if not p then return end

    -- playtime bonus: first time >=1h in a calendar day
    if elapsed >= Config.playtime.min_seconds then
        local meta    = p.PlayerData.metadata or {}
        local today   = todayStamp()
        local lastPt  = tostring(meta.lastPlaytimeBonus or '')
        if lastPt ~= today then
            p.Functions.SetMetaData('lastPlaytimeBonus', today)
            local gang = p.PlayerData.gang
            if gang and gang.name and gang.name ~= 'none' then
                pcall(function()
                    exports.pengu_gangs:AddRep(gang.name, Config.playtime.gang_rep)
                end)
                exports.pengu_xp:Award(src, Config.playtime.xp_category, Config.playtime.xp_amount)
            end
        end
    end

    -- clear cache on disconnect
    local cid = p.PlayerData.citizenid
    if xpCache[cid] then xpCache[cid] = nil end
end)

-- ===================== callback: get XP data for /myxp =====================
lib.callback.register('pengu_xp:getData', function(src)
    local p = qbx:GetPlayer(src)
    if not p then return nil end
    local cid = p.PlayerData.citizenid
    if xpCache[cid] then return xpCache[cid] end
    -- fallback: load synchronously
    local rows = MySQL.query.await('SELECT category, xp FROM pengu_character_xp WHERE citizenid = ?', { cid })
    local data = {}
    for _, r in ipairs(rows or {}) do data[r.category] = tonumber(r.xp) or 0 end
    xpCache[cid] = data
    return data
end)

-- ===================== hook: pengu_jobs gather =====================
AddEventHandler('pengu_xp:onGather', function(src, ptype)
    local mapping = Config.jobsXP[ptype]
    if not mapping then return end
    exports.pengu_xp:Award(src, mapping.category, mapping.amount)
end)

-- ===================== hook: pengu_jobs sell =====================
AddEventHandler('pengu_xp:onSell', function(src, ptype)
    local mapping = Config.sellXP[ptype]
    if not mapping then return end
    exports.pengu_xp:Award(src, mapping.category, mapping.amount)
end)

-- ===================== hook: pengu_jobs delivery (per delivered stop) =====================
AddEventHandler('pengu_xp:onDelivery', function(src)
    local mapping = Config.deliveryXP
    if not mapping then return end
    exports.pengu_xp:Award(src, mapping.category, mapping.amount)
end)

-- ===================== hook: pengu_drugs process =====================
AddEventHandler('pengu_xp:onDrugProcess', function(src)
    exports.pengu_xp:Award(src, 'drugs',    30)
    exports.pengu_xp:Award(src, 'criminal', 20)
end)

-- ===================== hook: criminal actions =====================
AddEventHandler('pengu_xp:onCrime', function(src, amount)
    exports.pengu_xp:Award(src, 'criminal', amount or 50)
end)
