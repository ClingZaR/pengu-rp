--[[
    pengu_mdt - CLIENT (REDESIGN2 overhaul)
    Standalone Qbox MDT. Stack: qbx_core + ox_lib + screenshot-basic.

    Responsibilities:
      - /mdt command + F11 keybind -> open the NUI for LEO
        (PlayerData.job.type == 'leo' covers police/bcso/sasp) AND for court
        (job.name 'judge'/'lawyer' -> restricted read-only role; the server
        re-checks the role on every callback).
      - Relay every NUI data fetch to the authoritative server callbacks
        via lib.callback.await('pengu_mdt:<name>', ...).
      - Booking camera: the pdloc 'mugshot' point calls exports startBookingMugshot
        -> ask for a name, drop to first person + viewfinder; on [E] capture via
        screenshot-basic, downscale the photo IN OUR OWN NUI to ~50KB, then send
        the small image to the server to store against the named citizen.
      - Cameras: scripted-cam presets (coords live both here + server CAMERAS);
        viewCamera renders a fixed CCTV angle, exitCamera restores the player view.
      - Bodycam: REAL captures via screenshot-basic (it IS installed; the
        booking camera below already uses it). REC ON grabs a frame immediately
        and then every 60s; each frame is downscaled in our own NUI and stored
        server-side (pengu_mdt_bodycam, pruned to 20 per officer).
      - closeMdt is handled entirely client-side (release NUI focus + restore cam).

    NUI <-> client contract (fetch https://pengu_mdt/<name>):
      Relayed to authoritative server callbacks (lib.callback.await):
        getDashboard  {}                 -> pengu_mdt:getDashboard
        searchVehicle {plate}            -> pengu_mdt:searchVehicle
        searchPerson  {name}             -> pengu_mdt:searchPerson
        getPenalCode  {}                 -> pengu_mdt:getPenalCode
        placeCharges  {name, items}      -> pengu_mdt:placeCharges
        getBolos      {}                 -> pengu_mdt:getBolos
        createBolo    {type,...}          -> pengu_mdt:createBolo
        cancelBolo    {id}               -> pengu_mdt:cancelBolo
        getWarrants   {}                 -> pengu_mdt:getWarrants  (derived)
        getReports    {}                 -> pengu_mdt:getReports
        getReport     {id}               -> pengu_mdt:getReport
        createReport  {title,...}         -> pengu_mdt:createReport
        getCameras    {}                 -> pengu_mdt:getCameras
        getBodycam    {}                 -> pengu_mdt:getBodycam
      Client-only (no server hop):
        closeMdt      {}                 -> SetNuiFocus(false) + restore cam
        viewCamera    {id}               -> scripted CCTV cam at the feed
        exitCamera    {}                 -> destroy cam + restore player view
        toggleBodycam {}                 -> start/stop the real bodycam capture loop

    Outbound (client -> NUI) messages:
      {action='open'} {action='close'}

    NOTE (REDESIGN2): the old jail-proximity thread / {jailProximity} message /
    BOOKING_POINTS and the Send-to-Jail + Issue-Fine buttons are GONE. Imprisonment
    and forced fines now happen exclusively through the server /jail command at the
    Department of Corrections; placeCharges only RECORDS outstanding charges.
]]

local isOpen = false

----------------------------------------------------------------------
-- Camera feeds (coords duplicated from the server CAMERAS config so the
-- scripted cam can be placed locally; the NUI only ever receives {id,label}).
----------------------------------------------------------------------

local CAMERAS = {
    { id = 'mrpd_lobby',       label = 'MRPD - Lobby',            cam = vec3(441.0, -979.0, 31.5),    point = vec3(441.5, -982.6, 30.7) },
    { id = 'mrpd_cells',       label = 'MRPD - Cell Block',       cam = vec3(461.5, -994.0, 30.7),    point = vec3(465.5, -1000.5, 24.9) },
    { id = 'legion_sq',        label = 'Legion Square',           cam = vec3(190.0, -933.0, 40.0),    point = vec3(195.5, -933.9, 30.7) },
    { id = 'pacific_bank',     label = 'Pacific Standard Bank',   cam = vec3(248.0, 225.0, 112.0),    point = vec3(235.0, 216.0, 106.3) },
    { id = 'fleeca_legion',    label = 'Fleeca - Alta St',        cam = vec3(146.5, -1045.5, 33.5),   point = vec3(151.0, -1037.0, 29.4) },
    { id = 'fleeca_hawick',    label = 'Fleeca - Hawick Ave',     cam = vec3(-355.5, -44.5, 53.5),    point = vec3(-350.5, -52.5, 49.0) },
    { id = 'store_strawberry', label = '24/7 - Strawberry Ave',   cam = vec3(29.5, -1340.5, 33.5),    point = vec3(24.5, -1348.5, 29.5) },
    { id = 'store_sandy',      label = '24/7 - Sandy Shores',     cam = vec3(1965.5, 3745.0, 36.0),   point = vec3(1959.0, 3741.0, 32.3) },
    { id = 'vespucci_pd',      label = 'Vespucci Police Station', cam = vec3(-1100.0, -835.0, 19.0),  point = vec3(-1110.0, -846.0, 13.5) },
    { id = 'sandy_sheriff',    label = 'Sandy Shores Sheriff',    cam = vec3(1860.0, 3679.0, 38.0),   point = vec3(1852.0, 3689.5, 34.0) },
    { id = 'paleto_sheriff',   label = 'Paleto Bay Sheriff',      cam = vec3(-437.0, 6021.0, 36.5),   point = vec3(-448.5, 6007.0, 31.7) },
    { id = 'doc_yard',         label = 'Bolingbroke DOC - Yard',  cam = vec3(1850.0, 2600.0, 55.0),   point = vec3(1845.8, 2585.9, 45.7) },
    { id = 'vinewood_blvd',    label = 'Vinewood Boulevard',      cam = vec3(294.0, 207.0, 92.0),     point = vec3(305.0, 195.0, 84.0) },
    { id = 'del_perro',        label = 'Del Perro Pier',          cam = vec3(-1843.0, -1242.0, 18.5), point = vec3(-1856.0, -1228.0, 12.5) },
    { id = 'lsia',             label = 'LS Intl Airport',         cam = vec3(-1031.0, -2730.0, 25.5), point = vec3(-1042.0, -2744.0, 19.5) },
    { id = 'casino',           label = 'Diamond Casino & Resort', cam = vec3(935.0, 46.0, 85.0),      point = vec3(924.5, 46.5, 80.0) },
    { id = 'paleto_bank',      label = 'Blaine County Savings',   cam = vec3(-93.0, 6453.0, 35.0),    point = vec3(-105.0, 6463.0, 31.5) },
    { id = 'fleeca_route68',   label = 'Fleeca - Route 68',       cam = vec3(1166.0, 2715.0, 42.0),   point = vec3(1175.0, 2708.0, 38.0) },
    { id = 'store_seoul',      label = '24/7 - Little Seoul',     cam = vec3(-700.0, -912.0, 24.0),   point = vec3(-709.0, -904.0, 19.5) },
    { id = 'store_grapeseed',  label = '24/7 - Grapeseed',        cam = vec3(1707.0, 4922.0, 46.0),   point = vec3(1697.0, 4924.0, 42.5) },
    { id = 'grove_st',         label = 'Grove Street - Davis',    cam = vec3(108.0, -1930.0, 25.0),   point = vec3(96.0, -1921.0, 20.8) },
    { id = 'forum_dr',         label = 'Forum Drive - Davis',     cam = vec3(-150.0, -1648.0, 38.0),  point = vec3(-163.0, -1641.0, 33.0) },
    { id = 'ls_docks',         label = 'LS Port - Terminal',      cam = vec3(390.0, -2640.0, 12.0),   point = vec3(382.0, -2622.0, 6.5) },
    { id = 'senora_fwy',       label = 'Senora Freeway (Rt 68)',  cam = vec3(2585.0, 1680.0, 38.0),   point = vec3(2600.0, 1690.0, 32.0) },
    { id = 'sandy_airfield',   label = 'Sandy Shores Airfield',   cam = vec3(1745.0, 3295.0, 45.0),   point = vec3(1730.0, 3308.0, 41.0) },
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

local function findFeed(id)
    if type(id) ~= 'string' then return nil end
    for _, c in ipairs(CAMERAS) do
        if c.id == id then return c end
    end
    return nil
end

local activeCam = nil
-- Live control state while a feed is up: { heading, pitch, fov, nightvision, thermal }.
local camState = nil

-- Clamp a number to the inclusive range [lo, hi].
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Tear down any active scripted cam and hand control back to the player ped.
local function exitCamera()
    if not activeCam then return end
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(activeCam, false)
    activeCam = nil
    camState = nil
    SetNightvision(false)       -- clear night vision so it never leaks after exit
    SetSeethrough(false)        -- clear thermal too
    ClearFocus()                -- stop streaming the remote feed area
    ClearTimecycleModifier()    -- drop the CCTV scanline look
end

----------------------------------------------------------------------
-- Mouse-look camera control. No cursor: every look / zoom / feed-switch /
-- vision / exit input is read on the CLIENT each frame while a feed is up.
----------------------------------------------------------------------

-- Look / zoom feel.
local SENS_X    = 7.0    -- degrees of yaw per unit of LookLeftRight
local SENS_Y    = 7.0    -- degrees of pitch per unit of LookUpDown
local ZOOM_STEP = 4.0    -- FOV change per wheel-notch frame
local FOV_MIN, FOV_MAX     = 20.0, 70.0
local PITCH_MIN, PITCH_MAX = -80.0, 80.0  -- clamp so the cam never flips over

local currentIdx = nil   -- index into CAMERAS of the live feed
local camToken = 0       -- bumped on every feed open so a re-open kills the old thread

-- Heading/pitch that frames cam -> point for a feed.
local function feedAim(feed)
    local dx = feed.point.x - feed.cam.x
    local dy = feed.point.y - feed.cam.y
    local dz = feed.point.z - feed.cam.z
    local dist2d = math.sqrt(dx * dx + dy * dy)
    return GetHeadingFromVector_2d(dx, dy), math.deg(math.atan(dz, dist2d))
end

-- Move the live cam to CAMERAS[idx] (reuses activeCam; resets aim / fov /
-- vision) and tell the overlay the new feed name + reset its vision badge.
local function applyFeed(idx)
    local feed = CAMERAS[idx]
    if not feed or not activeCam or not camState then return end
    currentIdx = idx
    SetFocusPosAndVel(feed.cam.x, feed.cam.y, feed.cam.z, 0.0, 0.0, 0.0)
    local heading, pitch = feedAim(feed)
    SetCamCoord(activeCam, feed.cam.x, feed.cam.y, feed.cam.z)
    SetCamRot(activeCam, pitch, 0.0, heading, 2)
    SetCamFov(activeCam, 60.0)
    camState.heading = heading
    camState.pitch = pitch
    camState.fov = 60.0
    camState.nightvision = false
    camState.thermal = false
    SetNightvision(false)
    SetSeethrough(false)
    SendNUIMessage({ action = 'camFeed', id = feed.id, label = feed.label, vision = 'off' })
end

-- Arrow / A,D feed switch (called by the control thread; no NUI hop).
local function switchFeed(dir)
    if currentIdx == nil then return end
    local n = #CAMERAS
    applyFeed(((currentIdx - 1 + dir) % n) + 1)
end

-- Cycle screen vision off -> night -> thermal -> off (mutually exclusive).
local function cycleVision()
    if not camState then return end
    if camState.nightvision then
        camState.nightvision = false
        camState.thermal = true
        SetNightvision(false)
        SetSeethrough(true)
        SendNUIMessage({ action = 'camVision', vision = 'thermal' })
    elseif camState.thermal then
        camState.thermal = false
        SetSeethrough(false)
        SetNightvision(false)
        SendNUIMessage({ action = 'camVision', vision = 'off' })
    else
        camState.nightvision = true
        SetNightvision(true)
        SetSeethrough(false)
        SendNUIMessage({ action = 'camVision', vision = 'night' })
    end
end

-- Backspace: tear the cam down and hand the cursor + MDT panel back.
local function leaveCamToPanel()
    exitCamera()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'camExit' })
end

-- Per-frame control thread: disable game controls, then drive yaw/pitch from
-- mouse look, FOV from the wheel, and read the feed-switch / vision / exit keys.
-- A generation token guarantees a re-open never leaves two drivers running.
local function startCamLookThread()
    camToken = camToken + 1
    local myToken = camToken
    CreateThread(function()
        while activeCam and camState and camToken == myToken do
            Wait(0)
            DisableAllControlActions(0) -- ped does not walk / shoot / etc.

            -- MOUSE LOOK. LookLeftRight (0,1) is +right; GTA Z-heading increases
            -- counter-clockwise, so SUBTRACT to pan right (right == right, NOT
            -- inverted). LookUpDown (0,2) is +down; SUBTRACT for natural tilt.
            local dx = GetDisabledControlNormal(0, 1)
            local dy = GetDisabledControlNormal(0, 2)
            if dx ~= 0.0 then
                camState.heading = (camState.heading - dx * SENS_X) % 360.0
            end
            if dy ~= 0.0 then
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

            -- FEED SWITCH. 174 arrow Left / 175 arrow Right (34 A / 35 D too).
            if IsDisabledControlJustPressed(0, 174) or IsDisabledControlJustPressed(0, 34) then
                switchFeed(-1)
            elseif IsDisabledControlJustPressed(0, 175) or IsDisabledControlJustPressed(0, 35) then
                switchFeed(1)
            end

            -- VISION TOGGLE. 22 = INPUT_JUMP (Space): clearly free, no clash
            -- with N (push-to-talk). Cycles off -> night -> thermal -> off.
            if IsDisabledControlJustPressed(0, 22) then
                cycleVision()
            end

            -- EXIT back to the MDT panel. 177 = Backspace.
            if IsDisabledControlJustPressed(0, 177) then
                leaveCamToPanel()
            end
        end
    end)
end

----------------------------------------------------------------------
-- Auth helper
----------------------------------------------------------------------

-- MDT role for the local player:
--   'leo'   = ON-DUTY LEO (off-duty officers cannot open the MDT)
--   'court' = judge/lawyer -> restricted read-only role (server re-checks)
--   nil     = no access
local function mdtRole()
    local data = exports.qbx_core:GetPlayerData()
    if data == nil or data.job == nil then return nil end
    if data.job.type == 'leo' and data.job.onduty == true then return 'leo' end
    if data.job.name == 'judge' or data.job.name == 'lawyer' then return 'court' end
    return nil
end

-- True only when the local player is an ON-DUTY LEO (radar, booking cam, bodycam).
local function isLeo()
    return mdtRole() == 'leo'
end

----------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------

local function openMdt()
    if isOpen then return end
    local role = mdtRole()
    if not role then
        -- PenguRP: feedback in chat, not a toast.
        TriggerEvent('chat:addMessage', {
            templateId = 'pengu:admin',
            args = { 'MDT', 'You are not authorized to use the police terminal.', 'err' },
        })
        return
    end

    isOpen = true
    SetNuiFocus(true, true)
    -- role drives the NUI: 'court' hides the Arrest Calculator, BOLO create
    -- form and every action button. The server enforces the same role on
    -- every callback, so this is presentation only.
    SendNUIMessage({ action = 'open', role = role })
end

local function closeMdt()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    exitCamera() -- never leave the player stuck in a scripted cam
    -- Tell the UI to hide (it already releases its own state on close).
    SendNUIMessage({ action = 'close' })
end

-- Radar HUD entry point: pengu_traffic fires this local event to open the MDT
-- straight onto the Vehicle tab with the selected plate already searched.
AddEventHandler('pengu_mdt:runPlate', function(plate)
    if not isLeo() then return end
    if type(plate) ~= 'string' or plate == '' then return end
    if not isOpen then
        isOpen = true
        SetNuiFocus(true, true)
    end
    SendNUIMessage({ action = 'open', plate = plate, role = 'leo' }) -- isLeo() checked above
end)

----------------------------------------------------------------------
-- Command + keybind
----------------------------------------------------------------------

-- NOTE: /mdt clashes with ps-mdt; the operator disables the ps-mdt command
-- separately. We still bind /mdt here as the canonical entry point.
RegisterCommand('mdt', function()
    -- Toggle: F11 / /mdt opens when closed and closes when open.
    if isOpen then closeMdt() else openMdt() end
end, false)

-- Default keybind F11 (players can rebind in GTA settings). The keymapping
-- triggers the 'mdt' command on key-down.
RegisterKeyMapping('mdt', 'Open Police MDT', 'keyboard', 'F11')

----------------------------------------------------------------------
-- Plea prompt (suspect side). After /jail processing, the suspect picks a
-- plea; guilty waives a trial and cuts the sentence. /plea re-opens a pending one.
----------------------------------------------------------------------

RegisterNetEvent('pengu_mdt:offerPlea', function(data)
    if type(data) ~= 'table' or not data.caseId then return end
    local pct = math.floor((tonumber(data.pct) or 0.25) * 100)
    lib.registerContext({
        id = 'pengu_plea',
        title = 'Enter Your Plea',
        colorScheme = 'grape', -- PenguRP: lavender accent to align ox_lib menus with our theme
        options = {
            {
                title = 'Charges',
                description = (data.charges ~= nil and data.charges ~= '') and data.charges or 'Various charges',
                icon = 'scroll',
                disabled = true,
            },
            {
                title = 'Plead GUILTY',
                description = ('Waive trial - cut your sentence by %d%%'):format(pct),
                icon = 'gavel',
                onSelect = function() TriggerServerEvent('pengu_mdt:submitPlea', data.caseId, 'guilty') end,
            },
            {
                title = 'Plead NOT GUILTY',
                description = 'Maintain innocence (full sentence)',
                icon = 'scale-balanced',
                onSelect = function() TriggerServerEvent('pengu_mdt:submitPlea', data.caseId, 'not_guilty') end,
            },
        },
    })
    lib.showContext('pengu_plea')
end)

RegisterCommand('plea', function()
    TriggerServerEvent('pengu_mdt:requestPlea')
end, false)
TriggerEvent('chat:addSuggestion', '/plea', 'Enter your plea for your current charges')

-- Wanted level commands are server-side (on-duty LEO only); suggestions here.
TriggerEvent('chat:addSuggestion', '/wanted', 'Flag a citizen as wanted (LEO)', {
    { name = 'id', help = 'Player server id' },
    { name = 'level', help = 'Wanted level 1-5' },
    { name = 'reason', help = 'Reason (optional)' },
})
TriggerEvent('chat:addSuggestion', '/unwanted', 'Clear a citizen wanted status (LEO)', {
    { name = 'id', help = 'Player server id' },
})

----------------------------------------------------------------------
-- NUI callbacks - data relays to the authoritative server callbacks.
-- Identical pattern for every one: forward the NUI payload verbatim and
-- return whatever the role-gated (LEO / court) server callback responds with.
----------------------------------------------------------------------

local RELAY_CALLBACKS = {
    'getDashboard',
    'searchVehicle', 'searchPerson',
    'getPenalCode', 'placeCharges',
    'getBolos', 'createBolo', 'cancelBolo',
    'getWarrants',
    'getReports', 'getReport', 'createReport',
    'getCameras', 'getBodycam',
    'setWanted',
}

for _, name in ipairs(RELAY_CALLBACKS) do
    RegisterNUICallback(name, function(data, cb)
        cb(lib.callback.await('pengu_mdt:' .. name, false, data or {}))
    end)
end

----------------------------------------------------------------------
-- NUI callbacks - client-only (no server hop).
----------------------------------------------------------------------

-- closeMdt {} - release focus, restore cam, ack the UI.
RegisterNUICallback('closeMdt', function(_, cb)
    closeMdt()
    cb('ok')
end)

-- viewCamera {id} - build a scripted CCTV cam at the requested feed, then hide
-- the cursor and start the mouse-look control thread. Triggered ONLY by a tile
-- click (cursor present, panel up); after this the cursor is gone and all look /
-- zoom / feed-switch / vision / exit input flows to the control thread.
RegisterNUICallback('viewCamera', function(data, cb)
    local feed = findFeed(data and data.id)
    if not feed then
        cb({ ok = false })
        return
    end

    exitCamera() -- swap cleanly if another feed was somehow already up

    -- Use SetCamRot (not PointCamAtCoord) so later mouse pan/tilt apply cleanly.
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(cam, true)
    SetTimecycleModifier('scanline_cam_cheap') -- cheap CCTV scanline look
    SetTimecycleModifierStrength(1.0)
    RenderScriptCams(true, false, 0, true, true)
    activeCam = cam
    camState = { heading = 0.0, pitch = 0.0, fov = 60.0, nightvision = false, thermal = false }

    -- Position the cam at the feed (and send the first camFeed to the overlay).
    local idx = 1
    for i, c in ipairs(CAMERAS) do
        if c.id == feed.id then
            idx = i
            break
        end
    end
    applyFeed(idx)

    SetNuiFocus(false, false) -- hide the cursor; hand input to the control thread
    startCamLookThread()

    cb({ ok = true, id = feed.id })
end)

-- exitCamera {} - harmless teardown fallback (no longer the cam-mode exit path;
-- Backspace -> leaveCamToPanel owns that). Kept so a stray NUI call is safe.
RegisterNUICallback('exitCamera', function(_, cb)
    exitCamera()
    cb({ ok = true })
end)

----------------------------------------------------------------------
-- Bodycam - REAL captures. REC ON grabs a frame immediately and then every
-- 60s while ON (stops on toggle OFF, resource stop or player unload). Each
-- frame mirrors the mugshot upload flow: screenshot-basic raw capture -> our
-- own NUI downscales it (downscaleBodycam / bodycamProcessed) -> the small
-- data URI goes to the server (pengu_mdt:storeBodycamCapture) which archives
-- it in pengu_mdt_bodycam (pruned to the newest 20 rows per officer).
----------------------------------------------------------------------

local bodycamOn = false
local bodycamToken = 0 -- bumped on every start/stop so a stale loop dies
local BODYCAM_INTERVAL_MS = 60000

local function snapBodycamFrame()
    exports['screenshot-basic']:requestScreenshot({ encoding = 'jpg', quality = 0.6 }, function(dataUri)
        -- re-check: the cam may have been toggled off while the shot was taken
        if bodycamOn and type(dataUri) == 'string' and dataUri:find('data:image', 1, true) then
            SendNUIMessage({ action = 'downscaleBodycam', src = dataUri })
        end
    end)
end

local function stopBodycam()
    if not bodycamOn then return end
    bodycamOn = false
    bodycamToken = bodycamToken + 1
    SendNUIMessage({ action = 'bodycamState', on = false }) -- keep the REC HUD in sync
end

local function startBodycam()
    if bodycamOn then return end
    bodycamOn = true
    bodycamToken = bodycamToken + 1
    local myToken = bodycamToken
    CreateThread(function()
        while bodycamOn and bodycamToken == myToken do
            snapBodycamFrame()
            Wait(BODYCAM_INTERVAL_MS)
        end
    end)
end

RegisterNUICallback('toggleBodycam', function(_, cb)
    if not isLeo() then -- court users can view the archive but never record
        stopBodycam()
        cb({ on = false })
        return
    end
    if bodycamOn then stopBodycam() else startBodycam() end
    cb({ on = bodycamOn })
end)

-- The NUI returns the downscaled bodycam frame; ship it to the server archive.
RegisterNUICallback('bodycamProcessed', function(data, cb)
    cb('ok')
    if bodycamOn and type(data) == 'table'
       and type(data.src) == 'string' and data.src ~= '' then
        TriggerServerEvent('pengu_mdt:storeBodycamCapture', data.src)
    end
end)

-- Bodycam must not survive a character unload (job may change on next login).
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    stopBodycam()
end)

----------------------------------------------------------------------
-- Booking camera (officer-driven, from the pdloc 'mugshot' point). The officer
-- "takes out a camera": we ask for the individual's name, drop to first person
-- with a viewfinder overlay, and on [E] capture the framed view via screenshot-
-- basic. The raw shot is downscaled in OUR OWN NUI (downscaleMugshot) and the
-- small result is sent to the server (storeBookingMugshot) for the named citizen.
----------------------------------------------------------------------

local booking = { on = false, capturing = false, prevView = nil, first = nil, last = nil }

local function bookingCleanup()
    booking.on = false
    booking.capturing = false
    booking.first = nil
    booking.last = nil
    SendNUIMessage({ action = 'bookingViewfinder', on = false })
    if booking.prevView ~= nil then
        SetFollowPedCamViewMode(booking.prevView)
        booking.prevView = nil
    end
end

-- Capture the officer's current (first-person) view, then hand the raw shot to
-- our OWN NUI to downscale to ~50KB. The NUI posts the small image back via the
-- 'mugProcessed' callback. Nothing depends on screenshot-basic's NUI patch.
local function snapBookingPhoto()
    exports['screenshot-basic']:requestScreenshot({ encoding = 'jpg', quality = 0.7 }, function(dataUri)
        if type(dataUri) == 'string' and dataUri:find('data:image', 1, true) then
            SendNUIMessage({ action = 'downscaleMugshot', src = dataUri })
        else
            bookingCleanup()
            lib.notify({ title = 'Booking Camera', description = 'Capture failed - try again.', type = 'error' })
        end
    end)
end

-- Exported so pengu_core's pdloc 'mugshot' point can launch the flow.
local function startBookingMugshot()
    if booking.on then return end
    if not isLeo() then
        lib.notify({ title = 'Booking Camera', description = 'On-duty officers only.', type = 'error' })
        return
    end
    local input = lib.inputDialog('Booking Photo', {
        { type = 'input', label = 'First name', required = true, max = 30 },
        { type = 'input', label = 'Last name',  required = true, max = 30 },
    })
    if not input then return end
    local first = (input[1] or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local last  = (input[2] or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if first == '' or last == '' then return end

    booking.on = true
    booking.capturing = false
    booking.first = first
    booking.last = last
    booking.prevView = GetFollowPedCamViewMode()
    SetFollowPedCamViewMode(4) -- first person: a clean shot of whoever is framed
    SendNUIMessage({ action = 'bookingViewfinder', on = true, name = first .. ' ' .. last })

    CreateThread(function()
        while booking.on do
            Wait(0)
            HideHudAndRadarThisFrame() -- keep the HUD/minimap out of the photo
            if not booking.capturing then
                if IsControlJustPressed(0, 38) then          -- E = capture
                    booking.capturing = true
                    SendNUIMessage({ action = 'bookingViewfinder', on = false })
                    snapBookingPhoto()
                    SetTimeout(8000, function() if booking.on then bookingCleanup() end end) -- safety
                elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 200) then -- Backspace / ESC = cancel
                    bookingCleanup()
                    lib.notify({ title = 'Booking Camera', description = 'Cancelled.', type = 'inform' })
                    return
                end
            end
        end
    end)
end
exports('startBookingMugshot', startBookingMugshot)

-- The NUI returns the downscaled photo; send it (small) to the server, then
-- restore the officer's view.
RegisterNUICallback('mugProcessed', function(data, cb)
    cb('ok')
    local first, last = booking.first, booking.last
    bookingCleanup()
    if first and last and type(data) == 'table'
       and type(data.src) == 'string' and data.src ~= '' then
        TriggerServerEvent('pengu_mdt:storeBookingMugshot', first, last, data.src)
    else
        lib.notify({ title = 'Booking Camera', description = 'Photo processing failed.', type = 'error' })
    end
end)

----------------------------------------------------------------------
-- Safety: release focus + restore cam if the resource stops while open.
----------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    exitCamera()
    bookingCleanup() -- restore view if the resource stops mid-booking
    stopBodycam()    -- kill the capture loop with the resource
    if isOpen then
        isOpen = false
        SetNuiFocus(false, false)
    end
end)
