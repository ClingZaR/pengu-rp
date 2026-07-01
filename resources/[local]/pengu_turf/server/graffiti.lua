-- PenguRP Gang Territory (pengu_turf) - SERVER graffiti / tagging. A gang member sprays a wall with the
-- spraycan item and TYPES the tag. Spraying your GANG NAME (matched loosely) registers an INFLUENCE tag:
-- the gang gains influence there, and tagging fresh OPEN ground auto-claims a new contested grid block
-- (EnsureCellAt) - the EXPANSION path; tagging inside an existing zone contests it. Spraying ANY OTHER
-- text registers a COSMETIC tag (zone_id 0, no influence, no claim) - pure decoration. Active influence
-- tags also top up influence each decay tick (presence). Rivals can PAINT OVER any tag (an influence tag
-- strips the owner's standing + earns rep; a cosmetic tag just gets covered); police can civic-REMOVE
-- tags; tags fade after a lifetime. All server-authoritative (server re-reads its own ped coords).
-- Replicated to GlobalState.penguGraffiti. ASCII only. luac clean.

local qbx = exports.qbx_core
local ox  = exports.ox_inventory

TAGS = {} -- id -> { id, zone_id, gang, x, y, z, h, text, infl, created(os.time) }
local busy = {} -- src -> true

-- idempotent ADD COLUMN (mirrors server/main.lua's helper; that one is file-local).
local function ensureColumn(tbl, col, ddl)
    local ex = MySQL.scalar.await(
        'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tbl, col })
    if not ex then MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(tbl, ddl)) end
end

-- ===================== replication =====================
local function publishTags()
    local out = {}
    for id, t in pairs(TAGS) do
        out[tostring(id)] = {
            zone_id = t.zone_id, gang = t.gang, x = t.x, y = t.y, z = t.z, h = t.h,
            text = t.text or '', infl = t.infl and true or false,
        }
    end
    GlobalState.penguGraffiti = out
end

local function dropTag(id)
    if not TAGS[id] then return end
    TAGS[id] = nil
    MySQL.update.await('DELETE FROM pengu_turf_graffiti WHERE id = ?', { id })
end

local function tagCount(zoneId, gang)
    local n = 0
    for _, t in pairs(TAGS) do if t.zone_id == zoneId and t.gang == gang then n = n + 1 end end
    return n
end

-- a gang's loose (cosmetic, non-influence) tags currently up - capped so vanity paint cannot spam the DB.
local function cosmeticCount(gang)
    local n = 0
    for _, t in pairs(TAGS) do if t.gang == gang and not t.infl then n = n + 1 end end
    return n
end

-- already a tag of this gang sitting on this exact patch? (stops stacking 10 tags on one spot)
local function sameGangTagNear(gang, x, y, z, d)
    local p = vector3(x, y, z)
    for _, t in pairs(TAGS) do
        if t.gang == gang and #(vector3(t.x, t.y, t.z) - p) <= d then return true end
    end
    return false
end

-- ===================== text =====================
-- printable ASCII only (resource is ASCII-only), trimmed + collapsed + length-capped. '' if nothing left.
local function sanitizeTagText(s)
    s = tostring(s or '')
    s = s:gsub('[^\32-\126]', '')
    s = s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #s > 28 then s = s:sub(1, 28) end
    return s
end

-- normalize for gang-name matching: lower, drop a leading "the", keep alphanumerics only.
-- ("The Lost MC" / "lost mc" / "lostmc" all -> "lostmc")
local function normKey(s)
    s = tostring(s or ''):lower()
    s = s:gsub('^the%s+', '')
    s = s:gsub('[^a-z0-9]', '')
    return s
end

-- does the tag text read as THIS gang's name? -> the tag builds turf influence (else it is cosmetic).
local function textCountsForGang(text, gang)
    local t = normKey(text)
    if t == '' then return true end -- blank already defaulted to the gang label by the caller
    return t == normKey(gang) or t == normKey(LabelOf(gang))
end

-- ===================== helpers =====================
local function nearCoords(src, x, y, z, d)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(x + 0.0, y + 0.0, z + 0.0)) <= d
end

local function isLaw(src)
    local p = qbx:GetPlayer(src)
    local j = p and p.PlayerData and p.PlayerData.job
    return (j and Config.lawJobs and Config.lawJobs[j.name]) and true or false
end

-- ===================== boot =====================
CreateThread(function()
    while next(ZONES) == nil do Wait(1000) end
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_turf_graffiti (
                id      INT AUTO_INCREMENT PRIMARY KEY,
                zone_id INT         NOT NULL,
                gang    VARCHAR(24) NOT NULL,
                x       FLOAT       NOT NULL,
                y       FLOAT       NOT NULL,
                z       FLOAT       NOT NULL,
                h       FLOAT       NOT NULL DEFAULT 0,
                text    VARCHAR(32) NOT NULL DEFAULT '',
                infl    TINYINT     NOT NULL DEFAULT 1,
                created INT         NOT NULL DEFAULT 0
            )
        ]])
        -- upgrade older installs that predate the text/infl columns
        ensureColumn('pengu_turf_graffiti', 'text', "`text` VARCHAR(32) NOT NULL DEFAULT ''")
        ensureColumn('pengu_turf_graffiti', 'infl', '`infl` TINYINT NOT NULL DEFAULT 1')

        local rows = MySQL.query.await('SELECT id, zone_id, gang, x, y, z, h, text, infl, created FROM pengu_turf_graffiti') or {}
        for _, r in ipairs(rows) do
            local infl = (tonumber(r.infl) or 1) == 1
            -- influence tags need a live zone; cosmetic tags (zone_id 0) stand on their own.
            if IsValidGang(r.gang) and ((not infl) or ZONES[r.zone_id]) then
                TAGS[r.id] = {
                    id = r.id, zone_id = r.zone_id, gang = r.gang,
                    x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0, h = (r.h or 0.0) + 0.0,
                    text = r.text or '', infl = infl,
                    created = tonumber(r.created) or 0,
                }
            else
                MySQL.update.await('DELETE FROM pengu_turf_graffiti WHERE id = ?', { r.id }) -- orphan zone
            end
        end
    end)
    if not ok then print('[pengu_turf] graffiti BOOT FAILED: ' .. tostring(err)) end
    publishTags()

    -- decay loop: fade old tags, top up influence for surviving INFLUENCE tags (active = standing presence)
    while true do
        Wait(Config.decayMs or 120000)
        local now = os.time()
        local changed = false
        for id, t in pairs(TAGS) do
            if (now - (t.created or 0)) >= (Config.tagLifetime or 7200) then
                dropTag(id); changed = true
            elseif t.infl and ZONES[t.zone_id] then
                BumpInfluence(t.zone_id, t.gang, Config.tagTickInfluence or 0)
            end
        end
        if changed then publishTags() end
    end
end)

-- ===================== place a tag (spraycan) =====================
-- INFLUENCE tag: your gang name on the wall. Resolves the turf (contest a zone, or claim fresh ground),
-- consumes a can, persists the row, then grants influence LAST (insert-before-grant: see below) so no
-- failure path ever has to reverse a partial/clamped influence grant or undo a capture's rep + notify.
local function placeInfluenceTag(src, gang, x, y, z, h, text)
    local zone = ZoneAtCoords(vector3(x, y, z))
    if zone and (zone.core or '') ~= '' and zone.core ~= gang then
        TurfNotify(src, "You can't tag another gang's home base.", 'error'); return false
    end
    if not zone then
        if not CanClaimNewZone(gang) then
            TurfNotify(src, 'Your crew already holds the most turf its level allows - level up or let a block go first.', 'error'); return false
        end
        zone = EnsureCellAt(x, y, z)
        if not zone then TurfNotify(src, 'Could not claim this ground - try again.', 'error'); return false end
    end
    if tagCount(zone.id, gang) >= (Config.maxTagsPerZone or 4) then
        TurfNotify(src, 'Your crew already tagged this block enough - tag elsewhere.', 'error'); return false
    end

    busy[src] = true
    local result = false
    if ox:RemoveItem(src, Config.spraycanItem, 1) then
        -- INSERT the row + re-check the cap BEFORE granting influence. Every failure path below happens
        -- before any influence is added, so a rollback never has to reverse a (possibly clamped) grant and
        -- never undoes a capture's rep/seize notifications - AddInfluence runs only on the committed path.
        local id = MySQL.insert.await(
            'INSERT INTO pengu_turf_graffiti (zone_id, gang, x, y, z, h, text, infl, created) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)',
            { zone.id, gang, x, y, z, h, text, os.time() })
        if not id then
            ox:AddItem(src, Config.spraycanItem, 1) -- DB insert failed; refund the can (no influence granted yet)
            TurfNotify(src, 'The tag did not take. Can returned.', 'error')
        elseif tagCount(zone.id, gang) >= (Config.maxTagsPerZone or 4) then
            -- a concurrent same-gang tag landed while we were inserting (busy[src] only blocks the same src)
            MySQL.update.await('DELETE FROM pengu_turf_graffiti WHERE id = ?', { id })
            ox:AddItem(src, Config.spraycanItem, 1)
            TurfNotify(src, 'Your crew already tagged this block enough - tag elsewhere.', 'error')
        else
            local okInf, reason = AddInfluence(zone.id, gang, Config.tagInfluence or 25)
            if okInf then
                TAGS[id] = { id = id, zone_id = zone.id, gang = gang, x = x, y = y, z = z, h = h, text = text, infl = true, created = os.time() }
                publishTags()
                TurfNotify(src, ('Tagged %s for %s.'):format(zone.label or zone.key, LabelOf(gang)), 'success')
                result = true
            else
                -- AddInfluence granted nothing (e.g. a level-cap/core race since the pre-checks); undo the row
                MySQL.update.await('DELETE FROM pengu_turf_graffiti WHERE id = ?', { id })
                ox:AddItem(src, Config.spraycanItem, 1)
                if reason == 'core' then
                    TurfNotify(src, "You can't tag another gang's home base.", 'error')
                elseif reason == 'maxzones' then
                    TurfNotify(src, 'Your crew already holds the most turf its level allows - level up or drop a zone first.', 'error')
                else
                    TurfNotify(src, 'Could not tag here.', 'error')
                end
            end
        end
    else
        TurfNotify(src, 'You have no spray cans.', 'error')
    end
    busy[src] = nil
    return result
end

-- COSMETIC tag: any text that is not the gang name. No zone, no influence, no claim - just paint.
local function placeCosmeticTag(src, gang, x, y, z, h, text)
    if cosmeticCount(gang) >= (Config.maxCosmeticTagsPerGang or 30) then
        TurfNotify(src, 'Your crew has too much loose graffiti up - it fades over time, or paint some over.', 'error'); return false
    end
    busy[src] = true
    local result = false
    if ox:RemoveItem(src, Config.spraycanItem, 1) then
        local id = MySQL.insert.await(
            'INSERT INTO pengu_turf_graffiti (zone_id, gang, x, y, z, h, text, infl, created) VALUES (0, ?, ?, ?, ?, ?, ?, 0, ?)',
            { gang, x, y, z, h, text, os.time() })
        if not id then
            ox:AddItem(src, Config.spraycanItem, 1) -- DB insert failed; refund the can
            TurfNotify(src, 'The tag did not take. Can returned.', 'error')
        elseif cosmeticCount(gang) >= (Config.maxCosmeticTagsPerGang or 30) then
            -- a concurrent same-gang cosmetic tag landed while we were inserting; stay under the cap
            MySQL.update.await('DELETE FROM pengu_turf_graffiti WHERE id = ?', { id })
            ox:AddItem(src, Config.spraycanItem, 1)
            TurfNotify(src, 'Your crew has too much loose graffiti up - it fades over time, or paint some over.', 'error')
        else
            TAGS[id] = { id = id, zone_id = 0, gang = gang, x = x, y = y, z = z, h = h, text = text, infl = false, created = os.time() }
            publishTags()
            TurfNotify(src, ('Sprayed "%s". (Spray your gang name to build turf influence.)'):format(text), 'inform')
            result = true
        end
    else
        TurfNotify(src, 'You have no spray cans.', 'error')
    end
    busy[src] = nil
    return result
end

lib.callback.register('pengu_turf:placeTag', function(src, x, y, z, h, text)
    if busy[src] then return false end
    local gang = GangOf(src)
    if not gang then return false end
    x, y, z, h = tonumber(x) or 0.0, tonumber(y) or 0.0, tonumber(z) or 0.0, tonumber(h) or 0.0

    text = sanitizeTagText(text)
    if text == '' then text = LabelOf(gang) end -- blank -> default to the gang name (an influence tag)

    -- server re-validates proximity from its OWN copy of the ped coords (never trust the client distance).
    -- tolerance covers a tag up to tagMaxHeight up a wall the player is flush against (3D ~= 5m worst case).
    if not nearCoords(src, x, y, z, (Config.tagReach or 3.0) + (Config.tagMaxHeight or 4.0) - 1.5) then
        TurfNotify(src, 'You are too far from that wall.', 'error'); return false
    end
    if sameGangTagNear(gang, x, y, z, Config.tagMinSpacing or 1.5) then
        TurfNotify(src, 'You already tagged this exact spot - pick a fresh patch of wall.', 'error'); return false
    end
    if (ox:Search(src, 'count', Config.spraycanItem) or 0) < 1 then
        TurfNotify(src, 'You have no spray cans.', 'error'); return false
    end

    if textCountsForGang(text, gang) then
        return placeInfluenceTag(src, gang, x, y, z, h, text)
    else
        return placeCosmeticTag(src, gang, x, y, z, h, text)
    end
end)

-- ===================== paint over a rival tag =====================
lib.callback.register('pengu_turf:paintTag', function(src, tagId)
    if busy[src] then return false end
    local gang = GangOf(src)
    if not gang then return false end
    local t = TAGS[tonumber(tagId) or -1]
    if not t then return false end
    if t.gang == gang then TurfNotify(src, 'That is your own crew tag.', 'error'); return false end
    if not nearCoords(src, t.x, t.y, t.z, (Config.tagReach or 3.0) + 2.0) then
        TurfNotify(src, 'You are too far from the tag.', 'error'); return false
    end

    busy[src] = true
    local victimGang = t.gang
    local wasInfl = t.infl and ZONES[t.zone_id]
    dropTag(t.id)
    if wasInfl then
        BumpInfluence(t.zone_id, victimGang, -(Config.tagPaintInfluence or 25)) -- strip the rival's standing
        AwardTurfRep(gang, 'tagOver')
    end
    publishTags()
    TurfNotify(src, ('You painted over %s tag.'):format(LabelOf(victimGang)), 'success')
    NotifyGang(victimGang, ('%s painted over one of your tags.'):format(LabelOf(gang)), 'error')
    busy[src] = nil
    return true
end)

-- ===================== police civic removal =====================
lib.callback.register('pengu_turf:policeRemoveTag', function(src, tagId)
    if busy[src] then return false end
    if not isLaw(src) then return false end
    local t = TAGS[tonumber(tagId) or -1]
    if not t then return false end
    if not nearCoords(src, t.x, t.y, t.z, (Config.tagReach or 3.0) + 2.0) then
        TurfNotify(src, 'You are too far from the tag.', 'error'); return false
    end
    busy[src] = true
    local victimGang = t.gang
    local wasInfl = t.infl and ZONES[t.zone_id]
    dropTag(t.id)
    if wasInfl then
        BumpInfluence(t.zone_id, victimGang, -(Config.tagPaintInfluence or 25))
    end
    publishTags()
    TurfNotify(src, 'You scrubbed off the graffiti.', 'success')
    busy[src] = nil
    return true
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)
