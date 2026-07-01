# pengu_mdt - BOLO multi-image + Camera CCTV upgrade (PLAN)

Plan for two feature upgrades on top of REDESIGN2. No code is changed by this
document; it is the build spec an implementer follows.

Files in play:
- server/main.lua  (DB schema/migration, createBolo/getBolos, CAMERAS config)
- client/main.lua  (CAMERAS mirror, scripted cam, new camControl callback)
- html/index.html  (BOLO create form, lightbox node, cam overlay controls)
- html/app.js      (BOLO gallery/lightbox/arrows, cam input loop)
- html/style.css   (gallery, lightbox, cam controls)

## Global constraints (carry through every edit)
- Keep the glass / lavender theme. Reuse existing vars (--accent, --glass-bg,
  --danger, --green). Reuse stroke icons from the ICON map (.ic style).
- NO citizenid anywhere in the UI or in any payload. BOLOs never reference cid;
  nothing in this change adds it.
- ASCII only. No em dash, no en dash, no ellipsis char in NEW strings. Use "-"
  and "->" and "..." spelled with three ASCII dots only where unavoidable.
- Server callbacks stay dual-registered (pengu_mdt:<name> AND
  pengu_mdt:server:<name>). This change reuses the EXISTING createBolo/getBolos
  handlers (already dual-registered) and adds NO new server callback. camControl
  is client-only (RegisterNUICallback), so no registration pair is needed.
- Validation gate before done:  luac -p client/main.lua server/main.lua  and
  node --check html/app.js  must both be clean.
- NUI focus stays balanced: cam-mode keeps SetNuiFocus(true,true) (set once on
  open, never toggled mid-session). The lightbox is pure HTML, no focus change.
  Exit paths (closeMdt, exitCamera, onResourceStop) must fully restore the view.

================================================================================
# PART A - BOLOs with MULTIPLE images + lightbox + BOLO arrows
================================================================================

## A1. Database: image_url (single) -> image_urls (JSON array), back-compat

Store a JSON-encoded array of links in a new TEXT column `image_urls`. Keep the
legacy `image_url VARCHAR(512)` column so old rows and old clients are not broken
(we also keep writing the first link into it).

CREATE_BOLOS_SQL (add one line):
```
CREATE TABLE IF NOT EXISTS pengu_mdt_bolos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  type VARCHAR(16) DEFAULT 'person',
  title VARCHAR(128) NOT NULL,
  description TEXT,
  image_url VARCHAR(512) DEFAULT '',     -- legacy single link (kept for back-compat)
  image_urls TEXT,                       -- JSON array of links, e.g. ["https://a","https://b"]
  officer VARCHAR(128),
  status VARCHAR(16) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
```

Migration block, inside the existing start-up CreateThread (after the CREATE
statements, alongside the other ensureColumn calls):
```
ensureColumn('pengu_mdt_bolos', 'image_urls', 'TEXT')

-- One-time backfill: wrap any legacy single image_url into the JSON array.
-- JSON_ARRAY() emits valid JSON even if the URL contains quotes/backslashes,
-- so this is safe. Runs only on rows not yet migrated.
MySQL.query.await([[
  UPDATE pengu_mdt_bolos
  SET image_urls = JSON_ARRAY(image_url)
  WHERE (image_urls IS NULL OR image_urls = '')
    AND image_url IS NOT NULL AND image_url <> ''
]])
```
Notes: ensureColumn already exists and is idempotent. JSON_ARRAY exists on
MySQL 5.7+ / MariaDB 10.2+ (the stack already uses JSON_VALUE, so this is fine).
FiveM exposes the global `json` library, so server Lua can json.encode/decode.

## A2. Server: createBolo accepts an array; getBolos returns an array

BOLOS_SELECT_SQL - add image_urls to the projection:
```
SELECT id, type, title, description, image_url, image_urls, officer,
  DATE_FORMAT(created_at,'%Y-%m-%d %H:%i') AS created_at
FROM pengu_mdt_bolos
WHERE status = 'active'
ORDER BY created_at DESC
LIMIT 50
```

BOLOS_INSERT_SQL - add the column + placeholder:
```
INSERT INTO pengu_mdt_bolos (type, title, description, image_url, image_urls, officer, status)
VALUES (?, ?, ?, ?, ?, ?, 'active')
```

handleGetBolos - decode the JSON array, validate each link, fall back to the
legacy single link, and expose ONLY a clean `images` array to the NUI:
```
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
        r.images = list        -- the ONLY image field the NUI reads
        r.image_url = nil       -- do not leak raw columns to the UI
        r.image_urls = nil
    end
    return { items = rows }
end
```

handleCreateBolo - accept `data.images` (array) with a single-link fallback;
validate each link (^https?://), trim, cap length 512 and count 8:
```
-- replace the old single-imageUrl block with:
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
    images[1] = data.image_url      -- legacy single-link callers still work
end

local imagesJson = json.encode(images)      -- "[]" when none
local firstUrl   = images[1] or ''           -- keep legacy column populated

MySQL.insert.await(BOLOS_INSERT_SQL,
    { btype, title, description, firstUrl, imagesJson, officerName(officer) })
return { success = true, message = 'BOLO created' }
```

Client (client/main.lua): NO change. createBolo and getBolos are already in
RELAY_CALLBACKS and forward the NUI payload verbatim, so the new `images` array
passes through untouched.

## A3. Create-form: repeatable "add link" rows (multi-link UX)

index.html - replace the single image input
(`<label>Image link (optional) ... #bolo-image</label>`) with a repeatable rows
block:
```
<label>Image links (optional)
  <div id="bolo-images" class="link-rows"></div>
  <button type="button" id="bolo-add-link" class="btn-ghost small link-add">
    <svg class="ic" viewBox="0 0 24 24" width="14" height="14"><path d="M12 5v14M5 12h14"/></svg>
    Add link
  </button>
</label>
```
Each row is built in JS as:
```
<div class="link-row">
  <input type="text" class="bolo-link" placeholder="https://... image URL"
         autocomplete="off" spellcheck="false" />
  <button type="button" class="btn-remove link-del" title="Remove link">&times;</button>
</div>
```

app.js helpers:
```
function addBoloLinkRow(value) {
  const wrap = $('#bolo-images');
  const row = document.createElement('div');
  row.className = 'link-row';
  row.innerHTML =
    '<input type="text" class="bolo-link" placeholder="https://... image URL" autocomplete="off" spellcheck="false" />' +
    '<button type="button" class="btn-remove link-del" title="Remove link">&times;</button>';
  if (value) row.querySelector('.bolo-link').value = value;
  row.querySelector('.link-del').addEventListener('click', () => {
    row.remove();
    if (!$$('#bolo-images .link-row').length) addBoloLinkRow();  // never empty
  });
  wrap.appendChild(row);
}
function resetBoloLinks() { $('#bolo-images').innerHTML = ''; addBoloLinkRow(); }
function boloLinkValues() {
  return $$('#bolo-images .bolo-link')
    .map((i) => i.value.trim())
    .filter((v) => /^https?:\/\//.test(v));     // client pre-filter; server re-validates
}
```

createBolo() change: send the array, reset rows on success:
```
const images = boloLinkValues();
...
const res = await nui('createBolo', { type, title, description, images });
...
if (res && res.success) {
  ...
  resetBoloLinks();
  toggleForm('#bolo-form', false);
  loadBolos();
}
```

Wiring in init(): `$('#bolo-add-link').addEventListener('click', () => addBoloLinkRow());`
and call `resetBoloLinks()` once on init so the form starts with one empty row.

(Alternative the implementer may pick instead: a single textarea, one URL per
line, split on \n in boloLinkValues(). The repeatable-rows UX above is the
chosen primary because it gives per-link remove buttons.)

## A4. BOLO card: thumbnail gallery (reserved 16:9, lazy, onerror placeholder)

Rewrite the media section of loadBolos() per card. Instead of one `.bolo-media`,
render a `.bolo-gallery` of small 16:9 thumb boxes from `b.images`:
```
const imgs = Array.isArray(b.images) ? b.images.filter((u) => /^https?:\/\//.test(u)) : [];
let media = '';
if (imgs.length) {
  const thumbs = imgs.map((u, i) =>
    `<button class="bolo-thumb" data-i="${i}" title="View image">` +
      `<img loading="lazy" src="${escapeHtml(u)}" alt="BOLO image ${i + 1}" />` +
      `<span class="thumb-ph hidden"><svg class="ic" viewBox="0 0 24 24" width="22" height="22">${ICON.image}</svg></span>` +
    `</button>`).join('');
  media = `<div class="bolo-gallery">${thumbs}</div>`;
}
```
After the card is in the DOM, wire each thumb: onerror swaps img -> .thumb-ph;
click opens the lightbox for THIS bolo at that index:
```
card.querySelectorAll('.bolo-thumb').forEach((btn) => {
  const im = btn.querySelector('img');
  const ph = btn.querySelector('.thumb-ph');
  im.addEventListener('error', () => { im.classList.add('hidden'); ph.classList.remove('hidden'); });
  btn.addEventListener('click', () => openLightbox(imgs, Number(btn.dataset.i)));
});
```
Keep the rest of the card (chip/title/desc/foot/Cancel) unchanged. Replace the
non-ASCII middot in `.bolo-foot` with an ASCII separator while here:
`${escapeHtml(b.officer || 'Unknown')} - ${escapeHtml(fmtDate(b.created_at))}`.

## A5. Fullscreen lightbox (object-fit:contain, dark scrim, prev/next/close)

index.html - add one node just before `<div id="toast">` (sibling of the panel,
inside #app so it inherits the overlay stacking):
```
<div id="lightbox" class="lightbox hidden" role="dialog" aria-modal="true" aria-label="BOLO image">
  <button id="lb-close" class="lb-close" title="Close (Esc)" aria-label="Close">
    <svg class="ic" viewBox="0 0 24 24" width="22" height="22"><path d="M6 6l12 12M18 6L6 18"/></svg>
  </button>
  <button id="lb-prev" class="lb-nav lb-prev" title="Previous (Left)" aria-label="Previous">
    <svg class="ic" viewBox="0 0 24 24" width="30" height="30"><path d="M15 6l-6 6 6 6"/></svg>
  </button>
  <img id="lb-img" class="lb-img" alt="BOLO image" />
  <button id="lb-next" class="lb-nav lb-next" title="Next (Right)" aria-label="Next">
    <svg class="ic" viewBox="0 0 24 24" width="30" height="30"><path d="M9 6l6 6-6 6"/></svg>
  </button>
  <div id="lb-index" class="lb-index tnum">1 / 1</div>
</div>
```

style.css - the lightbox sits above everything, dark scrim, image contained:
```
.lightbox{
  position:fixed; inset:0; z-index:90;
  display:flex; align-items:center; justify-content:center;
  background:rgba(0,0,0,0.88);
}
.lb-img{ max-width:92vw; max-height:88vh; object-fit:contain; display:block;
  border-radius:10px; box-shadow:var(--glass-shadow); }
.lb-nav{ position:absolute; top:50%; transform:translateY(-50%);
  width:46px; height:46px; border-radius:50%; display:grid; place-items:center;
  cursor:pointer; color:#fff; background:rgba(16,16,24,0.7);
  border:1px solid var(--glass-border); transition:.15s; }
.lb-nav:hover{ border-color:var(--accent); color:var(--accent); }
.lb-prev{ left:24px; } .lb-next{ right:24px; }
.lb-close{ position:absolute; top:20px; right:24px; width:40px; height:40px;
  border-radius:10px; display:grid; place-items:center; cursor:pointer;
  color:var(--text-2); background:rgba(16,16,24,0.7); border:1px solid var(--glass-border); }
.lb-close:hover{ color:var(--danger); border-color:var(--danger); }
.lb-index{ position:absolute; bottom:22px; left:50%; transform:translateX(-50%);
  font-family:var(--mono); font-size:13px; color:var(--text-2);
  background:rgba(16,16,24,0.7); border:1px solid var(--glass-border);
  padding:5px 12px; border-radius:20px; }
```

app.js - lightbox module:
```
state.lightbox = { images: [], index: 0 };

function isLightboxOpen(){ return !$('#lightbox').classList.contains('hidden'); }

function renderLightbox(){
  const lb = state.lightbox, n = lb.images.length;
  if (!n) { closeLightbox(); return; }
  if (lb.index < 0) lb.index = n - 1;
  if (lb.index >= n) lb.index = 0;
  const img = $('#lb-img');
  img.onerror = () => { img.removeAttribute('src'); };  // contain box stays, blank on bad URL
  img.src = lb.images[lb.index];
  $('#lb-index').textContent = (lb.index + 1) + ' / ' + n;
  // hide prev/next when a single image
  $('#lb-prev').classList.toggle('hidden', n < 2);
  $('#lb-next').classList.toggle('hidden', n < 2);
}
function openLightbox(images, index){
  state.lightbox.images = (images || []).slice();
  state.lightbox.index = Number(index) || 0;
  $('#lightbox').classList.remove('hidden');
  renderLightbox();
}
function closeLightbox(){ $('#lightbox').classList.add('hidden'); }
function lightboxStep(dir){ state.lightbox.index += dir; renderLightbox(); }
```
Wiring in init():
```
$('#lb-close').addEventListener('click', closeLightbox);
$('#lb-prev').addEventListener('click', () => lightboxStep(-1));
$('#lb-next').addEventListener('click', () => lightboxStep(1));
$('#lightbox').addEventListener('mousedown', (e) => { if (e.target.id === 'lightbox') closeLightbox(); });
```
Esc handling: the EXISTING Escape handler must check the lightbox FIRST so Esc
closes the image, not the MDT. Add at the very top of that handler:
```
if (isLightboxOpen()) { e.preventDefault(); closeLightbox(); return; }
```
Left/Right inside the lightbox are wired in the shared nav handler in A6.

## A6. BOLO arrows - step through BOLOs one at a time

Keep the grid. Add a small stepper in the BOLOs panel head (left/right arrow
buttons + "n / total"), and ArrowLeft/ArrowRight keys cycle the focused card.

index.html - add to the BOLOs `.head-actions` (before the refresh button):
```
<div class="bolo-stepper">
  <button id="bolo-prev" class="btn icon-only sm" title="Previous BOLO (Left)" aria-label="Previous BOLO">
    <svg class="ic" viewBox="0 0 24 24" width="16" height="16"><path d="M15 6l-6 6 6 6"/></svg>
  </button>
  <span id="bolo-step-index" class="cam-ov-index tnum">0 / 0</span>
  <button id="bolo-next" class="btn icon-only sm" title="Next BOLO (Right)" aria-label="Next BOLO">
    <svg class="ic" viewBox="0 0 24 24" width="16" height="16"><path d="M9 6l6 6-6 6"/></svg>
  </button>
</div>
```

style.css:
```
.bolo-stepper{ display:flex; align-items:center; gap:6px; }
.bolo-card.focused{ border-color:var(--accent); box-shadow:0 0 0 1px var(--accent), var(--glass-shadow); }
```

app.js - track items + focus. In loadBolos(): after rendering, set
`state.boloCount = items.length; state.boloFocus = 0;` and tag each card with a
data index plus call updateBoloStep(). Add:
```
function focusBolo(dir){
  const cards = $$('#bolo-list .bolo-card');
  if (!cards.length) return;
  state.boloFocus = (state.boloFocus + dir + cards.length) % cards.length;
  cards.forEach((c, i) => c.classList.toggle('focused', i === state.boloFocus));
  cards[state.boloFocus].scrollIntoView({ block:'nearest', behavior:'smooth' });
  updateBoloStep();
}
function updateBoloStep(){
  const n = $$('#bolo-list .bolo-card').length;
  $('#bolo-step-index').textContent = (n ? (state.boloFocus + 1) : 0) + ' / ' + n;
}
```
Wiring in init():
`$('#bolo-prev').addEventListener('click', () => focusBolo(-1));`
`$('#bolo-next').addEventListener('click', () => focusBolo(1));`

Shared nav keydown handler (add ONE new listener; ordered so each mode owns its
keys; never hijack typing):
```
document.addEventListener('keydown', (e) => {
  if (app.classList.contains('hidden')) return;
  // 1) Lightbox owns Left/Right (Esc already handled in the Escape listener).
  if (isLightboxOpen()) {
    if (e.key === 'ArrowLeft')  { e.preventDefault(); lightboxStep(-1); }
    if (e.key === 'ArrowRight') { e.preventDefault(); lightboxStep(1);  }
    return;
  }
  // 2) Camera mode owns arrows/WASD for pan -> handled by the cam input module.
  if (app.classList.contains('cam-mode')) return;
  // 3) Do not hijack typing in form fields.
  const tag = (document.activeElement && document.activeElement.tagName) || '';
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
  // 4) BOLOs tab: arrows step the focused BOLO.
  const onBolos = $('.tab-panel[data-tab="bolos"]').classList.contains('active');
  if (onBolos) {
    if (e.key === 'ArrowLeft')  { e.preventDefault(); focusBolo(-1); }
    if (e.key === 'ArrowRight') { e.preventDefault(); focusBolo(1);  }
  }
});
```

================================================================================
# PART B - Cameras: more feeds + full CCTV controls
================================================================================

## B1. New camera feeds (10 added -> 25 total)

Paste these 10 lines into BOTH the server CAMERAS table (server/main.lua) and the
client CAMERAS mirror (client/main.lua). Coords MUST be identical in both files.
getCameras keeps returning only { id, label } - coords never reach the NUI.

```
{ id = 'casino',          label = 'Diamond Casino & Resort',  cam = vec3(935.0, 46.0, 85.0),      point = vec3(924.5, 46.5, 80.0) },
{ id = 'paleto_bank',     label = 'Blaine County Savings',     cam = vec3(-93.0, 6453.0, 35.0),    point = vec3(-105.0, 6463.0, 31.5) },
{ id = 'fleeca_route68',  label = 'Fleeca - Route 68',         cam = vec3(1166.0, 2715.0, 42.0),   point = vec3(1175.0, 2708.0, 38.0) },
{ id = 'store_seoul',     label = '24/7 - Little Seoul',       cam = vec3(-700.0, -912.0, 24.0),   point = vec3(-709.0, -904.0, 19.5) },
{ id = 'store_grapeseed', label = '24/7 - Grapeseed',          cam = vec3(1707.0, 4922.0, 46.0),   point = vec3(1697.0, 4924.0, 42.5) },
{ id = 'grove_st',        label = 'Grove Street - Davis',      cam = vec3(108.0, -1930.0, 25.0),   point = vec3(96.0, -1921.0, 20.8) },
{ id = 'forum_dr',        label = 'Forum Drive - Davis',       cam = vec3(-150.0, -1648.0, 38.0),  point = vec3(-163.0, -1641.0, 33.0) },
{ id = 'ls_docks',        label = 'LS Port - Terminal',        cam = vec3(390.0, -2640.0, 12.0),   point = vec3(382.0, -2622.0, 6.5) },
{ id = 'senora_fwy',      label = 'Senora Freeway (Rt 68)',    cam = vec3(2585.0, 1680.0, 38.0),   point = vec3(2600.0, 1690.0, 32.0) },
{ id = 'sandy_airfield',  label = 'Sandy Shores Airfield',     cam = vec3(1745.0, 3295.0, 45.0),   point = vec3(1730.0, 3308.0, 41.0) },
```
Category coverage of the 10: casino (1), banks (2: paleto_bank, fleeca_route68),
24/7 stores (2: store_seoul, store_grapeseed), gang areas (2: grove_st Families,
forum_dr Ballas), docks (1: ls_docks), highway (1: senora_fwy), airport/airfield
(1: sandy_airfield). Vinewood/airport/highways already exist in the base 15
(vinewood_blvd, lsia, plus banks/stores/sheriff stations), so the full set spans
banks, stores, gangs, highways, docks, airports, casino, vinewood.

Note: coords are placement estimates on known GTA V landmarks; nudge cam.z / point
in-world if any feed clips geometry. The client SetFocusPosAndVel already streams
the area in, so the scene renders even when the officer is across the map.

## B2. Control scheme - NUI driven (keeps focus balanced)

In cam-mode NUI keeps full focus (keyboard + mouse), so the game does not see raw
input. Therefore the NUI captures the controls and relays intents to the client,
which owns the scripted cam and applies the natives. Data flow:

  key/scroll/button in NUI  ->  nui('camControl', { dyaw, dpitch, dzoom,
                                                    nightvision?, thermal? })
                            ->  client updates camState + SetCamRot / SetCamFov /
                                SetNightvision / SetSeethrough
                            ->  cb returns the clamped state -> NUI updates hints

Controls exposed:
- PAN / ROTATE: yaw + pitch. Keys ArrowLeft/Right or A/D (yaw),
  ArrowUp/Down or W/S (pitch). Overlay also has a D-pad cluster.
- ZOOM: mouse wheel, or +/- keys, or overlay +/- buttons. Clamp FOV 20..70.
- NIGHT VISION: toggle button + key N -> SetNightvision(true/false).
- THERMAL (optional): toggle button + key T -> SetSeethrough(true/false).
  Night vision and thermal are mutually exclusive (turning one on clears the
  other) so the screen effect is never stacked.

(Alternative considered: SetNuiFocus(true,false) + a client DisableControlAction
thread reading game keys. Rejected - it splits input handling, breaks scroll-to-
zoom into the NUI, and risks leaving focus half-released. The NUI-driven scheme
above keeps one input path and the existing SetNuiFocus(true,true).)

## B3. Client: cam state + initial heading/pitch + natives

Add a clamp helper and a camState near the top of client/main.lua:
```
local function clamp(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end
local camState = nil   -- { heading, pitch, fov, nightvision, thermal }
```

In the viewCamera callback, derive the starting heading/pitch from the
cam -> point vector so the controls begin aligned with the framed scene, and set
rotation explicitly (use SetCamRot from the start instead of PointCamAtCoord so
later rotation deltas do not jump):
```
local dx = feed.point.x - feed.cam.x
local dy = feed.point.y - feed.cam.y
local dz = feed.point.z - feed.cam.z
local dist2d = math.sqrt(dx * dx + dy * dy)
local heading = GetHeadingFromVector_2d(dx, dy)   -- native: 0 = +Y (north)
local pitch   = math.deg(math.atan(dz, dist2d))   -- lua54 atan(y,x) = atan2

local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
SetCamCoord(cam, feed.cam.x, feed.cam.y, feed.cam.z)
SetCamRot(cam, pitch, 0.0, heading, 2)            -- replaces PointCamAtCoord
SetCamFov(cam, 60.0)
SetCamActive(cam, true)
SetTimecycleModifier('scanline_cam_cheap')
SetTimecycleModifierStrength(1.0)
RenderScriptCams(true, false, 0, true, true)
activeCam = cam
camState = { heading = heading, pitch = pitch, fov = 60.0, nightvision = false, thermal = false }
```

exitCamera() MUST also clear the screen effects so nothing leaks after exit:
```
local function exitCamera()
    if not activeCam then return end
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(activeCam, false)
    activeCam = nil
    camState = nil
    SetNightvision(false)        -- clear NV
    SetSeethrough(false)         -- clear thermal
    ClearFocus()
    ClearTimecycleModifier()
end
```
exitCamera is already invoked by exitCamera callback, closeMdt, viewCamera (swap),
and onResourceStop, so every teardown path now restores NV/thermal/cam/focus.

## B4. Client: camControl NUI callback (client-only, no server hop)

Add next to the other client-only callbacks. It applies deltas to camState and
re-applies the natives; returns the clamped state for the overlay to display:
```
RegisterNUICallback('camControl', function(data, cb)
    if not activeCam or not camState then cb({ ok = false }); return end
    data = data or {}
    local s = camState

    if data.dyaw   then s.heading = (s.heading + (tonumber(data.dyaw)   or 0)) % 360.0 end
    if data.dpitch then s.pitch   = clamp(s.pitch + (tonumber(data.dpitch) or 0), -89.0, 89.0) end
    if data.dzoom  then s.fov     = clamp(s.fov  + (tonumber(data.dzoom)  or 0), 20.0, 70.0) end
    SetCamRot(activeCam, s.pitch, 0.0, s.heading, 2)
    SetCamFov(activeCam, s.fov)

    if data.nightvision ~= nil then
        s.nightvision = data.nightvision and true or false
        if s.nightvision then s.thermal = false; SetSeethrough(false) end
        SetNightvision(s.nightvision)
    end
    if data.thermal ~= nil then
        s.thermal = data.thermal and true or false
        if s.thermal then s.nightvision = false; SetNightvision(false) end
        SetSeethrough(s.thermal)
    end

    cb({ ok = true, heading = s.heading, pitch = s.pitch, fov = s.fov,
         nightvision = s.nightvision, thermal = s.thermal })
end)
```
Natives used: SetCamRot, SetCamFov, SetNightvision, SetSeethrough,
GetHeadingFromVector_2d (all standard FiveM client natives).

## B5. Overlay UI + key hints + JS input loop

index.html - extend #cam-overlay. Keep the existing left (LIVE/name) and right
(Prev / index / Next / Exit) clusters; ADD a controls block between them:
```
<div class="cam-ov-controls">
  <div class="cam-dpad">
    <button class="cam-ctl" data-ctl="up"    title="Tilt up (W / Up)">&uarr;</button>
    <button class="cam-ctl" data-ctl="left"  title="Pan left (A / Left)">&larr;</button>
    <button class="cam-ctl" data-ctl="right" title="Pan right (D / Right)">&rarr;</button>
    <button class="cam-ctl" data-ctl="down"  title="Tilt down (S / Down)">&darr;</button>
  </div>
  <button class="btn sm" data-ctl="zoomin"  title="Zoom in (+ / scroll up)">+</button>
  <button class="btn sm" data-ctl="zoomout" title="Zoom out (- / scroll down)">-</button>
  <button id="cam-nv"   class="btn sm" title="Night vision (N)">Night</button>
  <button id="cam-th"   class="btn sm" title="Thermal (T)">Thermal</button>
</div>
```
Also add a hint line under the overlay (ASCII only):
```
<div class="cam-ov-hint">WASD / Arrows pan - Scroll or +/- zoom - N night - T thermal - Esc exit</div>
```

style.css (reuse glass tokens):
```
.cam-ov-controls{ display:flex; align-items:center; gap:8px; }
.cam-dpad{ display:grid; grid-template-columns:repeat(3,22px); grid-template-rows:repeat(2,22px);
  gap:2px; align-items:center; justify-items:center; }
.cam-dpad .cam-ctl[data-ctl="up"]{ grid-column:2; grid-row:1; }
.cam-dpad .cam-ctl[data-ctl="left"]{ grid-column:1; grid-row:2; }
.cam-dpad .cam-ctl[data-ctl="right"]{ grid-column:3; grid-row:2; }
.cam-dpad .cam-ctl[data-ctl="down"]{ grid-column:2; grid-row:2; }
.cam-ctl{ width:22px; height:22px; border-radius:6px; cursor:pointer; line-height:1;
  background:var(--btn-bg); color:var(--text-2); border:1px solid var(--btn-border); }
.cam-ctl:hover{ color:#fff; border-color:rgba(255,255,255,.25); }
.btn.sm.active, #cam-nv.active, #cam-th.active{ background:var(--accent-tint);
  border-color:var(--accent); color:var(--accent); }
.cam-ov-hint{ position:fixed; left:50%; bottom:8px; transform:translateX(-50%);
  font-size:11px; color:var(--text-muted); font-family:var(--mono);
  white-space:nowrap; pointer-events:none; z-index:70; }
.cam-ov-hint.hidden{ display:none !important; }
```
The hint is shown/hidden together with cam-mode (toggle in enterCamMode/
exitCamMode).

app.js - cam input module. Steps in fixed increments via a held-key loop so
holding a key pans smoothly; single clicks nudge once; wheel zooms:
```
const CAM_STEP = { yaw: 2.0, pitch: 1.5, zoom: 2.0 };   // per tick / per nudge
const camKeys = new Set();    // active pan keys while held
let camTimer = null;

function camAxisFromKeys(){
  let dyaw = 0, dpitch = 0;
  if (camKeys.has('left'))  dyaw  -= CAM_STEP.yaw;
  if (camKeys.has('right')) dyaw  += CAM_STEP.yaw;
  if (camKeys.has('up'))    dpitch += CAM_STEP.pitch;   // tilt up = look higher
  if (camKeys.has('down'))  dpitch -= CAM_STEP.pitch;
  return { dyaw, dpitch };
}
function camTick(){
  if (!app.classList.contains('cam-mode')) { stopCamLoop(); return; }
  const a = camAxisFromKeys();
  if (a.dyaw || a.dpitch) nui('camControl', a);
  if (!camKeys.size) stopCamLoop();
}
function startCamLoop(){ if (!camTimer) camTimer = setInterval(camTick, 50); }
function stopCamLoop(){ if (camTimer) { clearInterval(camTimer); camTimer = null; } }

function camZoom(dir){ nui('camControl', { dzoom: dir * CAM_STEP.zoom }); }  // +in uses negative fov delta below

async function camToggleNV(){
  const r = await nui('camControl', { nightvision: !camNV });
  camNV = !!(r && r.nightvision); camTH = !!(r && r.thermal);
  $('#cam-nv').classList.toggle('active', camNV);
  $('#cam-th').classList.toggle('active', camTH);
}
async function camToggleTH(){
  const r = await nui('camControl', { thermal: !camTH });
  camTH = !!(r && r.thermal); camNV = !!(r && r.nightvision);
  $('#cam-th').classList.toggle('active', camTH);
  $('#cam-nv').classList.toggle('active', camNV);
}
```
Zoom sign: zooming IN should DECREASE fov. So map "+ / scroll up" to a negative
dzoom. Concretely: zoom-in button/key and wheel-up call nui('camControl',
{ dzoom: -CAM_STEP.zoom }); zoom-out calls { dzoom: +CAM_STEP.zoom }. Keep
`camNV`/`camTH` as module-level booleans, reset to false in exitCamera().

Key + wheel + button capture (cam-mode only). Add a dedicated cam keydown/keyup
pair (separate from the Part A nav handler, which returns early in cam-mode):
```
const CAM_KEYMAP = { a:'left', d:'right', w:'up', s:'down',
  ArrowLeft:'left', ArrowRight:'right', ArrowUp:'up', ArrowDown:'down' };

document.addEventListener('keydown', (e) => {
  if (!app.classList.contains('cam-mode')) return;
  const dir = CAM_KEYMAP[e.key] || CAM_KEYMAP[e.key.toLowerCase && e.key.toLowerCase()];
  if (dir) { e.preventDefault(); camKeys.add(dir); startCamLoop(); return; }
  if (e.key === '+' || e.key === '=') { e.preventDefault(); camZoom(-1); }
  else if (e.key === '-' || e.key === '_') { e.preventDefault(); camZoom(1); }
  else if (e.key === 'n' || e.key === 'N') { e.preventDefault(); camToggleNV(); }
  else if (e.key === 't' || e.key === 'T') { e.preventDefault(); camToggleTH(); }
  // Esc is handled by the existing Escape listener (exits the feed).
});
document.addEventListener('keyup', (e) => {
  const dir = CAM_KEYMAP[e.key] || (e.key.toLowerCase && CAM_KEYMAP[e.key.toLowerCase()]);
  if (dir) camKeys.delete(dir);
});
document.addEventListener('wheel', (e) => {
  if (!app.classList.contains('cam-mode')) return;
  e.preventDefault();
  camZoom(e.deltaY < 0 ? -1 : 1);   // wheel up = zoom in
}, { passive: false });
```
D-pad / zoom buttons (single nudge on click; optional press-hold via the same
camKeys set). Minimal wiring in init():
```
$$('.cam-ctl').forEach((b) => {
  const dir = b.dataset.ctl;
  b.addEventListener('mousedown', () => { camKeys.add(dir); startCamLoop(); });
  b.addEventListener('mouseup',   () => { camKeys.delete(dir); });
  b.addEventListener('mouseleave',() => { camKeys.delete(dir); });
});
$('[data-ctl="zoomin"]').addEventListener('click',  () => camZoom(-1));
$('[data-ctl="zoomout"]').addEventListener('click', () => camZoom(1));
$('#cam-nv').addEventListener('click', camToggleNV);
$('#cam-th').addEventListener('click', camToggleTH);
```

## B6. Exit / reset wiring (UI side)

In exitCamera() (app.js) and enterCamMode()/exitCamMode(), reset the cam input
UI so a re-entered feed starts clean:
```
function exitCamMode(){
  app.classList.remove('cam-mode');
  $('#cam-overlay').classList.add('hidden');
  $('#cam-ov-hint') && $('#cam-ov-hint').classList.add('hidden');
  camKeys.clear(); stopCamLoop();
  camNV = false; camTH = false;
  $('#cam-nv').classList.remove('active');
  $('#cam-th').classList.remove('active');
}
```
enterCamMode() reveals the hint (`.classList.remove('hidden')`). The client-side
exitCamera already clears SetNightvision/SetSeethrough (B3), so even if the UI is
force-hidden (closeMdt / Esc / resource stop) the screen effects are cleared.

================================================================================
# Files-touched summary
================================================================================
- server/main.lua : CREATE_BOLOS_SQL (+image_urls), ensureColumn + JSON_ARRAY
  backfill, BOLOS_SELECT_SQL (+image_urls), BOLOS_INSERT_SQL (+column), 
  handleGetBolos (decode -> images[]), handleCreateBolo (images[] validate),
  CAMERAS (+10 feeds). No new callback; existing ones stay dual-registered.
- client/main.lua : CAMERAS mirror (+10 identical feeds), clamp + camState,
  viewCamera (SetCamRot from computed heading/pitch + init camState),
  exitCamera (clear NV/thermal + camState), new RegisterNUICallback('camControl').
- html/index.html : BOLO form multi-link rows + Add link; lightbox node; BOLO
  stepper in head; cam-overlay controls block + hint line.
- html/style.css : .link-rows/.link-row, .bolo-gallery/.bolo-thumb,
  .bolo-card.focused, .lightbox + lb-*, .bolo-stepper, .cam-ov-controls/.cam-dpad/
  .cam-ctl/.cam-ov-hint, active states.
- html/app.js : BOLO link-row helpers + createBolo array, gallery + lightbox
  module, BOLO focus stepper, shared nav keydown, cam input module
  (keys/wheel/buttons + loop), exit/reset wiring.

================================================================================
# Validation checklist (run before declaring done)
================================================================================
1. luac -p client/main.lua  and  luac -p server/main.lua  -> no errors.
2. node --check html/app.js  -> no errors.
3. Grep the diff for non-ASCII in NEW lines (no em/en dash, no ellipsis char,
   no middot). The bolo-foot middot is converted to " - " while edited.
4. Grep the diff for "citizenid" / "cid" in html/* and in any NUI payload -> none.
5. CAMERAS row count identical in client and server (25 each); ids match 1:1.
6. Focus: open MDT (F11) -> SetNuiFocus(true,true); enter a feed -> overlay +
   keys work, panel hidden; Esc -> back to panel, NV/thermal cleared, cam
   destroyed; close MDT -> focus released, view restored. Stop the resource
   while a feed is live -> onResourceStop tears the cam down and clears effects.
7. BOLO with 0, 1, and many links: gallery renders reserved 16:9 boxes, bad URL
   shows the placeholder, lightbox prev/next wraps within that bolo only, Left/
   Right keys cycle BOLOs when no lightbox is open and not typing in a field.
