# pengu_mdt - Camera Expansion + FiveManage Booking Mugshot (PLAN)

Scope: two features, no behavior regressions.
A) Grow the static CCTV camera grid from 25 feeds to 47 and fix the inverted
   left/right pan control.
B) Replace the ugly MugShotBase64 head shot with a real booking-cam screenshot
   (screenshot-basic) uploaded server-side to FiveManage, storing the hosted URL.

Hard rules carried through this change (unchanged):
- NO citizenid is ever returned to the NUI. cid stays server-side only.
- All MDT callbacks stay LEO + on-duty gated via getOfficer (already requires
  job.type == 'leo' AND job.onduty). Camera/mugshot paths add no new NUI data
  that leaks cid.
- Callbacks remain dual-registered: pengu_mdt:<name> AND pengu_mdt:server:<name>.
- ASCII only. Labels use the plain hyphen-minus " - " separator (same style as
  the existing feeds). No em dashes, no en dashes anywhere.
- node --check (app.js) and luac5.4 -p (client/main.lua, server/main.lua) must
  pass clean after the edits. (Both tools confirmed present: node v18.20.4,
  luac5.4.)
- NUI focus stays balanced: the booking-cam path runs on the SUSPECT client and
  adds ZERO SetNuiFocus calls, so the officer's MDT focus is untouched.

Verified facts used by this plan:
- screenshot-basic is installed at
  resources/[standalone]/screenshot-basic (resource name "screenshot-basic").
  Server export signature (src/server/server.ts line 84):
    exports['screenshot-basic']:requestClientScreenshot(player, options, cb)
  options: { fileName? (omit to get a data URI back), encoding = 'png'|'jpg'|'webp'
  (default 'jpg'), quality = 0.0-1.0 (default 0.92) }.
  cb(err, data): err is false on success or an error string; data is the local
  file name when fileName was passed, otherwise a base64 data URI
  ("data:image/jpeg;base64,....."). Confirmed in README.md and server.ts.
- ps-mdt booking cam reference (do NOT copy): Config.MugshotCamera DefaultFov
  50.0, FovMin 15.0, FovMax 80.0; client/mugshot.lua places the cam at
  pedCoords + forwardVector*1.2, z+0.5, PointCamAtCoord(head, z+0.3), FOV 50.
  Their server upload uses GetConvar for the key and PerformHttpRequest with an
  Authorization header (server/fivemanage.lua) - same shape we use below.


====================================================================
A) CAMERAS - 22 additional feeds (25 -> 47) + inverted-pan fix
====================================================================

A1. New feeds
-------------
The coords stay SERVER-SIDE (getCameras only exposes {id,label}); the client
keeps an identical mirror so the scripted cam can be placed locally. Add the
SAME 22 entries to BOTH tables, ids must match exactly:
  - server/main.lua CAMERAS table: insert before the closing brace at line 58.
  - client/main.lua CAMERAS table: insert before the closing brace at line 81.

Both files currently end the list with the `sandy_airfield` row. Paste this
block immediately after that row in each file (client mirror may keep its
extra column alignment; values must be identical):

    -- ----- Expansion: full-map MDT coverage (banks, stores, PD/SO, gangs,
    -- highways, docks, airport, beaches, county) -----
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

Coverage check vs the brief:
- Banks: Pacific (existing) + Fleecas Alta/Hawick/Route68 (existing) + Fleeca
  Great Ocean + Fleeca Del Perro (new) + Blaine County Savings Paleto (existing).
- 24/7 stores: Strawberry/Sandy/Seoul/Grapeseed (existing) + Morningwood/
  Harmony/Paleto/Mirror Park (LTD)/Davis (new).
- Police/Sheriff: MRPD lobby+cells, Vespucci PD, Sandy SO, Paleto SO (existing)
  + Vinewood PD + La Mesa Depot (new).
- Gang territory: Grove St (Families), Forum Dr (existing) + Vagos El Burro,
  Ballas Chamberlain, O Neil Ranch cartel, Lost MC Stab City (new).
- Highways/overpasses: Senora Fwy (existing) + Del Perro Fwy + La Puerta Fwy (new).
- Docks/port: LS Port terminal (existing) + Elysian Island (new).
- Airport: LSIA terminal, Sandy airfield (existing) + LSIA runway/tower (new).
- Casino, Vinewood, Del Perro Pier (existing) + Vespucci beach, Mirror Park,
  Maze Bank Arena (new); Paleto + Grapeseed extra street feeds (new).
Total: 25 + 22 = 47 feeds. No id collisions with the existing set.

No NUI changes are required for the new feeds: app.js loadCameras() already
renders whatever {id,label} list getCameras returns and the overlay index
"i / n" recomputes from state.feeds.length.

A2. Inverted L/R pan - root cause and fix
-----------------------------------------
The Prev/Next feed buttons are NOT inverted (cycleCamera(-1)=Prev,
cycleCamera(1)=Next via array index; app.js lines 1200-1201). The actual
"press Right, view goes Left" bug is the YAW SIGN in the pan mapping.

Why it is inverted: GTA heading/Z-rotation increases COUNTER-CLOCKWISE
(0=N, 90=W, 180=S, 270=E). The client applies the yaw delta as
`s.heading = (s.heading + dyaw) % 360` (client/main.lua line 256) and the NUI
maps Right to a POSITIVE dyaw (app.js line 951). Positive dyaw raises heading,
which rotates the camera counter-clockwise = the scene pans LEFT. So Right pans
left and Left pans right - inverted.

Fix (single, canonical, in the input layer) - app.js camAxisFromKeys, lines
950-951. Swap the two yaw signs:

    BEFORE:
        if (camKeys.has('left')) dyaw -= CAM_STEP.yaw;
        if (camKeys.has('right')) dyaw += CAM_STEP.yaw;
    AFTER:
        if (camKeys.has('left')) dyaw += CAM_STEP.yaw;   // pan view left  = +heading (CCW)
        if (camKeys.has('right')) dyaw -= CAM_STEP.yaw;   // pan view right = -heading (CW)

This one change corrects BOTH the WASD keys and the Arrow keys, because both
funnel through CAM_KEYMAP -> camKeys -> camAxisFromKeys (app.js lines 1075-1097);
there are no separate on-screen pan arrow buttons to touch. Up/Down pitch is
already correct (line 952-953: up = tilt higher) and stays as-is.

Equivalent alternative (pick ONE, not both): instead of app.js, negate the
delta in client/main.lua line 256:
    s.heading = (s.heading - (tonumber(data.dyaw) or 0)) % 360.0
The app.js fix is preferred (keeps direction logic in the input layer; leaves
the initial heading derivation in viewCamera untouched).

Verify after edit: open a feed, hold D / Right -> view sweeps to the viewer's
right; hold A / Left -> sweeps left. Prev/Next still step feeds 1..n in order.


====================================================================
B) MUGSHOTS - booking-cam screenshot via screenshot-basic + FiveManage
====================================================================

Goal: when charges are placed on an ONLINE suspect, the suspect client frames a
clean booking shot, the SERVER captures it with screenshot-basic, uploads it to
FiveManage server-side (key never leaves the server), and stores the returned
URL in pengu_mdt_mugshots.image (column is already MEDIUMTEXT; we now store a
short URL instead of a giant base64 blob). searchPerson keeps returning that
value as `mugshot` and the NUI <img src> shows it - no NUI change needed.

B0. fxmanifest dependency
-------------------------
fxmanifest.lua dependencies{}: add 'screenshot-basic'. MugShotBase64 is no
longer used by the primary flow; either remove it or keep it ONLY as an
optional client fallback (see B4). Recommended final list:
    dependencies { 'qbx_core', 'ox_lib', 'oxmysql', 'xt-prison', 'screenshot-basic' }
(If keeping a MugShotBase64 fallback, leave 'MugShotBase64' in the list too.)

B1. Flow / handshake (ordering matters)
---------------------------------------
placeCharges already detects an online suspect and currently does
`TriggerClientEvent('pengu_mdt:captureMugshot', tgt.PlayerData.source)`
(server/main.lua lines 467-471). Keep that trigger but change what each side does:

  1. SERVER placeCharges: on an online suspect, record a short-lived pending
     entry pendingMugshot[src] = { cid = cid, expires = os.time()+30 } and fire
     pengu_mdt:captureMugshot to that src (unchanged trigger name).
  2. SUSPECT client (pengu_mdt:captureMugshot): build a scripted booking cam in
     front of its own ped pointed at the head/upper body, let the pose + render
     settle (~900 ms), then signal readiness with
     TriggerServerEvent('pengu_mdt:bookingReady'). A SetTimeout safety auto
     tears the cam down if the server never replies.
  3. SERVER (pengu_mdt:bookingReady): validate pendingMugshot[src] (exists and
     not expired), consume it, then
       exports['screenshot-basic']:requestClientScreenshot(src,
           { encoding = 'jpg', quality = 0.85 }, cb)
     In cb: ALWAYS TriggerClientEvent('pengu_mdt:bookingDone', src) to restore
     the suspect's view, then (on success) upload + store.
  4. SUSPECT client (pengu_mdt:bookingDone): destroy the booking cam, restore.

The handshake guarantees the screenshot is taken only while the booking cam is
live and only for a suspect the server actually charged (pendingMugshot guard
stops a client from spamming bookingReady to trigger arbitrary screenshots).

B2. Suspect-side booking cam (client/main.lua)
----------------------------------------------
Replace the existing pengu_mdt:captureMugshot handler (lines 303-311, the
MugShotBase64 path) with a booking-cam setup. Reference framing from ps-mdt
(FOV ~50, cam ~1.2 m in front, point at head) tuned to head + upper body:

    local bookingCam = nil
    local function teardownBookingCam()
        if not bookingCam then return end
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(bookingCam, false)
        bookingCam = nil
        local ped = cache.ped or PlayerPedId()
        ClearPedTasks(ped)            -- drop the forced stand-still
    end

    RegisterNetEvent('pengu_mdt:captureMugshot', function()
        CreateThread(function()
            local ped = cache.ped or PlayerPedId()
            local c = GetEntityCoords(ped)
            local f = GetEntityForwardVector(ped)   -- cam sits along the ped's
                                                    -- facing => ped faces camera
            ClearPedTasksImmediately(ped)           -- neutral idle, no weapon pose
            SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
            teardownBookingCam()
            bookingCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
            SetCamCoord(bookingCam, c.x + f.x * 1.4, c.y + f.y * 1.4, c.z + 0.55)
            PointCamAtCoord(bookingCam, c.x, c.y, c.z + 0.55)  -- head / upper body
            SetCamFov(bookingCam, 40.0)             -- head + shoulders framing
            SetCamActive(bookingCam, true)
            RenderScriptCams(true, false, 0, true, true)
            Wait(900)                               -- let pose + render settle
            TriggerServerEvent('pengu_mdt:bookingReady')
            SetTimeout(8000, teardownBookingCam)    -- safety if no bookingDone
        end)
    end)

    RegisterNetEvent('pengu_mdt:bookingDone', function()
        teardownBookingCam()
    end)

Notes:
- NO SetNuiFocus anywhere here -> officer MDT focus stays balanced; the suspect
  needs no focus (screenshot-basic renders the game view via its own hidden NUI).
- No teleport, plain framing; ped keeps its location, only stands still briefly.
- Extend the existing onResourceStop handler (client/main.lua lines 317-324) to
  also call teardownBookingCam() so a mid-capture resource stop cannot strand
  the suspect in the scripted cam.

B3. Server capture + FiveManage upload (server/main.lua)
--------------------------------------------------------
Add near the top constants:
    local FIVEMANAGE_URL = 'https://api.fivemanage.com/api/image'
    local pendingMugshot = {}   -- [src] = { cid = string, expires = number }

Add a small pure-Lua base64 decoder + multipart builder (PerformHttpRequest
sends the body as a raw string; binary bytes in a Lua string are fine):

    local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local function b64decode(data)
        data = data:gsub('[^' .. B64 .. '=]', '')
        return (data:gsub('.', function(x)
            if x == '=' then return '' end
            local r, f = '', (B64:find(x) - 1)
            for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0') end
            return r
        end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
            if #x ~= 8 then return '' end
            local cc = 0
            for i = 1, 8 do cc = cc + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0) end
            return string.char(cc)
        end))
    end

    local function multipartImage(boundary, filename, binary)
        return table.concat({
            '--' .. boundary,
            ('Content-Disposition: form-data; name="image"; filename="%s"'):format(filename),
            'Content-Type: image/jpeg',
            '',
            binary,
            '--' .. boundary .. '--',
            '',
        }, '\r\n')
    end

Upload helper (graceful fallback, never crashes):

    local function uploadMugshot(cid, dataUri)
        local token = GetConvar('pengu_mdt_fivemanage_key', '')
        if token == '' then
            print('^3[pengu_mdt]^7 FiveManage key unset (convar pengu_mdt_fivemanage_key); keeping existing mugshot.')
            return
        end
        local b64 = type(dataUri) == 'string' and (dataUri:match('base64,(.+)') or dataUri) or nil
        local binary = b64 and b64decode(b64) or nil
        if not binary or binary == '' then
            print('^3[pengu_mdt]^7 Mugshot decode failed; keeping existing mugshot.')
            return
        end
        local boundary = ('penguMDT%d'):format(math.random(100000, 999999))
        local body = multipartImage(boundary, ('mugshot_%s.jpg'):format(cid), binary)
        PerformHttpRequest(FIVEMANAGE_URL, function(status, resp)
            if status and status >= 200 and status < 300 and resp then
                local ok, parsed = pcall(json.decode, resp)
                local url = ok and parsed and
                    (((type(parsed.data) == 'table' and parsed.data.url) or parsed.url)) or nil
                if type(url) == 'string' and url:match('^https?://') then
                    MySQL.insert.await(MUGSHOT_UPSERT_SQL, { cid, url })   -- store URL, not base64
                else
                    print('^3[pengu_mdt]^7 FiveManage: no url in response: ' .. tostring(resp))
                end
            else
                print('^3[pengu_mdt]^7 FiveManage upload failed (HTTP ' .. tostring(status) .. '); keeping existing mugshot.')
            end
        end, 'POST', body, {
            ['Authorization'] = token,
            ['Content-Type'] = 'multipart/form-data; boundary=' .. boundary,
        })
    end

Wire placeCharges (server/main.lua lines 467-471) - keep the trigger, add the
pending guard:

    local tgt = exports.qbx_core:GetPlayerByCitizenId(cid)
    if tgt and tgt.PlayerData and tgt.PlayerData.source then
        local s = tgt.PlayerData.source
        pendingMugshot[s] = { cid = cid, expires = os.time() + 30 }
        TriggerClientEvent('pengu_mdt:captureMugshot', s)
    end

Capture on readiness:

    RegisterNetEvent('pengu_mdt:bookingReady', function()
        local src = source
        local pend = pendingMugshot[src]
        pendingMugshot[src] = nil
        if not pend or pend.expires < os.time() then return end
        if GetResourceState('screenshot-basic') ~= 'started' then
            print('^3[pengu_mdt]^7 screenshot-basic not started; skipping mugshot.')
            TriggerClientEvent('pengu_mdt:bookingDone', src)
            return
        end
        exports['screenshot-basic']:requestClientScreenshot(src, {
            encoding = 'jpg', quality = 0.85,
        }, function(err, data)
            TriggerClientEvent('pengu_mdt:bookingDone', src)   -- always restore view
            if err or type(data) ~= 'string' or data == '' then
                print('^3[pengu_mdt]^7 Mugshot screenshot failed: ' .. tostring(err))
                return
            end
            uploadMugshot(pend.cid, data)
        end)
    end)

Optional hygiene: clear pendingMugshot[src] on playerDropped so a disconnect
mid-booking leaves no stale entry.

B4. Storage change base64 -> URL, and what to remove
----------------------------------------------------
- pengu_mdt_mugshots stays as-is (citizenid PK, image MEDIUMTEXT). We now write
  a URL string into image instead of a base64 data URI. MUGSHOT_UPSERT_SQL
  (lines 198-201) and MUGSHOT_SELECT_SQL (lines 194-196) are reused unchanged.
- searchPerson (lines 373-375) is unchanged: it returns mugRow.image (now the
  URL) as `mugshot`, with the existing `if mugshot == '' then mugshot = nil`
  guard so an empty/absent value falls back to the NUI placeholder. No cid is
  exposed. No NUI edits.
- REMOVE the old client-trusted base64 intake event
  RegisterNetEvent('pengu_mdt:storeMugshot', ...) (server lines 664-671): the
  server now writes the row itself after upload, so the client never ships an
  image. MUGSHOT_MAX_LEN (line 60) becomes unused - delete it (or repurpose as a
  small URL length sanity cap if you keep any client write path).
- The client MugShotBase64 capture handler is fully replaced by the booking cam
  (B2). If you want a degraded fallback when screenshot-basic is down, you MAY
  keep MugShotBase64: in pengu_mdt:bookingReady, when screenshot-basic is not
  'started', instead of skipping you could fire a legacy capture event back to
  the client that uses MugShotBase64 and the old storeMugshot path. Default
  recommendation: do NOT keep the base64 fallback (it reintroduces the ugly head
  + huge payload); just warn and leave the prior photo / placeholder in place.

Fallback summary (no crashes): convar empty -> warn + keep existing mugshot;
upload non-2xx or no url -> warn + keep existing mugshot; screenshot-basic not
started -> warn + restore view + keep existing mugshot. In every failure path
we never overwrite a previously stored URL, so the last good photo (or the NUI
placeholder) survives.

API reference (FiveManage media/image):
- POST https://api.fivemanage.com/api/image
- Header Authorization: <token from convar pengu_mdt_fivemanage_key>
- Body: multipart/form-data, file field name "image" (filename .jpg, type
  image/jpeg).
- Response JSON: hosted link in `url` (some deployments nest it under
  `data.url`); the parser above accepts either.
Set the key in server.cfg (server-side only, never sent to clients):
    set pengu_mdt_fivemanage_key "YOUR_FIVEMANAGE_IMAGE_TOKEN"


====================================================================
Acceptance / verification checklist
====================================================================
- [ ] server/main.lua and client/main.lua CAMERAS tables each have 47 entries
      with identical ids; getCameras still returns only {id,label}.
- [ ] Pan: D/Right pans view right, A/Left pans view left; Prev/Next step feeds
      in order; Up/Down tilt unchanged; NV/Thermal unchanged.
- [ ] fxmanifest dependencies include 'screenshot-basic'.
- [ ] Charging an online suspect: suspect briefly framed by booking cam, server
      captures, FiveManage URL stored, searchPerson shows the photo via <img>.
- [ ] Key unset / upload fail / screenshot-basic down: clear server warning,
      no crash, prior photo or placeholder retained, suspect view restored.
- [ ] No citizenid in any NUI payload; callbacks dual-registered; getOfficer
      leo+onduty gate intact.
- [ ] ASCII only (zero em/en dashes). Verify: grep -nP "[\x{2013}\x{2014}]"
      across pengu_mdt returns nothing.
- [ ] node --check html/app.js passes; luac5.4 -p client/main.lua and
      luac5.4 -p server/main.lua pass.
- [ ] NUI focus balanced: each SetNuiFocus(true,...) on the officer path still
      has its matching SetNuiFocus(false,false); booking-cam path adds none.
