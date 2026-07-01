-- PenguRP Gang Territory (pengu_turf) - SERVER influence engine (revamped). Control is driven by
-- INFLUENCE points per (zone, gang), earned ONLY two ways: controlling the DEALERS inside a zone
-- (territory.lua) and GRAFFITI (graffiti.lua). A gang can contest any zone (no adjacency requirement),
-- capped by how many non-core zones its gang LEVEL allows (maxZones). Influence DECAYS on a timer so
-- turf must be worked. A CORE zone is the gang's tiny permanent base. Holding non-core zones is the
-- MAIN gang-rep source (rep tick + capture rep) + grants perks. 100% server-authoritative. ASCII only.

INFLUENCE = {}            -- zoneId -> { gang -> points }
local ownersDirty = false -- set when any owner flips; flushed with BroadcastTurf() after a pass

local function zoneInf(id)
    local t = INFLUENCE[id]; if not t then t = {}; INFLUENCE[id] = t end; return t
end

-- ===================== level cap =====================
-- non-core zones where the gang currently has any influence ("fronts"). Their level caps this.
local function influenceFronts(gang)
    local n = 0
    for id, inf in pairs(INFLUENCE) do
        local z = ZONES[id]
        if z and (z.core or '') == '' and (inf[gang] or 0) > 0 then n = n + 1 end
    end
    return n
end

-- ===================== persistence =====================
local function persistInf(zoneId, gang, pts)
    if (pts or 0) <= 0 then
        MySQL.update.await('DELETE FROM pengu_turf_influence WHERE zone_id = ? AND gang = ?', { zoneId, gang })
    else
        MySQL.update.await('INSERT INTO pengu_turf_influence (zone_id, gang, points) VALUES (?, ?, ?) ' ..
            'ON DUPLICATE KEY UPDATE points = VALUES(points)', { zoneId, gang, pts })
    end
end

-- ===================== HUD standings =====================
local function updateStandings(zone)
    if not zone then return end
    local inf = INFLUENCE[zone.id] or {}
    local rt = TurfRuntime[zone.id]; if not rt then rt = {}; TurfRuntime[zone.id] = rt end
    local s, leader, leaderPts = {}, '', 0
    for gang, pts in pairs(inf) do
        if pts > 0 then
            s[gang] = pts
            if pts > leaderPts then leader, leaderPts = gang, pts end
        end
    end
    rt.standings = s; rt.leader = leader; rt.leaderPts = leaderPts
end

-- ===================== rep (delegates to pengu_gangs, perk-multiplied) =====================
local function repMultFor(gang)
    local mult = 1.0
    local pv = Config.perks.rep_mult and Config.perks.rep_mult.mult or 0
    for _, z in pairs(ZONES) do
        if z.owner == gang and z.perk == 'rep_mult' then mult = mult + pv end
    end
    return mult
end

-- GLOBAL so bonus.lua / graffiti can award territory rep with the same perk multiplier.
function AwardTurfRep(gang, key, scale)
    if not gang or gang == '' or not IsValidGang(gang) then return end
    local base = 0
    pcall(function() base = exports.pengu_gangs:RepValue(key) or 0 end)
    if scale then base = base * scale end
    local amt = math.floor(base * repMultFor(gang))
    if amt > 0 then pcall(function() exports.pengu_gangs:AddRep(gang, amt) end) end
end

-- ===================== ownership =====================
local function setOwner(zone, newOwner, silent)
    local former = zone.owner or ''
    if newOwner == former then return end
    zone.owner = newOwner
    MySQL.update.await('UPDATE pengu_turf_zones SET owner = ? WHERE id = ?', { newOwner, zone.id })
    ownersDirty = true
    if silent then return end
    if newOwner ~= '' then
        AwardTurfRep(newOwner, 'zoneCaptured')
        NotifyGang(newOwner, ('%s seized %s.'):format(LabelOf(newOwner), zone.label or zone.key), 'success')
    end
    if former ~= '' and former ~= newOwner then
        NotifyGang(former, ('%s lost %s to %s.'):format(LabelOf(former), zone.label or zone.key, LabelOf(newOwner)), 'error')
    end
end

-- decide control for a zone from its influence (core zones are pinned to the core gang).
local function recompute(zone)
    if (zone.core or '') ~= '' then
        if zone.owner ~= zone.core then setOwner(zone, zone.core, true) end
        updateStandings(zone)
        return
    end
    local inf = INFLUENCE[zone.id] or {}
    -- seed with the incumbent so a tie favours the holder (only a STRICTLY greater rival displaces them)
    local bestGang = zone.owner or ''
    local bestPts  = inf[bestGang] or 0
    for gang, pts in pairs(inf) do
        if pts > bestPts then bestGang, bestPts = gang, pts end
    end
    local newOwner = zone.owner or ''
    if bestPts >= (Config.controlThreshold or 60) then
        newOwner = bestGang                          -- highest influence above threshold controls
    elseif newOwner ~= '' and (inf[newOwner] or 0) <= 0 then
        newOwner = ''                                -- former owner fully decayed and nobody qualifies
    end
    if newOwner ~= (zone.owner or '') then setOwner(zone, newOwner, false) end
    updateStandings(zone)
end

-- ===================== public: add influence (dealing / graffiti) =====================
-- returns true if influence was added; false (+reason) if gated: 'core' (another gang's base),
-- 'maxzones' (over the gang's level cap), 'invalid'/'amount'.
function AddInfluence(zoneId, gang, amount)
    local zone = ZONES[zoneId]
    if not zone or not IsValidGang(gang) then return false, 'invalid' end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'amount' end
    -- cannot build influence inside another gang's permanent core base
    if (zone.core or '') ~= '' and zone.core ~= gang then return false, 'core' end

    local inf = zoneInf(zoneId)
    local already = (inf[gang] or 0) > 0 or zone.owner == gang
    if not already and (zone.core or '') == '' then
        -- level cap: a gang can only contest up to maxZones non-core zones at once (a gang-level perk).
        -- No adjacency requirement - a gang can plant a flag anywhere it works a dealer or sprays a wall.
        local cap = 1
        pcall(function() cap = (exports.pengu_gangs:GetLevelPerks(gang) or {}).maxZones or 1 end)
        if influenceFronts(gang) >= cap then return false, 'maxzones' end
    end

    inf[gang] = math.min(Config.maxInfluence or 240, (inf[gang] or 0) + amount)
    persistInf(zoneId, gang, inf[gang])
    recompute(zone)
    PublishLive()
    if ownersDirty then BroadcastTurf(); ownersDirty = false end
    return true
end

-- ===================== admin helpers (called by admin.lua, same resource) =====================
-- hard override: wipe a zone's influence and pin it to a gang (or neutral). Core zones stay core.
function ForceZoneOwner(zone, gang)
    INFLUENCE[zone.id] = {}
    MySQL.update.await('DELETE FROM pengu_turf_influence WHERE zone_id = ?', { zone.id })
    local target = ((zone.core or '') ~= '' and zone.core) or gang
    if target ~= '' then
        local seed = (Config.controlThreshold or 60) + 40
        INFLUENCE[zone.id][target] = seed
        persistInf(zone.id, target, seed)
    end
    setOwner(zone, target, true)
    updateStandings(zone)
    PublishLive()
    if ownersDirty then BroadcastTurf(); ownersDirty = false end
end

function ClearZoneInfluence(zoneId)
    INFLUENCE[zoneId] = nil
    local rt = TurfRuntime[zoneId]
    if rt then rt.standings = nil; rt.leader = ''; rt.leaderPts = 0 end
    MySQL.update.await('DELETE FROM pengu_turf_influence WHERE zone_id = ?', { zoneId })
end

-- gate-free influence change (used by graffiti AFTER placement: per-tag top-up = +, paint-over = -).
-- Skips adjacency/level gates (those were enforced when the tag was first placed); clamps to [0, cap].
function BumpInfluence(zoneId, gang, amount)
    local zone = ZONES[zoneId]
    if not zone or not IsValidGang(gang) then return end
    local inf = zoneInf(zoneId)
    local np = math.max(0, math.min(Config.maxInfluence or 240, (inf[gang] or 0) + math.floor(amount or 0)))
    if np <= 0 then inf[gang] = nil else inf[gang] = np end
    persistInf(zoneId, gang, np)
    recompute(zone)
    PublishLive()
    if ownersDirty then BroadcastTurf(); ownersDirty = false end
end

-- the in-memory zone containing a world position, or nil. Admin/core zones take PRECEDENCE over auto
-- grid blocks (grid_*) where they overlap, so tagging inside a named zone contests it, not a grid cell.
function ZoneAtCoords(coords)
    local cx, cy = coords.x, coords.y
    local grid = nil
    for _, z in pairs(ZONES) do
        if cx >= z.x1 and cx <= z.x2 and cy >= z.y1 and cy <= z.y2 then
            if z.key:sub(1, 5) == 'grid_' then grid = grid or z else return z end
        end
    end
    return grid
end

-- can this gang start contesting a NEW zone? (under its gang-level maxZones cap). Used before claiming a
-- fresh grid block so we never create an empty cell the gang couldn't hold.
function CanClaimNewZone(gang)
    if not IsValidGang(gang) then return false end
    local cap = 1
    pcall(function() cap = (exports.pengu_gangs:GetLevelPerks(gang) or {}).maxZones or 1 end)
    return influenceFronts(gang) < cap
end

-- resolve the zone at a position, or AUTO-CREATE a contested grid block there (the expansion mechanic).
-- Returns the zone, or nil if creation failed. Caller should gate with CanClaimNewZone first.
function EnsureCellAt(x, y, z)
    local existing = ZoneAtCoords(vector3(x + 0.0, y + 0.0, (z or 0.0) + 0.0))
    if existing then return existing end
    local gs  = Config.gridSize or 80.0
    local gx  = math.floor(x / gs)
    local gy  = math.floor(y / gs)
    local key = ('grid_%d_%d'):format(gx, gy)
    for _, zz in pairs(ZONES) do if zz.key == key then return zz end end -- created by a concurrent claim
    local x1, y1 = gx * gs, gy * gs
    local x2, y2 = x1 + gs, y1 + gs
    local id
    local ok = pcall(function()
        id = MySQL.insert.await(
            'INSERT INTO pengu_turf_zones (zone_key, label, x1, y1, x2, y2, z, owner, default_owner) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            { key, 'Turf', x1 + 0.0, y1 + 0.0, x2 + 0.0, y2 + 0.0, (z or 0.0) + 0.0, '', '' })
    end)
    if not ok or not id then return nil end -- e.g. UNIQUE clash from a concurrent claim
    ZONES[id] = {
        id = id, key = key, label = 'Turf',
        x1 = x1 + 0.0, y1 = y1 + 0.0, x2 = x2 + 0.0, y2 = y2 + 0.0,
        x = (x1 + x2) / 2, y = (y1 + y2) / 2, z = (z or 0.0) + 0.0,
        owner = '', default_owner = '', core = '', perk = '',
    }
    PublishTurf()
    return ZONES[id]
end

-- ===================== perk queries (read by other systems, e.g. imports) =====================
local function gangPerks(gang)
    local out = {}
    if not gang or gang == '' then return out end
    for _, z in pairs(ZONES) do
        if z.owner == gang and (z.perk or '') ~= '' then out[z.perk] = true end
    end
    return out
end
exports('HasPerk', function(gang, perk) return gangPerks(gang)[perk] == true end)
exports('GetGangPerks', function(gang) return gangPerks(gang) end)
exports('GetInfluence', function(zoneId, gang) local i = INFLUENCE[zoneId]; return (i and i[gang]) or 0 end)
exports('AddInfluence', function(zoneId, gang, amount) return AddInfluence(zoneId, gang, amount) end)

-- ===================== boot: load influence, initial recompute =====================
local function loadInfluence()
    local rows = MySQL.query.await('SELECT zone_id, gang, points FROM pengu_turf_influence') or {}
    INFLUENCE = {}
    for _, r in ipairs(rows) do
        if ZONES[r.zone_id] and IsValidGang(r.gang) and (tonumber(r.points) or 0) > 0 then
            zoneInf(r.zone_id)[r.gang] = tonumber(r.points)
        end
    end
    for id in pairs(INFLUENCE) do updateStandings(ZONES[id]) end
end

CreateThread(function()
    while next(ZONES) == nil do Wait(1000) end
    loadInfluence()
    for _, z in pairs(ZONES) do recompute(z) end
    if ownersDirty then BroadcastTurf(); ownersDirty = false end
    PublishLive()

    -- decay loop: bleed influence everywhere, then recompute owners
    while true do
        Wait(Config.decayMs or 120000)
        local dirty = false
        for id, inf in pairs(INFLUENCE) do
            if ZONES[id] then
                for gang, pts in pairs(inf) do
                    local np = math.max(0, pts - (Config.decayPerTick or 4))
                    if np ~= pts then
                        persistInf(id, gang, np)
                        if np <= 0 then inf[gang] = nil else inf[gang] = np end
                        dirty = true
                    end
                end
                recompute(ZONES[id])
            end
        end
        if dirty then PublishLive() end
        if ownersDirty then BroadcastTurf(); ownersDirty = false end
    end
end)

-- rep tick: each gang earns rep per controlled NON-CORE zone (territory = standing, not salary)
CreateThread(function()
    while next(ZONES) == nil do Wait(1000) end
    while true do
        Wait(Config.repTickMs or 600000)
        local counts = {}
        for _, z in pairs(ZONES) do
            if z.owner and z.owner ~= '' and (z.core or '') == '' then
                counts[z.owner] = (counts[z.owner] or 0) + 1
            end
        end
        for gang, n in pairs(counts) do AwardTurfRep(gang, 'perZoneTick', n) end
    end
end)

-- an auto grid block with no claim on it: grid_*, neutral, no core, no influence, no tags. (no yields)
local function cellIsAbandoned(id)
    local z = ZONES[id]
    if not z or z.key:sub(1, 5) ~= 'grid_' or (z.owner or '') ~= '' or (z.core or '') ~= '' then return false end
    local inf = INFLUENCE[id]
    if inf then for _, p in pairs(inf) do if (p or 0) > 0 then return false end end end
    if TAGS then for _, t in pairs(TAGS) do if t.zone_id == id then return false end end end
    return true
end

-- janitor: sweep ABANDONED auto grid blocks so the contested map self-cleans as gangs move on. Cores +
-- admin-named zones are never auto-removed. TWO-PHASE to avoid yielding mid-pairs(ZONES): (1) snapshot
-- candidate ids with NO awaits; (2) re-check each, drop it from memory FIRST (so it is instantly
-- unclaimable - any in-flight claim then fails AddInfluence and refunds), THEN delete the DB row.
CreateThread(function()
    while next(ZONES) == nil do Wait(1000) end
    while true do
        Wait(Config.autoCleanMs or 600000)
        local candidates = {}
        for id in pairs(ZONES) do
            if cellIsAbandoned(id) then candidates[#candidates + 1] = id end
        end
        local removed = false
        for _, id in ipairs(candidates) do
            if cellIsAbandoned(id) then -- re-check (sync, no yield) - may have been claimed since the snapshot
                INFLUENCE[id]   = nil
                TurfRuntime[id] = nil
                ZONES[id]       = nil   -- remove from memory BEFORE the await
                MySQL.update.await('DELETE FROM pengu_turf_zones WHERE id = ?', { id })
                removed = true
            end
        end
        if removed then BroadcastTurf() end
    end
end)
