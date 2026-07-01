-- PenguRP: data-driven PD interaction system (CLIENT).
-- Walk up to a marker and HOLD Left Alt; a lavender bar fills over ~1.5s, then the typed
-- action fires. Points are loaded from the DB (pengu_pd_locations) via the server callback
-- 'pengu_pd:getLocations' on load and rebuilt live on 'pengu_pd:locationsUpdated' (sent after
-- any /pdloc change), so the admin can move/add/remove points with no resource restart.
--
-- Self-contained: ox_target uses SetNuiFocusKeepInput, so IsControlPressed(0,19)=Left Alt still
-- reads even while the targeting eye is up, and these points carry NO ox_target options, so there
-- is no competing bind. Every action requires being in a legal faction (Factions.legal -
-- police/bcso/sasp/ambulance/...) on top of each system's own server-side enforcement
-- (per-faction armoury/fleet/wardrobe re-validation, ace gate on /pdloc, etc.).
--
-- Point types and their hold-Alt action (garage/clothing/armory open the lavender
-- "Police Services" NUI in pdmenu.css/js; the server re-validates the armory take):
--   armory   -> Police Services menu, Armory grid (issued gear, grade-gated server-side)
--   locker   -> open the faction's personal locker stash (Factions.lockerOf, per legal faction)
--   clothing -> Police Services menu, Wardrobe (Officer Uniform / SWAT / Body Armor / Remove)
--   garage   -> Police Services menu, Vehicle Bay (all cruisers, spawned at the marker)
--   duty     -> toggle on/off duty (QBCore:ToggleDuty + police:server:UpdateCurrentCops)

-- ===================== CLOTHING PRESETS (tune these in-game) =====================
-- Freemode component ids: 3 arms/torso, 4 legs, 6 shoes, 7 accessory, 8 undershirt,
-- 9 body-armor/vest, 11 top/jacket. Each uniform/swat entry = { comp, drawable, texture }.
-- These are reasonable vanilla GTA police/tactical values; refine them later in-game. More
-- granular customization (per-officer saved outfits) comes in a later pass.
local WARDROBE = {
    male = { -- mp_m_freemode_01
        uniform = { -- Officer Uniform (patrol)
            { 8, 58, 0 },  -- undershirt
            { 3,  0, 0 },  -- arms / torso
            { 11, 55, 0 }, -- top: police shirt
            { 4, 35, 0 },  -- legs: police trousers
            { 6, 25, 0 },  -- shoes: boots
            { 7,  0, 0 },  -- accessory: none
            { 9,  0, 0 },  -- vest off for plain uniform
        },
        swat = { -- SWAT / tactical
            { 8, 15, 0 },  -- undershirt
            { 3, 11, 0 },  -- arms
            { 11, 38, 0 }, -- top: tactical
            { 4, 31, 0 },  -- legs: tactical trousers
            { 6, 24, 0 },  -- shoes: tactical boots
            { 7,  5, 0 },  -- accessory
            { 9, 16, 0 },  -- heavy vest
        },
        armorVest = { comp = 9, drawable = 1, texture = 0 }, -- visible police vest (Body Armor)
    },
    female = { -- mp_f_freemode_01
        uniform = {
            { 8, 35, 0 },
            { 3,  0, 0 },
            { 11, 48, 0 },
            { 4, 34, 0 },
            { 6, 25, 0 },
            { 7,  0, 0 },
            { 9,  0, 0 },
        },
        swat = {
            { 8, 14, 0 },
            { 3, 11, 0 },
            { 11, 35, 0 },
            { 4, 32, 0 },
            { 6, 25, 0 },
            { 7,  5, 0 },
            { 9, 17, 0 },
        },
        armorVest = { comp = 9, drawable = 1, texture = 0 },
    },
}

-- ===================== POLICE CRUISERS (shown in the lavender garage menu) =====================
-- Flat list of every cruiser an officer can pull. Add `grade = N` to any entry to require grade
-- N+ (no grade = available to any on-duty officer). Models must exist on the server (these are the
-- base-game police / sheriff / unmarked lineup; add custom models the same way).
local CRUISERS = {
    { model = 'police',   label = 'Stanier Cruiser',  icon = 'car'  },
    { model = 'police2',  label = 'Buffalo Cruiser',  icon = 'car'  },
    { model = 'police3',  label = 'Interceptor',      icon = 'car'  },
    { model = 'police4',  label = 'Unmarked Cruiser', icon = 'car'  },
    { model = 'policeb',  label = 'Police Bike',      icon = 'bike' },
    { model = 'policet',  label = 'Transport Van',    icon = 'van'  },
    { model = 'riot',     label = 'Riot Van',         icon = 'van'  },
    { model = 'sheriff',  label = 'Sheriff Cruiser',  icon = 'car'  },
    { model = 'sheriff2', label = 'Sheriff SUV',      icon = 'suv'  },
    { model = 'fbi',        label = 'Unmarked Buffalo', icon = 'car'  },
    { model = 'fbi2',       label = 'Unmarked SUV',     icon = 'suv'  },
    { model = 'pranger',    label = 'Park Ranger',      icon = 'suv'  },
    { model = 'policeold1', label = 'Police Rancher',   icon = 'suv'  },
    { model = 'policeold2', label = 'Classic Cruiser',  icon = 'car'  },
    { model = 'riot2',      label = 'RCV (Riot)',       icon = 'van'  },
    { model = 'pbus',       label = 'Prisoner Bus',     icon = 'van'  },
}

-- Police Wardrobe options shown in the lavender clothing menu.
local CLOTHING_ITEMS = {
    { id = 'uniform',     name = 'Officer Uniform', meta = 'Standard patrol',   icon = 'shirt'  },
    { id = 'swat',        name = 'SWAT / Tactical', meta = 'Tactical loadout',  icon = 'vest'   },
    { id = 'armor',       name = 'Body Armor',      meta = 'Equip vest (100)',  icon = 'armor'  },
    { id = 'removearmor', name = 'Remove Armor',    meta = 'Take off the vest', icon = 'remove' },
}

-- Officer grade level (0 if unknown).
local function gradeOf()
    local d = exports.qbx_core:GetPlayerData()
    return (d and d.job and d.job.grade and d.job.grade.level) or 0
end

-- Open the lavender Police Services menu in a mode with a list of cards. Holds the
-- garage point so a cruiser spawns where the marker sits.
local pdGaragePoint = nil
local function openPdMenu(mode, sub, headIcon, items, footer)
    -- Title the drawer with the viewer's faction (LSPD / BCSO / SASP / EMS ...), not a hardcoded
    -- "POLICE", so every legal faction sees its own branding. Computed inline because myFaction()
    -- is declared further down. The marker loop only opens this for on-duty legal members.
    local d  = exports.qbx_core:GetPlayerData()
    local jn = d and d.job and d.job.name
    local label = (jn and Factions.isLegal(jn) and Factions.labelOf('legal', jn)) or 'Police'
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openPdMenu',
        mode = mode, sub = sub, headIcon = headIcon, items = items, footer = footer,
        title = label .. ' <span>Services</span>',
    })
end
-- ============================================================================================

-- Hold-Alt visuals + tuning (unchanged from the original armoury implementation).
local DRAW_DIST = 12.0
local USE_DIST  = 1.8
local PARK_DIST = 3.4  -- drive-in radius for 'parking' points (cars are big)
local HELIPAD_DIST = 7.0 -- land-to-store radius for 'helipad' points (helicopters are bigger + land imprecisely)
local HOLD_MS   = 1500
local ALT       = 19 -- INPUT_CHARACTER_WHEEL = Left Alt

-- Default hint labels per type (used only if a DB row has no label).
local TYPE_HINT = {
    armory   = 'Armoury',
    locker   = 'Locker',
    clothing = 'Wardrobe',
    garage   = 'Garage',
    duty     = 'Toggle Duty',
    mugshot  = 'Booking Camera',
    parking  = 'Parking',
    cell     = 'Jail Cell',
    lobby    = 'Release Lobby',
    fingerprint = 'Fingerprint Scanner',
    helipad  = 'Helipad',
}

-- ============================ shared helpers ============================

-- The player's legal-faction job name (any Factions.legal key) or nil. Drives every PD/legal
-- point: only members of a legal faction interact, and faction-scoped points filter on this.
local function myFaction()
    local d = exports.qbx_core:GetPlayerData()
    local job = d and d.job
    if job and Factions.isLegal(job.name) then return job.name end
    return nil
end

local function altHeld()
    return IsControlPressed(0, ALT) or IsDisabledControlPressed(0, ALT)
end

local function drawHint(text)
    SetTextFont(4); SetTextScale(0.4, 0.4); SetTextColour(255, 255, 255, 220)
    SetTextOutline(); SetTextCentre(true)
    SetTextEntry('STRING'); AddTextComponentString(text)
    DrawText(0.5, 0.60)
end

local function drawProgress(p)
    DrawRect(0.5, 0.62, 0.152, 0.020, 0, 0, 0, 150)
    local w = 0.14 * p
    DrawRect(0.5 - 0.07 + w / 2, 0.62, w, 0.012, 225, 199, 249, 235)
end

local function genderKey()
    return GetEntityModel(PlayerPedId()) == GetHashKey('mp_m_freemode_01') and 'male' or 'female'
end

-- ============================ point actions ============================

-- armory: lavender grid of issued gear. The authoritative list (+ counts / weapon
-- metadata / grade) lives server-side; we fetch it for display and the server
-- re-validates on take. Grade-locked items render dimmed with a badge.
local function openArmoury()
    local res = lib.callback.await('pengu_pd:getArmoury', false) or { items = {}, canManage = false }
    local list = type(res.items) == 'table' and res.items or {}
    local canManage = res.canManage == true
    local grade = gradeOf()
    local items = {}
    for _, a in ipairs(list) do
        local locked = a.grade and a.grade > 0 and grade < a.grade
        items[#items + 1] = {
            id = a.item, name = a.label, icon = a.icon,
            meta = locked and ('Requires grade ' .. a.grade) or nil,
            badge = (a.grade and a.grade > 0) and ('G' .. a.grade) or nil,
            badgeKind = locked and 'danger' or nil,
            locked = locked,
        }
    end
    if canManage then
        items[#items + 1] = {
            id = '__armoryManage__', name = 'Manage Armory', meta = 'Add / remove / grade',
            icon = 'gear', badge = 'CHIEF',
        }
    end
    openPdMenu('armory', 'Armory', 'armor', items,
        '<b>Click</b> to draw gear &nbsp;&middot;&nbsp; <b>Esc</b> to close')
end

-- locker: open the shared police locker stash (registered by qbx_police, no location gate).
local function openLocker()
    -- Each legal faction opens its OWN personal locker (police/bcso/sasp -> 'policelocker',
    -- EMS+others -> pengu_locker_<job>), resolved from the shared registry. Server registers them.
    local fac = myFaction()
    local id = (fac and Factions.lockerOf(fac)) or 'policelocker'
    exports.ox_inventory:openInventory('stash', { id = id })
end

-- clothing: snapshot the player's CURRENT (civilian) outfit before the first uniform change, so
-- going off duty restores it ON THE SPOT (no illenium reloadSkin -> no ped model respawn / camera glitch / lag).
local CLOTH_COMPONENTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local CLOTH_PROPS = { 0, 1, 2, 6, 7 }
local savedOutfit = nil

local function snapshotOutfit()
    if savedOutfit then return end -- already captured the civ state this on-duty cycle
    local ped = PlayerPedId()
    local comps, props = {}, {}
    for _, c in ipairs(CLOTH_COMPONENTS) do
        comps[c] = { GetPedDrawableVariation(ped, c), GetPedTextureVariation(ped, c) }
    end
    for _, p in ipairs(CLOTH_PROPS) do
        props[p] = { GetPedPropIndex(ped, p), GetPedPropTextureIndex(ped, p) }
    end
    savedOutfit = { comps = comps, props = props }
end

local function restoreOutfit()
    if not savedOutfit then return end
    local ped = PlayerPedId()
    for c, v in pairs(savedOutfit.comps) do
        SetPedComponentVariation(ped, c, v[1], v[2], 0)
    end
    for p, v in pairs(savedOutfit.props) do
        if v[1] == -1 then ClearPedProp(ped, p) else SetPedPropIndex(ped, p, v[1], v[2], true) end
    end
    SetPedArmour(ped, 0) -- the police vest armor comes off with the uniform
    savedOutfit = nil
end

-- clothing: apply a preset component set (snapshots the civ outfit first), detecting gender.
local function applyPreset(preset)
    snapshotOutfit()
    local ped = PlayerPedId()
    for i = 1, #preset do
        local c = preset[i]
        SetPedComponentVariation(ped, c[1], c[2], c[3], 0)
    end
end

-- Capture the player's CURRENT outfit (components + props + gender) so a chief can
-- save it as a faction wardrobe preset. Same component/prop set as snapshotOutfit.
-- String keys keep the JSON an object (not a sparse array) across the round-trip.
local function captureCurrentOutfit()
    local ped = PlayerPedId()
    local comps, props = {}, {}
    for _, c in ipairs(CLOTH_COMPONENTS) do
        comps[tostring(c)] = { GetPedDrawableVariation(ped, c), GetPedTextureVariation(ped, c) }
    end
    for _, pr in ipairs(CLOTH_PROPS) do
        props[tostring(pr)] = { GetPedPropIndex(ped, pr), GetPedPropTextureIndex(ped, pr) }
    end
    return { comps = comps, props = props, gender = genderKey() }
end

-- Apply a stored custom outfit (snapshots the civ outfit first so off-duty restores it).
local function applyStoredOutfit(data)
    if type(data) ~= 'table' then return end
    snapshotOutfit()
    local ped = PlayerPedId()
    if type(data.comps) == 'table' then
        for c, v in pairs(data.comps) do
            local comp = tonumber(c)
            if comp and type(v) == 'table' then SetPedComponentVariation(ped, comp, v[1] or 0, v[2] or 0, 0) end
        end
    end
    if type(data.props) == 'table' then
        for pr, v in pairs(data.props) do
            local prop = tonumber(pr)
            if prop and type(v) == 'table' then
                if (v[1] or -1) == -1 then ClearPedProp(ped, prop) else SetPedPropIndex(ped, prop, v[1], v[2] or 0, true) end
            end
        end
    end
end

-- Wardrobe preset cache (menuId -> { kind, preset, components, gender }), filled by openWardrobe.
local wardrobePresets = {}

-- Apply a wardrobe choice by menu id (called from the menu-select callback).
local function applyClothing(id)
    local entry = wardrobePresets[id]
    if not entry then return end
    local kind = entry.kind or 'builtin'
    if kind == 'outfit' then
        applyStoredOutfit(entry.components)
        return
    elseif kind == 'armor' then
        snapshotOutfit()
        local ped = PlayerPedId()
        local set = WARDROBE[genderKey()]
        local v = (set and set.armorVest) or { comp = 9, drawable = 1, texture = 0 }
        SetPedArmour(ped, 100)
        SetPedComponentVariation(ped, v.comp, v.drawable, v.texture, 0)
        return
    elseif kind == 'removearmor' then
        local ped = PlayerPedId()
        SetPedArmour(ped, 0)
        SetPedComponentVariation(ped, 9, 0, 0, 0)
        return
    end
    -- builtin uniform / swat -> hardcoded component sets.
    local set = WARDROBE[genderKey()]
    if not set then return end
    if entry.preset == 'uniform' then applyPreset(set.uniform)
    elseif entry.preset == 'swat' then applyPreset(set.swat) end
end

local function openWardrobe()
    local res = lib.callback.await('pengu_pd:getWardrobe', false) or { items = {}, canManage = false }
    local list = type(res.items) == 'table' and res.items or {}
    local canManage = res.canManage == true
    local grade = gradeOf()
    local myGender = genderKey()
    wardrobePresets = {}
    local items = {}
    for _, c in ipairs(list) do
        -- Hide gender-specific outfits captured on the other body type (components
        -- would not map cleanly); 'any'/builtin presets always show.
        if not (c.gender == 'male' or c.gender == 'female') or c.gender == myGender then
            local mid = tostring(c.id)
            wardrobePresets[mid] = { kind = c.kind, preset = c.preset, components = c.components, gender = c.gender }
            local locked = c.grade and c.grade > 0 and grade < c.grade
            items[#items + 1] = {
                id = mid, name = c.name,
                meta = locked and ('Requires grade ' .. c.grade) or c.meta,
                icon = c.icon,
                badge = (c.grade and c.grade > 0) and ('G' .. c.grade) or nil,
                badgeKind = locked and 'danger' or nil,
                locked = locked,
            }
        end
    end
    if canManage then
        items[#items + 1] = {
            id = '__wardrobeManage__', name = 'Manage Wardrobe', meta = 'Add / remove / customize',
            icon = 'gear', badge = 'CHIEF',
        }
    end
    openPdMenu('clothing', 'Wardrobe', 'shirt', items,
        '<b>Click</b> to change outfit &nbsp;&middot;&nbsp; <b>Esc</b> to close')
end

-- garage: spawn a grade-authorized vehicle at the point coords/heading via the GLOBAL qbx callback
-- (warps the officer in + gives keys server-side). Moving the point with /pdloc moves the spawn.
-- Fleet cache (model -> { id, mods }) + manage permission, filled by openGarage.
local fleetCars = {}
local fleetCanManage = false
-- Air fleet (helipad) state. fleetManageAir disambiguates the SHARED fleetManage NUI callbacks
-- (reqGarage/reqManage/fleetAdd/...) so back-navigation routes to the air manager, not the car one.
local fleetManageAir = false
local pdHelipadPoint = nil   -- the helipad point whose Air Fleet menu is currently open
local airCars = {}           -- air fleet cache (id -> { model, mods }), filled by openHelipad
local airCanManage = false
local heliLeftPad = true     -- re-store guard: a just-spawned heli must leave the pad before it can be stored

-- Apply a chief-set mod PRESET to a freshly spawned vehicle. Every field is
-- optional; a missing field leaves the spawn default.
local function applyVehicleMods(veh, m)
    if not veh or veh == 0 or type(m) ~= 'table' then return end
    SetVehicleModKit(veh, 0)
    local perf = m.performance
    if perf then
        if perf.engine       then SetVehicleMod(veh, 11, perf.engine, false) end
        if perf.brakes       then SetVehicleMod(veh, 12, perf.brakes, false) end
        if perf.transmission then SetVehicleMod(veh, 13, perf.transmission, false) end
        if perf.suspension   then SetVehicleMod(veh, 15, perf.suspension, false) end
        if perf.armor        then SetVehicleMod(veh, 16, perf.armor, false) end
        if perf.turbo ~= nil then ToggleVehicleMod(veh, 18, perf.turbo and true or false) end
    end
    local w = m.wheels
    if w then
        if w.type   then SetVehicleWheelType(veh, w.type) end
        if w.design then SetVehicleMod(veh, 23, w.design, false) end
    end
    local col = m.colors
    if col then
        if col.primary   then SetVehicleCustomPrimaryColour(veh, col.primary[1], col.primary[2], col.primary[3]) end
        if col.secondary then SetVehicleCustomSecondaryColour(veh, col.secondary[1], col.secondary[2], col.secondary[3]) end
    end
    if m.tint then SetVehicleWindowTint(veh, m.tint) end
    local x = m.xenon
    if x then
        ToggleVehicleMod(veh, 22, x.on and true or false)
        if x.on and x.color and x.color >= 0 then SetVehicleXenonLightsColor(veh, x.color) end
    end
    local n = m.neon
    if n then
        SetVehicleNeonLightEnabled(veh, 0, n.left == true)
        SetVehicleNeonLightEnabled(veh, 1, n.right == true)
        SetVehicleNeonLightEnabled(veh, 2, n.front == true)
        SetVehicleNeonLightEnabled(veh, 3, n.back == true)
        if n.color then SetVehicleNeonLightsColour(veh, n.color[1], n.color[2], n.color[3]) end
    end
    if m.livery and m.livery > 0 then
        SetVehicleLivery(veh, m.livery)
        SetVehicleMod(veh, 48, m.livery, false)
    end
    if type(m.extras) == 'table' then
        for k, on in pairs(m.extras) do
            local ex = tonumber(k)
            if ex then SetVehicleExtra(veh, ex, on and 0 or 1) end -- 0 = on, 1 = off
        end
    end
end

local function spawnPolice(model, point, mods)
    local coords = vec4(point.coords.x, point.coords.y, point.coords.z, point.heading or 0.0)
    -- Per-faction plate prefix from the registry label (LSPD/BCSO/SASP/EMS), not a hardcoded
    -- 'LSPD', so an EMS ambulance reads EMS#### etc. Normalised to <=4 chars within the plate limit.
    local fac    = myFaction()
    local label  = fac and Factions.labelOf('legal', fac) or nil
    local prefix = (label and label:gsub('%s+', ''):sub(1, 4):upper()) or 'LSPD'
    local plate  = prefix .. tostring(math.random(1000, 9999))

    -- Primary: the qbx spawn (warps the officer in + grants keys server-side). It returns nil/0 for
    -- models NOT in qbx_core's vehicle registry (its type lookup hard-errors on those) and on transient
    -- owner-sync timeouts (it self-deletes the vehicle after 5s). So when it fails, fall back to our own
    -- robust spawn (pengu_pd:spawnFleetVehicle) which resolves the vehicle type safely and never
    -- self-deletes. `warped` tracks whether the officer was already seated (qbx) or we must warp them.
    local warped = true
    local netId = lib.callback.await('qbx_policejob:server:spawnVehicle', false, model, coords, plate, true)
    if not netId or netId == 0 then
        warped = false
        netId = lib.callback.await('pengu_pd:spawnFleetVehicle', false, model, coords.x, coords.y, coords.z, coords.w, plate)
    end
    if not netId or netId == 0 then
        TriggerEvent('chat:addMessage', { templateId = 'pengu:admin', args = { 'FLEET', ('Could not spawn %s - the spawn point may be blocked, or that model does not exist on this server.'):format(model), 'err' } })
        return
    end

    -- Authoritatively tag it as a fleet vehicle server-side so the parking pad + helipad ALWAYS accept
    -- it (the client-side tag below is skipped if the heli netId sync times out - common for big helis).
    TriggerServerEvent('pengu_pd:tagFleet', netId)

    -- lib.waitFor THROWS on timeout (ox_lib uses `errMessage or 'failed to resolve callback'`),
    -- so wrap it in pcall: a slow network sync just skips the cosmetic setup below without a
    -- script error. The vehicle already spawned server-side.
    local ok, veh = pcall(lib.waitFor, function()
        if NetworkDoesEntityExistWithNetworkId(netId) then
            return NetToVeh(netId)
        end
    end, 'pengu_pd: vehicle netId did not sync', 5000)

    if ok and veh and veh ~= 0 then
        if not warped then SetPedIntoVehicle(PlayerPedId(), veh, -1) end -- fallback path: warp client-side
        SetEntityHeading(veh, coords.w)
        SetVehicleFuelLevel(veh, 100.0)
        SetVehicleEngineOn(veh, true, true, false)
        if mods then applyVehicleMods(veh, mods) end
        -- Tag it as a fleet vehicle (replicated) so the parking pad accepts it even
        -- when it is an undercover/citizen or military model, not just class 18.
        Entity(veh).state:set('penguFleet', true, true)
    end
end

-- Before spawning a new aircraft on a helipad, clear any EMPTY fleet aircraft already sitting on the
-- pad so the new one doesn't spawn into it and fail/explode (the most common "I can only take one out"
-- cause). Only deletes unoccupied penguFleet aircraft within the pad radius - never an aircraft a
-- pilot is currently in (so a colleague hovering/landed in theirs is left alone).
local function clearHelipadAircraft(point)
    if not point or not point.coords then return end
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) then
            local class = GetVehicleClass(veh)
            if (class == 15 or class == 16) and Entity(veh).state.penguFleet == true
                and IsVehicleSeatFree(veh, -1) and GetVehicleNumberOfPassengers(veh) == 0
                and #(GetEntityCoords(veh) - point.coords) < HELIPAD_DIST then
                local tries = 0
                while not NetworkHasControlOfEntity(veh) and tries < 20 do
                    NetworkRequestControlOfEntity(veh); Wait(20); tries = tries + 1
                end
                SetEntityAsMissionEntity(veh, true, true)
                DeleteVehicle(veh)
                if DoesEntityExist(veh) then DeleteEntity(veh) end
            end
        end
    end
end

local openFleetManager -- forward decl (defined in the management block below)

-- garage: pull the player's FACTION fleet from the server (cars + chief mod
-- presets). Chiefs also get a "Manage Fleet" entry.
local function openGarage(point)
    fleetManageAir = false -- entering the CAR flow: route shared manager callbacks to the car fleet
    pdGaragePoint = point
    local res = lib.callback.await('pengu_pd:getFleet', false) or { cars = {} }
    fleetCanManage = res.canManage == true
    fleetCars = {}
    local grade = gradeOf()
    local items = {}
    for _, c in ipairs(res.cars or {}) do
        -- Key by the unique row id (a chief may list the same model twice with
        -- different presets), NOT by model - models can collide.
        local key = tostring(c.id)
        fleetCars[key] = { model = c.model, mods = c.mods }
        local gated  = c.grade and c.grade > 0
        local locked = gated and grade < c.grade
        items[#items + 1] = {
            id = key, name = c.label, icon = c.icon or 'car',
            meta = locked and ('Requires grade ' .. c.grade) or nil,
            badge = gated and ('G' .. c.grade) or nil,
            badgeKind = locked and 'danger' or nil,
            locked = locked,
        }
    end
    if fleetCanManage then
        items[#items + 1] = {
            id = '__manage__', name = 'Manage Fleet', meta = 'Add / remove / mods',
            icon = 'gear', badge = 'CHIEF',
        }
    end
    openPdMenu('garage', 'Vehicle Bay', 'car', items,
        '<b>Click</b> a vehicle to pull it out &nbsp;&middot;&nbsp; <b>Esc</b> to close')
end

-- helipad: pull the faction AIR fleet (helicopters) and spawn the chosen one on the pad. Mirrors
-- openGarage but uses the air fleet (getAirFleet) + the 'heli' icon. The point is held so the heli
-- spawns where the pad sits; landing a fleet aircraft back on the pad stores it (marker loop below).
local function openHelipad(point)
    fleetManageAir = false -- entering the AIR spawn menu; the manage entry flips this true (openAirFleetManager)
    pdHelipadPoint = point
    local res = lib.callback.await('pengu_pd:getAirFleet', false) or { cars = {} }
    airCanManage = res.canManage == true
    airCars = {}
    local grade = gradeOf()
    local items = {}
    for _, c in ipairs(res.cars or {}) do
        local key = tostring(c.id)
        airCars[key] = { model = c.model, mods = c.mods }
        local gated  = c.grade and c.grade > 0
        local locked = gated and grade < c.grade
        items[#items + 1] = {
            id = key, name = c.label, icon = c.icon or 'heli',
            meta = locked and ('Requires grade ' .. c.grade) or nil,
            badge = gated and ('G' .. c.grade) or nil,
            badgeKind = locked and 'danger' or nil,
            locked = locked,
        }
    end
    if airCanManage then
        items[#items + 1] = {
            id = '__manageAir__', name = 'Manage Air Fleet', meta = 'Add / remove / mods',
            icon = 'gear', badge = 'CHIEF',
        }
    end
    openPdMenu('helipad', 'Air Fleet', 'heli', items,
        '<b>Click</b> an aircraft to take it out &nbsp;&middot;&nbsp; <b>Esc</b> to close')
end

-- ===================== Fleet management (chief / faction lead) =====================
-- The manager / vehicle picker / mod editor all render in the lavender NUI
-- (pdmenu.js). Here we only fetch data, enumerate every available vehicle, and
-- relay the NUI's actions to the server.
local fleetManageCache = {}   -- last fetched fleet, so fleetEditOpen can find a car by id
local vehicleListCache        -- all spawnable vehicles { model, label }, built once

local function getAllVehicles()
    if vehicleListCache then return vehicleListCache end
    local out, models = {}, GetAllVehicleModels()
    for i = 1, #models do
        local model = models[i]
        local lbl = GetLabelText(GetDisplayNameFromVehicleModel(GetHashKey(model)))
        if not lbl or lbl == '' or lbl == 'NULL' then lbl = model end
        out[#out + 1] = { model = string.lower(model), label = lbl }
    end
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    vehicleListCache = out
    return out
end

-- Aircraft-only subset (class 15 heli / 16 plane) for the AIR fleet picker, built once.
local aircraftListCache
local function getAllAircraft()
    if aircraftListCache then return aircraftListCache end
    local out = {}
    for _, v in ipairs(getAllVehicles()) do
        local class = GetVehicleClassFromName(GetHashKey(v.model))
        if class == 15 or class == 16 then out[#out + 1] = v end
    end
    aircraftListCache = out
    return out
end

local function iconForModel(model)
    local class = GetVehicleClassFromName(GetHashKey(model))
    if class == 8 then return 'bike'
    elseif class == 2 or class == 9 then return 'suv'
    elseif class == 11 or class == 12 or class == 20 then return 'van'
    elseif class == 15 or class == 16 then return 'heli' end -- 15=Helicopters, 16=Planes
    return 'car'
end

-- Open the lavender fleet manager (chief only): fetch the fleet + render in the NUI.
openFleetManager = function()
    local res = lib.callback.await('pengu_pd:getFleet', false) or { cars = {} }
    if not res.canManage then return end
    fleetManageCache = res.cars or {}
    SendNUIMessage({ action = 'fleetManage', cars = fleetManageCache, faction = res.faction })
end

-- Open the lavender fleet manager for the AIR fleet (chief only). Reuses the SAME 'fleetManage' NUI
-- view; fleetManageAir=true routes the shared add/remove/mods/back callbacks to the air fleet.
local function openAirFleetManager()
    fleetManageAir = true
    local res = lib.callback.await('pengu_pd:getAirFleet', false) or { cars = {} }
    if not res.canManage then return end
    fleetManageCache = res.cars or {}
    SendNUIMessage({ action = 'fleetManage', cars = fleetManageCache, faction = res.faction })
end

RegisterNUICallback('fleetPickerOpen', function(_, cb)
    cb('ok')
    -- Air manager sees aircraft only; car manager sees the full list.
    local vehicles = fleetManageAir and getAllAircraft() or getAllVehicles()
    SendNUIMessage({ action = 'fleetPicker', vehicles = vehicles })
end)

RegisterNUICallback('fleetEditOpen', function(data, cb)
    cb('ok')
    local id = data and data.id
    for _, c in ipairs(fleetManageCache) do
        if tostring(c.id) == tostring(id) then
            SendNUIMessage({ action = 'fleetEditor', car = c })
            return
        end
    end
end)

RegisterNUICallback('fleetAdd', function(data, cb)
    cb('ok')
    if data and type(data.model) == 'string' and data.model ~= '' then
        local ev = fleetManageAir and 'pengu_pd:airFleetAdd' or 'pengu_pd:fleetAdd'
        TriggerServerEvent(ev, {
            model = data.model, label = data.label, icon = iconForModel(data.model), grade = 0,
        })
    end
    Wait(350)
    if fleetManageAir then openAirFleetManager() else openFleetManager() end
end)

RegisterNUICallback('fleetRemove', function(data, cb)
    cb('ok')
    if data and data.id then
        local ev = fleetManageAir and 'pengu_pd:airFleetRemove' or 'pengu_pd:fleetRemove'
        TriggerServerEvent(ev, tonumber(data.id) or data.id)
    end
    Wait(300)
    if fleetManageAir then openAirFleetManager() else openFleetManager() end
end)

RegisterNUICallback('fleetSetMods', function(data, cb)
    cb('ok')
    if data and data.id and type(data.mods) == 'table' then
        local ev = fleetManageAir and 'pengu_pd:airFleetSetMods' or 'pengu_pd:fleetSetMods'
        TriggerServerEvent(ev, tonumber(data.id) or data.id, data.mods)
    end
end)

RegisterNUICallback('reqManage', function(_, cb)
    cb('ok')
    if fleetManageAir then openAirFleetManager() else openFleetManager() end
end)

RegisterNUICallback('reqGarage', function(_, cb)
    cb('ok')
    -- goBack() from the manager view: route to whichever spawn menu we came from.
    if fleetManageAir then
        if pdHelipadPoint then openHelipad(pdHelipadPoint) end
    else
        if pdGaragePoint then openGarage(pdGaragePoint) end
    end
end)

-- ===================== Armory management (chief / faction lead) =====================
local function openArmoryManager()
    local res = lib.callback.await('pengu_pd:getArmoryForManage', false)
    if not res then return end
    SendNUIMessage({ action = 'armoryManage', items = res.items, catalog = res.catalog, faction = res.faction })
end

local function openWardrobeManager()
    local res = lib.callback.await('pengu_pd:getWardrobeForManage', false)
    if not res then return end
    SendNUIMessage({ action = 'wardrobeManage', items = res.items, faction = res.faction })
end

RegisterNUICallback('reqArmoryManage', function(_, cb)
    cb('ok')
    openArmoryManager()
end)

RegisterNUICallback('reqWardrobeManage', function(_, cb)
    cb('ok')
    openWardrobeManager()
end)

RegisterNUICallback('reqArmory', function(_, cb)
    cb('ok')
    openArmoury()
end)

RegisterNUICallback('reqWardrobe', function(_, cb)
    cb('ok')
    openWardrobe()
end)

RegisterNUICallback('armoryPickerOpen', function(_, cb)
    cb('ok')
    -- Full ox_inventory catalog so chiefs can stock ANY item (not just the curated list).
    local all = lib.callback.await('pengu_pd:getAllItems', false) or {}
    SendNUIMessage({ action = 'armoryPicker', catalog = all })
end)

RegisterNUICallback('armoryAdd', function(data, cb)
    cb('ok')
    if data and type(data.item) == 'string' and data.item ~= '' then
        TriggerServerEvent('pengu_pd:armoryAdd', data.item)
    end
    Wait(350)
    openArmoryManager()
end)

RegisterNUICallback('armoryRemove', function(data, cb)
    cb('ok')
    if data and data.id then TriggerServerEvent('pengu_pd:armoryRemove', tonumber(data.id) or data.id) end
    Wait(300)
    openArmoryManager()
end)

RegisterNUICallback('armorySetGrade', function(data, cb)
    cb('ok')
    if data and data.id and data.grade ~= nil then
        TriggerServerEvent('pengu_pd:armorySetGrade', tonumber(data.id) or data.id, tonumber(data.grade) or 0)
    end
end)

RegisterNUICallback('armorySetCount', function(data, cb)
    cb('ok')
    if data and data.id and data.count ~= nil then
        TriggerServerEvent('pengu_pd:armorySetCount', tonumber(data.id) or data.id, tonumber(data.count) or 1)
    end
end)

RegisterNUICallback('wardrobeSetGrade', function(data, cb)
    cb('ok')
    if data and data.id and data.grade ~= nil then
        TriggerServerEvent('pengu_pd:wardrobeSetGrade', tonumber(data.id) or data.id, tonumber(data.grade) or 0)
    end
end)

RegisterNUICallback('wardrobeToggle', function(data, cb)
    cb('ok')
    if data and data.id and data.enabled ~= nil then
        TriggerServerEvent('pengu_pd:wardrobeToggle', tonumber(data.id) or data.id, data.enabled == true)
    end
end)

-- Chief: capture the player's CURRENT outfit and save it as a faction preset.
RegisterNUICallback('wardrobeAddCurrent', function(data, cb)
    cb('ok')
    local name = (data and type(data.name) == 'string' and data.name ~= '') and data.name or 'Outfit'
    local outfit = captureCurrentOutfit()
    TriggerServerEvent('pengu_pd:wardrobeAdd', {
        name = name,
        components = { comps = outfit.comps, props = outfit.props },
        gender = outfit.gender,
    })
    Wait(350)
    openWardrobeManager()
end)

-- ============================ clothing designer (chief) ============================
-- A friendly in-house clothing editor (replaces the numeric illenium UI for this flow):
-- a framed camera on the ped + a side panel of NAMED categories with Prev/Next arrows
-- for each item + colour, live-previewed on the ped, then saved as a faction preset.
-- Covers exactly the components/props captureCurrentOutfit stores.
local CLOTH_CATS = {
    { key = 'top',     label = 'Top / Shirt',  kind = 'comp', id = 11 },
    { key = 'under',   label = 'Undershirt',   kind = 'comp', id = 8  },
    { key = 'arms',    label = 'Arms',         kind = 'comp', id = 3  },
    { key = 'vest',    label = 'Vest / Armor', kind = 'comp', id = 9  },
    { key = 'pants',   label = 'Pants',        kind = 'comp', id = 4  },
    { key = 'shoes',   label = 'Shoes',        kind = 'comp', id = 6  },
    { key = 'bag',     label = 'Bag',          kind = 'comp', id = 5  },
    { key = 'acc',     label = 'Accessory',    kind = 'comp', id = 7  },
    { key = 'decal',   label = 'Decal',        kind = 'comp', id = 10 },
    { key = 'mask',    label = 'Mask',         kind = 'comp', id = 1  },
    { key = 'hat',     label = 'Hat',          kind = 'prop', id = 0  },
    { key = 'glasses', label = 'Glasses',      kind = 'prop', id = 1  },
    { key = 'ears',    label = 'Earrings',     kind = 'prop', id = 2  },
    { key = 'watch',   label = 'Watch',        kind = 'prop', id = 6  },
    { key = 'brace',   label = 'Bracelet',     kind = 'prop', id = 7  },
}

local clothState = { active = false, orig = nil, cam = nil, vals = {}, byKey = {} }

-- Current item/colour position + counts for a category, so the NUI can show "5 / 120".
-- item: comp 0..max-1 ; prop -1(none)..max-1. colour: 0..max-1.
local function clothInfo(key)
    local cat, v = clothState.byKey[key], clothState.vals[key]
    if not cat or not v then return nil end
    local ped = PlayerPedId()
    local itemMax, colorMax
    if cat.kind == 'comp' then
        itemMax  = GetNumberOfPedDrawableVariations(ped, cat.id)
        colorMax = (v.draw >= 0) and GetNumberOfPedTextureVariations(ped, cat.id, v.draw) or 0
    else
        itemMax  = GetNumberOfPedPropDrawableVariations(ped, cat.id)
        colorMax = (v.draw >= 0) and GetNumberOfPedPropTextureVariations(ped, cat.id, v.draw) or 0
    end
    return { key = key, isProp = cat.kind == 'prop', item = v.draw, itemMax = itemMax, color = v.tex, colorMax = colorMax }
end

local function openClothCam(ped)
    local coords = GetEntityCoords(ped)
    local fwd = GetEntityForwardVector(ped)
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, coords.x + fwd.x * 2.0, coords.y + fwd.y * 2.0, coords.z + 0.2)
    PointCamAtEntity(cam, ped, 0.0, 0.0, 0.2, true)
    SetCamFov(cam, 50.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    return cam
end

local function teardownClothEditor()
    -- Restore the chief's own appearance (non-destructive: their character is unchanged).
    if clothState.orig then exports['illenium-appearance']:setPlayerAppearance(clothState.orig) end
    RenderScriptCams(false, false, 0, true, true)
    if clothState.cam then DestroyCam(clothState.cam, false) end
    clothState.active, clothState.cam, clothState.orig = false, nil, nil
    SendNUIMessage({ action = 'clothClose' })
    -- Unfreeze the CURRENT ped. illenium may REBUILD the ped during the appearance restore,
    -- so a handle captured before it would be stale and leave the new ped frozen ("stuck in
    -- place"). Unfreeze now AND once more after the rebuild settles.
    FreezeEntityPosition(PlayerPedId(), false)
    CreateThread(function()
        Wait(300)
        FreezeEntityPosition(PlayerPedId(), false)
    end)
end

local function openClothEditor(name)
    if clothState.active then return end -- guard against re-entry
    local ped = PlayerPedId()
    clothState.orig = exports['illenium-appearance']:getPedAppearance(ped)
    clothState.vals, clothState.byKey, clothState.active = {}, {}, true
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, true)
    clothState.cam = openClothCam(ped)
    local cats = {}
    for _, c in ipairs(CLOTH_CATS) do
        local draw, tex
        if c.kind == 'comp' then
            draw, tex = GetPedDrawableVariation(ped, c.id), GetPedTextureVariation(ped, c.id)
        else
            draw, tex = GetPedPropIndex(ped, c.id), GetPedPropTextureIndex(ped, c.id)
        end
        clothState.vals[c.key] = { draw = draw, tex = tex }
        clothState.byKey[c.key] = { kind = c.kind, id = c.id }
        cats[#cats + 1] = { key = c.key, label = c.label, info = clothInfo(c.key) }
    end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'clothOpen', name = name, cats = cats })
end

-- Reopen the wardrobe manager, or release focus cleanly if the chief lost boss status
-- (never leave the player focus-locked behind a hidden panel).
local function reopenWardrobeOrRelease()
    local res = lib.callback.await('pengu_pd:getWardrobeForManage', false)
    if res then
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'wardrobeManage', items = res.items, faction = res.faction })
    else
        SetNuiFocus(false, false)
    end
end

-- Chief: open the in-house clothing designer to build an outfit + save it as a preset.
RegisterNUICallback('wardrobeCustomize', function(data, cb)
    cb('ok')
    local name = (data and type(data.name) == 'string' and data.name ~= '') and data.name or 'Outfit'
    SendNUIMessage({ action = 'hideForEditor' })
    openClothEditor(name)
end)

-- Cycle an item (drawable) or colour (texture) for a category, live on the ped.
RegisterNUICallback('clothChange', function(data, cb)
    cb('ok')
    if not clothState.active or type(data) ~= 'table' or not data.key then return end
    local cat, v = clothState.byKey[data.key], clothState.vals[data.key]
    if not cat or not v then return end
    local ped = PlayerPedId()
    local dir = (data.dir == -1) and -1 or 1
    if data.target == 'color' then
        local maxTex
        if cat.kind == 'comp' then
            maxTex = GetNumberOfPedTextureVariations(ped, cat.id, v.draw)
        else
            if v.draw < 0 then return end
            maxTex = GetNumberOfPedPropTextureVariations(ped, cat.id, v.draw)
        end
        if maxTex < 1 then return end
        local t = v.tex + dir
        if t < 0 then t = maxTex - 1 elseif t >= maxTex then t = 0 end
        v.tex = t
    elseif cat.kind == 'comp' then
        local maxD = GetNumberOfPedDrawableVariations(ped, cat.id)
        if maxD < 1 then return end
        local d = v.draw + dir
        if d < 0 then d = maxD - 1 elseif d >= maxD then d = 0 end
        v.draw, v.tex = d, 0
    else
        local maxD = GetNumberOfPedPropDrawableVariations(ped, cat.id)
        local d = v.draw + dir
        if d < -1 then d = maxD - 1 elseif d >= maxD then d = -1 end -- -1 = none
        v.draw, v.tex = d, 0
    end
    if cat.kind == 'comp' then
        SetPedComponentVariation(ped, cat.id, v.draw, v.tex, 0)
    elseif v.draw < 0 then
        ClearPedProp(ped, cat.id)
    else
        SetPedPropIndex(ped, cat.id, v.draw, v.tex, true)
    end
    SendNUIMessage({ action = 'clothUpdate', info = clothInfo(data.key) })
end)

RegisterNUICallback('clothRotate', function(data, cb)
    cb('ok')
    if not clothState.active then return end
    local ped = PlayerPedId()
    SetEntityHeading(ped, GetEntityHeading(ped) + ((data and data.dir == -1) and -25.0 or 25.0))
end)

RegisterNUICallback('clothSave', function(data, cb)
    cb('ok')
    if not clothState.active then return end
    local name = (data and type(data.name) == 'string' and data.name ~= '') and data.name or 'Outfit'
    local outfit = captureCurrentOutfit()
    TriggerServerEvent('pengu_pd:wardrobeAdd', {
        name = name,
        components = { comps = outfit.comps, props = outfit.props },
        gender = outfit.gender,
    })
    teardownClothEditor()
    Wait(300)
    reopenWardrobeOrRelease()
end)

RegisterNUICallback('clothCancel', function(_, cb)
    cb('ok')
    if not clothState.active then return end
    teardownClothEditor()
    Wait(300)
    reopenWardrobeOrRelease()
end)

-- Safety: if the resource stops while the designer is open, never leave the player
-- stuck in a scripted camera with a frozen ped.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false) -- always release focus so a restart with the PD menu (or any NUI) open never freezes input
    if clothState.active then
        if clothState.orig then
            pcall(function() exports['illenium-appearance']:setPlayerAppearance(clothState.orig) end)
        end
        RenderScriptCams(false, false, 0, true, true)
        if clothState.cam then DestroyCam(clothState.cam, false) end
        FreezeEntityPosition(PlayerPedId(), false)
        SetNuiFocus(false, false)
    end
end)

RegisterNUICallback('wardrobeRemove', function(data, cb)
    cb('ok')
    if data and data.id then TriggerServerEvent('pengu_pd:wardrobeRemove', tonumber(data.id) or data.id) end
    Wait(300)
    openWardrobeManager()
end)

RegisterNUICallback('wardrobeRename', function(data, cb)
    cb('ok')
    if data and data.id and type(data.name) == 'string' and data.name ~= '' then
        TriggerServerEvent('pengu_pd:wardrobeRename', tonumber(data.id) or data.id, data.name)
    end
end)

-- Menu close: release NUI focus.
RegisterNUICallback('pdMenuClose', function(_, cb)
    SetNuiFocus(false, false)
    pdGaragePoint = nil -- drop the stale garage reference
    cb('ok')
end)

-- Menu card click. garage spawns + closes; clothing / armory stay open so the
-- officer can grab several. The server re-validates the armory take.
RegisterNUICallback('pdMenuSelect', function(data, cb)
    local mode = data and data.mode
    local id   = data and data.id
    if mode == 'garage' then
        if id == '__manage__' then
            cb({ close = false }) -- keep the drawer open + focused; just switch to the manager view
            openFleetManager()
            return
        end
        local pt = pdGaragePoint -- capture before the close clears it
        local carInfo = fleetCars[id]
        SetNuiFocus(false, false)
        cb({ close = true })
        if pt and carInfo then spawnPolice(carInfo.model, pt, carInfo.mods) end
        return
    elseif mode == 'helipad' then
        if id == '__manageAir__' then
            cb({ close = false }) -- keep the drawer open + focused; switch to the air manager view
            openAirFleetManager()
            return
        end
        local pt = pdHelipadPoint -- capture before the close clears it
        local heli = airCars[id]
        SetNuiFocus(false, false)
        cb({ close = true })
        heliLeftPad = false -- arm the guard: the heli spawns with the pilot inside, within HELIPAD_DIST
        if pt and heli then
            clearHelipadAircraft(pt) -- swap: clear an empty fleet aircraft already on the pad first
            spawnPolice(heli.model, pt, heli.mods)
        end
        return
    elseif mode == 'clothing' then
        if id == '__wardrobeManage__' then
            cb({ close = false })
            openWardrobeManager()
            return
        end
        if id then applyClothing(id) end
        cb({ close = false })
        return
    elseif mode == 'armory' then
        if id == '__armoryManage__' then
            cb({ close = false })
            openArmoryManager()
            return
        end
        if id then TriggerServerEvent('pengu_pd:takeArmouryItem', id) end
        cb({ close = false })
        return
    end
    cb({ close = false })
end)

-- duty: mirror qbx_police ToggleDuty so the cop count stays in sync.
local function toggleDuty()
    TriggerServerEvent('QBCore:ToggleDuty')
    TriggerServerEvent('police:server:UpdateCurrentCops')
end

-- mugshot: hand off to the MDT booking-camera flow (asks for a name, frames a
-- first-person shot, captures via screenshot-basic, updates the MDT mugshot).
local function bookingCamera()
    exports.pengu_mdt:startBookingMugshot()
end

-- parking: store (delete) the EMERGENCY vehicle the officer drives into the
-- checkpoint. Triggered by the drive-in detection in the loop below - NOT by
-- hold-Alt - so parkingNoop is only here so the point loads + draws its marker.
local parkingBusy = false

local function parkVehicle(veh)
    local tries = 0
    while veh ~= 0 and not NetworkHasControlOfEntity(veh) and tries < 25 do
        NetworkRequestControlOfEntity(veh)
        Wait(40); tries = tries + 1
    end
    SetVehicleHasBeenOwnedByPlayer(veh, false)
    SetEntityAsMissionEntity(veh, true, true)
    DeleteVehicle(veh)
    if DoesEntityExist(veh) then DeleteEntity(veh) end
    TriggerEvent('chat:addMessage', { templateId = 'pengu:admin', args = { 'GARAGE', 'Vehicle parked.', 'ok' } })
end

local function parkingNoop() end

-- A vehicle counts as fleet (parkable / storable) if it was tagged on spawn (penguFleet), is an
-- emergency class (18), OR its MODEL is a known fleet model. The model check is replication-timing
-- independent, so a freshly-pulled heli is recognised immediately even if its per-entity penguFleet
-- state has not synced yet (closes the "only faction aircraft can be stored" race for big helis).
local function isFleetVehicle(veh)
    if Entity(veh).state.penguFleet == true then return true end
    if GetVehicleClass(veh) == 18 then return true end
    local fm = GlobalState.penguFleetModels
    return fm ~= nil and fm[GetEntityModel(veh)] == true
end

-- 'cell' (jail) and 'lobby' (release) are pure visual markers; the actual jailing/release is
-- driven by the /jail, /unjail and /release commands (server/jail.lua), not hold-Alt. They still
-- need an ACTIONS entry or rebuildPoints() would silently drop the rows and the marker would
-- never draw.
local function jailMarkerNoop() end

-- fingerprint: scan the NEAREST player's prints onto their MDT record. Shared by the hold-Alt point
-- action and the /collectprints command. Finds the closest player ped (players carry a citizenid;
-- NPCs are excluded since GetActivePlayers only returns players) and asks the MDT server to upsert.
local PRINT_DIST = 3.0
local function nearestPlayerServerId(maxDist)
    local myPed = cache.ped
    local myPos = GetEntityCoords(myPed)
    local bestId, bestD = nil, maxDist
    for _, pl in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pl)
        if ped ~= 0 and ped ~= myPed and DoesEntityExist(ped) then
            local d = #(GetEntityCoords(ped) - myPos)
            if d < bestD then bestD = d; bestId = GetPlayerServerId(pl) end
        end
    end
    return bestId
end
local function collectPrints()
    local targetSrc = nearestPlayerServerId(PRINT_DIST)
    if not targetSrc then
        TriggerEvent('chat:addMessage', { templateId = 'pengu:admin', args = { 'PRINTS', 'No person close enough to print.', 'err' } })
        return
    end
    TriggerServerEvent('pengu_mdt:collectPrints', targetSrc)
end

local ACTIONS = {
    armory   = openArmoury,
    locker   = openLocker,
    clothing = openWardrobe,
    garage   = openGarage,
    duty     = toggleDuty,
    mugshot  = bookingCamera,
    parking  = parkingNoop,
    cell     = jailMarkerNoop,
    lobby    = jailMarkerNoop,
    fingerprint = collectPrints,
    helipad  = openHelipad,
}

-- ============================ point list (rebuilt live from the DB) ============================

local POINTS = {}

-- Convert DB rows -> in-memory POINTS with a resolved action. Unknown types are skipped.
local function rebuildPoints(rows)
    local t = {}
    if rows then
        for i = 1, #rows do
            local r = rows[i]
            local action = ACTIONS[r.type]
            if action then
                t[#t + 1] = {
                    type      = r.type,
                    label     = (r.label ~= nil and r.label ~= '') and r.label or (TYPE_HINT[r.type] or r.type),
                    coords    = vec3(r.x + 0.0, r.y + 0.0, r.z + 0.0),
                    heading   = (r.heading or 0.0) + 0.0,
                    invisible = (r.invisible == 1 or r.invisible == true),
                    faction   = (r.faction ~= nil and r.faction ~= '') and r.faction or '',
                    action    = action,
                }
            end
        end
    end
    POINTS = t
end

-- Fetch the current location list from the server and rebuild the points.
local function refreshLocations()
    local rows = lib.callback.await('pengu_pd:getLocations', false)
    rebuildPoints(rows)
end

-- Pull on resource load and whenever the player (re)loads into the session.
CreateThread(function()
    refreshLocations()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    refreshLocations()
end)

-- Live update after any /pdloc add/remove (server broadcasts the full list).
RegisterNetEvent('pengu_pd:locationsUpdated', function(rows)
    rebuildPoints(rows)
end)

-- ============================ marker + hold-Alt loop ============================

CreateThread(function()
    local holdStart, activePoint, opened = nil, nil, false
    local ringOn = false
    while true do
        local wait = 500
        local ringP, ringLabel = nil, nil
        local pdata = exports.qbx_core:GetPlayerData()
        local pjob = pdata and pdata.job
        local fac = (pjob ~= nil and Factions.isLegal(pjob.name)) and pjob.name or nil
        local onDuty = fac ~= nil and pjob.onduty == true
        if fac and #POINTS > 0 then
            local pos = GetEntityCoords(cache.ped)
            local near = nil
            -- 0..1 "breathing" value so the flat ground rings pulse (brightness + radius) together.
            local pulse = 0.5 + 0.5 * math.sin(GetGameTimer() / 350.0)
            for i = 1, #POINTS do
                local pt = POINTS[i]
                -- Faction scoping: '' = shared (every legal faction), else only that faction's
                -- members see/use it. Off-duty members can ONLY use the 'duty' point (to clock
                -- on); armoury, locker, wardrobe, garage and parking all require being ON duty.
                if (pt.faction == '' or pt.faction == fac) and (pt.type == 'duty' or onDuty) then
                    local dist = #(pos - pt.coords)
                    if dist < DRAW_DIST then
                        wait = 0
                        if pt.type == 'parking' then
                            -- A larger green drive-in ring. No hold-Alt: drive an emergency
                            -- vehicle in as the driver and it is stored automatically. The ring is
                            -- hidden when the point is invisible, but the drive-in still works.
                            if not pt.invisible then
                                local psz = 3.0 + pulse * 0.5
                                DrawMarker(25, pt.coords.x, pt.coords.y, pt.coords.z - 0.95,
                                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, psz, psz, psz,
                                    60, 200, 100, math.floor(50 + pulse * 90), false, false, 2, false, nil, nil, false)
                            end
                            local veh = GetVehiclePedIsIn(cache.ped, false)
                            if veh ~= 0 and dist < PARK_DIST and GetPedInVehicleSeat(veh, -1) == cache.ped then
                                -- Allow any vehicle pulled from the fleet (tagged on spawn,
                                -- incl. undercover citizen + military models), or any emergency
                                -- class vehicle as a fallback.
                                if isFleetVehicle(veh) then
                                    if not parkingBusy then
                                        parkingBusy = true
                                        local v = veh
                                        CreateThread(function() parkVehicle(v); Wait(2500); parkingBusy = false end)
                                    end
                                else
                                    drawHint('Only faction fleet vehicles can be parked here')
                                end
                            end
                        elseif pt.type == 'helipad' then
                            -- A cyan landing ring. On foot: hold-Alt opens the Air Fleet menu. As a
                            -- pilot of a fleet aircraft landed on the pad: auto-store it (like parking,
                            -- but gated to aircraft classes). heliLeftPad prevents the just-spawned heli
                            -- (which appears within the ring with the pilot inside) from instantly storing.
                            if not pt.invisible then
                                local hsz = 3.4 + pulse * 0.6
                                DrawMarker(25, pt.coords.x, pt.coords.y, pt.coords.z - 0.95,
                                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, hsz, hsz, hsz,
                                    80, 180, 230, math.floor(50 + pulse * 90), false, false, 2, false, nil, nil, false)
                            end
                            local veh = GetVehiclePedIsIn(cache.ped, false)
                            if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == cache.ped then
                                local class = GetVehicleClass(veh)
                                local isAir = (class == 15 or class == 16)
                                if dist >= HELIPAD_DIST then
                                    heliLeftPad = true -- the pilot has cleared the pad; re-store now allowed
                                elseif isAir and heliLeftPad and dist < HELIPAD_DIST then
                                    if isFleetVehicle(veh) then
                                        if not parkingBusy then
                                            parkingBusy = true
                                            local v = veh
                                            CreateThread(function() parkVehicle(v); Wait(2500); parkingBusy = false end)
                                        end
                                    else
                                        drawHint('Only faction aircraft can be stored on the helipad')
                                    end
                                elseif (not isAir) and dist < HELIPAD_DIST then
                                    drawHint('Only aircraft can be stored on the helipad')
                                end
                            elseif not near and dist < USE_DIST then
                                near = pt -- on foot near the pad: hold-Alt opens the Air Fleet menu
                            end
                        else
                            -- flat pulsing ground ring (type 25), hidden when the point is invisible
                            -- (the hold-Alt interaction + hint below still work either way).
                            if not pt.invisible then
                                local mr, mg, mb = 40, 110, 225            -- default: blue
                                if pt.type == 'cell'  then mr, mg, mb = 220, 60, 60 end   -- jail cell: red
                                if pt.type == 'lobby' then mr, mg, mb = 60, 200, 100 end  -- release lobby: green
                                if pt.type == 'fingerprint' then mr, mg, mb = 90, 200, 200 end -- print lab: teal
                                local rsz = 1.0 + pulse * 0.25
                                DrawMarker(25, pt.coords.x, pt.coords.y, pt.coords.z - 0.95,
                                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, rsz, rsz, rsz,
                                    mr, mg, mb, math.floor(60 + pulse * 110), false, false, 2, false, nil, nil, false)
                            end
                            -- cell/lobby are pure visual markers (jailing is /jail-driven), so they
                            -- never become a hold-Alt target.
                            if not near and dist < USE_DIST and pt.type ~= 'cell' and pt.type ~= 'lobby' then
                                near = pt
                            end
                        end
                    end
                end
            end

            if near then
                if altHeld() then
                    if activePoint ~= near then holdStart = GetGameTimer(); activePoint = near; opened = false end
                    if not opened then
                        local p = (GetGameTimer() - holdStart) / HOLD_MS
                        if p >= 1.0 then
                            opened = true
                            near.action(near)
                        else
                            ringP, ringLabel = p, near.label
                        end
                    end
                else
                    holdStart, activePoint, opened = nil, nil, false
                    drawHint('[Hold Alt]  ' .. near.label)
                end
            end
        end

        -- Drive the NUI hold ring (replaces the old DrawRect bar): show + fill while
        -- holding, hide once on the transition back to not-holding.
        if ringP then
            SendNUIMessage({ action = 'pdHold', show = true, p = ringP, label = ringLabel })
            ringOn = true
        elseif ringOn then
            SendNUIMessage({ action = 'pdHold', show = false })
            ringOn = false
        end

        Wait(wait)
    end
end)

-- PenguRP: when a LEO clocks OFF duty, revert to their saved civilian clothing. The Wardrobe
-- (Officer/SWAT/Body Armor) only changes components temporarily; reloadSkin restores the player's
-- saved character appearance from illenium-appearance, so the uniform/vest comes off automatically.
RegisterNetEvent('QBCore:Client:SetDuty', function(onDuty)
    if onDuty then return end
    if myFaction() then
        restoreOutfit() -- on the spot: restore the saved civ components, no respawn
    end
end)

-- ============================ /collectprints [ID] (LEO fingerprints) ============================
-- On-duty LEO only, usable when standing at a 'fingerprint' pdloc OR seated in a cruiser
-- (class 18 or a penguFleet-tagged unit). Prints the player with the given SERVER ID onto their MDT
-- record; the server re-checks they are within 3.5m, so the target must be physically next to you.
-- Defined here (after POINTS) so nearFingerprintPoint can read the live point list.
local function isLeoOnDuty()
    local d = exports.qbx_core:GetPlayerData()
    local job = d and d.job
    if not job or not job.onduty then return false end
    local def = Factions.legal[job.name]
    return def ~= nil and def.kind == 'leo'
end

local function nearFingerprintPoint()
    local pos = GetEntityCoords(cache.ped)
    local fac = myFaction()
    for i = 1, #POINTS do
        local pt = POINTS[i]
        if pt.type == 'fingerprint' and (pt.faction == '' or pt.faction == fac) then
            if #(pos - pt.coords) < USE_DIST then return true end
        end
    end
    return false
end

local function inCruiser()
    local veh = GetVehiclePedIsIn(cache.ped, false)
    if veh == 0 then return false end
    return GetVehicleClass(veh) == 18 or Entity(veh).state.penguFleet == true
end

RegisterCommand('collectprints', function(_, args)
    if not isLeoOnDuty() then
        TriggerEvent('chat:addMessage', { templateId = 'pengu:admin', args = { 'PRINTS', 'On-duty officers only.', 'err' } })
        return
    end
    if not (nearFingerprintPoint() or inCruiser()) then
        TriggerEvent('chat:addMessage', { templateId = 'pengu:admin', args = { 'PRINTS', 'You must be at a station scanner or in your cruiser.', 'err' } })
        return
    end
    local targetSrc = tonumber(args[1])
    if not targetSrc then
        TriggerEvent('chat:addMessage', { templateId = 'pengu:admin', args = { 'PRINTS', 'Usage: /collectprints [ID] - the person must be right next to you.', 'err' } })
        return
    end
    -- The server re-validates getOfficer + a 3.5m proximity between the two peds, so "they must be
    -- near" is enforced authoritatively; here we only forward the chosen id.
    TriggerServerEvent('pengu_mdt:collectPrints', targetSrc)
end, false)

-- Chat suggestion for discoverability.
CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/collectprints', 'Scan a nearby person\'s fingerprints onto their MDT record (LEO, at a station or in a cruiser).', {
        { name = 'id', help = 'Server ID of the person next to you' },
    })
end)
