-- PenguRP Drug Supply Chain (pengu_drugs) - SERVER-WIDE DRUG DEMAND (roadmap 3.2: "demand
-- fluctuates server-wide"). One demand factor per sellable drug, clamped demandMin..demandMax:
--   * every unit of drug X sold drops X's demand by Config.demandDropPerUnit
--   * every OTHER drug gains a quarter of that (buyers substitute toward what is scarce)
--   * a Config.demandRegenMs tick regresses all factors toward 1.0 by Config.demandRegen
-- Sellers apply the factor at their price roll (qbx_drugs cornerselling + the pengu_dealers
-- drug_dealer) and report COMPLETED sales back via the RecordDrugSale export or the server-only
-- 'pengu_drugs:recordDrugSale' event (deliberately NOT a net event - clients cannot move the
-- market). Authoritative state lives in memory here, is persisted to pengu_drug_demand on every
-- change (batched upsert, awaited - sales are low-frequency), and is published rounded to 2dp as
-- GlobalState.penguDrugDemand for client-side menu hints (only when a rounded value actually
-- moved, to avoid statebag spam). ASCII only. luac clean.

local DEMAND = {}    -- drug -> float demand factor (authoritative)
local READY  = false -- gates sale recording until the DB seed/load finishes

local function clampDemand(v)
    local mn = Config.demandMin or 0.55
    local mx = Config.demandMax or 1.45
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

local function round2(v)
    return math.floor(v * 100 + 0.5) / 100
end

-- ===================== publish (GlobalState, rounded, spam-guarded) =====================
local lastPublished = nil
local function publish(force)
    local rounded = {}
    local moved = force == true
    for drug, val in pairs(DEMAND) do
        local r = round2(val)
        rounded[drug] = r
        if not moved and (lastPublished == nil or lastPublished[drug] ~= r) then moved = true end
    end
    if not moved and lastPublished then
        for drug in pairs(lastPublished) do
            if rounded[drug] == nil then
                moved = true
                break
            end
        end
    end
    if moved then
        lastPublished = rounded
        GlobalState.penguDrugDemand = rounded
    end
    return moved
end

-- ===================== persistence (single batched multi-row upsert) =====================
local function persist()
    local marks, params = {}, {}
    for drug, val in pairs(DEMAND) do
        marks[#marks + 1] = '(?, ?)'
        params[#params + 1] = drug
        params[#params + 1] = val
    end
    if #marks == 0 then return end
    MySQL.query.await(
        'INSERT INTO pengu_drug_demand (drug, demand) VALUES ' .. table.concat(marks, ', ') ..
        ' ON DUPLICATE KEY UPDATE demand = VALUES(demand)', params)
end

-- ===================== sellable drug list =====================
-- Union of qbx_drugs' cornerSellingDrugsList and the pengu_dealers drug_dealer 'accepts' items,
-- read straight from those resources' config files at boot. Both are plain data files; each is
-- executed in an empty sandbox env, pcall-guarded. If BOTH reads fail we fall back to a snapshot
-- union so the market still boots; RecordDrugSale also auto-seeds unknown drugs at 1.0, so a
-- drug added to either config later self-heals on its first reported sale.
local FALLBACK_DRUGS = {
    'weed_white-widow', 'weed_skunk', 'weed_purple-haze', 'weed_og-kush', 'weed_amnesia',
    'weed_ak47', 'crack_baggy', 'cokebaggy', 'meth', -- qbx_drugs cornerSellingDrugsList
    'weed_brick', 'coke_brick',                      -- pengu_dealers drug_dealer accepts (rest overlap)
}

local function deriveDrugList()
    local list, seen = {}, {}
    local function add(name)
        if type(name) == 'string' and name ~= '' and #name <= 32 and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    -- qbx_drugs config/server.lua is a plain 'return { ... }' module
    pcall(function()
        local raw = LoadResourceFile('qbx_drugs', 'config/server.lua')
        local chunk = raw and load(raw, '@qbx_drugs/config/server.lua', 't', {})
        local cfg = chunk and chunk()
        if type(cfg) == 'table' then
            for _, item in ipairs(cfg.cornerSellingDrugsList or {}) do add(item) end
        end
    end)
    -- pengu_dealers shared/config.lua fills a Config global; run it against a sandbox table
    pcall(function()
        local raw = LoadResourceFile('pengu_dealers', 'shared/config.lua')
        local env = {}
        local chunk = raw and load(raw, '@pengu_dealers/shared/config.lua', 't', env)
        if chunk then
            chunk()
            local dd = env.Config and env.Config.dealerTypes and env.Config.dealerTypes.drug_dealer
            for _, acc in ipairs((dd and dd.accepts) or {}) do add(acc.item) end
        end
    end)
    if #list == 0 then
        print('[pengu_drugs] demand: config reads failed, seeding from fallback drug list')
        for _, item in ipairs(FALLBACK_DRUGS) do add(item) end
    end
    return list
end

-- ===================== boot =====================
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_drug_demand (
                drug   VARCHAR(32) NOT NULL PRIMARY KEY,
                demand FLOAT       NOT NULL DEFAULT 1.0
            )
        ]])
        -- seed any missing drugs at neutral 1.0 (INSERT IGNORE keeps persisted factors)
        local list = deriveDrugList()
        if #list > 0 then
            local marks, params = {}, {}
            for _, drug in ipairs(list) do
                marks[#marks + 1] = '(?)'
                params[#params + 1] = drug
            end
            MySQL.query.await(
                'INSERT IGNORE INTO pengu_drug_demand (drug) VALUES ' .. table.concat(marks, ', '), params)
        end
        local rows = MySQL.query.await('SELECT drug, demand FROM pengu_drug_demand') or {}
        for _, r in ipairs(rows) do
            DEMAND[r.drug] = clampDemand(tonumber(r.demand) or 1.0)
        end
    end)
    if not ok then
        print('[pengu_drugs] demand BOOT FAILED: ' .. tostring(err))
        -- degrade to a neutral in-memory market so sellers still get sane factors
        for _, drug in ipairs(FALLBACK_DRUGS) do
            if DEMAND[drug] == nil then DEMAND[drug] = 1.0 end
        end
    end
    publish(true)
    READY = true
    local n = 0
    for _ in pairs(DEMAND) do n = n + 1 end
    print(('[pengu_drugs] demand model %s (%d drugs tracked).'):format(ok and 'ready' or 'DEGRADED', n))
end)

-- ===================== sale recording (the only way demand moves down) =====================
local function recordSale(drug, count)
    if not READY then return end
    if type(drug) ~= 'string' or drug == '' or #drug > 32 then return end
    count = math.floor(tonumber(count) or 0)
    if count < 1 then return end
    if count > 1000 then count = 1000 end -- sanity cap: one report can never nuke the market
    if DEMAND[drug] == nil then DEMAND[drug] = 1.0 end -- auto-seed drugs added to configs later
    local drop = (Config.demandDropPerUnit or 0.004) * count
    local sub  = drop * 0.25 -- substitution: flooding one product lifts every other one
    for name, val in pairs(DEMAND) do
        if name == drug then
            DEMAND[name] = clampDemand(val - drop)
        else
            DEMAND[name] = clampDemand(val + sub)
        end
    end
    local okP, errP = pcall(persist) -- batched upsert in the same handler (low-frequency)
    if not okP then print('[pengu_drugs] demand persist failed: ' .. tostring(errP)) end
    publish(false)
end

-- ===================== regression toward 1.0 (10-min market cooldown) =====================
CreateThread(function()
    while true do
        Wait(Config.demandRegenMs or 600000)
        if READY then
            local step = Config.demandRegen or 0.02
            local moved = false
            for drug, val in pairs(DEMAND) do
                local nv = val
                if val > 1.0 then
                    nv = math.max(1.0, val - step)
                elseif val < 1.0 then
                    nv = math.min(1.0, val + step)
                end
                if nv ~= val then
                    DEMAND[drug] = clampDemand(nv)
                    moved = true
                end
            end
            if moved then
                local okP, errP = pcall(persist)
                if not okP then print('[pengu_drugs] demand persist failed: ' .. tostring(errP)) end
                publish(false)
            end
        end
    end
end)

-- ===================== cross-resource API =====================
-- current demand factor for a drug; 1.0 for anything untracked (safe default for sellers)
exports('GetDemand', function(drug)
    local v = (type(drug) == 'string') and DEMAND[drug] or nil
    return tonumber(v) or 1.0
end)

-- report a COMPLETED sale of `count` units of `drug` (call under pcall from other resources)
exports('RecordDrugSale', function(drug, count)
    local ok, err = pcall(recordSale, drug, count)
    if not ok then print('[pengu_drugs] RecordDrugSale failed: ' .. tostring(err)) end
    return ok
end)

-- server-only sibling of the export (TriggerEvent from any server resource). Deliberately NOT
-- RegisterNetEvent: demand must never be movable from a client.
AddEventHandler('pengu_drugs:recordDrugSale', function(drug, count)
    local ok, err = pcall(recordSale, drug, count)
    if not ok then print('[pengu_drugs] recordDrugSale event failed: ' .. tostring(err)) end
end)
