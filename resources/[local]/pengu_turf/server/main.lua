-- PenguRP Gang Territory (pengu_turf) - SERVER core. Block-based zone system.
-- Each zone is a rectangle (x1,y1 -> x2,y2). No hardcoded seeds; admin places all zones
-- in-game with /turf mark + /turf add. ASCII only. luac clean.

ZONES       = {}
TurfRuntime = {}

local function ensureColumn(tbl, col, ddl)
    local ex = MySQL.scalar.await(
        'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tbl, col })
    if not ex then MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(tbl, ddl)); return true end
    return false
end

-- drop a leftover column if it still exists (idempotent migration helper)
local function dropColumn(tbl, col)
    local ex = MySQL.scalar.await(
        'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tbl, col })
    if ex then MySQL.query.await(('ALTER TABLE `%s` DROP COLUMN `%s`'):format(tbl, col)) end
end

function LoadZones()
    local rows = MySQL.query.await(
        'SELECT id, zone_key, label, x1, y1, x2, y2, z, owner, default_owner, core_gang, perk FROM pengu_turf_zones ORDER BY id') or {}
    local t = {}
    for _, r in ipairs(rows) do
        local core = r.core_gang or ''
        local x1 = (r.x1 or 0.0) + 0.0
        local y1 = (r.y1 or 0.0) + 0.0
        local x2 = (r.x2 or 0.0) + 0.0
        local y2 = (r.y2 or 0.0) + 0.0
        t[r.id] = {
            id = r.id, key = r.zone_key, label = r.label,
            x1 = x1, y1 = y1, x2 = x2, y2 = y2,
            x = (x1 + x2) / 2, y = (y1 + y2) / 2, z = (r.z or 0.0) + 0.0,
            owner         = (core ~= '' and core) or (r.owner or ''),
            default_owner = r.default_owner or '',
            core          = core,
            perk          = r.perk or '',
        }
    end
    ZONES = t
    return t
end

function PublishTurf()
    local compact = {}
    for id, z in pairs(ZONES) do
        compact[id] = {
            key = z.key, label = z.label,
            x1 = z.x1, y1 = z.y1, x2 = z.x2, y2 = z.y2,
            x = z.x, y = z.y, z = z.z,
            owner = z.owner or '', colour = ColourOf(z.owner),
            core = z.core or '', perk = z.perk or '',
        }
    end
    GlobalState.penguTurf = compact
end

function PublishLive()
    local live = {}
    for id, rt in pairs(TurfRuntime) do
        local s = rt.standings
        if s and next(s) ~= nil then
            live[id] = {
                leader = rt.leader or '', leaderPts = rt.leaderPts or 0,
                threshold = Config.controlThreshold or 0, standings = s,
            }
        end
    end
    GlobalState.penguTurfLive = live
end

function BroadcastTurf()
    PublishTurf()
    PublishLive()
end

local function zoneCount()
    local n = 0; for _ in pairs(ZONES) do n = n + 1 end; return n
end

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_turf_zones (
                id            INT AUTO_INCREMENT PRIMARY KEY,
                zone_key      VARCHAR(32)  NOT NULL,
                label         VARCHAR(64)  NOT NULL DEFAULT '',
                x1            FLOAT        NOT NULL DEFAULT 0.0,
                y1            FLOAT        NOT NULL DEFAULT 0.0,
                x2            FLOAT        NOT NULL DEFAULT 0.0,
                y2            FLOAT        NOT NULL DEFAULT 0.0,
                z             FLOAT        NOT NULL DEFAULT 0.0,
                owner         VARCHAR(24)  NOT NULL DEFAULT '',
                default_owner VARCHAR(24)  NOT NULL DEFAULT '',
                created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uniq_zone_key (zone_key)
            )
        ]])
        ensureColumn('pengu_turf_zones', 'x1',            '`x1`            FLOAT        NOT NULL DEFAULT 0.0')
        ensureColumn('pengu_turf_zones', 'y1',            '`y1`            FLOAT        NOT NULL DEFAULT 0.0')
        ensureColumn('pengu_turf_zones', 'x2',            '`x2`            FLOAT        NOT NULL DEFAULT 0.0')
        ensureColumn('pengu_turf_zones', 'y2',            '`y2`            FLOAT        NOT NULL DEFAULT 0.0')
        ensureColumn('pengu_turf_zones', 'core_gang',     "`core_gang`     VARCHAR(24)  NOT NULL DEFAULT ''")
        ensureColumn('pengu_turf_zones', 'perk',          "`perk`          VARCHAR(24)  NOT NULL DEFAULT ''")
        ensureColumn('pengu_turf_zones', 'default_owner', "`default_owner` VARCHAR(24)  NOT NULL DEFAULT ''")

        -- drop legacy circle-model columns. The block model computes x,y from x1..y2 IN MEMORY and never
        -- reads these; left over from the old schema as NOT NULL with no default, `x`/`y` made EVERY zone
        -- INSERT fail ("Field 'x' doesn't have a default value") - so no turf could ever be created.
        dropColumn('pengu_turf_zones', 'x')
        dropColumn('pengu_turf_zones', 'y')
        dropColumn('pengu_turf_zones', 'radius')

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_turf_influence (
                zone_id    INT         NOT NULL,
                gang       VARCHAR(24) NOT NULL,
                points     INT         NOT NULL DEFAULT 0,
                updated_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (zone_id, gang)
            )
        ]])

        LoadZones()
    end)

    if not ok then print('[pengu_turf] BOOT FAILED: ' .. tostring(err)) end
    PublishTurf()
    PublishLive()
    print(('[pengu_turf] %s (%d zones).'):format(ok and 'ready' or 'DEGRADED', zoneCount()))
end)
