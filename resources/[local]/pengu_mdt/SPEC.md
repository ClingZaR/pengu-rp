# pengu_mdt — Build Spec (verified against live server)

Standalone Qbox MDT resource. Stack: qbx_core + ox_lib + oxmysql.
Path: `/opt/fivem/server/txData/Qbox_389702.base/resources/[local]/pengu_mdt`

## Verified facts (live server, 2026-06-23)

- DB: MariaDB, schema `fivem`. `charinfo` is `text` holding valid JSON; **`JSON_VALUE(charinfo,'$.key')` works** (tested → firstname=David, lastname=Loan).
- `players` columns: `citizenid` varchar(50) PK, `userId`, `cid`, `license`, `name` (display/Steam name = "PenguWin", **NOT** the RP name — do not search this), `money` text, `charinfo` text JSON, `job` text, `gang`, `position`, `metadata`, `inventory`, `phone_number` varchar(20), `last_updated`, `last_logged_out`.
  - `charinfo` JSON keys: `firstname`, `lastname`, `phone`, `cid`, `account`, `gender`, `backstory`, `nationality`, `birthdate`. Example: `{"firstname":"David","lastname":"Loan","phone":"8199926343",...}`.
  - `phone_number` top-level column mirrors `charinfo.phone`.
- `player_vehicles` columns: `id` PK, `license`, `citizenid` varchar(50) (MUL), `vehicle` varchar(50) (= model/spawn name), `hash` varchar(50), `mods`, `plate` varchar(15) UNIQUE, `fakeplate`, `garage`, `fuel`, `engine`, `body`, `state`, `depotprice`, `drivingdistance`, `status`, `coords`, `glovebox`, `trunk`, `mdt_vehicle_information` text, `mdt_vehicle_points` int, `mdt_vehicle_status` enum('valid','suspended','expired','impounded'), `mdt_vehicle_stolen` tinyint, `mdt_vehicle_boloactive` tinyint, `mdt_vehicle_image`.
  - **No `vin` column exists.** Synthesize VIN response from `id` (stable) — see query below.
- qbx_core exports (server, `qbx_core/server/functions.lua`):
  - `exports.qbx_core:GetPlayer(source)` — line 48, exported line 56. Arg = source (number) or identifier (string); returns the online Player object `QBX.Players[src]`. Use `.PlayerData` → `.job.type`, `.charinfo`, `.citizenid`, `.source`.
  - `exports.qbx_core:GetPlayerByCitizenId(cid)` — line 60, exported line 68. **Iterates ONLINE players only** (no offline fallback in this fn). Returns `Player?`; `.PlayerData.source` present when online → use to detect online target for jail/fine.
  - Money: `targetPlayer.Functions.RemoveMoney("bank", amount, "mdt-fine")`.
- xt-prison export confirmed: `exports('JailPlayerById', function(targetSource, minutes))` at `[standalone]/xt-prison/server/sv_commands.lua:158`. Internally clamps `minutes` to `MAX_JAIL_MINUTES = 60`, requires the target **online**, teleports/books, returns bool. Call: `exports["xt-prison"]:JailPlayerById(targetSrc, jailMinutes)`.

## Architecture (one consistent pattern)

ox_lib server callbacks invoked from the client NUI relay.
- CLIENT: one `RegisterNUICallback(<name>, ...)` per NUI fetch. For data callbacks it does `cb(lib.callback.await('pengu_mdt:server:<name>', false, data))`.
- SERVER: `lib.callback.register('pengu_mdt:server:<name>', function(source, data) ... end)`.
- **`closeMdt`** is client-only (`SetNuiFocus(false,false)`, hide UI) — no server hop.
- **Auth gate (server, every data callback):** `local p = exports.qbx_core:GetPlayer(source); if not p or p.PlayerData.job.type ~= 'leo' then return {found=false} (or {success=false,message='Not authorized'}) end`. `leo` covers police/bcso/sasp.
- `shared/penalcode.lua` listed as `shared_script` in fxmanifest so global `PenalCode` exists client + server. **Do not author penalcode.lua** (other build owns it).

## Exact SQL (oxmysql; use `MySQL.single.await` / `MySQL.query.await`)

### Table creation (on resource start)
```sql
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
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### searchVehicle — find vehicle by plate + owner name/phone
Normalize plate (Qbox stores uppercase, may be space-padded) — strip spaces both sides.
```sql
SELECT
  pv.plate                                         AS plate,
  pv.vehicle                                       AS model,
  pv.hash                                          AS hash,
  CONCAT('VIN-', LPAD(pv.id, 8, '0'))              AS vin,
  pv.citizenid                                     AS citizenid,
  TRIM(CONCAT(
    COALESCE(JSON_VALUE(p.charinfo,'$.firstname'),''),' ',
    COALESCE(JSON_VALUE(p.charinfo,'$.lastname'),'')))  AS owner,
  COALESCE(p.phone_number, JSON_VALUE(p.charinfo,'$.phone')) AS phone
FROM player_vehicles pv
LEFT JOIN players p ON p.citizenid = pv.citizenid
WHERE REPLACE(UPPER(pv.plate),' ','') = REPLACE(UPPER(?),' ','')
LIMIT 1;
```
Param: `{ plate }`. `found = row ~= nil`. Then run the **owner aggregate** queries below with `row.citizenid` for `totals` + `outstanding`. If no row → `{found=false}`.

### searchPerson — find by RP name OR phone
Do NOT use `players.name` (it is the account/Steam name). Match on charinfo firstname/lastname + phone.
```sql
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
LIMIT 1;
```
Params: build `local q = '%'..query..'%'` → `{ q, q, q, q, q }`. `found = row ~= nil`. Then run aggregate queries with `row.cid` for `totals` + `outstanding`.

### Owner / person aggregates (pengu_mdt_charges) — used by both searches
totals:
```sql
SELECT
  COUNT(*)                                              AS charges,
  COALESCE(SUM(class = 'citation'),0)                   AS citations,
  COALESCE(SUM(months > 0),0)                           AS imprisonments
FROM pengu_mdt_charges
WHERE citizenid = ?;
```
outstanding (recent records):
```sql
SELECT
  DATE_FORMAT(created_at,'%Y-%m-%d') AS date,
  title                              AS charge,
  officer                           AS officer,
  plea                              AS plea
FROM pengu_mdt_charges
WHERE citizenid = ?
ORDER BY created_at DESC
LIMIT 25;
```
(`imprisonments` = count of charges with months>0; "keep it simple" per requirements.)

### placeCharges — insert one row per placed charge
```sql
INSERT INTO pengu_mdt_charges
  (citizenid, code, title, class, months, fine, modifiers, officer, plea)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
```
Params per item: `{ targetCid, code, title, class, finalMonths, finalFine, table.concat(modIds,','), officerName, 'Guilty' }`. `officerName` = officer's `charinfo.firstname..' '..charinfo.lastname`.

## qbx export call list (server)
- `exports.qbx_core:GetPlayer(source)` → officer PlayerData (auth + officer name).
- `exports.qbx_core:GetPlayerByCitizenId(targetCid)` → target (online check via `.PlayerData.source`).
- `targetPlayer.Functions.RemoveMoney("bank", fine, "mdt-fine")` → fine (online only).
- `exports["xt-prison"]:JailPlayerById(targetSrc, jailMinutes)` → jail (online only; self-caps 60).

## Callback list (final)

| NUI name (`fetch https://pengu_mdt/<name>`) | Server callback `pengu_mdt:server:<name>` | Request | Response |
|---|---|---|---|
| `searchVehicle` | yes | `{plate}` | `{found, owner, model, plate, vin, phone, totals:{charges,citations,imprisonments}, outstanding:[{date,charge,officer,plea}]}` |
| `searchPerson` | yes | `{query}` | `{found, name, cid, phone, totals:{...}, outstanding:[...]}` |
| `getPenalCode` | yes | `{}` | `{charges = PenalCode.charges, modifiers = PenalCode.modifiers}` |
| `placeCharges` | yes | `{targetCid, items:[{code, modifiers:[id...]}], sendToJail, issueFine}` | `{success, jailMinutes, fine, message}` |
| `closeMdt` | **client-only** | `{}` | `ok` (SetNuiFocus false) |

## placeCharges server algorithm (AUTHORITATIVE)
1. Auth: officer `job.type == 'leo'`.
2. `local jailMinutes, fine = 0, 0`. For each `item`:
   - Look up `base` in `PenalCode.charges` by `item.code`; skip if missing.
   - `mult = 1.0`. For each `modId` in `item.modifiers`:
     - **Reject** if `modId` ∈ `base.blockedModifiers` → return `{success=false, message="Blocked modifier on "..base.code}`.
     - Find modifier in `PenalCode.modifiers` by `id`; `mult = mult * mod.mult`.
   - `local m = math.floor(base.months * mult + 0.5)`; `local f = math.floor(base.fine * mult + 0.5)`.
   - `jailMinutes = jailMinutes + m`; `fine = fine + f`.
   - INSERT row (months=m, fine=f, modifiers=joined ids, class=base.class, title=base.title, officer=officerName).
3. Resolve target: `local tgt = exports.qbx_core:GetPlayerByCitizenId(targetCid)`.
   - If `sendToJail` and `tgt` and `jailMinutes > 0`: `exports["xt-prison"]:JailPlayerById(tgt.PlayerData.source, jailMinutes)` (export re-caps at 60).
   - If `issueFine` and `tgt` and `fine > 0`: `tgt.Functions.RemoveMoney("bank", fine, "mdt-fine")`.
4. Return `{success=true, jailMinutes=jailMinutes, fine=fine, message="..."}`. (Charges are recorded even if target offline; only jail/fine require online target.)

## fxmanifest.lua essentials
```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'
shared_scripts {
  '@ox_lib/init.lua',
  'shared/penalcode.lua',   -- external; provides global PenalCode (client + server)
}
client_scripts { 'client/main.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }
ui_page 'html/index.html'
files { 'html/index.html', 'html/**/*' }
dependencies { 'qbx_core', 'ox_lib', 'oxmysql', 'xt-prison' }
```
