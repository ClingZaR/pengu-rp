# pengu_mdt - POLISH PLAN

Concrete implementation plan for the Cameras / Warrants / OOC / dash polish pass.
Scope is `pengu_mdt` only. Keep callback names, NO citizenid in UI, glass theme
(lavender #E1C7F9, stroke icons), luac + `node --check` clean, NUI focus balanced.

Files: `html/app.js`, `html/index.html`, `html/style.css`, `client/main.lua`, `server/main.lua`.

Reference reviewed (NOT copied): `[standalone]/ps-mdt/client/cameras.lua`. Useful real-CCTV
techniques to borrow conceptually: `CreateCam('DEFAULT_SCRIPTED_CAMERA', true)` +
`SetCamCoord`/`PointCamAtCoord`/`SetCamFov` + `RenderScriptCams(true,...)` (already used here),
plus `SetFocusPosAndVel(cam.x,cam.y,cam.z,0,0,0)` to stream the area in when the ped is far,
an optional `SetTimecycleModifier('scanline_cam_cheap')` for a CCTV look, and matching
`ClearFocus()` / `ClearTimecycleModifier()` on exit. We keep our simpler point-at model.

---

## 1) CAMERAS - real CCTV behaviour

### 1a. Feed list (14 feeds) - SERVER `CAMERAS` config + mirrored client `CAMERAS`

Define identically in `server/main.lua` (`local CAMERAS`, lines ~32-37) and
`client/main.lua` (`local CAMERAS`, lines ~55-60). Server `getCameras` keeps exposing
only `{id,label}`; client keeps full `{id,label,cam,point}` for scripted-cam placement.

| id              | label                       | cam (vec3)                  | point (vec3)                |
|-----------------|-----------------------------|-----------------------------|-----------------------------|
| mrpd_lobby      | MRPD - Lobby                | 441.0, -979.0, 31.5         | 441.5, -982.6, 30.7         |
| mrpd_cells      | MRPD - Cell Block           | 461.5, -994.0, 30.7         | 465.5, -1000.5, 24.9        |
| legion_sq       | Legion Square               | 190.0, -933.0, 40.0         | 195.5, -933.9, 30.7         |
| pacific_bank    | Pacific Standard Bank       | 248.0, 225.0, 112.0         | 235.0, 216.0, 106.3         |
| fleeca_legion   | Fleeca - Alta St            | 146.5, -1045.5, 33.5        | 151.0, -1037.0, 29.4        |
| fleeca_hawick   | Fleeca - Hawick Ave         | -355.5, -44.5, 53.5         | -350.5, -52.5, 49.0         |
| store_strawberry| 24/7 - Strawberry Ave       | 29.5, -1340.5, 33.5         | 24.5, -1348.5, 29.5         |
| store_sandy     | 24/7 - Sandy Shores         | 1965.5, 3745.0, 36.0        | 1959.0, 3741.0, 32.3        |
| vespucci_pd     | Vespucci Police Station     | -1100.0, -835.0, 19.0       | -1110.0, -846.0, 13.5       |
| sandy_sheriff   | Sandy Shores Sheriff        | 1860.0, 3679.0, 38.0        | 1852.0, 3689.5, 34.0        |
| paleto_sheriff  | Paleto Bay Sheriff          | -437.0, 6021.0, 36.5        | -448.5, 6007.0, 31.7        |
| doc_yard        | Bolingbroke DOC - Yard      | 1850.0, 2600.0, 55.0        | 1845.8, 2585.9, 45.7        |
| vinewood_blvd   | Vinewood Boulevard          | 294.0, 207.0, 92.0          | 305.0, 195.0, 84.0          |
| del_perro       | Del Perro Pier              | -1843.0, -1242.0, 18.5      | -1856.0, -1228.0, 12.5      |
| lsia            | LS Intl Airport             | -1031.0, -2730.0, 25.5      | -1042.0, -2744.0, 19.5      |

(4 existing feeds kept verbatim; 11 added - that is 15 total. `mrpd_cells` is the extra
beyond the 14 named locations; drop it if exactly 14 is preferred.)

### 1b. Camera-mode UI flow (the real fix: panel must get out of the way)

Goal: opening a feed HIDES the MDT panel and makes the dim backdrop transparent so the
player sees the scripted cam view of the game world, with only a compact overlay on top.
NUI focus stays TRUE the whole time (overlay buttons need the cursor); exiting returns to
the panel; closing the MDT releases focus and restores the player view.

**index.html** - add a camera overlay as a direct child of `#app` but OUTSIDE `.mdt-panel`
(so it survives the panel being hidden). Place it right before `<div id="toast">`:

```html
<div id="cam-overlay" class="cam-overlay glass hidden" role="group" aria-label="Camera feed">
  <div class="cam-ov-left">
    <span class="rec-dot live"></span>
    <span class="cam-ov-live">LIVE</span>
    <span class="cam-ov-name" id="cam-ov-name">-</span>
  </div>
  <div class="cam-ov-right">
    <button id="cam-prev" class="btn sm" title="Previous feed">Prev</button>
    <span class="cam-ov-index tnum" id="cam-ov-index">1 / 15</span>
    <button id="cam-next" class="btn sm" title="Next feed">Next</button>
    <button id="cam-exit-ov" class="btn danger sm">Exit</button>
  </div>
</div>
```

In the Cameras tab, REMOVE the in-panel `#cam-active` red bar (index.html lines 431-437);
its job moves to the overlay. (Alternatively keep it hidden - but removing is cleaner.)

**index.html tile caption** - REMOVE the "Click to view feed" caption entirely. It is
rendered in app.js `loadCameras()` (line ~827) as `<span class="cam-tile-sub">Click to view
feed</span>`. Delete that span so each tile shows only the feed label. Also remove the now
unused `.cam-tile-sub` CSS rule (style.css line 531).

**style.css** - add cam-mode rules (after the CAMERAS block, ~line 532):

```css
/* camera mode: hide the panel, drop the dim, show only the overlay */
#app.cam-mode{ background:transparent; }
#app.cam-mode .mdt-panel{ display:none; }

.cam-overlay{
  position:fixed; left:50%; bottom:30px; transform:translateX(-50%);
  display:flex; align-items:center; gap:20px;
  padding:10px 16px; z-index:70;
}
.cam-ov-left{ display:flex; align-items:center; gap:9px; }
.cam-ov-live{ font-size:11px; font-weight:800; letter-spacing:1.5px; color:var(--danger); }
.cam-ov-name{ font-size:14px; font-weight:700; color:#fff; }
.cam-ov-right{ display:flex; align-items:center; gap:8px; }
.cam-ov-index{ font-size:12px; color:var(--text-muted); font-family:var(--mono); min-width:48px; text-align:center; }
```
(`.rec-dot.live` and `.glass` already exist; reuse them. No backdrop-filter.)

**app.js** - state already has `activeCam`. Add the cam-mode toggles and prev/next.

- `enterCamMode()`: `app.classList.add('cam-mode')`; `$('#cam-overlay').classList.remove('hidden')`.
- `exitCamMode()`: `app.classList.remove('cam-mode')`; `$('#cam-overlay').classList.add('hidden')`.
- Rework `markActiveCam()` to drive the overlay (name + `N / total` index) and the
  `.cam-tile.active` highlight, instead of the deleted `#cam-active` bar.
- `viewCamera(id,label)`: unchanged server hop `nui('viewCamera',{id})`; on `ok` set
  `state.activeCam={id,label}`, `enterCamMode()`, `markActiveCam()`. Keep a module-level
  `state.feeds` array (filled in `loadCameras`) so prev/next can index it.
- `exitCamera()`: `nui('exitCamera',{})`; `state.activeCam=null`; `exitCamMode()`;
  `markActiveCam()` (re-shows panel, clears highlight).
- `cycleCamera(dir)`: find current index in `state.feeds`, wrap-around `(i+dir+n)%n`,
  call `viewCamera(next.id, next.label)`. The client `viewCamera` callback already
  `exitCamera()`s the old cam before creating the new one, so staying in cam-mode is safe.
- Wiring in `init()`: replace the single `#cam-exit` handler with
  `#cam-exit-ov -> exitCamera`, `#cam-prev -> cycleCamera(-1)`, `#cam-next -> cycleCamera(1)`.
- `hideMdt()` (line ~161): also `exitCamMode()` so a fresh open is never stuck in cam-mode.
- Esc handling (keydown, line ~176): if `app.classList.contains('cam-mode')` then
  `exitCamera()` (back to panel) and return; else `closeMdt()` as today. Keeps focus balanced.

**client/main.lua** - extend the existing `viewCamera`/`exitCamera` (already present):

- In the `viewCamera` NUI callback (lines ~166-183), before/after `CreateCam`, add
  `SetFocusPosAndVel(feed.cam.x, feed.cam.y, feed.cam.z, 0.0, 0.0, 0.0)` so the scene
  streams in even when the officer ped is across the map; then `SetCamActive(cam, true)`
  and (optional CCTV look) `SetTimecycleModifier('scanline_cam_cheap')` +
  `SetTimecycleModifierStrength(1.0)`. Keep `RenderScriptCams(true,false,0,true,true)`.
- In `exitCamera()` (lines ~73-78), after `DestroyCam`, add `ClearFocus()` and
  `ClearTimecycleModifier()`. `onResourceStop` already calls `exitCamera()`, so cleanup
  is covered. `closeMdt()` already calls `exitCamera()` -> focus + view always restored.

Focus balance summary: focus TRUE from `openMdt` through cam-mode and back; only
`closeMdt` sets it FALSE (and restores the cam). No path leaves a stuck cursor.

---

## 2) WARRANTS

**index.html** (lines 330-344):
- Change panel-sub from `Online suspects with outstanding charges.` to
  `Suspects with outstanding charges.` (drop "Online").
- DELETE the `#warrant-refresh` button (lines 336-339) entirely.

**app.js**:
- `showTab()` (line ~198): make warrants AUTO-REFRESH on activate - call `loadWarrants()`
  every time the tab is shown (remove the `!state.loaded.warrants` guard for this tab).
- `loadWarrants()` empty state (line ~704): change sub text from
  `'No online suspects have outstanding charges.'` to `'Suspects with outstanding charges.'`
  (name/wording only; server `getWarrants` is unchanged, still returns name + counts, no id).
- Each warrant row (lines ~708-720): add a `View Record` button in `.list-right`.
  Handler `openWarrantRecord(w.name)`:
  ```js
  function openWarrantRecord(name){
    if(!name) return;
    showTab('person');
    $('#person-name').value = name;   // NAME only - no id anywhere
    searchPerson();
  }
  ```
  Button markup (themed, reuse `.btn.sm` / `.btn-ghost.small`):
  `<button class="btn-ghost small view-rec">View Record</button>` and attach
  `addEventListener('click', () => openWarrantRecord(w.name))` per row.
- `init()` (line ~934): REMOVE `$('#warrant-refresh').addEventListener('click', loadWarrants);`
  (button no longer exists).

---

## 3) OOC CLARITY - wrap command/OOC references in (( ))

Audit result: the only UI strings that name an OOC mechanic/command are in the Arrest
Calculator. Wrap them:

**index.html line 213** (calculator panel-sub), currently:
`Build charges and record them as outstanding. Imprisonment is processed at the DOC via /jail.`
->
`Build charges and record them as outstanding. (( Imprison via /jail at the DOC. ))`

**index.html line 275** (`.action-hint`), currently:
`Records charges as outstanding only &mdash; no jail or fine.`
->
`Records charges as outstanding only - no jail or fine here. (( Imprison via /jail at the DOC. ))`
(also resolves the em-dash entity here, see section 4.)

Borderline (leave as-is): the "Are you on duty as an officer?" empty states in
`renderVehicle`/`renderPerson` use IC duty phrasing and name no command - not wrapped.
No other UI string references a command or OOC mechanic.

---

## 4) DASH SWEEP - zero em (U+2014) / en (U+2013) dashes

Current literal count = **39** (em only; no en dashes). Plus **15** `&mdash;` HTML entities
in index.html (render as em dashes; convert too for visual consistency - the literal-char
gate does not count them but they should go).

Replacement rule: em dash between words -> `" - "` (spaced) or `-`; placeholder em dashes
(`'—'`, `&mdash;`) -> `-`; any number range (none currently) -> `-`. Do NOT touch the
middot separators `·` (U+00B7) in app.js lines 643 / 754 - they are not dashes.

Literal U+2014 occurrences to fix:

- **html/app.js** (21): lines 2, 5, 34, 66, 93, 204, 222, 287, 288, 289, 290, 291, 324,
  325, 367, 368, 372, 393, 564, 574, 694. Lines 66/93/222/287-291/324-325/367-368/372 are
  `'—'` placeholders -> `'-'`. Lines 2/5/34/204/393/564/574/694 are comments/UI text ->
  ` - ` (e.g. line 564 `'No target - search a person first'`).
- **html/index.html** (0 literal, 15 `&mdash;`): lines 145, 146, 198, 199, 200, 201, 202,
  266, 404, 407, 408, 409, 411 (some lines hold two). Replace each `&mdash;` -> `-`.
  Line 266 `No target &mdash; search a person first` -> `No target - search a person first`.
- **html/style.css** (5): lines 2, 30, 71, 77, 551 (all comments) -> ` - `.
- **client/main.lua** (8): lines 2, 134, 156, 159, 165, 185, 191, 201 (all comments) -> ` - `.
- **server/main.lua** (5): lines 2, 42, 96, 131, 613 (all comments) -> ` - `.

Verify after editing (must print 0):
```
python3 -c "import sys;print(sum(open(p,encoding='utf-8').read().count(chr(0x2014))+open(p,encoding='utf-8').read().count(chr(0x2013)) for p in sys.argv[1:]))" html/app.js html/index.html html/style.css client/main.lua server/main.lua
```
Recommended extra (entities): `grep -c '&mdash;\|&ndash;' html/index.html` should be 0.

---

## 5) VERIFY / CONSTRAINTS CHECKLIST

- Lua: `luac5.4 -p client/main.lua && luac5.4 -p server/main.lua` (parse-only, clean).
- JS: `node --check html/app.js` (clean).
- Callbacks unchanged: searchPerson, getWarrants, getCameras, viewCamera, exitCamera, etc.
  (server `getCameras` still returns `{id,label}` only; coords stay server/client-side).
- NO citizenid anywhere in the UI; warrant "View Record" passes NAME only.
- Theme preserved: glass surfaces, accent #E1C7F9, stroke `.ic` icons, no backdrop-filter.
- NUI focus balanced: TRUE on open -> stays TRUE in cam-mode -> FALSE only on closeMdt;
  exitCamera/onResourceStop restore the player view; no stuck cursor.
