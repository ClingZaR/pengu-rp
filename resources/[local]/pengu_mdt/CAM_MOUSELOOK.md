# pengu_mdt - CAM_MOUSELOOK change plan

Rework the Cameras feed view from a free-cursor + clickable-overlay + `camControl`
NUI round-trip scheme into a MOUSE-DRIVEN, NO-CURSOR scripted cam. All look /
zoom / feed-switch / vision / exit input is read on the CLIENT every frame; the
NUI page keeps rendering an INFO-ONLY overlay (it has no focus, so it can no
longer be clicked or receive key/wheel events).

Theme stays glass / lavender. No citizenid anywhere. ASCII only (no em/en
dashes). LEO + onduty gate is untouched. Must stay `luac5.4 -p` clean and
`node --check` clean.

--------------------------------------------------------------------
## 1. HOW THE CAM WORKS TODAY (exact map)

### client/main.lua
- `CAMERAS` (lines 57-106): array of `{ id, label, cam=vec3, point=vec3 }`.
  `findFeed(id)` (108-114) looks one up by id.
- `activeCam` (116): scripted cam handle or nil. `camState` (118):
  `{ heading, pitch, fov, nightvision, thermal }` while a feed is up.
- `clamp(v,lo,hi)` (121-125).
- `exitCamera()` (128-138): teardown - `RenderScriptCams(false,...)`, `DestroyCam`,
  nil `activeCam`/`camState`, `SetNightvision(false)`, `SetSeethrough(false)`,
  `ClearFocus()`, `ClearTimecycleModifier()`. Early-returns if no `activeCam`.
- `isLeo()` (145-148): `job.type == 'leo' and job.onduty == true`. GATE - keep.
- `openMdt()` (154-168): `SetNuiFocus(true,true)` + `SendNUIMessage{action='open'}`.
- `closeMdt()` (170-177): `SetNuiFocus(false,false)` + `exitCamera()` +
  `SendNUIMessage{action='close'}`.
- NUI callback `viewCamera {id}` (227-261): `exitCamera()` to swap, `SetFocusPosAndVel`
  on the feed coords, derive `heading`/`pitch` from the cam->point vector,
  `CreateCam('DEFAULT_SCRIPTED_CAMERA', true)`, `SetCamCoord`,
  `SetCamRot(cam, pitch, 0.0, heading, 2)`, `SetCamFov(cam, 60.0)`, `SetCamActive`,
  `SetTimecycleModifier('scanline_cam_cheap')` (strength 1.0),
  `RenderScriptCams(true,...)`, store `activeCam`/`camState`. Returns `{ok,id}`.
- NUI callback `exitCamera {}` (264-267): calls `exitCamera()`.
- NUI callback `camControl {dyaw,dpitch,dzoom,nightvision?,thermal?}` (273-316):
  the CURRENT control path. `s.heading = (s.heading - dyaw) % 360` (note the
  recent inversion fix at ~line 285 - it SUBTRACTS dyaw so NUI "right" pans
  right), `s.pitch` clamp -89..89, `s.fov` clamp 20..70, then
  `SetCamRot`/`SetCamFov`, plus mutually exclusive NV / thermal.
- `onResourceStop` (383-391): `exitCamera()` + booking teardown + release focus.

FOCUS TODAY: `SetNuiFocus(true,true)` is set on open and never dropped while a
feed is up. So the OS cursor stays visible in cam-mode and the overlay buttons
are clickable; the JS pushes `camControl` deltas over NUI fetch. The moment the
cursor is hidden this entire scheme dies (no clicks, no key/wheel events to JS).

### html/app.js
- `state.activeCam = {id,label}`, `state.feeds = [{id,label}]` (35-36).
- `message` listener (173-177): `open`->openMdt, `close`->hideMdt.
- `Escape`/F11 keydown (179-195) and outside-panel `mousedown` (198-202): in
  cam-mode call `exitCamera()`, else `closeMdt()`. (These need NUI focus to fire,
  so they are unreachable once the cursor is hidden.)
- `loadCameras()` (914-940): builds `.cam-tile`s; each tile
  `click -> viewCamera(f.id, label)`.
- Control machinery (942-1015): `CAM_STEP {yaw,pitch,zoom}`, `camKeys` Set,
  `camTimer`, `camNV/camTH`, `camAxisFromKeys`, `camTick` (fires `camControl`),
  `startCamLoop`/`stopCamLoop`, `camZoom`, `camToggleNV`, `camToggleTH`,
  `enterCamMode`/`exitCamMode` (toggle `cam-mode` class, show/hide overlay+hint,
  reset NV/TH).
- `markActiveCam()` (1018-1027): highlights the active tile and sets
  `#cam-ov-name` + `#cam-ov-index` (`i+1 / n`) from `state.feeds` by id.
- `viewCamera(id,label)` (1029-1038): `nui('viewCamera')`; on ok set
  `state.activeCam`, `enterCamMode()`, `markActiveCam()`.
- `exitCamera()` (1040-1045): `nui('exitCamera')` + `exitCamMode()`.
- `cycleCamera(dir)` (1049-1058): wrap index, `viewCamera(next)`.
- Cam-mode `keydown`/`keyup`/`wheel` (1084-1102): WASD/arrows -> `camKeys`,
  `+/-` -> `camZoom`, `n` -> NV, `t` -> thermal, wheel -> zoom.
- init wiring (1199-1215): `#cam-exit-ov`->exitCamera, `#cam-prev`/`#cam-next`->
  cycleCamera, `.cam-ctl` press-hold, zoom buttons, `#cam-nv`/`#cam-th`.

### html/index.html cam overlay (443-468)
`#cam-overlay.cam-overlay.glass.hidden` contains:
- `.cam-ov-left`: rec-dot, `LIVE`, `#cam-ov-name`.
- `.cam-ov-controls`: `.cam-dpad` (4 `.cam-ctl` arrow buttons), zoomin/zoomout
  `.btn.sm`, `#cam-nv`, `#cam-th`.
- `.cam-ov-right`: `#cam-prev`, `#cam-ov-index`, `#cam-next`, `#cam-exit-ov`.
Plus a separate bottom `#cam-ov-hint` line (468). Cameras tab sub-hint at 432.

### html/style.css cam (593-632)
`#app.cam-mode{background:transparent}`, `#app.cam-mode .mdt-panel{display:none}`,
`.cam-overlay` (fixed bottom-center flex bar), `.cam-ov-left/live/name/right/index`,
`.cam-ov-controls`, `.cam-dpad`, `.cam-dpad .cam-ctl[...]`, `.cam-ctl`,
`.btn.sm.active, #cam-nv.active, #cam-th.active`, `.cam-ov-hint`.

--------------------------------------------------------------------
## 2. NEW FOCUS MODEL

- Cameras tab open, panel up: `SetNuiFocus(true,true)` (unchanged from openMdt) -
  cursor present, tiles clickable.
- Click a feed tile -> `viewCamera` NUI callback builds the scripted cam, then
  IMMEDIATELY calls `SetNuiFocus(false, false)`. Cursor disappears, game input
  flows to the control thread. The NUI page still RENDERS the overlay (focus does
  not affect rendering, only input routing + cursor).
- Exit feed back to the panel (Backspace in cam-mode): client tears the cam down
  and calls `SetNuiFocus(true, true)` again so the cursor + panel return, then
  tells the NUI to re-show the panel.
- Full MDT close (F11 keymapping now fires in cam-mode because game has input,
  or via the panel): `closeMdt()` -> `exitCamera()` + `SetNuiFocus(false,false)` +
  `SendNUIMessage{action='close'}`. Player returns to normal gameplay.

Custom keymapping commands (the F11 `+mdt` bind, pma-voice push-to-talk) are NOT
affected by `DisableAllControlActions(0)`, so the MDT toggle and voice keep
working while a feed is up. Only built-in controls are blocked.

--------------------------------------------------------------------
## 3. CLIENT CONTROL THREAD (the new control path)

Add a single per-frame thread, guarded by `activeCam` plus a generation token so
a re-open never leaves two drivers running. Reference implementation:

```lua
-- look / zoom feel
local SENS_X    = 7.0    -- deg per unit of LookLeftRight
local SENS_Y    = 7.0    -- deg per unit of LookUpDown
local ZOOM_STEP = 4.0    -- FOV change per wheel notch frame
local FOV_MIN, FOV_MAX     = 20.0, 70.0
local PITCH_MIN, PITCH_MAX = -80.0, 80.0   -- clamp so it cannot flip over

local camToken = 0       -- bumped on every feed open; thread captures its own

-- cycle vision: off -> night -> thermal -> off (Space). Mutually exclusive.
local function cycleVision()
    if not camState then return end
    if camState.nightvision then
        camState.nightvision = false; camState.thermal = true
        SetNightvision(false); SetSeethrough(true)
        SendNUIMessage({ action = 'camVision', vision = 'thermal' })
    elseif camState.thermal then
        camState.thermal = false
        SetSeethrough(false); SetNightvision(false)
        SendNUIMessage({ action = 'camVision', vision = 'off' })
    else
        camState.nightvision = true
        SetNightvision(true); SetSeethrough(false)
        SendNUIMessage({ action = 'camVision', vision = 'night' })
    end
end

local function startCamLookThread()
    camToken = camToken + 1
    local myToken = camToken
    CreateThread(function()
        while activeCam and camState and camToken == myToken do
            Wait(0)
            DisableAllControlActions(0)  -- ped does not walk / shoot / etc.

            -- MOUSE LOOK. LookLeftRight (0,1) is +right; GTA Z-heading increases
            -- counter-clockwise, so SUBTRACT to pan right (right == right, NOT
            -- inverted - same direction the old camControl fix used).
            local dx = GetDisabledControlNormal(0, 1)   -- LookLeftRight
            local dy = GetDisabledControlNormal(0, 2)    -- LookUpDown (+down)
            if dx ~= 0.0 then
                camState.heading = (camState.heading - dx * SENS_X) % 360.0
            end
            if dy ~= 0.0 then
                -- mouse up -> look up. dy is +down, so SUBTRACT for natural feel.
                camState.pitch = clamp(camState.pitch - dy * SENS_Y, PITCH_MIN, PITCH_MAX)
            end
            if dx ~= 0.0 or dy ~= 0.0 then
                SetCamRot(activeCam, camState.pitch, 0.0, camState.heading, 2)
            end

            -- ZOOM (mouse wheel). 241/242 are cursor scroll; 14/15 weapon-wheel
            -- next/prev are the reliable wheel reads while the cursor is hidden.
            if IsDisabledControlPressed(0, 241) or IsDisabledControlPressed(0, 15) then
                camState.fov = clamp(camState.fov - ZOOM_STEP, FOV_MIN, FOV_MAX)
                SetCamFov(activeCam, camState.fov)
            elseif IsDisabledControlPressed(0, 242) or IsDisabledControlPressed(0, 14) then
                camState.fov = clamp(camState.fov + ZOOM_STEP, FOV_MIN, FOV_MAX)
                SetCamFov(activeCam, camState.fov)
            end

            -- FEED SWITCH. 174 left arrow / 175 right arrow (A 34 / D 35 too).
            if IsDisabledControlJustPressed(0, 174) or IsDisabledControlJustPressed(0, 34) then
                switchFeed(-1)
            elseif IsDisabledControlJustPressed(0, 175) or IsDisabledControlJustPressed(0, 35) then
                switchFeed(1)
            end

            -- VISION TOGGLE. 22 = INPUT_JUMP (Space): clearly free, no clash with
            -- N (push-to-talk). First press = night vision; cycles to thermal/off.
            if IsDisabledControlJustPressed(0, 22) then
                cycleVision()
            end

            -- EXIT back to the panel. 177 = Backspace.
            if IsDisabledControlJustPressed(0, 177) then
                leaveCamToPanel()
            end
        end
    end)
end
```

CONTROL ID REFERENCE (group 0):
- 1  LookLeftRight   (yaw, +right)
- 2  LookUpDown      (pitch, +down)
- 14 WeaponWheelNext (wheel down -> zoom out) / 15 WeaponWheelPrev (wheel up -> in)
- 241 CursorScrollUp / 242 CursorScrollDown (wheel, cursor context)
- 174 arrow Left / 175 arrow Right (34 A / 35 D as secondary) -> prev / next feed
- 22 Jump (Space) -> vision cycle
- 177 Backspace -> exit to panel

--------------------------------------------------------------------
## 4. CLIENT REFACTOR (client/main.lua)

Factor the cam build out of the NUI callback so feed-switch reuses it WITHOUT a
NUI hop and WITHOUT tearing the cam down (reuse the handle, just move it).

```lua
local currentIdx = nil   -- index into CAMERAS of the live feed

-- Compute heading/pitch that frames cam->point for CAMERAS[idx].
local function feedAim(feed)
    local dx = feed.point.x - feed.cam.x
    local dy = feed.point.y - feed.cam.y
    local dz = feed.point.z - feed.cam.z
    local dist2d = math.sqrt(dx * dx + dy * dy)
    return GetHeadingFromVector_2d(dx, dy), math.deg(math.atan(dz, dist2d))
end

-- Move the live cam to CAMERAS[idx] (reuses activeCam; resets aim/fov/vision).
local function applyFeed(idx)
    local feed = CAMERAS[idx]
    if not feed or not activeCam then return end
    currentIdx = idx
    SetFocusPosAndVel(feed.cam.x, feed.cam.y, feed.cam.z, 0.0, 0.0, 0.0)
    local heading, pitch = feedAim(feed)
    SetCamCoord(activeCam, feed.cam.x, feed.cam.y, feed.cam.z)
    SetCamRot(activeCam, pitch, 0.0, heading, 2)
    SetCamFov(activeCam, 60.0)
    camState.heading = heading
    camState.pitch   = pitch
    camState.fov     = 60.0
    camState.nightvision = false
    camState.thermal     = false
    SetNightvision(false)
    SetSeethrough(false)
    -- Tell the overlay the new feed (name + index look-up by id, vision reset).
    SendNUIMessage({ action = 'camFeed', id = feed.id, label = feed.label, vision = 'off' })
end

function switchFeed(dir)             -- called by the control thread (arrows/AD)
    if currentIdx == nil then return end
    local n = #CAMERAS
    applyFeed(((currentIdx - 1 + dir) % n) + 1)
end

function leaveCamToPanel()           -- Backspace: back to the MDT panel
    exitCamera()                     -- destroy cam + clear nv/seethrough/focus/timecycle
    SetNuiFocus(true, true)          -- restore cursor + panel interaction
    SendNUIMessage({ action = 'camExit' })
end
```

`viewCamera {id}` NUI callback (tile click, cursor present) becomes:
- `findFeed(id)`; if missing return `{ok=false}`.
- `exitCamera()` (clean swap if somehow already up).
- `CreateCam('DEFAULT_SCRIPTED_CAMERA', true)`, `SetCamActive(cam,true)`,
  `SetTimecycleModifier('scanline_cam_cheap')` (strength 1.0),
  `RenderScriptCams(true,...)`, set `activeCam` and a fresh
  `camState = { heading=0, pitch=0, fov=60, nightvision=false, thermal=false }`.
- Find the feed index in CAMERAS, call `applyFeed(idx)` (positions the cam +
  sends the first `camFeed`).
- `SetNuiFocus(false, false)`  -- hide cursor, hand input to the control thread.
- `startCamLookThread()`.
- `cb({ ok = true, id = feed.id })`. (JS uses ok to hide the panel.)

REMOVE the `camControl` NUI callback entirely (lines 273-316) - all look / zoom /
vision input now comes from the control thread. Keep the `exitCamera {}` NUI
callback as a harmless teardown fallback (no longer the cam-mode exit path).

`closeMdt()` and `onResourceStop` already call `exitCamera()` - leave them.
`exitCamera()` keeps clearing nv / seethrough / focus / timecycle. The control
thread self-terminates the next frame because `activeCam` is nil.

--------------------------------------------------------------------
## 5. NUI REFACTOR (html/app.js)

DELETE the JS control machinery (it can never run without focus):
- `CAM_STEP`, `camKeys`, `camTimer`, `camNV`, `camTH`.
- `camAxisFromKeys`, `camTick`, `startCamLoop`, `stopCamLoop`, `camZoom`,
  `camToggleNV`, `camToggleTH`.
- The cam-mode `keydown`/`keyup`/`wheel` listeners (1084-1102).
- `cycleCamera` and the JS `exitCamera()` function.
- init wiring for `#cam-exit-ov`, `#cam-prev`, `#cam-next`, `.cam-ctl`,
  `[data-ctl=zoomin/zoomout]`, `#cam-nv`, `#cam-th` (1199-1215).

SIMPLIFY enter/exitCamMode to overlay-only (no control state):
```js
function enterCamMode() {
  app.classList.add('cam-mode');
  $('#cam-overlay').classList.remove('hidden');
  setCamVision('off');
}
function exitCamMode() {
  app.classList.remove('cam-mode');
  $('#cam-overlay').classList.add('hidden');
}
function setCamVision(mode) {                 // 'off' | 'night' | 'thermal'
  const el = $('#cam-ov-vision');
  if (!el) return;
  el.classList.toggle('hidden', mode === 'off');
  el.textContent = mode === 'thermal' ? 'THERMAL' : 'NIGHT VISION';
}
```

`viewCamera(id,label)` stays as the TILE entry only (cursor still present):
```js
async function viewCamera(id, label) {
  const res = await nui('viewCamera', { id });
  if (res && res.ok) { state.activeCam = { id, label }; enterCamMode(); markActiveCam(); }
  else { toast('Could not open that feed.', 'err'); }
}
```
(The client also sends `camFeed` right after building the cam; that path keeps
`markActiveCam` authoritative for feed name + index.)

EXTEND the `message` listener to drive cam-mode from the client:
```js
window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') openMdt();
  else if (d.action === 'close') hideMdt();
  else if (d.action === 'camFeed') {            // initial open OR arrow switch
    state.activeCam = { id: d.id, label: d.label };
    markActiveCam();
    setCamVision(d.vision || 'off');
  }
  else if (d.action === 'camVision') setCamVision(d.vision || 'off');
  else if (d.action === 'camExit') {            // client tore the cam down
    state.activeCam = null;
    exitCamMode();
    markActiveCam();
  }
});
```

`markActiveCam()` is unchanged: it still derives `#cam-ov-name` and
`#cam-ov-index` (`i+1 / n`) from `state.feeds` by id, so the index stays correct
through client-side switching as long as the client `CAMERAS` order matches the
server `getCameras` order (already a documented invariant).

The `Escape`/F11 keydown and outside-panel `mousedown` handlers only fire when
the panel has focus (panel up), so trim their cam-mode branches to just
`closeMdt()` - exit is owned by the client Backspace now.

--------------------------------------------------------------------
## 6. OVERLAY AS INFO ONLY (html/index.html)

Replace the whole `#cam-overlay` body and the trailing `#cam-ov-hint` (443-468)
with an info-only glass card - LIVE dot, feed name, index, a vision badge, and a
single static control-hints line. No buttons.

```html
<div id="cam-overlay" class="cam-overlay glass hidden" role="group" aria-label="Camera feed">
  <div class="cam-ov-row">
    <span class="rec-dot live"></span>
    <span class="cam-ov-live">LIVE</span>
    <span class="cam-ov-name" id="cam-ov-name">-</span>
    <span class="cam-ov-index tnum" id="cam-ov-index">1 / 1</span>
    <span class="cam-ov-vision hidden" id="cam-ov-vision">NIGHT VISION</span>
  </div>
  <div class="cam-ov-hint" id="cam-ov-hint">Mouse: look | Scroll: zoom | Arrows: feed | Space: night vision | Backspace: exit</div>
</div>
```

Update the Cameras tab sub-hint (line 432) to match the new flow, ASCII only:
`Select a feed to open the live view. Mouse looks around; Backspace returns.`

--------------------------------------------------------------------
## 7. STYLE (html/style.css)

Keep: `#app.cam-mode{background:transparent}`, `#app.cam-mode .mdt-panel{display:none}`,
`.cam-overlay` (glass card), `.cam-ov-live`, `.cam-ov-name`, `.cam-ov-index`,
`.cam-ov-hint`. Stack the card as two rows now:
```css
.cam-overlay{ flex-direction:column; align-items:center; gap:6px; }
.cam-ov-row{ display:flex; align-items:center; gap:10px; }
.cam-ov-hint{ position:static; transform:none; }   /* now inside the card */
.cam-ov-vision{
  font-size:11px; font-weight:800; letter-spacing:1px;
  color:var(--accent); background:var(--accent-tint);
  border:1px solid var(--accent); border-radius:6px; padding:2px 7px;
}
```
DELETE the now-dead button rules: `.cam-ov-controls`, `.cam-dpad`,
`.cam-dpad .cam-ctl[...]`, `.cam-ctl`, `.cam-ctl:hover`,
`.btn.sm.active, #cam-nv.active, #cam-th.active`, `.cam-ov-right`. (`.btn.sm`
base style stays; only the removed combined `.active` rule referencing
`#cam-nv`/`#cam-th` goes.) Lavender vars (`--accent`, `--accent-tint`) keep the
theme intact.

--------------------------------------------------------------------
## 8. CLIENT <-> NUI MESSAGE CONTRACT (final)

NUI -> client (RegisterNUICallback / fetch):
- `viewCamera {id}`  -> build cam, `applyFeed`, `SetNuiFocus(false,false)`,
  start control thread, send `camFeed`; returns `{ok,id}`. (tile click only)
- `exitCamera {}`    -> `exitCamera()` teardown fallback (kept, not the hot path).
- `closeMdt {}`      -> `closeMdt()` (unchanged).
- All data relays    -> unchanged.
- REMOVED: `camControl`.

client -> NUI (SendNUIMessage):
- `{action='open'}` / `{action='close'}`  -> unchanged.
- `{action='camFeed', id, label, vision}`  -> NEW. Feed opened or switched; NUI
  sets `state.activeCam`, `markActiveCam()`, `setCamVision(vision)`.
- `{action='camVision', vision}`           -> NEW. Vision cycled; update badge.
- `{action='camExit'}`                     -> NEW. Client tore the cam down +
  restored focus; NUI clears `state.activeCam`, `exitCamMode()`, `markActiveCam()`.

--------------------------------------------------------------------
## 9. TEARDOWN / SAFETY CHECKLIST (never strand the player)

`exitCamera()` (DestroyCam + RenderScriptCams(false) + ClearFocus +
ClearTimecycleModifier + SetNightvision(false) + SetSeethrough(false)) must run,
and focus / cursor must end correct, on EVERY path:
- Backspace in cam-mode -> `leaveCamToPanel()` -> `exitCamera()` +
  `SetNuiFocus(true,true)` + `camExit`. Control thread stops (activeCam nil).
- F11 keymapping in cam-mode (game input live) -> `closeMdt()` -> `exitCamera()` +
  `SetNuiFocus(false,false)` + `close`. Thread stops.
- `closeMdt()` from the panel -> same as above.
- `onResourceStop` -> `exitCamera()` + booking teardown + release focus.
The control thread's `while activeCam and camState and camToken == myToken`
guard guarantees `DisableAllControlActions` stops the frame after teardown, so
the player is never frozen, cursorless, or stuck in night vision.

--------------------------------------------------------------------
## 10. VALIDATION (must pass before done)
- `luac5.4 -p client/main.lua`  -> clean.
- `node --check html/app.js`    -> clean.
- ASCII only across all three files (no em/en dashes); grep for the bytes if
  unsure. No citizenid introduced. LEO + onduty gate unchanged.
