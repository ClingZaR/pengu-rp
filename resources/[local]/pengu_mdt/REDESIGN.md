# pengu_mdt — Redesign + Feature Expansion Spec

Reskin the MDT to match **pengu_hud**, FIX the full-black-background bug, and ADD
three deliberately-simple tabs (BOLOs, Warrants, Reports), each backed by its own
`pengu_mdt_*` table. Adds a realism **jail proximity gate** on Send to Jail.

Path: `/opt/fivem/server/txData/Qbox_389702.base/resources/[local]/pengu_mdt`
Stack (unchanged): qbx_core + ox_lib + oxmysql (+ xt-prison).

---

## 0. The bug being fixed (read first)

`html/style.css` currently does:

```css
#app{ ... background:radial-gradient(...); backdrop-filter:blur(2px); }
.mdt-window{ background:linear-gradient(180deg, var(--bg-2), var(--bg)); ... }
```

`backdrop-filter` renders as a **fullscreen black box** in CEF/FiveM NUI — this is the
"full black background" bug. The whole `style.css` is also a blue/dark `#070a11`
police theme that does not match pengu_hud.

**Fix:** rewrite `style.css` to the pengu_hud glass theme.
- **Remove every `backdrop-filter`** (there must be zero in the final file).
- `html, body { background: transparent !important; }`.
- The overlay `#app` uses a flat dim, NOT a gradient and NOT a blur:
  `background: rgba(0,0,0,0.45);` (light dim so the world shows through — not solid black).
- All panels use the `.glass` recipe (below). No solid `#0c111c`/`#070a11` fills.

---

## 1. Theme tokens (match pengu_hud EXACTLY)

Replace the `:root` block in `html/style.css` with these tokens and use them everywhere.

```css
:root{
  /* surfaces */
  --glass-bg:      rgba(16,16,24,0.72);
  --glass-border:  rgba(255,255,255,0.09);
  --glass-radius:  14px;
  --glass-shadow:  0 6px 24px rgba(0,0,0,0.45);
  --dim:           rgba(0,0,0,0.45);   /* overlay backdrop, NOT solid black */

  /* accents */
  --accent:        #E1C7F9;            /* lavender — primary/highlight/active */
  --accent-tint:   rgba(225,199,249,0.13);
  --green:         #7CFFA0;            /* success / positive */
  --danger:        #ff5a5a;
  --warning:       #facc15;

  /* charge-class badges */
  --felony:        #ff5a5a;
  --misdemeanor:   #facc15;
  --citation:      #5BAAFF;

  /* text */
  --text:          #fff;
  --text-2:        rgba(255,255,255,0.6);
  --text-muted:    rgba(255,255,255,0.4);

  /* controls */
  --btn-bg:        rgba(255,255,255,0.06);
  --btn-border:    rgba(255,255,255,0.1);
  --hairline:      rgba(255,255,255,0.09);

  --font: Arial, "Helvetica Neue", sans-serif;
}

* { margin:0; padding:0; box-sizing:border-box; }
html, body {
  width:100vw; height:100vh; overflow:hidden;
  background: transparent !important;
  font-family: var(--font); color: var(--text); user-select:none;
}
.hidden { display:none !important; }

.glass{
  background: var(--glass-bg);
  border: 1px solid var(--glass-border);
  border-radius: var(--glass-radius);
  box-shadow: var(--glass-shadow);
}
```

**Component rules (apply throughout):**

| Element | Style |
|---|---|
| Overlay `#app` | `position:fixed; inset:0; display:flex; place-items:center; background:var(--dim);` — **no blur, no gradient** |
| MDT panel | `.glass`, **centered**, `width:min(1100px,70vw); height:min(760px,80vh);` flex row (rail + content) |
| Cards/panels | `.glass` (or `background:var(--glass-bg); border:1px solid var(--glass-border)`); rounded 14px |
| Hairline dividers | `1px solid var(--hairline)` |
| Text | primary `#fff`; secondary `var(--text-2)`; muted `var(--text-muted)` |
| Button (default) | `background:var(--btn-bg); border:1px solid var(--btn-border); color:var(--text-2);` hover → `color:#fff; border-color:rgba(255,255,255,0.25)` |
| Button (primary/active) | `background:var(--accent-tint); border:1px solid var(--accent); color:var(--accent);` |
| Button (danger) | tint `rgba(255,90,90,0.13)`, border+text `var(--danger)` |
| Button (success) | tint `rgba(124,255,160,0.13)`, border+text `var(--green)` |
| Button (disabled) | `opacity:0.4; cursor:not-allowed;` + `title` tooltip |
| Active rail tab | accent: `background:var(--accent-tint); border-color:var(--accent); color:var(--accent)` |
| Badge felony | text/border `--felony`, bg `rgba(255,90,90,0.16)` |
| Badge misdemeanor | text/border `--misdemeanor`, bg `rgba(250,204,21,0.15)` |
| Badge citation | text/border `--citation`, bg `rgba(91,170,255,0.15)` |
| Status dot / accent dot | `var(--accent)` with `box-shadow:0 0 8px var(--accent)` (from `#sett-dot`) |

**Icons:** replace all current `<svg><path fill="currentColor">` filled glyphs with
**thin stroke line SVGs** like the HUD (`fill:none; stroke:currentColor; stroke-width:2;
stroke-linecap:round; stroke-linejoin:round`). Strokes are accent or white. No
font-awesome, no filled shields/glyphs. Rail icons: car, person, gavel/scale, eye
(BOLO), document-stamp (warrant), file-text (report) — all outline style.

---

## 2. Layout

Replace `.mdt-window` (dark gradient) with a centered `.glass` panel:

```
#app  (fixed inset:0, background:var(--dim), flex center)
└── .mdt-panel.glass   (min(1100px,70vw) × min(760px,80vh), display:flex)
    ├── header .mdt-titlebar  (brand + "SECURE LINK" accent dot + close ✕)
    └── .mdt-body (flex:1, display:flex)
        ├── nav .mdt-rail   (left tab rail — 6 buttons, outline icons)
        └── main .mdt-content  (active tab panel)
```

The titlebar status dot uses `var(--accent)` (lavender) + glow. Close button is a
stroke ✕; hover tints `--danger`.

---

## 3. Tab list (6 tabs)

| # | Tab | Keep/New | Purpose |
|---|---|---|---|
| 1 | **Vehicle** | keep (reskin) | Plate lookup → registration + owner totals + outstanding charges |
| 2 | **Person** | keep (reskin) | Name/phone lookup → record + totals + outstanding; "Charge in Calculator →" |
| 3 | **Arrest** | keep (reskin) | Penal-code calculator → Send to Jail (**proximity-gated**) / Issue Fine |
| 4 | **BOLOs** | NEW | List active BOLOs + create + cancel |
| 5 | **Warrants** | NEW | List active warrants + create + close |
| 6 | **Reports** | NEW | List reports + create + view |

Tabs 1–3 keep their existing markup/JS logic; only the CSS classes + icons change to
the glass theme. Tabs 4–6 are new (sections below).

---

## 4. New tables (keep columns minimal)

Created on resource start via `MySQL.query.await(...)` (alongside `pengu_mdt_charges`).
All three are **standalone** — no foreign keys, no joins to ps-mdt tables. ps-mdt links
BOLOs/warrants to a `reportId`; we deliberately drop that coupling to stay simple.

### pengu_mdt_bolos
```sql
CREATE TABLE IF NOT EXISTS pengu_mdt_bolos (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  type        VARCHAR(16)  DEFAULT 'person',   -- person | vehicle | other
  title       VARCHAR(128) NOT NULL,           -- subject / plate / short label
  description TEXT,                             -- free-text details
  officer     VARCHAR(128),                     -- author (charinfo name)
  status      VARCHAR(16)  DEFAULT 'active',    -- active | cancelled
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```
(Mirrors ps-mdt `mdt_bolos.type` enum + `subject_name`(→title) + `notes`(→description)
+ `status`, minus `reportId`/`subject_id` FK noise. We collapse status to active/cancelled.)

### pengu_mdt_warrants
```sql
CREATE TABLE IF NOT EXISTS pengu_mdt_warrants (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  citizenid   VARCHAR(64),                      -- subject cid (optional)
  name        VARCHAR(128) NOT NULL,            -- subject display name
  reason      TEXT,                             -- charge summary / cause
  officer     VARCHAR(128),                     -- issuing officer
  status      VARCHAR(16)  DEFAULT 'active',    -- active | closed
  expires_at  TIMESTAMP NULL,                   -- default now()+7d
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```
(ps-mdt `mdt_reports_warrants` keys on reportid+citizenid with felony/misd/infraction
counts and an `expirydate`; "close" = set expirydate=NOW(). We keep `expires_at` +
an explicit `status` flag and a single free-text `reason` instead of the count triplet.)

### pengu_mdt_reports
```sql
CREATE TABLE IF NOT EXISTS pengu_mdt_reports (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  title       VARCHAR(128) NOT NULL,
  type        VARCHAR(32)  DEFAULT 'Incident',  -- Incident | Arrest | Other
  content     TEXT,                             -- plaintext body
  citizenid   VARCHAR(64),                      -- optional subject cid
  officer     VARCHAR(128),                     -- author (charinfo name)
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```
(ps-mdt `mdt_reports` fans out to ~10 child tables — involved, charges, evidence,
restrictions, tags, vehicles, warrants. We collapse to a single flat row: title + type +
plaintext content + optional subject cid + author. No restrictions/job-scoping.)

---

## 5. New server callbacks

Register under BOTH `pengu_mdt:<name>` and `pengu_mdt:server:<name>` (same dual-naming
loop already in `server/main.lua`). Every handler first runs the existing
`getOfficer(source)` LEO gate and returns `{success=false, message='Not authorized'}`
(or `{items={}}` for reads) when it fails. Author name = `officerName(officer)` (existing
helper). New SQL constants live next to the current ones in `server/main.lua`.

| NUI name | Req | Response | Notes |
|---|---|---|---|
| `getBolos` | `{}` | `{items:[{id,type,title,description,officer,created_at}]}` | `WHERE status='active' ORDER BY created_at DESC LIMIT 50` |
| `createBolo` | `{type,title,description}` | `{success, message}` | validate `title~=''`; INSERT with officer, status='active' |
| `cancelBolo` | `{id}` | `{success, message}` | `UPDATE ... SET status='cancelled' WHERE id=?` |
| `getWarrants` | `{}` | `{items:[{id,citizenid,name,reason,officer,expires_at,created_at}]}` | `WHERE status='active' ORDER BY created_at DESC LIMIT 50` |
| `createWarrant` | `{citizenid,name,reason}` | `{success, message}` | validate `name~=''`; `expires_at = NOW()+INTERVAL 7 DAY`, status='active' |
| `closeWarrant` | `{id}` | `{success, message}` | `UPDATE ... SET status='closed' WHERE id=?` |
| `getReports` | `{}` | `{items:[{id,title,type,citizenid,officer,created_at}]}` | list view omits `content`; `ORDER BY created_at DESC LIMIT 50` |
| `getReport` | `{id}` | `{found, report:{id,title,type,content,citizenid,officer,created_at}}` | full body for the viewer |
| `createReport` | `{title,type,content,citizenid}` | `{success, message}` | validate `title~=''`; INSERT with officer |

Reads return plain arrays (no jail/fine logic). Writes return
`{success, message}` so the NUI can toast (`ok`/`err`) and refresh the list. All inputs
are validated/typed server-side; unknown columns ignored. Use parameterized queries only.

Client `client/main.lua`: add one `RegisterNUICallback` per name that relays via
`cb(lib.callback.await('pengu_mdt:'..name, false, data or {}))` — identical pattern to
the existing four.

---

## 6. New tabs — UI behavior (kept simple)

Each new tab = a `.glass` list card + a small inline "create" form (`.glass`), all using
the theme tokens. No modals required; an inline collapsible create panel is enough.

**BOLOs**
- Header: "BOLOs" + `+ New BOLO` (primary/accent button) toggling the create form.
- Create form: `type` select (Person/Vehicle/Other) · `title` text · `description` textarea · `Create` (accent) / `Cancel`.
- List rows (`.glass`): type chip · title (bold) · description (muted) · officer + date (muted) · `Cancel` (danger) button → `cancelBolo` then refresh.
- Empty state: muted "No active BOLOs." Refresh on tab open + after create/cancel.

**Warrants**
- Header: "Warrants" + `+ New Warrant`.
- Create form: `name` text (required) · `citizenid` text (optional; auto-filled if coming from Person tab) · `reason` textarea · `Create` / `Cancel`.
- List rows: name (bold) · cid (mono muted) · reason · officer · expires_at (date) · `Close` (danger) → `closeWarrant` then refresh.
- Empty state: "No active warrants."

**Reports**
- Header: "Reports" + `+ New Report`.
- Create form: `title` text (required) · `type` select (Incident/Arrest/Other) · `citizenid` text (optional) · `content` textarea · `Create` / `Cancel`.
- List rows: title (bold) · type chip · officer · date · `View` (default button) → `getReport` → show body in a read-only detail card (in-tab, with a `← Back` button).
- Empty state: "No reports filed."

All three: a `loadX()` runs on first open of the tab and after any mutation; reuse the
existing `nui()` fetch wrapper, `toast()`, and `escapeHtml()` in `app.js`. Buttons go
disabled (`is-busy`) during in-flight requests.

---

## 7. Jail proximity gate (realism)

**Booking points** (Send to Jail enabled within **30m** of either):
- Bolingbroke Penitentiary `vec3(1845.83, 2585.90, 45.67)`
- MRPD cells/booking `vec3(461.8, -995.0, 25.06)`

### CLIENT (`client/main.lua`)
- Add booking points table + 30m radius constant.
- While the MDT `isOpen`, run a `CreateThread` that every ~1000ms computes the min
  distance from `GetEntityCoords(PlayerPedId())` to the two points and sends:
  `SendNUIMessage({ action='jailProximity', canJail = (minDist <= 30.0) })`.
  Loop exits when `isOpen` becomes false. Send one immediate message on open so the
  button state is correct before the first tick.

### NUI (`app.js` + `style.css`)
- Handle `message.action === 'jailProximity'`: store `state.canJail = !!d.canJail`,
  then call `updateActionButtons()`.
- In `updateActionButtons()`: the **Send to Jail** button is enabled only when
  `hasTarget && hasItems && state.canJail`. When `!state.canJail`, add `disabled` +
  `title="Take the suspect to a jail/booking to imprison"` (greyed via the disabled
  style). **Issue Fine stays gated only on `hasTarget && hasItems`** (always allowed
  near/away).

### SERVER (`server/main.lua`, authoritative re-check in `handlePlaceCharges`)
- Before jailing: if `data.sendToJail`, get the **officer** (source) coords via
  `GetEntityCoords(GetPlayerPed(source))` and verify min distance to a booking point
  `<= 30.0`.
  - If too far → **skip jail only**: still record charges + apply fine, set
    `jailed=false`, and add `"Not at a booking location"` to the result message
    (`success` stays true for recording/fine).
  - If within range → proceed to `JailPlayerById` as today (xt-prison still caps 60 min).
- Booking points + radius are duplicated server-side (do not trust the client flag).

```lua
local BOOKING_POINTS = {
  vec3(1845.83, 2585.90, 45.67),  -- Bolingbroke
  vec3(461.8,  -995.0,  25.06),   -- MRPD
}
local BOOKING_RADIUS = 30.0
```

---

## 8. File-by-file change list

| File | Change |
|---|---|
| `html/style.css` | **Rewrite** to glass theme tokens (§1). Delete all `backdrop-filter`; `#app` → flat `var(--dim)`; `.mdt-panel.glass` centered 70vw/80vh max 1100×760; restyle cards/buttons/badges/rail; add BOLO/Warrant/Report list + create-form + report-viewer styles. |
| `html/index.html` | Restyle existing 3 tabs (swap filled SVGs → stroke icons, classes → theme). Add 3 rail buttons + 3 `<section class="tab-panel" data-tab="...">` for bolos/warrants/reports (list card + inline create form + reports detail view). |
| `html/app.js` | Add `state.canJail`; handle `jailProximity` message; gate Send-to-Jail in `updateActionButtons()`. Add `loadBolos/createBolo/cancelBolo`, `loadWarrants/createWarrant/closeWarrant`, `loadReports/createReport/openReport`, render fns + wiring; lazy-load each tab on first show. |
| `client/main.lua` | Add booking points + radius; proximity `CreateThread` while open sending `jailProximity`; add `RegisterNUICallback` relays for the 9 new callbacks. |
| `server/main.lua` | Add 3 `CREATE TABLE` on start; new SQL constants + 9 handlers (BOLO/Warrant/Report) registered in the dual-name loop; officer-coords booking gate in `handlePlaceCharges`. |
| `fxmanifest.lua` | No structural change (html files already globbed/listed). Bump `version` to `1.1.0`. |
| `SPEC.md` | Append the 3 new tables, 9 callbacks, and the proximity gate to the callback table. |

---

## 9. Out of scope (kept simple on purpose)

- No reportId/case linkage between BOLOs/warrants/reports (ps-mdt couples them; we don't).
- No evidence, tags, restrictions, involved-persons, vehicles, or job-scoping on reports.
- No warrant felony/misd/infraction count triplet — a single `reason` string instead.
- No edit/delete of reports (create + view only); BOLOs/warrants get cancel/close (soft).
- No images/mugshots, no dispatch, no plate-scan BOLO integration.
- Auto-expiry is informational (`expires_at`); list filters on `status='active'`.
```

The verified inputs from ps-mdt are reflected: `mdt_bolos(type,subject_name,notes,status)`,
`mdt_reports_warrants(reportid,citizenid,...,expirydate)` where close = `SET expirydate=NOW()`,
and `mdt_reports(title,type,contentplaintext,author,datecreated)` + child tables.
