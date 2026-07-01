-- PenguRP - Traffic & Pursuit (Phase 2.4)
-- Tunables for spike strips, radar gun, traffic cones, speed cameras,
-- parking tickets and carjacking. Loaded as a shared_script so `Config`
-- is visible on BOTH client and server. ASCII only.

Config = {}

-- LEO factions allowed to issue fines / use police tools (must be on duty).
Config.policeJobs = { police = true, bcso = true, sasp = true }

-- Detection unit for all speed readouts. 'mph' or 'kph'.
Config.speedUnit = 'mph'

-- ===================== FINES =====================
Config.fines = {
    speedingBase    = 200,    -- flat base added to every speeding fine
    speedingPerOver = 12,     -- $ per unit (mph/kph) over the limit
    speedingMax     = 3000,   -- hard cap on a single speeding fine
    parking         = 250,    -- flat illegal-parking ticket
    reckless        = 750,    -- reckless driving (radar manual add)
}

-- Society account (Renewed-Banking GetJobAccount) that receives paid fines.
-- Set to false to make fines simply leave the economy.
Config.payToSociety = 'police'

-- ===================== SPEED CAMERAS =====================
-- Fixed automated cameras. A vehicle passing within `radius` while over
-- `limit` is auto-fined (owner). Coords/limits are tunable; headings unused
-- by detection (kept for prop facing). Limits are in Config.speedUnit.
Config.spawnCameraProps = true
Config.cameraPropModel  = 'prop_cctv_cam_02a'
Config.cameraPoleModel  = 'prop_cctv_pole_02'
Config.cameraRadius     = 22.0   -- detection radius around each camera (m)
Config.cameraCooldown   = 60     -- seconds before the SAME plate can be re-fined by the SAME cam
Config.cameraDispatchOver = 35   -- units over limit that also pings dispatch (egregious)

Config.cameras = {
    { coords = vec3(  101.0, -1720.0, 28.5), heading = 320.0, limit = 70, label = 'La Mesa Fwy' },
    { coords = vec3( -510.0,  -700.0, 32.5), heading = 180.0, limit = 70, label = 'Olympic Fwy' },
    { coords = vec3( 1180.0, -1500.0, 34.0), heading =  90.0, limit = 70, label = 'Palomino Fwy' },
    { coords = vec3( 1700.0,  3300.0, 40.5), heading =  60.0, limit = 80, label = 'Senora Fwy (Sandy)' },
    { coords = vec3( -150.0,  6300.0, 31.0), heading = 215.0, limit = 60, label = 'Great Ocean Hwy (Paleto)' },
    { coords = vec3(-1500.0,  -500.0, 30.0), heading = 125.0, limit = 70, label = 'Del Perro Fwy' },
}

-- ===================== RADAR (vehicle-mounted ANPR HUD) =====================
-- Shown automatically when an on-duty officer is in a police-class vehicle. Reads
-- the plate + speed of every vehicle in a forward cone and lists them above the
-- speedometer. Arrow keys select a row; right arrow runs it in the MDT.
Config.radar = {
    range        = 35.0,   -- forward scan distance (m) - keep it short so only nearby traffic shows
    frontDot     = 0.62,   -- min dot(forward, dir-to-vehicle); ~0.62 ~= 52deg half-cone ahead
    maxPlates    = 6,      -- max rows shown
    scanMs       = 300,    -- rescan interval (ms)
    vehicleClass = 18,     -- GTA vehicle class that counts as a police car (18 = Emergency)
    upKey        = 172,    -- arrow up    (INPUT_CELLPHONE_UP)    - move selection up
    downKey      = 173,    -- arrow down  (INPUT_CELLPHONE_DOWN)  - move selection down
    runKey       = 175,    -- arrow right (INPUT_CELLPHONE_RIGHT) - run selected plate in MDT
}

-- ===================== SPIKE STRIPS =====================
Config.spikes = {
    model         = 'p_ld_stinger_s',
    burstSpeedMin = 15,    -- vehicle must exceed this (Config.speedUnit) for tires to pop
    triggerRadius = 2.6,   -- proximity (m) of a wheel-bearing vehicle to a spike
    maxPerOfficer = 6,     -- safety cap on deployed spikes per player
}

-- ===================== TRAFFIC CONES =====================
Config.cones = {
    model       = 'prop_mp_cone_01',
    maxPerPlayer = 12,
}

-- ===================== CARJACKING =====================
-- Pull a driver (NPC or player) out of a vehicle. Requires a drawn weapon.
Config.carjack = {
    requireWeapon = true,
    dispatch      = true,   -- ping ps-dispatch CarJacking on success
}
