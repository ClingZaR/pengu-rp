# pengu_mdt — REDESIGN2 (Overhaul Build Plan)

Second-pass overhaul. Locks the MDT to the operator's HARD RULES: **no citizen IDs
anywhere in the UI or in any callback response** (lookups are by NAME only), the Arrest
Calculator only **records outstanding charges** (no jail/fine buttons), imprisonment +
forced fines happen exclusively via a new **`/jail` command** at the DOC, plus new
**Dashboard (on-duty units)**, **Mugshots**, **derived Warrants**, **image BOLOs**, and a
simple **Cameras** tab.

Path: `/opt/fivem/server/txData/Qbox_389702.base/resources/[local]/pengu_mdt`
Stack: qbx_core + ox_lib + oxmysql + xt-prison + MugShotBase64.
Use literal paths (brackets included) for every Write/Edit.

---

## 0. Verified live-server facts (grepped 2026-06-23)

| Need | Verified call | Source |
|---|---|---|
| Capture base64 mugshot of local ped | `exports["MugShotBase64"]:GetMugShotBase64(ped, transparent)` — **resource name case-sensitive `MugShotBase64`**; client-only; blocking (uses `promise`+`Citizen.Await`); returns a base64 PNG data string (`true` = transparent bg). | `[standalone]/MugShotBase64/client.lua` (`exports("GetMugShotBase64", ...)`) |
| Officer callsign | `player.PlayerData.metadata.callsign` (defaults to `'NO CALLSIGN'`) | `[qbx]/qbx_core/server/player.lua:647` |
| Enumerate ONLINE players (server) | `exports.qbx_core:GetQBPlayers()` → `table<source, Player>` (`QBX.Players`). Iterate; keep `p.PlayerData.job.type == 'leo'` **and** `p.PlayerData.job.onduty == true`. | `[qbx]/qbx_core/server/functions.lua:101`; job fields `player.lua:683-684` |
| Resolve a source / cid to a Player | `exports.qbx_core:GetPlayer(src)`, `exports.qbx_core:GetPlayerByCitizenId(cid)` (ONLINE only) | `functions.lua:56/68` |
| Jail by server id | `exports["xt-prison"]:JailPlayerById(targetSrc, minutes)` → bool; **self-caps at `MAX_JAIL_MINUTES = 60`**; requires target online; teleports/books at Bolingbroke. | `[standalone]/xt-prison/server/sv_commands.lua:158` |
| Force-remove money | `target.Functions.RemoveMoney('bank', amount, 'doc-processing')` → boolean success (false if insufficient). | `[qbx]/qbx_core/server/player.lua:836` |
| Both deps auto-start | `ensure [standalone]` (covers MugShotBase64 + xt-prison); `ensure [local]` covers pengu_mdt. | `server.cfg:82,92` |

DB facts (unchanged from SPEC.md): `players.charinfo` is JSON text → `JSON_VALUE(charinfo,'$.firstname/$.lastname/$.phone')`; `phone_number` mirrors `charinfo.phone`; never search `players.name` (Steam/account name). `player_vehicles` has no `vin` → synthesize `CONCAT('VIN-',LPAD(pv.id,8,'0'))`. DOC anchor coords `vec3(1845.83, 2585.90, 45.67)`.

---

## 1. The metagaming rule (drives everything)

- **No `citizenid` is ever returned to the NUI.** Server resolves name→citizenid INTERNALLY for storage/queries only.
- All person targeting is **by NAME** (chosen from a Person Search), never by typing a cid.
- UI removals to enforce this:
  - Person tab: delete the **"Citizen ID"** field (`#per-cid`).
  - Arrest Calculator: delete the **"Target Citizen ID"** input (`#target-cid`); the target is a **name** carried from Person Search ("Charge in Calculator →") or shown as a read-only "Target: <name>" chip.
  - Warrants: no cid column (now derived; see §4).
  - Reports: replace the "Citizen ID" input with an optional **"Subject Name"** field.
- Internally, `placeCharges` and `/jail` resolve name→cid with the existing `PERSON_SQL` (LIKE on charinfo first/last) and `pengu_mdt_charges.citizenid`; the cid never leaves the server.

---

## 2. Callback list (server, LEO-gated, dual-registered)

Every handler runs the existing `getOfficer(source)` gate (`job.type == 'leo'`). Register each under BOTH `pengu_mdt:<name>` and `pengu_mdt:server:<name>` (existing dual-name loop). NUI fetches `https://pengu_mdt/<name>`; client relays via `lib.callback.await('pengu_mdt:<name>', false, data)`.

| NUI name | Request | Response | Notes |
|---|---|---|---|
| `getDashboard` | `{}` | `{units:[{callsign, name, jobLabel}]}` | ON-DUTY leo only via `GetQBPlayers()`; `callsign`=metadata; `name`=charinfo first+last; `jobLabel`=`job.label`. **No cid.** |
| `searchPerson` | `{name}` | `{found, name, mugshot, phone, totals:{charges,citations,imprisonments}, outstanding:[{code,title,class,months,fine,modifiers}]}` | Resolve by name LIKE. `mugshot`=stored base64 or `null`. `outstanding` = `status='outstanding'` rows only. `totals` = lifetime (all statuses). **No cid.** |
| `searchVehicle` | `{plate}` | `{found, owner, model, plate, vin, phone}` | `owner`=name. **No cid, no totals/outstanding** (simplified from v1). |
| `getPenalCode` | `{}` | `{charges, modifiers}` | Unchanged (global `PenalCode`). |
| `placeCharges` | `{name, items:[{code, modifiers:[id]}]}` | `{success, message}` | Resolve name→cid server-side. Recompute months/fine AUTHORITATIVELY (`floor(x*mult+0.5)`); reject blocked modifiers; INSERT each row `status='outstanding'`. **No jail, no fine.** If named person ONLINE → fire mugshot capture. **No cid in response.** |
| `getBolos` | `{}` | `{items:[{id,type,title,description,image_url,officer,created_at}]}` | `WHERE status='active' ORDER BY created_at DESC`. |
| `createBolo` | `{type,title,description,image_url}` | `{success, message}` | `image_url` optional; validate `^https?://` else store `''`. |
| `cancelBolo` | `{id}` | `{success, message}` | `SET status='cancelled'`. |
| `getWarrants` | `{}` | `{items:[{name, charges, months, fine}]}` | **DERIVED**: ONLINE players that currently have `status='outstanding'` charges. `charges`=count, `months`/`fine`=sums. Name only. **No cid.** |
| `getReports` | `{}` | `{items:[{id,title,type,subject_name,officer,created_at}]}` | List omits content. |
| `getReport` | `{id}` | `{found, report:{id,title,type,content,subject_name,officer,created_at}}` | Full body. |
| `createReport` | `{title,type,content,subject_name}` | `{success, message}` | `subject_name` optional (person referenced by NAME). |
| `getCameras` | `{}` | `{feeds:[{id,label}]}` | Static from server `CAMERAS` config (coords stay server-side). |

**Removed callbacks:** `createWarrant`, `closeWarrant` (warrants are now derived, read-only). The `pengu_mdt_warrants` table is dropped from use (leave `CREATE TABLE IF NOT EXISTS` out; existing rows ignored).

**Client-only NUI callbacks (no server hop):** `closeMdt`, `viewCamera {id}`, `exitCamera {}`, `toggleBodycam {}` (see §7).

---

## 3. `pengu_mdt_charges` — add `status` column

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
  status VARCHAR(16) DEFAULT 'outstanding',   -- 'outstanding' | 'processed'
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

Idempotent migration for existing installs (run on resource start, after the CREATE):

```sql
ALTER TABLE pengu_mdt_charges
  ADD COLUMN IF NOT EXISTS status VARCHAR(16) DEFAULT 'outstanding';
```
(MariaDB supports `ADD COLUMN IF NOT EXISTS`. If the engine rejects it, guard with an `INFORMATION_SCHEMA.COLUMNS` check first.)

- `placeCharges` INSERT sets `status='outstanding'` explicitly.
- `searchPerson.outstanding` query: `WHERE citizenid=? AND status='outstanding' ORDER BY created_at DESC`.
- `totals` query stays lifetime (all statuses) — represents the person's record.
- `/jail` flips the served rows to `status='processed'` (they leave outstanding + warrants but remain in lifetime totals).

New SQL constants to add in `server/main.lua`:

```sql
-- OUTSTANDING_FOR_PERSON (replaces OUTSTANDING_SQL)
SELECT code, title, class, months, fine, modifiers
FROM pengu_mdt_charges
WHERE citizenid = ? AND status = 'outstanding'
ORDER BY created_at DESC;

-- SUM_OUTSTANDING (used by /jail)
SELECT COALESCE(SUM(months),0) AS months, COALESCE(SUM(fine),0) AS fine, COUNT(*) AS charges
FROM pengu_mdt_charges
WHERE citizenid = ? AND status = 'outstanding';

-- MARK_PROCESSED (used by /jail)
UPDATE pengu_mdt_charges SET status='processed'
WHERE citizenid = ? AND status='outstanding';
```

`getWarrants` is computed in Lua: loop `GetQBPlayers()` → for each, run `SUM_OUTSTANDING` with their cid; emit `{name, charges, months, fine}` only when `charges > 0`. (Online-only, so the count stays small.)

---

## 4. `pengu_mdt_bolos` — add `image_url`

```sql
CREATE TABLE IF NOT EXISTS pengu_mdt_bolos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  type VARCHAR(16) DEFAULT 'person',          -- person | vehicle | other
  title VARCHAR(128) NOT NULL,
  description TEXT,
  image_url VARCHAR(512) DEFAULT '',          -- optional http(s) image
  officer VARCHAR(128),
  status VARCHAR(16) DEFAULT 'active',         -- active | cancelled
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```
Migration: `ALTER TABLE pengu_mdt_bolos ADD COLUMN IF NOT EXISTS image_url VARCHAR(512) DEFAULT '';`

`createBolo` validation: `if type(image_url)=='string' and image_url:match('^https?://') then keep else image_url = '' end`. `getBolos` SELECT adds `image_url`. NUI renders `<img>` when non-empty, else no image.

---

## 5. `pengu_mdt_mugshots` — new table

```sql
CREATE TABLE IF NOT EXISTS pengu_mdt_mugshots (
  citizenid VARCHAR(64) PRIMARY KEY,
  image MEDIUMTEXT,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
```

Flow:
1. `placeCharges` — after resolving the named target, if ONLINE (`GetPlayerByCitizenId(cid).PlayerData.source`), `TriggerClientEvent('pengu_mdt:captureMugshot', targetSrc)`.
2. CLIENT `RegisterNetEvent('pengu_mdt:captureMugshot')`: in a `CreateThread`, `local img = exports["MugShotBase64"]:GetMugShotBase64(cache.ped or PlayerPedId(), true)`; if `img` and `img ~= ''` and `img ~= 'none'` → `TriggerServerEvent('pengu_mdt:storeMugshot', img)`. (Capture is blocking ~≤2s; run off-thread so it never stalls.)
3. SERVER `RegisterNetEvent('pengu_mdt:storeMugshot', function(image))`: derive cid from `GetPlayer(source)` (the captured player IS the source — never trust a cid from the client). Validate `type(image)=='string'` and a sane length cap (e.g. `#image < 600000`). UPSERT:
   ```sql
   INSERT INTO pengu_mdt_mugshots (citizenid, image) VALUES (?, ?)
   ON DUPLICATE KEY UPDATE image = VALUES(image), updated_at = CURRENT_TIMESTAMP;
   ```
4. `searchPerson` SELECTs `image` from `pengu_mdt_mugshots WHERE citizenid=?` → returns as `mugshot` (or `null`). NUI shows the image or a placeholder silhouette.

---

## 6. `/jail` command — the ONLY way to imprison

Register a **server** command (`lib.addCommand('jail', ...)` or `RegisterCommand('jail', ...)`, server-side). Usage: `/jail [id]` where `id` = target server id.

Flow (all server-side, authoritative):
1. **Officer auth:** `getOfficer(source)` must be leo, else notify "Not authorized."
2. **Resolve target:** `local target = exports.qbx_core:GetPlayer(tonumber(id))`; if nil → notify officer "Invalid target id." `local targetSrc = target.PlayerData.source`.
3. **DOC proximity (on the SUSPECT):**
   ```lua
   local DOC = vec3(1845.83, 2585.90, 45.67)
   local pos = GetEntityCoords(GetPlayerPed(targetSrc))
   if #(pos - DOC) > 50.0 then notify officer "Suspect must be at the Department of Corrections." return end
   ```
4. **Sum outstanding:** run `SUM_OUTSTANDING` with `target.PlayerData.citizenid` → `totalMonths, totalFine, charges`. If `charges == 0` → notify "No outstanding charges." return.
5. **Jail:** `exports["xt-prison"]:JailPlayerById(targetSrc, totalMonths)` (caps at 60 internally).
6. **Forced fine:** `target.Functions.RemoveMoney('bank', totalFine, 'doc-processing')` — deducts what is collectible (the forced payment; no insufficient-funds abort).
7. **Mark processed:** run `MARK_PROCESSED` with the cid (`SET status='processed' WHERE citizenid=? AND status='outstanding'`). This clears them from Person-search outstanding + Warrants.
8. **Notify both:** officer + target via `lib.notify`, reporting `charges` charges, **served minutes = `math.min(totalMonths, 60)`**, and `$totalFine` fined.

No proximity/booking gate remains in `placeCharges` (the old `BOOKING_POINTS`/`officerAtBooking` and the client `jailProximity` thread/message are deleted — see §8).

---

## 7. Cameras tab

### Server `CAMERAS` config (coords stay server-side)

```lua
local CAMERAS = {
  { id = 'mrpd_lobby',  label = 'MRPD — Lobby',            cam = vec3(441.0, -979.0, 31.5),   point = vec3(441.5, -982.6, 30.7) },
  { id = 'legion_sq',   label = 'Legion Square',           cam = vec3(190.0, -933.0, 40.0),   point = vec3(195.5, -933.9, 30.7) },
  { id = 'pacific_bank',label = 'Pacific Standard Bank',   cam = vec3(248.0, 225.0, 112.0),   point = vec3(235.0, 216.0, 106.3) },
  { id = 'doc_yard',    label = 'Bolingbroke DOC — Yard',  cam = vec3(1850.0, 2600.0, 55.0),  point = vec3(1845.8, 2585.9, 45.7) },
}
```
`getCameras` returns only `{id, label}` per feed (NUI never sees coords). The full table is also needed CLIENT-side for `viewCamera` — duplicate the same `CAMERAS` (id→cam/point) in `client/main.lua`, or expose via a `lib.callback` the client awaits once. Simplest: hard-code the same table in both files.

### Client NUI callbacks (client-only)
- `viewCamera {id}`: look up the feed; `local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)`; `SetCamCoord(cam, feed.cam)`; `PointCamAtCoord(cam, feed.point)`; `SetCamFov(cam, 60.0)`; `RenderScriptCams(true, false, 0, true, true)`. Track the active cam handle. `cb('ok')`.
- `exitCamera {}`: `RenderScriptCams(false, false, 0, true, true)`; `DestroyCam(activeCam, false)`; clear handle. `cb('ok')`.
- Force-exit on `closeMdt` and `onResourceStop` so a player is never stuck in a scripted cam.

### Bodycam toggle
Keep SIMPLE — `screenshot-basic` is **not installed**, so do **not** attempt a real capture. `toggleBodycam {}` just flips a client `bodycamOn` flag and the NUI shows a corner **● REC / bodycam timestamp** indicator overlay (a stub). `cb({on = bodycamOn})`.

---

## 8. Tab structure (8 tabs)

Left rail, outline icons, glass theme (carry over §1 tokens from REDESIGN.md):

| # | Tab | State | Purpose |
|---|---|---|---|
| 1 | **Dashboard** | NEW (landing) | On-duty units roster (`getDashboard`): callsign · name · job label. Refresh button. |
| 2 | **Vehicle** | reskin/simplify | Plate lookup → owner, model, plate, VIN, phone. (Drop totals/outstanding block.) |
| 3 | **Person** | rework | Name lookup → **mugshot** + name + phone + totals + outstanding (`{code,title,class,months,fine,modifiers}`); "Charge in Calculator →" sets target NAME. **No cid field.** |
| 4 | **Arrest** | rework | Penal-code calculator. Target = NAME (read-only chip from Person). Single **"Place Charges"** button → records outstanding only. **Remove Send-to-Jail + Issue-Fine buttons.** |
| 5 | **BOLOs** | extend | List (with optional image) + create (type/title/description/image_url) + cancel. |
| 6 | **Warrants** | rework | **Read-only derived** list: name · charges(count) · months(sum) · fine(sum). No create/close form. |
| 7 | **Reports** | reword | List + create (title/type/content/**subject_name**) + view. No cid. |
| 8 | **Cameras** | NEW | Feed buttons (`getCameras`) → `viewCamera`; "Exit Camera" → `exitCamera`; bodycam toggle. |

---

## 9. File-by-file change list

| File | Change |
|---|---|
| `server/main.lua` | Add `status` to charges DDL + migration; add `image_url` to bolos DDL + migration; add `pengu_mdt_mugshots` DDL. New SQL: `OUTSTANDING_FOR_PERSON`, `SUM_OUTSTANDING`, `MARK_PROCESSED`, mugshot UPSERT/SELECT, bolos w/ image_url, reports w/ `subject_name`. Rewrite `handleSearchPerson` (by name, mugshot, new outstanding shape, **no cid**), `handleSearchVehicle` (drop totals/outstanding, **no cid**), `handlePlaceCharges` (`{name,items}` → resolve cid, insert `status='outstanding'`, fire mugshot capture, **no jail/fine, no cid out**). Add `handleGetDashboard`, `handleGetWarrants` (derived), `handleGetCameras`. Update bolo/report handlers. **Delete** `handleCreateWarrant`/`handleCloseWarrant` + `BOOKING_POINTS`/`officerAtBooking`. Add `RegisterNetEvent('pengu_mdt:storeMugshot')`. Add `/jail` command + `CAMERAS` config + `DOC` const. Update the dual-register `handlers` map. |
| `client/main.lua` | Add `pengu_mdt:captureMugshot` net event (calls `MugShotBase64`, stores via `pengu_mdt:storeMugshot`). Add `CAMERAS` table + `viewCamera`/`exitCamera`/`toggleBodycam` NUI callbacks + active-cam cleanup on close/stop. Add NUI relays for `getDashboard`/`getCameras`. **Remove** the jail-proximity thread, `sendJailProximity`, `jailProximity` message, `BOOKING_POINTS`. Remove `createWarrant`/`closeWarrant` from the relay list; keep `searchPerson` (now `{name}`), `placeCharges` (now `{name,items}`). |
| `html/index.html` | Add Dashboard + Cameras rail buttons/sections. Person: replace cid field with a mugshot `<img id="per-mug">` + placeholder; rebuild outstanding table headers to `Code/Charge/Class/Jail/Fine/Modifiers`. Arrest: delete `#target-cid` input + jail/fine buttons; add read-only `#target-name` chip + single `#btn-place` "Place Charges". Warrants: delete create form; static read-only list. Reports: rename cid input → `#report-subject` "Subject Name (optional)". BOLOs: add image_url input + `<img>` in rows. |
| `html/app.js` | Add `loadDashboard`, `loadCameras`/`viewCamera`/`exitCamera`/`toggleBodycam`. Rework `searchPerson` (`{name}`, render mugshot, new outstanding rows), `searchVehicle` (drop totals/outstanding), `placeCharges` (`{name, items}`, single button, success just clears cart + refreshes person), target = name chip not cid input. **Remove** `state.canJail`, `jailProximity` handling, `updateActionButtons` jail branch, warrant create/close fns. Update `getWarrants` render (name/charges/months/fine). Reports use `subject_name`. |
| `fxmanifest.lua` | Add `'MugShotBase64'` to `dependencies`; bump `version` to `2.0.0`. (html files already globbed.) |
| `SPEC.md` | Append the new callback contract, `status`/`image_url`/mugshots schema, `/jail` flow, derived warrants, cameras. |

---

## 10. Authoritative `placeCharges` (revised)

1. `getOfficer(source)` leo gate.
2. Resolve `name` → row via `PERSON_SQL` (LIKE first/last); if none → `{success=false, message='Person not found'}`. Capture `cid` (server-only).
3. For each `item`: look up `base = chargeIndex[item.code]` (skip unknown); `mult=1.0`; for each `modId`: reject if in `base.blockedModifiers` → `{success=false, message='Blocked modifier on '..base.code}`; else `mult = mult * modIndex[modId].mult`. `m = floor(months*mult+0.5)`, `f = floor(fine*mult+0.5)`. Collect insert row with `status='outstanding'`.
4. If zero valid → `{success=false, message='No valid charges'}`. Else INSERT all rows.
5. `local tgt = GetPlayerByCitizenId(cid)`; if `tgt` online → `TriggerClientEvent('pengu_mdt:captureMugshot', tgt.PlayerData.source)`.
6. Return `{success=true, message=('Recorded %d charge(s) as outstanding.'):format(placed)}` — **no cid, no jail, no fine.**

---

## 11. Out of scope / kept simple

- No real bodycam capture (no `screenshot-basic`); REC indicator stub only.
- Warrants are a live derived view of online players' outstanding charges — no warrant table, no expiry.
- Cameras: 4 fixed scripted-cam presets, no PTZ, no NUI video element.
- Mugshot is whatever the suspect's ped looks like at charge time (MugShotBase64 headshot); placeholder when none stored.
- Reports stay flat (title/type/content/subject_name/officer); person refs are names only.
