--[[
    pengu_mdt - SERVER (REDESIGN2 overhaul)
    Standalone Qbox MDT. Stack: qbx_core + ox_lib + oxmysql + xt-prison + screenshot-basic.

    HARD RULES enforced here:
      - NO citizenid is EVER returned to the NUI. All person targeting is BY NAME.
        The server resolves name->citizenid INTERNALLY for storage/queries only.
      - The Arrest Calculator (placeCharges) ONLY records charges as OUTSTANDING.
        It performs NO jailing and NO fining.
      - Imprisonment + forced fines happen EXCLUSIVELY via the /jail command at the
        Department of Corrections (DOC). It sums a target's outstanding charges,
        jails (xt-prison, caps at 60), force-removes the fine from bank, then flips
        those rows to status='processed' (clearing them from Person/Warrants views).

    Callbacks (dual-registered under pengu_mdt:<name> AND pengu_mdt:server:<name>):
      LEO-only (getOfficer): getDashboard, placeCharges, getBolos, createBolo,
        cancelBolo, createReport, getCameras, setWanted
      LEO + court (getMdtUser; judge/lawyer read-only): searchVehicle,
        searchPerson, getPenalCode, getWarrants (derived, online-only),
        getReports, getReport, getBodycam
      EMS-only (getEms; on-duty job 'ambulance'): searchMedical,
        getRecentMedical. EMS gets NOTHING else, and LEO/court get NO
        medical data (medical privacy) - see pengu_mdt_medical below.

    WANTED LEVEL (0-5, pengu_mdt_wanted): auto-derived on placeCharges, cleared
    by /jail, manual via /wanted, /unwanted + the setWanted MDT action, offline
    decay, dispatch BOLO ping at level >= 3. Exports: GetWantedLevel(cid),
    SetWantedLevel(cid, level, reason).
]]

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

-- Department of Corrections anchor (suspect must be within 50m for /jail).
local DOC = vec3(1845.83, 2585.90, 45.67)
local DOC_RADIUS = 50.0
-- PenguRP: /jail now processes at the pdloc 'cell' marker (GlobalState.penguJailAnchor), not the
-- fixed DOC above. Proximity radius for BOTH the officer and the suspect around that marker.
local JAIL_RADIUS = 20.0

-- Static camera feeds. Coords stay SERVER-SIDE; getCameras exposes only {id,label}.
-- (The client duplicates this table for the actual scripted-cam placement.)
local CAMERAS = {
    { id = 'mrpd_lobby',       label = 'MRPD - Lobby',           cam = vec3(441.0, -979.0, 31.5),    point = vec3(441.5, -982.6, 30.7) },
    { id = 'mrpd_cells',       label = 'MRPD - Cell Block',      cam = vec3(461.5, -994.0, 30.7),    point = vec3(465.5, -1000.5, 24.9) },
    { id = 'legion_sq',        label = 'Legion Square',          cam = vec3(190.0, -933.0, 40.0),    point = vec3(195.5, -933.9, 30.7) },
    { id = 'pacific_bank',     label = 'Pacific Standard Bank',  cam = vec3(248.0, 225.0, 112.0),    point = vec3(235.0, 216.0, 106.3) },
    { id = 'fleeca_legion',    label = 'Fleeca - Alta St',       cam = vec3(146.5, -1045.5, 33.5),   point = vec3(151.0, -1037.0, 29.4) },
    { id = 'fleeca_hawick',    label = 'Fleeca - Hawick Ave',    cam = vec3(-355.5, -44.5, 53.5),    point = vec3(-350.5, -52.5, 49.0) },
    { id = 'store_strawberry', label = '24/7 - Strawberry Ave',  cam = vec3(29.5, -1340.5, 33.5),    point = vec3(24.5, -1348.5, 29.5) },
    { id = 'store_sandy',      label = '24/7 - Sandy Shores',    cam = vec3(1965.5, 3745.0, 36.0),   point = vec3(1959.0, 3741.0, 32.3) },
    { id = 'vespucci_pd',      label = 'Vespucci Police Station',cam = vec3(-1100.0, -835.0, 19.0),  point = vec3(-1110.0, -846.0, 13.5) },
    { id = 'sandy_sheriff',    label = 'Sandy Shores Sheriff',   cam = vec3(1860.0, 3679.0, 38.0),   point = vec3(1852.0, 3689.5, 34.0) },
    { id = 'paleto_sheriff',   label = 'Paleto Bay Sheriff',     cam = vec3(-437.0, 6021.0, 36.5),   point = vec3(-448.5, 6007.0, 31.7) },
    { id = 'doc_yard',         label = 'Bolingbroke DOC - Yard', cam = vec3(1850.0, 2600.0, 55.0),   point = vec3(1845.8, 2585.9, 45.7) },
    { id = 'vinewood_blvd',    label = 'Vinewood Boulevard',     cam = vec3(294.0, 207.0, 92.0),     point = vec3(305.0, 195.0, 84.0) },
    { id = 'del_perro',        label = 'Del Perro Pier',         cam = vec3(-1843.0, -1242.0, 18.5), point = vec3(-1856.0, -1228.0, 12.5) },
    { id = 'lsia',             label = 'LS Intl Airport',        cam = vec3(-1031.0, -2730.0, 25.5), point = vec3(-1042.0, -2744.0, 19.5) },
    { id = 'casino',           label = 'Diamond Casino & Resort',cam = vec3(935.0, 46.0, 85.0),      point = vec3(924.5, 46.5, 80.0) },
    { id = 'paleto_bank',      label = 'Blaine County Savings',  cam = vec3(-93.0, 6453.0, 35.0),    point = vec3(-105.0, 6463.0, 31.5) },
    { id = 'fleeca_route68',   label = 'Fleeca - Route 68',      cam = vec3(1166.0, 2715.0, 42.0),   point = vec3(1175.0, 2708.0, 38.0) },
    { id = 'store_seoul',      label = '24/7 - Little Seoul',    cam = vec3(-700.0, -912.0, 24.0),   point = vec3(-709.0, -904.0, 19.5) },
    { id = 'store_grapeseed',  label = '24/7 - Grapeseed',       cam = vec3(1707.0, 4922.0, 46.0),   point = vec3(1697.0, 4924.0, 42.5) },
    { id = 'grove_st',         label = 'Grove Street - Davis',   cam = vec3(108.0, -1930.0, 25.0),   point = vec3(96.0, -1921.0, 20.8) },
    { id = 'forum_dr',         label = 'Forum Drive - Davis',    cam = vec3(-150.0, -1648.0, 38.0),  point = vec3(-163.0, -1641.0, 33.0) },
    { id = 'ls_docks',         label = 'LS Port - Terminal',     cam = vec3(390.0, -2640.0, 12.0),   point = vec3(382.0, -2622.0, 6.5) },
    { id = 'senora_fwy',       label = 'Senora Freeway (Rt 68)', cam = vec3(2585.0, 1680.0, 38.0),   point = vec3(2600.0, 1690.0, 32.0) },
    { id = 'sandy_airfield',   label = 'Sandy Shores Airfield',  cam = vec3(1745.0, 3295.0, 45.0),   point = vec3(1730.0, 3308.0, 41.0) },
    -- Expansion: full-map MDT coverage (banks, stores, PD/SO, gangs, highways, docks, airport, beaches, county).
    { id = 'fleeca_great_ocean', label = 'Fleeca - Great Ocean Hwy',  cam = vec3(-2956.0, 489.0, 21.0),   point = vec3(-2962.6, 482.6, 15.7) },
    { id = 'fleeca_del_perro',   label = 'Fleeca - Del Perro',        cam = vec3(-1205.0, -322.0, 43.0),  point = vec3(-1212.9, -330.8, 37.8) },
    { id = 'store_morningwood',  label = '24/7 - Morningwood',        cam = vec3(-1480.0, -372.0, 45.0),  point = vec3(-1487.6, -379.1, 40.2) },
    { id = 'store_harmony',      label = '24/7 - Harmony (Rt 68)',    cam = vec3(556.0, 2678.0, 47.0),    point = vec3(547.4, 2671.8, 42.2) },
    { id = 'store_paleto',       label = '24/7 - Paleto Bay',         cam = vec3(1736.0, 6423.0, 40.0),   point = vec3(1729.2, 6414.1, 35.0) },
    { id = 'store_mirror_park',  label = 'LTD - Mirror Park',         cam = vec3(1172.0, -316.0, 74.0),   point = vec3(1163.9, -323.8, 69.2) },
    { id = 'store_davis',        label = '24/7 - Davis (Carson Ave)', cam = vec3(-40.0, -1748.0, 34.0),   point = vec3(-47.5, -1757.5, 29.4) },
    { id = 'vinewood_pd',        label = 'Vinewood Police Station',   cam = vec3(629.0, 9.0, 88.0),       point = vec3(638.0, 1.0, 82.8) },
    { id = 'la_mesa_pd',         label = 'La Mesa Police Depot',      cam = vec3(835.0, -1281.0, 33.0),   point = vec3(826.0, -1290.0, 28.2) },
    { id = 'vagos_elburro',      label = 'Vagos Turf - El Burro',     cam = vec3(1382.0, -1511.0, 62.0),  point = vec3(1390.0, -1520.0, 57.0) },
    { id = 'ballas_chamberlain', label = 'Ballas Turf - Chamberlain', cam = vec3(-138.0, -1890.0, 29.0),  point = vec3(-130.0, -1899.0, 24.0) },
    { id = 'oneil_ranch',        label = 'O Neil Ranch - Grapeseed',  cam = vec3(2432.0, 4962.0, 51.0),   point = vec3(2440.0, 4970.0, 45.0) },
    { id = 'lost_mc_stab',       label = 'Lost MC - Stab City',       cam = vec3(100.0, 3712.0, 45.0),    point = vec3(108.0, 3704.0, 39.6) },
    { id = 'vespucci_beach',     label = 'Vespucci Beach Boardwalk',  cam = vec3(-1230.0, -1499.0, 10.0), point = vec3(-1223.0, -1507.0, 4.4) },
    { id = 'mirror_park_lake',   label = 'Mirror Park Lake',          cam = vec3(1090.0, -700.0, 63.0),   point = vec3(1082.0, -710.0, 57.0) },
    { id = 'del_perro_fwy',      label = 'Del Perro Fwy Overpass',    cam = vec3(-1282.0, -551.0, 33.0),  point = vec3(-1290.0, -560.0, 26.0) },
    { id = 'la_puerta_fwy',      label = 'La Puerta Freeway',         cam = vec3(-512.0, -2071.0, 33.0),  point = vec3(-520.0, -2080.0, 26.0) },
    { id = 'elysian_island',     label = 'Elysian Island Docks',     cam = vec3(258.0, -2881.0, 13.0),   point = vec3(250.0, -2890.0, 6.0) },
    { id = 'lsia_runway',        label = 'LSIA - Runway / Tower',     cam = vec3(-1292.0, -3001.0, 22.0), point = vec3(-1300.0, -3010.0, 14.0) },
    { id = 'paleto_main',        label = 'Paleto Bay Boulevard',      cam = vec3(-102.0, 6318.0, 37.0),   point = vec3(-110.0, 6310.0, 31.0) },
    { id = 'grapeseed_main',     label = 'Grapeseed Main Street',     cam = vec3(1698.0, 4818.0, 47.0),   point = vec3(1690.0, 4810.0, 42.0) },
    { id = 'maze_arena',         label = 'Maze Bank Arena',           cam = vec3(-242.0, -2021.0, 37.0),  point = vec3(-250.0, -2030.0, 30.0) },
}


----------------------------------------------------------------------
-- SQL - schema (idempotent CREATE; migrations handled in ensureColumn)
----------------------------------------------------------------------

local CREATE_CHARGES_SQL = [[
CREATE TABLE IF NOT EXISTS pengu_mdt_charges (
  id INT AUTO_INCREMENT PRIMARY KEY,
  citizenid VARCHAR(64),
  code VARCHAR(16),
  title VARCHAR(128),
  class VARCHAR(16),
  months INT,
  fine INT,
  modifiers VARCHAR(128),
  officer VARCHAR(128),
  plea VARCHAR(16) DEFAULT 'Guilty',
  status VARCHAR(16) DEFAULT 'outstanding',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
]]

local CREATE_BOLOS_SQL = [[
CREATE TABLE IF NOT EXISTS pengu_mdt_bolos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  type VARCHAR(16) DEFAULT 'person',
  title VARCHAR(128) NOT NULL,
  description TEXT,
  image_url VARCHAR(512) DEFAULT '',
  image_urls TEXT,
  officer VARCHAR(128),
  status VARCHAR(16) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
]]

local CREATE_REPORTS_SQL = [[
CREATE TABLE IF NOT EXISTS pengu_mdt_reports (
  id INT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(128) NOT NULL,
  type VARCHAR(32) DEFAULT 'Incident',
  content TEXT,
  subject_name VARCHAR(128) DEFAULT '',
  officer VARCHAR(128),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
]]

local CREATE_MUGSHOTS_SQL = [[
CREATE TABLE IF NOT EXISTS pengu_mdt_mugshots (
  citizenid VARCHAR(64) PRIMARY KEY,
  image MEDIUMTEXT,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
)
]]

-- One row per citizen who has been fingerprinted. Presence = "on file" (the Person tab shows a
-- boolean; the citizenid itself is never sent to the NUI, preserving the anti-metagaming rule).
local CREATE_PRINTS_SQL = [[
CREATE TABLE IF NOT EXISTS pengu_mdt_prints (
  citizenid VARCHAR(64) PRIMARY KEY,
  officer VARCHAR(128) DEFAULT '',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
)
]]

-- One row per actual /jail execution. The Person tab "imprisonments" total is a
-- COUNT of these rows - NOT how many charges carry prison time.
local CREATE_IMPRISONMENTS_SQL = [[
CREATE TABLE IF NOT EXISTS pengu_mdt_imprisonments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  citizenid VARCHAR(64) NOT NULL,
  officer VARCHAR(128) DEFAULT '',
  months INT DEFAULT 0,
  fine INT DEFAULT 0,
  charges INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_imp_cid (citizenid)
)
]]

-- Bodycam archive: one row per captured frame; pruned to the newest 20
-- rows per officer on every insert.
local CREATE_BODYCAM_SQL = [[
CREATE TABLE IF NOT EXISTS pengu_mdt_bodycam (
  id INT AUTO_INCREMENT PRIMARY KEY,
  officer_cid VARCHAR(64) NOT NULL,
  officer_name VARCHAR(128) DEFAULT '',
  captured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  image LONGTEXT,
  INDEX idx_bodycam_cid (officer_cid)
)
]]

-- Wanted levels (1-5): one row per wanted citizen; level 0 = row deleted.
local CREATE_WANTED_SQL = [[
CREATE TABLE IF NOT EXISTS pengu_mdt_wanted (
  citizenid VARCHAR(64) PRIMARY KEY,
  level TINYINT NOT NULL DEFAULT 1,
  reason VARCHAR(255) DEFAULT '',
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
)
]]

-- EMS medical log (revives + treatment item uses). Written ONLY via the
-- server-only 'pengu_mdt:server:medicalLog' event (qbx_ambulancejob hooks);
-- pruned to the newest 500 rows TOTAL on every insert.
local CREATE_MEDICAL_SQL = [[
CREATE TABLE IF NOT EXISTS pengu_mdt_medical (
  id INT AUTO_INCREMENT PRIMARY KEY,
  citizenid VARCHAR(64) NOT NULL,
  patient_name VARCHAR(128) DEFAULT '',
  medic_name VARCHAR(128) DEFAULT '',
  action VARCHAR(32) NOT NULL,
  detail VARCHAR(128) DEFAULT '',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_medical_cid (citizenid)
)
]]

----------------------------------------------------------------------
-- SQL - lookups
----------------------------------------------------------------------

local VEHICLE_SQL = [[
SELECT
  pv.plate                                         AS plate,
  pv.vehicle                                       AS model,
  CONCAT('VIN-', LPAD(pv.id, 8, '0'))              AS vin,
  TRIM(CONCAT(
    COALESCE(JSON_VALUE(p.charinfo,'$.firstname'),''),' ',
    COALESCE(JSON_VALUE(p.charinfo,'$.lastname'),'')))  AS owner,
  COALESCE(p.phone_number, JSON_VALUE(p.charinfo,'$.phone')) AS phone
FROM player_vehicles pv
LEFT JOIN players p ON p.citizenid = pv.citizenid
WHERE REPLACE(UPPER(pv.plate),' ','') = REPLACE(UPPER(?),' ','')
LIMIT 1
]]

-- Resolves a NAME (or phone) to a single person; cid stays server-side only.
local PERSON_SQL = [[
SELECT
  citizenid                                        AS cid,
  TRIM(CONCAT(
    COALESCE(JSON_VALUE(charinfo,'$.firstname'),''),' ',
    COALESCE(JSON_VALUE(charinfo,'$.lastname'),''))) AS name,
  COALESCE(phone_number, JSON_VALUE(charinfo,'$.phone')) AS phone
FROM players
WHERE CONCAT(JSON_VALUE(charinfo,'$.firstname'),' ',JSON_VALUE(charinfo,'$.lastname')) LIKE ?
   OR JSON_VALUE(charinfo,'$.firstname') LIKE ?
   OR JSON_VALUE(charinfo,'$.lastname')  LIKE ?
   OR phone_number LIKE ?
   OR JSON_VALUE(charinfo,'$.phone') LIKE ?
LIMIT 1
]]

-- Lifetime totals (ALL statuses - represents the person's record).
local TOTALS_SQL = [[
SELECT
  COUNT(*)                            AS charges,
  COALESCE(SUM(class = 'citation'),0) AS citations
FROM pengu_mdt_charges
WHERE citizenid = ?
]]

-- Actual imprisonments = number of times /jail was executed on this person.
local IMPRISONMENTS_COUNT_SQL = [[
SELECT COUNT(*) AS imprisonments FROM pengu_mdt_imprisonments WHERE citizenid = ?
]]

-- Guilty plea cuts this fraction off the remaining sentence.
local PLEA_GUILTY_PCT = 0.25

-- Processed charge history (rap sheet): each past charge/citation + its case plea.
local HISTORY_FOR_PERSON_SQL = [[
SELECT c.code, c.title, c.class, c.months, c.fine, i.plea AS plea
FROM pengu_mdt_charges c
LEFT JOIN pengu_mdt_imprisonments i ON i.id = c.case_id
WHERE c.citizenid = ? AND c.status = 'processed'
ORDER BY c.created_at DESC
LIMIT 60
]]

local INSERT_IMPRISONMENT_SQL = [[
INSERT INTO pengu_mdt_imprisonments (citizenid, officer, months, fine, charges)
VALUES (?, ?, ?, ?, ?)
]]

-- Outstanding charges for a person (Person tab outstanding list).
local OUTSTANDING_FOR_PERSON_SQL = [[
SELECT code, title, class, months, fine, modifiers
FROM pengu_mdt_charges
WHERE citizenid = ? AND status = 'outstanding'
ORDER BY created_at DESC
]]

-- Sum of outstanding charges (used by /jail + derived Warrants).
local SUM_OUTSTANDING_SQL = [[
SELECT
  COALESCE(SUM(months),0) AS months,
  COALESCE(SUM(fine),0)   AS fine,
  COUNT(*)                AS charges
FROM pengu_mdt_charges
WHERE citizenid = ? AND status = 'outstanding'
]]

-- Flip served rows to processed (clears them from outstanding + warrants).
local MARK_PROCESSED_SQL = [[
UPDATE pengu_mdt_charges SET status = 'processed'
WHERE citizenid = ? AND status = 'outstanding'
]]

local INSERT_CHARGE_SQL = [[
INSERT INTO pengu_mdt_charges
  (citizenid, code, title, class, months, fine, modifiers, officer, plea, status)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
]]

-- Mugshots
local MUGSHOT_SELECT_SQL = [[
SELECT image FROM pengu_mdt_mugshots WHERE citizenid = ? LIMIT 1
]]

local MUGSHOT_UPSERT_SQL = [[
INSERT INTO pengu_mdt_mugshots (citizenid, image) VALUES (?, ?)
ON DUPLICATE KEY UPDATE image = VALUES(image), updated_at = CURRENT_TIMESTAMP
]]

-- Fingerprints (boolean on-file lookup + collect upsert)
local PRINTS_SELECT_SQL = [[
SELECT 1 AS has FROM pengu_mdt_prints WHERE citizenid = ? LIMIT 1
]]

local PRINTS_UPSERT_SQL = [[
INSERT INTO pengu_mdt_prints (citizenid, officer) VALUES (?, ?)
ON DUPLICATE KEY UPDATE officer = VALUES(officer), updated_at = CURRENT_TIMESTAMP
]]

-- BOLOs
local BOLOS_SELECT_SQL = [[
SELECT id, type, title, description, image_url, image_urls, officer,
  DATE_FORMAT(created_at,'%Y-%m-%d %H:%i') AS created_at
FROM pengu_mdt_bolos
WHERE status = 'active'
ORDER BY created_at DESC
LIMIT 50
]]

local BOLOS_INSERT_SQL = [[
INSERT INTO pengu_mdt_bolos (type, title, description, image_url, image_urls, officer, status)
VALUES (?, ?, ?, ?, ?, ?, 'active')
]]

local BOLOS_CANCEL_SQL = [[
UPDATE pengu_mdt_bolos SET status = 'cancelled' WHERE id = ?
]]

-- Reports
local REPORTS_SELECT_SQL = [[
SELECT id, title, type, subject_name, officer,
  DATE_FORMAT(created_at,'%Y-%m-%d %H:%i') AS created_at
FROM pengu_mdt_reports
ORDER BY created_at DESC
LIMIT 50
]]

local REPORT_SELECT_SQL = [[
SELECT id, title, type, content, subject_name, officer,
  DATE_FORMAT(created_at,'%Y-%m-%d %H:%i') AS created_at
FROM pengu_mdt_reports
WHERE id = ?
LIMIT 1
]]

local REPORTS_INSERT_SQL = [[
INSERT INTO pengu_mdt_reports (title, type, content, subject_name, officer)
VALUES (?, ?, ?, ?, ?)
]]

-- Bodycam
local BODYCAM_SELECT_SQL = [[
SELECT id, officer_name,
  DATE_FORMAT(captured_at,'%Y-%m-%d %H:%i:%s') AS captured_at, image
FROM pengu_mdt_bodycam
ORDER BY id DESC
LIMIT 30
]]

local BODYCAM_INSERT_SQL = [[
INSERT INTO pengu_mdt_bodycam (officer_cid, officer_name, image) VALUES (?, ?, ?)
]]

-- Prune to the newest 20 frames per officer (the derived-table wrapper is
-- required so MySQL/MariaDB allows deleting from the table being selected).
local BODYCAM_PRUNE_SQL = [[
DELETE FROM pengu_mdt_bodycam
WHERE officer_cid = ? AND id NOT IN (
  SELECT id FROM (
    SELECT id FROM pengu_mdt_bodycam WHERE officer_cid = ? ORDER BY id DESC LIMIT 20
  ) keep_newest
)
]]

-- Wanted level lookups
local WANTED_SELECT_SQL = [[
SELECT level, reason FROM pengu_mdt_wanted WHERE citizenid = ? LIMIT 1
]]

local WANTED_UPSERT_SQL = [[
INSERT INTO pengu_mdt_wanted (citizenid, level, reason) VALUES (?, ?, ?)
ON DUPLICATE KEY UPDATE level = VALUES(level), reason = VALUES(reason), updated_at = CURRENT_TIMESTAMP
]]

local WANTED_DELETE_SQL = [[
DELETE FROM pengu_mdt_wanted WHERE citizenid = ?
]]

local WANTED_ALL_SQL = [[
SELECT citizenid, level, reason FROM pengu_mdt_wanted
]]

local WANTED_HIGH_SQL = [[
SELECT citizenid, level, reason FROM pengu_mdt_wanted WHERE level >= 3
]]

-- Medical log (EMS tab): per-patient history + the newest-30 activity feed.
local MEDICAL_INSERT_SQL = [[
INSERT INTO pengu_mdt_medical (citizenid, patient_name, medic_name, action, detail)
VALUES (?, ?, ?, ?, ?)
]]

-- Prune to the newest 500 rows TOTAL (same derived-table wrapper as bodycam
-- so MySQL/MariaDB allows deleting from the table being selected).
local MEDICAL_PRUNE_SQL = [[
DELETE FROM pengu_mdt_medical
WHERE id NOT IN (
  SELECT id FROM (
    SELECT id FROM pengu_mdt_medical ORDER BY id DESC LIMIT 500
  ) keep_newest
)
]]

local MEDICAL_FOR_PERSON_SQL = [[
SELECT action, detail, medic_name,
  DATE_FORMAT(created_at,'%Y-%m-%d %H:%i') AS created_at
FROM pengu_mdt_medical
WHERE citizenid = ?
ORDER BY id DESC
LIMIT 60
]]

local MEDICAL_RECENT_SQL = [[
SELECT patient_name, action, detail, medic_name,
  DATE_FORMAT(created_at,'%Y-%m-%d %H:%i') AS created_at
FROM pengu_mdt_medical
ORDER BY id DESC
LIMIT 30
]]

-- Outstanding charge severity for the derived (automatic) wanted level.
local WANTED_SEVERITY_SQL = [[
SELECT
  COALESCE(SUM(class = 'felony'),0)      AS felonies,
  COALESCE(SUM(class = 'misdemeanor'),0) AS misdemeanors,
  COALESCE(SUM(class = 'citation'),0)    AS citations,
  COALESCE(MAX(months),0)                AS maxmonths
FROM pengu_mdt_charges
WHERE citizenid = ? AND status = 'outstanding'
]]

----------------------------------------------------------------------
-- PenalCode indices (built from the global shared table)
----------------------------------------------------------------------

local chargeIndex, modIndex

local function buildPenalIndex()
    chargeIndex, modIndex = {}, {}
    if type(PenalCode) ~= 'table' then return end
    for _, c in ipairs(PenalCode.charges or {}) do
        if c.code then chargeIndex[c.code] = c end
    end
    for _, m in ipairs(PenalCode.modifiers or {}) do
        if m.id then modIndex[m.id] = m end
    end
end

local function ensureIndex()
    if not chargeIndex or not modIndex then buildPenalIndex() end
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- Returns the officer Player object only if source is an ON-DUTY LEO, else nil.
-- (Off-duty officers cannot use any MDT callback or /jail.)
local function getOfficer(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or not player.PlayerData then return nil end
    local job = player.PlayerData.job
    if not job or job.type ~= 'leo' or not job.onduty then return nil end
    return player
end

-- Court access: judge/lawyer (qbx_core/shared/jobs.lua job names). Returns the
-- Player object or nil. Court users get a RESTRICTED read-only MDT role:
-- searchPerson, searchVehicle, getPenalCode, getWarrants, getReports,
-- getReport, getBodycam ONLY. Everything else stays getOfficer-gated.
local function isCourt(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or not player.PlayerData then return nil end
    local job = player.PlayerData.job
    if not job or (job.name ~= 'judge' and job.name ~= 'lawyer') then return nil end
    return player
end

-- Shared read-only gate: on-duty LEO OR court (judge/lawyer).
local function getMdtUser(source)
    return getOfficer(source) or isCourt(source)
end

-- EMS access: ON-DUTY 'ambulance' job ONLY (qbx_core/shared/jobs.lua). EMS
-- users get the two Medical callbacks and NOTHING else; every LEO/court
-- callback keeps its getOfficer/getMdtUser gate, which already rejects ems
-- (job.type 'ems' is not 'leo' and 'ambulance' is not judge/lawyer). And
-- getEms rejects LEO/court in turn - medical data is EMS-only (privacy).
local function getEms(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or not player.PlayerData then return nil end
    local job = player.PlayerData.job
    if not job or job.name ~= 'ambulance' or not job.onduty then return nil end
    return player
end

-- Build a "First Last" display name from a charinfo table.
local function fullName(ci)
    ci = ci or {}
    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return 'Unknown' end
    return name
end

local function officerName(player)
    local name = fullName(player.PlayerData and player.PlayerData.charinfo)
    if name == 'Unknown' then return 'Unknown Officer' end
    return name
end

-- PenguRP: MDT feedback goes to chat (qbx_chat_theme 'pengu:admin' template), not a toast.
-- tag defaults to 'DOC' (the jail / sentencing / plea flow = Department of Corrections); police MDT
-- functions (units, fingerprints, booking) pass 'LEO' via leoNotify below.
local NKIND = { success = 'ok', error = 'err', inform = 'info' }
local function notify(src, message, ntype, tag)
    if not src or src == 0 then return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { tag or 'DOC', message, NKIND[ntype or 'inform'] or 'info' },
    })
end

-- LEO-tagged feedback for police functions (unit callsigns, fingerprints, mugshot booking).
local function leoNotify(src, message, ntype)
    notify(src, message, ntype, 'LEO')
end

----------------------------------------------------------------------
-- Wanted level (0-5). GTA native wanted is disabled server-wide; this is the
-- replacement. Server-authoritative, keyed by citizenid (never sent to any NUI).
--   AUTO:  placeCharges raises the level from outstanding charge severity.
--   CLEAR: /jail processing (charges -> processed) deletes the row.
--   DECAY: -1 level per 30 continuous minutes OFFLINE (online players stay wanted).
--   PING:  level >= 3 sends a BOLO-style dispatch on connect + every 10 min online
--          (via the shared exports.pengu_core:Dispatch relay, pcall-guarded).
----------------------------------------------------------------------

local WANTED_MAX = 5
local WANTED_DECAY_SECONDS = 30 * 60
local WANTED_PING_MS = 10 * 60 * 1000

local offlineSecs = {} -- [citizenid] = offline seconds accrued toward the next decay step

local function clampWanted(level)
    level = math.floor(tonumber(level) or 0)
    if level < 0 then return 0 end
    if level > WANTED_MAX then return WANTED_MAX end
    return level
end

-- -> level (0 = not wanted), reason
local function getWantedLevel(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return 0, '' end
    local row = MySQL.single.await(WANTED_SELECT_SQL, { citizenid })
    if not row then return 0, '' end
    return clampWanted(row.level), row.reason or ''
end

-- Level 0 deletes the row; 1-5 upserts. Resets the decay clock on every change.
local function setWantedLevel(citizenid, level, reason)
    if type(citizenid) ~= 'string' or citizenid == '' then return false end
    level = clampWanted(level)
    offlineSecs[citizenid] = nil
    if level == 0 then
        MySQL.query.await(WANTED_DELETE_SQL, { citizenid })
        return true
    end
    if type(reason) ~= 'string' then reason = '' end
    MySQL.query.await(WANTED_UPSERT_SQL, { citizenid, level, reason:sub(1, 255) })
    return true
end

-- Exports for future systems (server-side; citizenid in, never through a NUI).
exports('GetWantedLevel', function(citizenid)
    local level = getWantedLevel(citizenid)
    return level
end)

exports('SetWantedLevel', function(citizenid, level, reason)
    return setWantedLevel(citizenid, level, reason)
end)

-- Outstanding severity -> derived level: 3+ felonies or any charge >= 30 months
-- -> 5; any felony -> 3; misdemeanors only -> 2; citations only -> 1; none -> 0.
local function deriveWantedLevel(citizenid)
    local row = MySQL.single.await(WANTED_SEVERITY_SQL, { citizenid })
    if not row then return 0 end
    local felonies = tonumber(row.felonies) or 0
    if felonies >= 3 or (tonumber(row.maxmonths) or 0) >= 30 then return 5 end
    if felonies > 0 then return 3 end
    if (tonumber(row.misdemeanors) or 0) > 0 then return 2 end
    if (tonumber(row.citations) or 0) > 0 then return 1 end
    return 0
end

-- BOLO ping for an ONLINE wanted citizen (level >= 3). Uses the shared
-- pengu_core dispatch relay (one officer client fires ps-dispatch CustomAlert).
local function sendWantedAlert(player, level, reason)
    local ped = GetPlayerPed(player.PlayerData.source)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)
    local name = fullName(player.PlayerData.charinfo)
    local message
    if level >= WANTED_MAX then
        message = ('BOLO: %s - WANTED 5/5 - ARMED AND DANGEROUS - ALL UNITS'):format(name)
    else
        message = ('BOLO: %s - WANTED %d/5 - approach with caution'):format(name, level)
    end
    if type(reason) == 'string' and reason ~= '' then
        message = ('%s (%s)'):format(message, reason:sub(1, 80))
    end
    pcall(function()
        exports.pengu_core:Dispatch(coords, {
            message = message,
            code = '10-99',
            icon = 'fas fa-star',
            priority = level >= WANTED_MAX and 1 or 2,
        })
    end)
end

----------------------------------------------------------------------
-- Callback handlers
----------------------------------------------------------------------

-- getDashboard {} -> { units:[{callsign, members:[name], unassigned?}] }  (ON-DUTY leo only).
-- Officers are GROUPED by callsign so the dashboard shows each unit + who is in it; officers with
-- no callsign are collected under an 'Unassigned' pseudo-unit. (No job label - removed.)
local function handleGetDashboard(source)
    if not getOfficer(source) then return { units = {} } end

    local byUnit, solo = {}, {}
    local players = exports.qbx_core:GetQBPlayers() or {}
    for _, p in pairs(players) do
        local pd = p.PlayerData
        if pd and pd.job and pd.job.type == 'leo' and pd.job.onduty then
            local cs = (pd.metadata and pd.metadata.callsign) or ''
            local name = fullName(pd.charinfo)
            if cs == '' or cs == 'NO CALLSIGN' then
                solo[#solo + 1] = name
            else
                byUnit[cs] = byUnit[cs] or {}
                byUnit[cs][#byUnit[cs] + 1] = name
            end
        end
    end

    local units = {}
    for cs, members in pairs(byUnit) do
        table.sort(members)
        units[#units + 1] = { callsign = cs, members = members }
    end
    table.sort(units, function(a, b) return a.callsign < b.callsign end)
    if #solo > 0 then
        table.sort(solo)
        units[#units + 1] = { callsign = '-', members = solo, unassigned = true }
    end
    return { units = units }
end

-- searchVehicle {plate} -> { found, owner, model, plate, vin, phone }  (NO cid)
-- Read-only: available to court (judge/lawyer) as well as LEO.
local function handleSearchVehicle(source, data)
    if not getMdtUser(source) then return { found = false } end

    local plate = data and data.plate
    if type(plate) ~= 'string' or plate == '' then return { found = false } end

    local row = MySQL.single.await(VEHICLE_SQL, { plate })
    if not row then return { found = false } end

    return {
        found = true,
        owner = row.owner,
        model = row.model,
        plate = row.plate,
        vin = row.vin,
        phone = row.phone,
    }
end

-- searchPerson {name} -> { found, name, mugshot, phone, totals, outstanding, history, prints }  (NO cid)
-- Read-only: available to court (judge/lawyer) as well as LEO.
local function handleSearchPerson(source, data)
    if not getMdtUser(source) then return { found = false } end

    local name = data and data.name
    if type(name) ~= 'string' or name == '' then return { found = false } end

    local q = '%' .. name .. '%'
    local row = MySQL.single.await(PERSON_SQL, { q, q, q, q, q })
    if not row then return { found = false } end

    local cid = row.cid -- internal only; never returned

    local totalsRow = MySQL.single.await(TOTALS_SQL, { cid })
    local impRow = MySQL.single.await(IMPRISONMENTS_COUNT_SQL, { cid })
    local totals = {
        charges = totalsRow and tonumber(totalsRow.charges) or 0,
        citations = totalsRow and tonumber(totalsRow.citations) or 0,
        imprisonments = impRow and tonumber(impRow.imprisonments) or 0,
    }

    local outstanding = MySQL.query.await(OUTSTANDING_FOR_PERSON_SQL, { cid }) or {}
    for _, c in ipairs(outstanding) do
        c.months = tonumber(c.months) or 0
        c.fine = tonumber(c.fine) or 0
        c.modifiers = c.modifiers or ''
    end

    local mugRow = MySQL.single.await(MUGSHOT_SELECT_SQL, { cid })
    local mugshot = mugRow and mugRow.image
    if mugshot == '' then mugshot = nil end -- omitted key -> NUI shows placeholder

    -- Fingerprints on file? Boolean only - the cid never leaves the server (anti-metagaming).
    local printRow = MySQL.single.await(PRINTS_SELECT_SQL, { cid })
    local hasPrints = printRow ~= nil

    -- Mugshots are downscaled to ~50KB at capture (in the MDT's own NUI), so they
    -- are small enough to return inline here without overflowing the net event.

    -- Processed charge history (rap sheet) with the plea per charge (N/A for citations).
    local historyRows = MySQL.query.await(HISTORY_FOR_PERSON_SQL, { cid }) or {}
    local history = {}
    for _, h in ipairs(historyRows) do
        local months = tonumber(h.months) or 0
        local isCitation = (h.class == 'citation')
        history[#history + 1] = {
            code = h.code,
            title = h.title,
            class = h.class,
            months = months,
            fine = tonumber(h.fine) or 0,
            outcome = months > 0 and 'served' or 'paid',
            plea = isCitation and 'na' or (h.plea or 'na'),
        }
    end

    -- Current wanted level (0 = not wanted) + reason; stars render in the NUI.
    local wLevel, wReason = getWantedLevel(cid)

    return {
        found = true,
        name = row.name,
        mugshot = mugshot,
        phone = row.phone,
        totals = totals,
        outstanding = outstanding,
        history = history,
        prints = hasPrints,
        wanted = { level = wLevel, reason = wReason },
    }
end

-- getPenalCode {} -> { charges, modifiers }  (read-only: LEO + court)
local function handleGetPenalCode(source)
    if not getMdtUser(source) then return { charges = {}, modifiers = {} } end
    if type(PenalCode) ~= 'table' then return { charges = {}, modifiers = {} } end
    return {
        charges = PenalCode.charges or {},
        modifiers = PenalCode.modifiers or {},
    }
end

-- placeCharges {name, items:[{code, modifiers:[id]}]} -> { success, message }
-- AUTHORITATIVE: recompute months/fine; reject blocked modifiers; record as
-- OUTSTANDING only. NO jail, NO fine. NO cid in response.
local function handlePlaceCharges(source, data)
    local officer = getOfficer(source)
    if not officer then return { success = false, message = 'Not authorized' } end
    if type(data) ~= 'table' then return { success = false, message = 'Invalid request' } end

    local name = data.name
    local items = data.items
    if type(name) ~= 'string' or name == '' then
        return { success = false, message = 'No target selected' }
    end
    if type(items) ~= 'table' or #items == 0 then
        return { success = false, message = 'No charges selected' }
    end

    -- Resolve name -> cid server-side ONLY (never returned to the NUI).
    local q = '%' .. name .. '%'
    local prow = MySQL.single.await(PERSON_SQL, { q, q, q, q, q })
    if not prow then return { success = false, message = 'Person not found' } end
    local cid = prow.cid

    ensureIndex()
    if type(PenalCode) ~= 'table' then
        return { success = false, message = 'Penal code unavailable' }
    end

    local offName = officerName(officer)
    local placed = 0
    local rows = {} -- collect; commit only after full validation passes

    for _, item in ipairs(items) do
        local base = item and chargeIndex[item.code]
        if base then -- unknown codes are silently skipped
            local mult = 1.0

            local blocked = {}
            for _, b in ipairs(base.blockedModifiers or {}) do blocked[b] = true end

            local modList = item.modifiers or {}
            for _, modId in ipairs(modList) do
                if blocked[modId] then
                    return { success = false, message = 'Blocked modifier on ' .. base.code }
                end
                local mod = modIndex[modId]
                if mod and tonumber(mod.mult) then
                    mult = mult * tonumber(mod.mult)
                end
            end

            local m = math.floor((tonumber(base.months) or 0) * mult + 0.5)
            local f = math.floor((tonumber(base.fine) or 0) * mult + 0.5)
            placed = placed + 1

            rows[#rows + 1] = {
                cid, base.code, base.title, base.class, m, f,
                table.concat(modList, ','), offName, 'Guilty', 'outstanding',
            }
        end
    end

    if placed == 0 then
        return { success = false, message = 'No valid charges to apply' }
    end

    for _, params in ipairs(rows) do
        MySQL.insert.await(INSERT_CHARGE_SQL, params)
    end

    -- AUTO WANTED: raise (never lower) the level from outstanding charge severity.
    local current = getWantedLevel(cid)
    local derived = deriveWantedLevel(cid)
    if derived > current then
        setWantedLevel(cid, derived, 'Outstanding charges')
    end

    -- Mugshots are NOT auto-captured on charge anymore. An officer takes the photo
    -- deliberately at the pdloc 'mugshot' booking camera (pengu_mdt:storeBookingMugshot).

    return {
        success = true,
        message = ('Recorded %d charge%s as outstanding.'):format(placed, placed == 1 and '' or 's'),
    }
end

-- getBolos {} -> { items:[{id,type,title,description,images,officer,created_at}] }
-- Decodes the image_urls JSON array, validates each link, falls back to the
-- legacy single image_url, and exposes ONLY a clean images[] to the NUI.
local function handleGetBolos(source)
    if not getOfficer(source) then return { items = {} } end
    local rows = MySQL.query.await(BOLOS_SELECT_SQL, {}) or {}
    for _, r in ipairs(rows) do
        local list = {}
        if type(r.image_urls) == 'string' and r.image_urls ~= '' then
            local ok, decoded = pcall(json.decode, r.image_urls)
            if ok and type(decoded) == 'table' then
                for _, u in ipairs(decoded) do
                    if type(u) == 'string' and u:match('^https?://') then
                        list[#list + 1] = u
                    end
                end
            end
        end
        -- Back-compat: a pre-migration row with only the legacy single link.
        if #list == 0 and type(r.image_url) == 'string' and r.image_url:match('^https?://') then
            list[#list + 1] = r.image_url
        end
        r.images = list      -- the ONLY image field the NUI reads
        r.image_url = nil    -- do not leak raw columns to the UI
        r.image_urls = nil
    end
    return { items = rows }
end

-- createBolo {type,title,description,images:[http(s) link]} -> { success, message }
-- Accepts an array of links (legacy single image_url still works). Each link is
-- trimmed, must match ^https?://, is capped at 512 chars, and at most 8 are kept.
local function handleCreateBolo(source, data)
    local officer = getOfficer(source)
    if not officer then return { success = false, message = 'Not authorized' } end
    if type(data) ~= 'table' then return { success = false, message = 'Invalid request' } end

    local title = data.title
    if type(title) ~= 'string' or title:gsub('%s+', '') == '' then
        return { success = false, message = 'Title is required' }
    end

    local btype = data.type
    if btype ~= 'person' and btype ~= 'vehicle' and btype ~= 'other' then
        btype = 'person'
    end
    local description = type(data.description) == 'string' and data.description or ''

    local images = {}
    if type(data.images) == 'table' then
        for _, u in ipairs(data.images) do
            if type(u) == 'string' then
                u = u:gsub('^%s+', ''):gsub('%s+$', '')
                if u:match('^https?://') and #u <= 512 then
                    images[#images + 1] = u
                    if #images >= 8 then break end
                end
            end
        end
    elseif type(data.image_url) == 'string' and data.image_url:match('^https?://') then
        images[1] = data.image_url -- legacy single-link callers still work
    end

    local imagesJson = json.encode(images) -- "[]" when none
    local firstUrl = images[1] or ''        -- keep the legacy column populated

    MySQL.insert.await(BOLOS_INSERT_SQL,
        { btype, title, description, firstUrl, imagesJson, officerName(officer) })
    return { success = true, message = 'BOLO created' }
end

-- cancelBolo {id} -> { success, message }
local function handleCancelBolo(source, data)
    if not getOfficer(source) then return { success = false, message = 'Not authorized' } end
    local id = data and tonumber(data.id)
    if not id then return { success = false, message = 'Invalid BOLO id' } end

    MySQL.update.await(BOLOS_CANCEL_SQL, { id })
    return { success = true, message = 'BOLO cancelled' }
end

-- getWarrants {} -> { items:[{name, charges, months, fine}] }
-- DERIVED: ONLINE players that currently have status='outstanding' charges. NO cid.
-- Read-only: available to court (judge/lawyer) as well as LEO.
local function handleGetWarrants(source)
    if not getMdtUser(source) then return { items = {} } end

    local items = {}
    local players = exports.qbx_core:GetQBPlayers() or {}
    for _, p in pairs(players) do
        local pd = p.PlayerData
        if pd and pd.citizenid then
            local row = MySQL.single.await(SUM_OUTSTANDING_SQL, { pd.citizenid })
            local charges = row and tonumber(row.charges) or 0
            if charges > 0 then
                items[#items + 1] = {
                    name = fullName(pd.charinfo),
                    charges = charges,
                    months = row and tonumber(row.months) or 0,
                    fine = row and tonumber(row.fine) or 0,
                    wanted = getWantedLevel(pd.citizenid),
                }
            end
        end
    end
    return { items = items }
end

-- getReports {} -> { items:[{id,title,type,subject_name,officer,created_at}] }  (read-only: LEO + court)
local function handleGetReports(source)
    if not getMdtUser(source) then return { items = {} } end
    local rows = MySQL.query.await(REPORTS_SELECT_SQL, {}) or {}
    return { items = rows }
end

-- getReport {id} -> { found, report }  (read-only: LEO + court)
local function handleGetReport(source, data)
    if not getMdtUser(source) then return { found = false } end
    local id = data and tonumber(data.id)
    if not id then return { found = false } end

    local row = MySQL.single.await(REPORT_SELECT_SQL, { id })
    if not row then return { found = false } end
    return { found = true, report = row }
end

-- createReport {title,type,content,subject_name} -> { success, message }
local function handleCreateReport(source, data)
    local officer = getOfficer(source)
    if not officer then return { success = false, message = 'Not authorized' } end
    if type(data) ~= 'table' then return { success = false, message = 'Invalid request' } end

    local title = data.title
    if type(title) ~= 'string' or title:gsub('%s+', '') == '' then
        return { success = false, message = 'Title is required' }
    end

    local rtype = data.type
    if rtype ~= 'Incident' and rtype ~= 'Arrest' and rtype ~= 'Other' then
        rtype = 'Incident'
    end
    local content = type(data.content) == 'string' and data.content or ''
    local subject = type(data.subject_name) == 'string' and data.subject_name or ''

    MySQL.insert.await(REPORTS_INSERT_SQL, { title, rtype, content, subject, officerName(officer) })
    return { success = true, message = 'Report filed' }
end

-- getBodycam {} -> { items:[{id, officer, captured_at, image}] }
-- Newest 30 frames across all officers. Frames are downscaled small at capture
-- (same NUI flow as mugshots) so returning them inline is safe.
-- Read-only: available to court (judge/lawyer) as well as LEO.
local function handleGetBodycam(source)
    if not getMdtUser(source) then return { items = {} } end
    local rows = MySQL.query.await(BODYCAM_SELECT_SQL, {}) or {}
    local items = {}
    for _, r in ipairs(rows) do
        items[#items + 1] = {
            id = r.id,
            officer = r.officer_name or 'Unknown',
            captured_at = r.captured_at,
            image = r.image,
        }
    end
    return { items = items }
end

-- getCameras {} -> { feeds:[{id,label}] }  (coords stay server-side)
local function handleGetCameras(source)
    if not getOfficer(source) then return { feeds = {} } end
    local feeds = {}
    for _, c in ipairs(CAMERAS) do
        feeds[#feeds + 1] = { id = c.id, label = c.label }
    end
    return { feeds = feeds }
end

-- setWanted {name, level:0-5, reason} -> { success, message, wanted:{level,reason} }
-- MDT Person tab action (LEO only; court sees the level read-only). BY NAME -
-- the cid is resolved internally and never returned.
local function handleSetWanted(source, data)
    local officer = getOfficer(source)
    if not officer then return { success = false, message = 'Not authorized' } end
    if type(data) ~= 'table' then return { success = false, message = 'Invalid request' } end

    local name = data.name
    if type(name) ~= 'string' or name == '' then
        return { success = false, message = 'No target selected' }
    end
    local level = clampWanted(data.level)

    local q = '%' .. name .. '%'
    local prow = MySQL.single.await(PERSON_SQL, { q, q, q, q, q })
    if not prow then return { success = false, message = 'Person not found' } end

    local reason = type(data.reason) == 'string' and data.reason or ''
    if level > 0 and reason:gsub('%s+', '') == '' then
        reason = 'Flagged by ' .. officerName(officer)
    end
    setWantedLevel(prow.cid, level, reason)

    return {
        success = true,
        message = level == 0 and 'Wanted status cleared.' or ('Wanted level set to %d/5.'):format(level),
        wanted = { level = level, reason = level > 0 and reason or '' },
    }
end

-- searchMedical {name} -> { found, name, items:[{action,detail,medic,created_at}] }
-- EMS ONLY (LEO/court are rejected - medical privacy). BY NAME: the citizenid
-- is resolved internally and never returned to the NUI.
local function handleSearchMedical(source, data)
    if not getEms(source) then return { found = false } end

    local name = data and data.name
    if type(name) ~= 'string' or name == '' then return { found = false } end

    local q = '%' .. name .. '%'
    local row = MySQL.single.await(PERSON_SQL, { q, q, q, q, q })
    if not row then return { found = false } end

    local rows = MySQL.query.await(MEDICAL_FOR_PERSON_SQL, { row.cid }) or {}
    local items = {}
    for _, r in ipairs(rows) do
        items[#items + 1] = {
            action = r.action,
            detail = r.detail or '',
            medic = r.medic_name or 'Unknown',
            created_at = r.created_at,
        }
    end
    return { found = true, name = row.name, items = items }
end

-- getRecentMedical {} -> { items:[{patient,action,detail,medic,created_at}] }
-- Newest 30 log rows across all patients. EMS ONLY.
local function handleGetRecentMedical(source)
    if not getEms(source) then return { items = {} } end
    local rows = MySQL.query.await(MEDICAL_RECENT_SQL, {}) or {}
    local items = {}
    for _, r in ipairs(rows) do
        items[#items + 1] = {
            patient = r.patient_name or 'Unknown',
            action = r.action,
            detail = r.detail or '',
            medic = r.medic_name or 'Unknown',
            created_at = r.created_at,
        }
    end
    return { items = items }
end

----------------------------------------------------------------------
-- Register callbacks (both naming conventions for client compatibility)
----------------------------------------------------------------------

local handlers = {
    getDashboard  = handleGetDashboard,
    searchVehicle = handleSearchVehicle,
    searchPerson  = handleSearchPerson,
    getPenalCode  = handleGetPenalCode,
    placeCharges  = handlePlaceCharges,
    getBolos      = handleGetBolos,
    createBolo    = handleCreateBolo,
    cancelBolo    = handleCancelBolo,
    getWarrants   = handleGetWarrants,
    getReports    = handleGetReports,
    getReport     = handleGetReport,
    createReport  = handleCreateReport,
    getCameras    = handleGetCameras,
    getBodycam    = handleGetBodycam,
    setWanted     = handleSetWanted,
    searchMedical    = handleSearchMedical,    -- EMS only
    getRecentMedical = handleGetRecentMedical, -- EMS only
}

for name, fn in pairs(handlers) do
    lib.callback.register('pengu_mdt:' .. name, fn)        -- task-prompt names
    lib.callback.register('pengu_mdt:server:' .. name, fn) -- SPEC.md names
end

----------------------------------------------------------------------
-- Booking camera (officer-driven): store the named citizen's mugshot.
--
-- The officer triggers this from the pdloc 'mugshot' point (pengu_core). They
-- enter a name; the client captures + DOWNSCALES the photo entirely client-side
-- (screenshot-basic raw capture -> the MDT's own NUI resizes it to ~50KB) and
-- sends only the small data URI here. The SERVER just resolves the name ->
-- citizenid and writes it to pengu_mdt_mugshots.image. No huge images ever cross
-- the network, so it can be returned inline on lookup with no risk.
----------------------------------------------------------------------

-- Exact (case-insensitive) first + last name -> citizenid.
local BOOKING_CID_SQL = [[
SELECT citizenid AS cid FROM players
WHERE LOWER(JSON_VALUE(charinfo,'$.firstname')) = LOWER(?)
  AND LOWER(JSON_VALUE(charinfo,'$.lastname'))  = LOWER(?)
LIMIT 1
]]

RegisterNetEvent('pengu_mdt:storeBookingMugshot', function(first, last, image)
    local src = source
    local officer = getOfficer(src) -- on-duty LEO only
    if not officer then return end
    if type(first) ~= 'string' or type(last) ~= 'string' or type(image) ~= 'string' then return end
    first = first:gsub('^%s+', ''):gsub('%s+$', '')
    last  = last:gsub('^%s+', ''):gsub('%s+$', '')
    if first == '' or last == '' then return end

    -- The client already downscaled to ~50KB; reject anything that is not a small
    -- data URI so a misbehaving client can never store a giant blob.
    if not image:find('^data:image') or #image > 524288 then -- 512KB ceiling
        leoNotify(src, 'Photo rejected (bad/oversized).', 'error')
        return
    end

    local row = MySQL.single.await(BOOKING_CID_SQL, { first, last })
    if not row or not row.cid then
        leoNotify(src, ('No citizen found named %s %s.'):format(first, last), 'error')
        return
    end

    MySQL.insert(MUGSHOT_UPSERT_SQL, { row.cid, image })
    leoNotify(src, ('Mugshot updated for %s %s.'):format(first, last), 'success')
end)

----------------------------------------------------------------------
-- Bodycam archive: while an officer's bodycam is ON the client captures a
-- frame every 60s (screenshot-basic, downscaled in the MDT's own NUI - the
-- same flow as booking mugshots) and sends it here. On-duty LEO only; the
-- table is pruned to the newest 20 frames per officer on every insert.
----------------------------------------------------------------------

local BODYCAM_MIN_INTERVAL = 45 -- seconds; the client sends every 60s, so
                                -- anything faster is a misbehaving client.
local bodycamLast = {}          -- [src] = os.time() of last accepted frame

RegisterNetEvent('pengu_mdt:storeBodycamCapture', function(image)
    local src = source
    local officer = getOfficer(src) -- on-duty LEO only (court can view, never record)
    if not officer then return end
    if type(image) ~= 'string' then return end
    -- Frames are downscaled to ~30KB client-side; reject anything that is not
    -- a small data URI so a misbehaving client can never store a giant blob.
    if not image:find('^data:image') or #image > 262144 then return end -- 256KB ceiling

    local now = os.time()
    if bodycamLast[src] and (now - bodycamLast[src]) < BODYCAM_MIN_INTERVAL then return end
    bodycamLast[src] = now

    local cid = officer.PlayerData.citizenid
    MySQL.insert.await(BODYCAM_INSERT_SQL, { cid, officerName(officer), image })
    MySQL.query.await(BODYCAM_PRUNE_SQL, { cid, cid })
end)

AddEventHandler('playerDropped', function()
    bodycamLast[source] = nil
end)

----------------------------------------------------------------------
-- EMS medical log intake. qbx_ambulancejob fires this SERVER event (pcall-
-- wrapped there) when a revive completes or a treatment item is used
-- successfully. AddEventHandler - NOT RegisterNetEvent - on purpose: only
-- server resources can trigger it, so a client can never inject fake rows.
-- medicSrcOrName: numeric player source (medic name resolved here) or an
-- already-resolved name string.
----------------------------------------------------------------------

local MEDICAL_ACTIONS = { revive = true, treatment = true }

AddEventHandler('pengu_mdt:server:medicalLog', function(citizenid, patientName, medicSrcOrName, action, detail)
    if type(citizenid) ~= 'string' or citizenid == '' or #citizenid > 64 then return end
    if type(action) ~= 'string' or not MEDICAL_ACTIONS[action] then return end
    if type(patientName) ~= 'string' or patientName == '' then patientName = 'Unknown' end
    if type(detail) ~= 'string' then detail = '' end

    local medicName = 'Unknown'
    if type(medicSrcOrName) == 'number' then
        local medic = exports.qbx_core:GetPlayer(medicSrcOrName)
        if medic and medic.PlayerData then
            medicName = fullName(medic.PlayerData.charinfo)
        end
    elseif type(medicSrcOrName) == 'string' and medicSrcOrName ~= '' then
        medicName = medicSrcOrName
    end

    MySQL.insert.await(MEDICAL_INSERT_SQL, {
        citizenid, patientName:sub(1, 128), medicName:sub(1, 128),
        action, detail:sub(1, 128),
    })
    MySQL.query.await(MEDICAL_PRUNE_SQL)
end)

----------------------------------------------------------------------
-- Fingerprints: an officer triggers this from a 'fingerprint' pdloc or their cruiser
-- (pengu_core /collectprints) with the NEAREST player's server id. The server re-validates
-- on-duty LEO + a 3.5m proximity, resolves the target's citizenid INTERNALLY, and upserts
-- pengu_mdt_prints. The cid never reaches any NUI - searchPerson only returns a boolean.
----------------------------------------------------------------------
RegisterNetEvent('pengu_mdt:collectPrints', function(targetId)
    local src = source
    local officer = getOfficer(src) -- on-duty LEO only
    if not officer then leoNotify(src, 'Not authorized.', 'error') return end
    targetId = tonumber(targetId)
    if not targetId then return end
    local target = exports.qbx_core:GetPlayer(targetId)
    if not target or not target.PlayerData then
        leoNotify(src, 'No valid person to print.', 'error'); return
    end
    -- Server-side proximity re-check so a spoofed id cannot print someone across the map.
    local op = GetPlayerPed(src)
    local tp = GetPlayerPed(targetId)
    if op == 0 or tp == 0 or #(GetEntityCoords(op) - GetEntityCoords(tp)) > 3.5 then
        leoNotify(src, 'That person is not close enough to print.', 'error'); return
    end
    local cid = target.PlayerData.citizenid
    MySQL.insert(PRINTS_UPSERT_SQL, { cid, officerName(officer) }) -- fire-and-forget upsert (mirrors mugshot)
    local tName = fullName(target.PlayerData.charinfo)
    leoNotify(src, ('Fingerprints collected for %s and added to record.'):format(tName), 'success')
end)

----------------------------------------------------------------------
-- /jail [id] - the ONLY way to imprison. DOC-gated, authoritative.
----------------------------------------------------------------------

RegisterCommand('jail', function(source, args)
    -- (1) Officer must be LEO.
    local officer = getOfficer(source)
    if not officer then
        notify(source, 'Not authorized.', 'error')
        return
    end

    -- (2) Resolve target by server id.
    local id = tonumber(args[1])
    if not id then
        notify(source, 'Usage: /jail [id]', 'error')
        return
    end
    local target = exports.qbx_core:GetPlayer(id)
    if not target or not target.PlayerData then
        notify(source, 'Invalid target id.', 'error')
        return
    end
    local targetSrc = target.PlayerData.source

    -- (3) The officer must be standing AT a 'cell' pdloc; whatever cell is nearest is THE cell, and
    -- the suspect is jailed there. Cells live in pengu_pd_locations; pengu_core resolves the nearest.
    local officerPed = GetPlayerPed(source)
    if not officerPed or officerPed == 0 then
        notify(source, 'Could not resolve your position.', 'error')
        return
    end
    local officerPos = GetEntityCoords(officerPed)

    local cell = exports['pengu_core']:GetNearestCell(officerPos.x, officerPos.y, officerPos.z)
    if not cell then
        notify(source, 'No jail cell is set. Place one with /pdloc add cell.', 'error')
        return
    end
    -- Require a release lobby too, so nobody is jailed without a clean place to be released.
    if not GlobalState.penguJailLobby then
        notify(source, 'No release lobby is set. Place one with /pdloc add lobby.', 'error')
        return
    end

    local cellPos = vec3(cell.x + 0.0, cell.y + 0.0, cell.z + 0.0)
    if #(officerPos - cellPos) > JAIL_RADIUS then
        notify(source, 'You must be standing at a jail cell to process someone.', 'error')
        return
    end

    local ped = GetPlayerPed(targetSrc)
    if not ped or ped == 0 then
        notify(source, 'Invalid target id.', 'error')
        return
    end
    local pos = GetEntityCoords(ped)
    if not pos or #(pos - cellPos) > JAIL_RADIUS then
        notify(source, 'Suspect must be at the same cell.', 'error')
        return
    end

    -- (4) Sum outstanding charges.
    local cid = target.PlayerData.citizenid
    local sumRow = MySQL.single.await(SUM_OUTSTANDING_SQL, { cid })
    local totalMonths = sumRow and tonumber(sumRow.months) or 0
    local totalFine = sumRow and tonumber(sumRow.fine) or 0
    local charges = sumRow and tonumber(sumRow.charges) or 0
    if charges == 0 then
        notify(source, 'No outstanding charges.', 'error')
        return
    end

    -- (5) Jail at the pdloc cell (pengu_core self-contained jail; caps at 60 minutes internally).
    -- Fine-only charge sets (totalMonths == 0) skip jail but still process the fine + clear charges,
    -- matching the prior behaviour.
    if totalMonths > 0 then
        local jailedOk = exports['pengu_core']:JailPlayerCustom(targetSrc, totalMonths, cell)
        if not jailedOk then
            notify(source, 'Could not jail the suspect (no cell set or target offline).', 'error')
            return
        end
    end

    -- (6) Forced fine: deduct from bank (the forced DOC payment). Surface it to the officer if the
    -- suspect can't cover it (RemoveMoney returns false on insufficient funds and deducts nothing).
    if totalFine > 0 and target.Functions and target.Functions.RemoveMoney then
        if not target.Functions.RemoveMoney('bank', totalFine, 'doc-processing') then
            notify(source, ('Suspect could not pay the $%d fine (insufficient bank funds).'):format(totalFine), 'error')
        end
    end

    -- (7) Capture the charge titles (for the plea prompt + rap sheet) BEFORE clearing them.
    local chargeRows = MySQL.query.await(OUTSTANDING_FOR_PERSON_SQL, { cid }) or {}
    local titles = {}
    for _, r in ipairs(chargeRows) do titles[#titles + 1] = r.title end
    local chargeList = table.concat(titles, ', ')

    -- (8) Record this imprisonment event FIRST so we can stamp its id onto the charges.
    local served = math.min(totalMonths, 60)
    local caseId = MySQL.insert.await(
        'INSERT INTO pengu_mdt_imprisonments (citizenid, officer, months, fine, charges, plea, charge_list) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { cid, officerName(officer), served, totalFine, charges, 'pending', chargeList })

    -- Mark those rows processed + link them to this case (the rap sheet joins on case_id
    -- to show the plea per charge). Clears them from outstanding + warrants.
    MySQL.update.await(
        "UPDATE pengu_mdt_charges SET status = 'processed', case_id = ? WHERE citizenid = ? AND status = 'outstanding'",
        { caseId or 0, cid })

    -- Charges are processed -> the citizen is no longer wanted.
    setWantedLevel(cid, 0)

    -- (8b) Offer the suspect a plea (only if actually jailed; fine-only sets skip it).
    if served > 0 and caseId then
        TriggerClientEvent('pengu_mdt:offerPlea', targetSrc, {
            caseId = caseId, charges = chargeList, minutes = served, pct = PLEA_GUILTY_PCT,
        })
    end

    -- (9) Notify both parties (served = capped minutes).
    notify(source, ('Processed %d charge%s: %d min, $%d fined.'):format(
        charges, charges == 1 and '' or 's', served, totalFine), 'success')
    notify(targetSrc, ('DOC processing: %d charge%s, %d min, $%d fined. Enter your plea.'):format(
        charges, charges == 1 and '' or 's', served, totalFine), 'inform')
end, false)

----------------------------------------------------------------------
-- Plea system: after processing, the suspect pleads guilty / not guilty.
-- Guilty waives a trial and cuts the remaining sentence; the plea shows on
-- the MDT Person record. /plea re-opens a pending plea.
----------------------------------------------------------------------

local pleaLock = {} -- [caseId] = true while committing (blocks concurrent spam double-cut)

RegisterNetEvent('pengu_mdt:submitPlea', function(caseId, plea)
    local src = source
    caseId = tonumber(caseId)
    if not caseId or (plea ~= 'guilty' and plea ~= 'not_guilty') then return end
    -- Lock is set SYNCHRONOUSLY (before any .await yields the handler) so concurrent
    -- handlers spawned by a spammed event all see it and bail; only the first commits.
    if pleaLock[caseId] then return end
    pleaLock[caseId] = true

    local p = exports.qbx_core:GetPlayer(src)
    if p then
        local cid = p.PlayerData.citizenid
        -- The case must belong to THIS player and still be pending (no re-pleading).
        local row = MySQL.single.await(
            "SELECT id FROM pengu_mdt_imprisonments WHERE id = ? AND citizenid = ? AND plea = 'pending'",
            { caseId, cid })
        if row then
            if plea == 'guilty' then
                local cur = exports['pengu_core']:GetJailMinutes(src) or 0
                local cut = math.floor(cur * PLEA_GUILTY_PCT)
                if cut > 0 then exports['pengu_core']:ReduceJailMinutes(src, cut) end
                MySQL.update.await("UPDATE pengu_mdt_imprisonments SET plea = 'guilty', reduced = ? WHERE id = ?", { cut, caseId })
                notify(src, ('Guilty plea entered. Your sentence was cut by %d minute(s).'):format(cut), 'inform')
            else
                MySQL.update.await("UPDATE pengu_mdt_imprisonments SET plea = 'not_guilty' WHERE id = ?", { caseId })
                notify(src, 'Not-guilty plea entered. It is on your record.', 'inform')
            end
        end
    end

    pleaLock[caseId] = nil
end)

RegisterNetEvent('pengu_mdt:requestPlea', function()
    local src = source
    local p = exports.qbx_core:GetPlayer(src)
    if not p then return end
    if (exports['pengu_core']:GetJailMinutes(src) or 0) <= 0 then
        notify(src, 'You are not currently jailed.', 'error')
        return
    end
    local cid = p.PlayerData.citizenid
    local row = MySQL.single.await(
        "SELECT id, charge_list FROM pengu_mdt_imprisonments WHERE citizenid = ? AND plea = 'pending' ORDER BY id DESC LIMIT 1",
        { cid })
    if not row then
        notify(src, 'You have no pending plea.', 'inform')
        return
    end
    TriggerClientEvent('pengu_mdt:offerPlea', src, {
        caseId = row.id, charges = row.charge_list or '',
        minutes = exports['pengu_core']:GetJailMinutes(src), pct = PLEA_GUILTY_PCT,
    })
end)

----------------------------------------------------------------------
-- PD units (callsigns). An officer's "unit" IS their callsign (metadata.callsign,
-- which the Active Units dashboard reads). On-duty LEO only.
----------------------------------------------------------------------

local function sanitizeCallsign(raw)
    if type(raw) ~= 'string' then return nil end
    local cs = raw:upper():gsub('[^%w%-]', ''):sub(1, 12)
    if cs == '' then return nil end
    return cs
end

local function currentCallsign(officer)
    local cs = officer.PlayerData.metadata and officer.PlayerData.metadata.callsign
    if cs == nil or cs == '' or cs == 'NO CALLSIGN' then return nil end
    return cs
end

RegisterCommand('createunit', function(source, args)
    local officer = getOfficer(source)
    if not officer then leoNotify(source, 'On-duty officers only.', 'error') return end
    local cs = sanitizeCallsign(args[1])
    if not cs then leoNotify(source, 'Usage: /createunit [CALLSIGN]', 'error') return end
    if currentCallsign(officer) then
        leoNotify(source, ('You are already Unit %s. Use /renameunit or /disbandunit.'):format(currentCallsign(officer)), 'error')
        return
    end
    exports.qbx_core:SetMetadata(source, 'callsign', cs)
    leoNotify(source, ('Unit %s created - you are on the air.'):format(cs), 'success')
end, false)

-- Join an existing unit (another on-duty officer's callsign), so multiple officers share a unit.
RegisterCommand('joinunit', function(source, args)
    local officer = getOfficer(source)
    if not officer then leoNotify(source, 'On-duty officers only.', 'error') return end
    local cs = sanitizeCallsign(args[1])
    if not cs then leoNotify(source, 'Usage: /joinunit [CALLSIGN]', 'error') return end
    local exists = false
    for src2, p in pairs(exports.qbx_core:GetQBPlayers() or {}) do
        if tonumber(src2) ~= source then
            local pd = p.PlayerData
            if pd and pd.job and pd.job.type == 'leo' and pd.job.onduty
                and pd.metadata and pd.metadata.callsign == cs then
                exists = true; break
            end
        end
    end
    if not exists then
        leoNotify(source, ('No active unit "%s" to join - use /createunit to start one.'):format(cs), 'error')
        return
    end
    exports.qbx_core:SetMetadata(source, 'callsign', cs)
    leoNotify(source, ('You joined Unit %s.'):format(cs), 'success')
end, false)

RegisterCommand('renameunit', function(source, args)
    local officer = getOfficer(source)
    if not officer then leoNotify(source, 'On-duty officers only.', 'error') return end
    local cs = sanitizeCallsign(args[1])
    if not cs then leoNotify(source, 'Usage: /renameunit [CALLSIGN]', 'error') return end
    exports.qbx_core:SetMetadata(source, 'callsign', cs)
    leoNotify(source, ('Unit renamed to %s.'):format(cs), 'success')
end, false)

RegisterCommand('disbandunit', function(source)
    local officer = getOfficer(source)
    if not officer then leoNotify(source, 'On-duty officers only.', 'error') return end
    exports.qbx_core:SetMetadata(source, 'callsign', 'NO CALLSIGN')
    leoNotify(source, 'Unit disbanded.', 'success')
end, false)

----------------------------------------------------------------------
-- /wanted [id] [1-5] [reason] + /unwanted [id] - on-duty LEO only.
----------------------------------------------------------------------

RegisterCommand('wanted', function(source, args)
    local officer = getOfficer(source)
    if not officer then leoNotify(source, 'On-duty officers only.', 'error') return end
    local id = tonumber(args[1])
    local level = tonumber(args[2])
    if not id or not level or level < 1 or level > WANTED_MAX then
        leoNotify(source, 'Usage: /wanted [id] [1-5] [reason]', 'error')
        return
    end
    local target = exports.qbx_core:GetPlayer(id)
    if not target or not target.PlayerData then
        leoNotify(source, 'Invalid target id.', 'error')
        return
    end
    level = clampWanted(level)
    local reason = table.concat(args, ' ', 3)
    if reason == '' then reason = 'Flagged by ' .. officerName(officer) end
    setWantedLevel(target.PlayerData.citizenid, level, reason)
    leoNotify(source, ('%s is now WANTED %d/5.'):format(fullName(target.PlayerData.charinfo), level), 'success')
end, false)

RegisterCommand('unwanted', function(source, args)
    local officer = getOfficer(source)
    if not officer then leoNotify(source, 'On-duty officers only.', 'error') return end
    local id = tonumber(args[1])
    if not id then leoNotify(source, 'Usage: /unwanted [id]', 'error') return end
    local target = exports.qbx_core:GetPlayer(id)
    if not target or not target.PlayerData then
        leoNotify(source, 'Invalid target id.', 'error')
        return
    end
    setWantedLevel(target.PlayerData.citizenid, 0)
    leoNotify(source, ('Wanted status cleared for %s.'):format(fullName(target.PlayerData.charinfo)), 'success')
end, false)

----------------------------------------------------------------------
-- Wanted threads: offline decay + periodic BOLO ping + connect ping.
----------------------------------------------------------------------

-- DECAY: every 60s, accrue offline time per wanted citizen; 30 continuous
-- offline minutes = -1 level (row deleted at 0). Online citizens stay wanted
-- and their decay clock resets.
CreateThread(function()
    while true do
        Wait(60000)
        local rows = MySQL.query.await(WANTED_ALL_SQL) or {}
        local seen = {}
        for _, r in ipairs(rows) do
            local cid = r.citizenid
            seen[cid] = true
            if exports.qbx_core:GetPlayerByCitizenId(cid) ~= nil then
                offlineSecs[cid] = nil
            else
                local acc = (offlineSecs[cid] or 0) + 60
                if acc >= WANTED_DECAY_SECONDS then
                    setWantedLevel(cid, clampWanted(r.level) - 1, r.reason)
                else
                    offlineSecs[cid] = acc
                end
            end
        end
        for cid in pairs(offlineSecs) do -- drop clocks for rows that no longer exist
            if not seen[cid] then offlineSecs[cid] = nil end
        end
    end
end)

-- PING: every 10 min, BOLO every ONLINE citizen at wanted level >= 3.
CreateThread(function()
    while true do
        Wait(WANTED_PING_MS)
        local rows = MySQL.query.await(WANTED_HIGH_SQL) or {}
        for _, r in ipairs(rows) do
            local player = exports.qbx_core:GetPlayerByCitizenId(r.citizenid)
            if player then
                sendWantedAlert(player, clampWanted(r.level), r.reason or '')
            end
        end
    end
end)

-- CONNECT: a wanted citizen (level >= 3) coming online pings dispatch once.
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    if not player or not player.PlayerData then return end
    local cid = player.PlayerData.citizenid
    CreateThread(function()
        Wait(5000) -- let the ped exist before reading its coords
        local p = exports.qbx_core:GetPlayerByCitizenId(cid)
        if not p then return end
        local level, reason = getWantedLevel(cid)
        if level >= 3 then sendWantedAlert(p, level, reason) end
    end)
end)

----------------------------------------------------------------------
-- Resource start: create/migrate tables + index penal code
----------------------------------------------------------------------

-- Adds a column only if it does not already exist (robust across MySQL/MariaDB).
local function ensureColumn(tableName, columnName, ddl)
    local row = MySQL.single.await([[
        SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
    ]], { tableName, columnName })
    if not row or (tonumber(row.c) or 0) == 0 then
        MySQL.query.await(('ALTER TABLE %s ADD COLUMN %s %s'):format(tableName, columnName, ddl))
    end
end

CreateThread(function()
    MySQL.query.await(CREATE_CHARGES_SQL)
    MySQL.query.await(CREATE_BOLOS_SQL)
    MySQL.query.await(CREATE_REPORTS_SQL)
    MySQL.query.await(CREATE_MUGSHOTS_SQL)
    MySQL.query.await(CREATE_IMPRISONMENTS_SQL)
    MySQL.query.await(CREATE_PRINTS_SQL)
    MySQL.query.await(CREATE_BODYCAM_SQL)
    MySQL.query.await(CREATE_WANTED_SQL)
    MySQL.query.await(CREATE_MEDICAL_SQL)

    -- Idempotent migrations for pre-existing installs.
    ensureColumn('pengu_mdt_charges', 'status', "VARCHAR(16) DEFAULT 'outstanding'")
    -- Plea system: each imprisonment (case) records the suspect's plea + any guilty-plea cut.
    ensureColumn('pengu_mdt_imprisonments', 'plea', "VARCHAR(16) DEFAULT 'pending'")
    ensureColumn('pengu_mdt_imprisonments', 'reduced', 'INT DEFAULT 0')
    ensureColumn('pengu_mdt_imprisonments', 'charge_list', 'TEXT')
    -- Links a processed charge to the imprisonment (case) it was part of, so the
    -- rap sheet can show the plea per charge.
    ensureColumn('pengu_mdt_charges', 'case_id', 'INT DEFAULT 0')
    ensureColumn('pengu_mdt_bolos', 'image_url', "VARCHAR(512) DEFAULT ''")
    ensureColumn('pengu_mdt_bolos', 'image_urls', 'TEXT')
    ensureColumn('pengu_mdt_reports', 'subject_name', "VARCHAR(128) DEFAULT ''")

    -- One-time backfill: wrap any legacy single image_url into the JSON array.
    -- JSON_ARRAY() emits valid JSON even if the URL contains quotes or
    -- backslashes, so this is safe. Runs only on rows not yet migrated.
    MySQL.query.await([[
        UPDATE pengu_mdt_bolos
        SET image_urls = JSON_ARRAY(image_url)
        WHERE (image_urls IS NULL OR image_urls = '')
          AND image_url IS NOT NULL AND image_url <> ''
    ]])

    buildPenalIndex()
end)
