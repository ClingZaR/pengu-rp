-- PenguRP Gang Territory (pengu_turf) - CLIENT graffiti (Phase 3). Using a spray can (ox_inventory
-- client.export -> useSpraycan) raycasts the wall you are facing and sprays a gang tag there. The player
-- TYPES the tag text; spraying your GANG NAME claims/builds turf INFLUENCE, any other text is cosmetic.
-- Active tags (GlobalState.penguGraffiti) render as 3D labels (gang-coloured for influence tags, off-white
-- for cosmetic) - only criminal-gang members + law see them - and expose an ox_target: rivals "Paint over",
-- law "Remove".
--
-- Raycast (fixed): cast a LONG ray along the camera look-direction, but decide "too far" by the distance
-- from the PED to the hit point (NOT the camera, which in third-person sits metres behind you - that was
-- the old "too far from the wall" false negative). Flags 17 = world+objects so the ray never stops on a
-- ped (incl. your own back). Reads the surface normal via GetShapeTestResultEx (the old code read
-- GetShapeTestResult whose 4th return is the ENTITY, not the normal -> it crashed on every hit).
-- ASCII only. luac clean.

local busyClient = false
local tags     = {} -- id -> { id, gang, x, y, z, h, text, infl }
local tagZones = {} -- id -> ox_target zone id

-- approx RGB per gang for the tag label (the Config colour is a blip index, not RGB).
local GANG_RGB = {
    lostmc = { 245, 205, 50 }, ballas = { 155, 85, 205 }, vagos = { 235, 150, 45 },
    cartel = { 210, 60, 60 },  families = { 70, 180, 95 }, triads = { 70, 140, 235 },
}
local COSMETIC_RGB = { 225, 225, 225 } -- non-gang-name (vanity) tags read as plain white paint

-- ===================== identity =====================
local function isCriminal()
    local pd = exports.qbx_core:GetPlayerData()
    local g = pd and pd.gang
    local n = g and g.name
    return n and n ~= 'none' and Factions.isCriminal(n) and true or false
end

local function myGang()
    local pd = exports.qbx_core:GetPlayerData()
    local g = pd and pd.gang
    local n = g and g.name
    return (n and n ~= 'none') and n or nil
end

local function isLaw()
    local pd = exports.qbx_core:GetPlayerData()
    local j = pd and pd.job
    return (j and Config.lawJobs and Config.lawJobs[j.name]) and true or false
end

local function canSeeTags()
    return Config.tagsPublic or isCriminal() or isLaw()
end

local function gangLabel(key)
    local g = Config.gangs[key]
    return (g and g.label) or key or 'Gang'
end

-- ===================== raycast: find the wall you are facing =====================
local function dirFromRot(rot)
    local z = math.rad(rot.z); local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

-- one probe via ox_lib (already a dependency). flags 17 = world(1)|object(16): hits walls/props but never
-- a ped, so the ray can't stop on your own back in third-person; ox_lib passes cache.ped as the ignore
-- entity for us and returns the surface NORMAL. (The old code read GetShapeTestResult, whose 4th return is
-- the ENTITY, not the normal - indexing that number as normal.x crashed on every successful hit.)
local function probe(from, to)
    local hit, _, endCoords, normal = lib.raycast.fromCoords(from, to, 17, 4)
    return (hit == true or hit == 1), endCoords, normal
end

-- Find the wall the player is aiming at. Returns ok, endCoords, normal, reason.
-- The whole trick that fixes "too far when I'm right against it": the ray ORIGIN is the camera (so aim +
-- look-up/down is respected and the hit matches the crosshair), but the proximity gate measures from the
-- PED to the hit point - the third-person camera offset can no longer make a touched wall read as "far".
-- Three casts in order of preference cover every stance: camera ray (aim), ped-eye along cam dir (flush
-- walls), ped-eye flat-forward (you are against a wall but looking at the sky/floor).
local function castWall()
    local ped   = PlayerPedId()
    local pc    = GetEntityCoords(ped)
    local reach = (Config.tagReach or 3.0)
    local eye   = pc + vector3(0.0, 0.0, 0.6)
    local camD  = dirFromRot(GetGameplayCamRot(2))
    local fwd   = GetEntityForwardVector(ped)

    local casts = {
        { from = GetGameplayCamCoord(), dir = camD, len = 20.0 },        -- aim ray (matches crosshair)
        { from = eye,                   dir = camD, len = reach + 1.5 }, -- flush wall, respects pitch
        { from = eye,                   dir = fwd,  len = reach + 1.0 }, -- against wall, looking off-axis
    }

    local sawWallFar, sawSomething = false, false
    for _, c in ipairs(casts) do
        local ok, ec, nrm = probe(c.from, c.from + c.dir * c.len)
        if ok and ec and nrm then
            sawSomething = true
            if math.abs(nrm.z) <= 0.7 then            -- a (near-)vertical surface = a wall, not floor/ceiling
                -- judge "too far" by HORIZONTAL distance to the wall (height-independent) so aiming high or
                -- low on a wall you are flush against still counts; clamp how far up/down the tag may land.
                local dx, dy = ec.x - pc.x, ec.y - pc.y
                if (dx * dx + dy * dy) <= (reach * reach)
                   and math.abs(ec.z - pc.z) <= (Config.tagMaxHeight or 4.0) then
                    return true, ec, nrm
                end
                sawWallFar = true
            end
        end
    end

    local reason = sawWallFar and 'far' or (sawSomething and 'aim' or 'none')
    return false, nil, nil, reason
end

-- ===================== use a spray can =====================
exports('useSpraycan', function()
    if busyClient then return end
    if not isCriminal() then
        lib.notify({ title = 'Graffiti', description = 'Only gangs tag turf.', type = 'error' }); return
    end
    busyClient = true

    -- 1) find a wall in front of us BEFORE asking for text (don't prompt if we can't tag here)
    local ok, endCoords, normal, reason = castWall()
    if not ok then
        local msg = (reason == 'far')  and 'Get closer to the wall, then use the can.'
                 or (reason == 'aim')  and 'Aim straight at a wall (not the ground), then use the can.'
                 or                        'Stand in front of a wall and use the can.'
        lib.notify({ title = 'Graffiti', description = msg, type = 'error' })
        busyClient = false; return
    end

    -- 2) what should the wall say? default to YOUR gang name (the influence-building tag).
    local label = gangLabel(myGang())
    local input = lib.inputDialog('Spray Graffiti', {
        {
            type = 'input',
            label = 'Tag text',
            description = ('Spray "%s" (your gang name) to claim and build turf influence. Any other text is just decoration.'):format(label),
            default = label,
            required = true,
            min = 1,
            max = 24,
        },
    })
    if not input or not input[1] then busyClient = false; return end
    local text = input[1]

    -- 3) spray it
    local done = lib.progressCircle({
        label = 'Tagging the wall',
        duration = Config.tagSprayTime or 5000,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'switch@franklin@lamar_tagging_wall', clip = 'lamar_tagging_wall' },
    })
    if not done then busyClient = false; return end

    local h = GetHeadingFromVector_2d(normal.x, normal.y)
    local placed = lib.callback.await('pengu_turf:placeTag', false, endCoords.x, endCoords.y, endCoords.z, h, text)
    if not placed then lib.notify({ title = 'Graffiti', description = 'Could not tag here.', type = 'error' }) end
    busyClient = false
end)

-- ===================== paint over / remove =====================
local function doProgressCall(label, dur, cbName, tagId)
    if busyClient then return end
    busyClient = true
    local ok = lib.progressCircle({
        label = label, duration = dur, position = 'bottom',
        useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'switch@franklin@lamar_tagging_wall', clip = 'lamar_tagging_wall' },
    })
    if ok then lib.callback.await(cbName, false, tagId) end
    busyClient = false
end

-- ===================== targets =====================
local function clearTagZones()
    for _, zid in pairs(tagZones) do if zid then exports.ox_target:removeZone(zid) end end
    tagZones = {}
end

-- `g` is the new value the state-bag change handler hands us. Re-reading GlobalState.penguGraffiti from
-- INSIDE the handler returns the PREVIOUS value (the getter lags the change), which made a fresh tag only
-- appear after the NEXT spray. Use the passed value; fall back to the getter for the boot/loaded callers.
local function rebuildTags(g)
    clearTagZones()
    tags = {}
    if type(g) ~= 'table' then g = GlobalState.penguGraffiti end
    if type(g) ~= 'table' then return end
    for k, t in pairs(g) do
        local id = tonumber(k)
        if id then
            tags[id] = {
                id = id, gang = t.gang,
                x = t.x + 0.0, y = t.y + 0.0, z = t.z + 0.0, h = (t.h or 0.0) + 0.0,
                text = (t.text and t.text ~= '') and t.text or gangLabel(t.gang),
                infl = t.infl ~= false,
            }
            local ref = tags[id]
            tagZones[id] = exports.ox_target:addSphereZone({
                coords = vector3(ref.x, ref.y, ref.z),
                radius = 1.6,
                debug = false,
                options = {
                    {
                        name = 'pengu_tag_paint_' .. id,
                        icon = 'fa-solid fa-spray-can-sparkles',
                        label = 'Paint over tag',
                        canInteract = function() return isCriminal() and ref.gang ~= myGang() end,
                        onSelect = function() doProgressCall('Painting over the tag', Config.tagPaintTime or 6000, 'pengu_turf:paintTag', id) end,
                    },
                    {
                        name = 'pengu_tag_police_' .. id,
                        icon = 'fa-solid fa-broom',
                        label = 'Remove graffiti',
                        canInteract = function() return isLaw() end,
                        onSelect = function() doProgressCall('Scrubbing off the graffiti', Config.tagPaintTime or 6000, 'pengu_turf:policeRemoveTag', id) end,
                    },
                },
            })
        end
    end
end

-- ===================== render tags FLAT on the wall (DUI -> world textured quad) =====================
-- FiveM has no native to draw flat text on a surface, so each tag's text is rendered in a DUI (HTML/CSS
-- graffiti font) into a runtime texture, then painted onto the wall with DrawSpritePoly (a world-space
-- textured quad oriented to the wall by the tag's stored heading). A small POOL of DUI surfaces is recycled
-- across the NEAREST tags so many tags can be up without one browser per tag. If DrawSpritePoly is not
-- usable on this build the render falls back to a simple label drawn at the wall.

local DUI_URL   = ('nui://%s/ui/graffiti.html'):format(GetCurrentResourceName())
local pool      = {}    -- slot -> { dui, key=tagId|nil, resendUntil=gameTimerMs }
local poolBuilt = false
local flatOk    = true  -- flips false if DrawSpritePoly errors -> billboard fallback

local function rgbOf(t)
    return (t.infl and (GANG_RGB[t.gang] or COSMETIC_RGB)) or COSMETIC_RGB
end

local function buildPool()
    if poolBuilt then return end
    for i = 1, (Config.graffitiMaxRendered or 6) do
        pool[i] = { dui = lib.dui:new({ url = DUI_URL, width = 1024, height = 512 }), key = nil, resendUntil = 0 }
    end
    poolBuilt = true
end

local function sendSlot(slot)
    local t = slot.key and tags[slot.key]
    if not t then return end
    local rgb = rgbOf(t)
    local rot = ((slot.key * 13) % 9) - 4 -- stable per-tag lean (-4..+4 deg) so tags don't all look identical
    slot.dui:sendMessage({
        type = 'set',
        text = tostring(t.text),
        color = ('#%02x%02x%02x'):format(rgb[1], rgb[2], rgb[3]),
        rot = rot,
    })
end

-- assign the nearest tags to DUI slots; keep re-sending a slot's text for ~3s after it changes (the
-- assignment thread runs every 300ms, so this lands ~10 messages - covers a slow DUI page load where an
-- immediate message would be missed before the html is ready).
local function assignSlots()
    local pc = GetEntityCoords(PlayerPedId())
    local dd = Config.tagDrawDist or 30.0
    local near = {}
    for id, t in pairs(tags) do
        local d = #(pc - vector3(t.x, t.y, t.z))
        if d < dd then near[#near + 1] = { id = id, d = d } end
    end
    table.sort(near, function(a, b) return a.d < b.d end)

    local want = {}
    for i = 1, math.min(#near, #pool) do want[near[i].id] = true end

    local assigned = {}
    for _, slot in ipairs(pool) do
        if slot.key and not want[slot.key] then slot.key = nil; slot.resendUntil = 0 end
        if slot.key then assigned[slot.key] = true end
    end
    for id in pairs(want) do
        if not assigned[id] then
            for _, slot in ipairs(pool) do
                if not slot.key then
                    slot.key = id
                    slot.resendUntil = GetGameTimer() + 3000 -- resend for ~3s to beat the DUI page-load race
                    assigned[id] = true
                    break
                end
            end
        end
    end
    for _, slot in ipairs(pool) do
        if slot.key and GetGameTimer() < (slot.resendUntil or 0) then sendSlot(slot) end
    end
end

-- one world-space textured triangle (UVW per vertex, w = 0)
local function tri(dict, txt, a, b, c, au, av, bu, bv, cu, cv)
    DrawSpritePoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, 255, 255, 255, 255, dict, txt,
        au, av, 0.0, bu, bv, 0.0, cu, cv, 0.0)
end

local function drawQuad(t, dict, txt)
    local hr = math.rad(t.h or 0.0)
    local nx, ny = -math.sin(hr), math.cos(hr)      -- outward wall normal (horizontal)
    local rx, ry = math.cos(hr), math.sin(hr)       -- along-wall "right" (viewer's right, facing the wall)
    local hw = (Config.graffitiWidth or 1.3) * 0.5
    local hh = (Config.graffitiHeight or 0.65) * 0.5
    local cx, cy, cz = t.x + nx * 0.05, t.y + ny * 0.05, t.z   -- nudge off the wall to avoid z-fighting
    local TL = vector3(cx - rx * hw, cy - ry * hw, cz + hh)
    local TR = vector3(cx + rx * hw, cy + ry * hw, cz + hh)
    local BL = vector3(cx - rx * hw, cy - ry * hw, cz - hh)
    local BR = vector3(cx + rx * hw, cy + ry * hw, cz - hh)
    -- map the image's LEFT edge to the viewer's left (text reads correctly from the spray/outward side).
    -- the front face's viewer-right is -(rx,ry), so the -right corners (TL/BL) take u=1; flip if mirrored.
    local lu, ru = 1.0, 0.0
    if Config.graffitiMirror then lu, ru = 0.0, 1.0 end
    -- front faces + reversed-winding back faces so it reads from either side
    tri(dict, txt, TL, TR, BR, lu, 0.0, ru, 0.0, ru, 1.0)
    tri(dict, txt, TL, BR, BL, lu, 0.0, ru, 1.0, lu, 1.0)
    tri(dict, txt, TL, BR, TR, lu, 0.0, ru, 1.0, ru, 0.0)
    tri(dict, txt, TL, BL, BR, lu, 0.0, lu, 1.0, ru, 1.0)
end

-- simple on-wall label, used only if DrawSpritePoly is unavailable on this build
local function drawBillboard(t)
    local rgb = rgbOf(t)
    SetDrawOrigin(t.x, t.y, t.z, 0)
    SetTextScale(0.5, 0.5); SetTextFont(4)
    SetTextColour(rgb[1], rgb[2], rgb[3], 215)
    SetTextOutline(); SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(tostring(t.text):upper())
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

-- assignment thread (low frequency)
CreateThread(function()
    while true do
        if canSeeTags() and Config.graffitiFlat ~= false and next(tags) ~= nil then
            buildPool()
            assignSlots()
            Wait(300)
        else
            if poolBuilt then for _, slot in ipairs(pool) do slot.key = nil; slot.resendUntil = 0 end end
            Wait(750)
        end
    end
end)

-- render thread (per frame while there is something to draw)
CreateThread(function()
    while true do
        local drew = false
        if canSeeTags() and next(tags) ~= nil then
            if Config.graffitiFlat ~= false and flatOk then
                -- flat mode: draw quads once the DUI pool exists. If it isn't built yet (the assignment
                -- thread builds it within ~300ms) draw nothing this frame rather than flashing the label.
                if poolBuilt then
                    local ok = pcall(function()
                        for _, slot in ipairs(pool) do
                            local t = slot.key and tags[slot.key]
                            if t then drawQuad(t, slot.dui.dictName, slot.dui.txtName); drew = true end
                        end
                    end)
                    if not ok then flatOk = false end -- DrawSpritePoly errored on this build; use the label
                end
            else
                local pc = GetEntityCoords(PlayerPedId())
                local dd = Config.tagDrawDist or 30.0
                for _, t in pairs(tags) do
                    if #(pc - vector3(t.x, t.y, t.z)) < dd then drawBillboard(t); drew = true end
                end
            end
        end
        Wait(drew and 0 or 300)
    end
end)

-- ===================== wiring =====================
AddStateBagChangeHandler('penguGraffiti', 'global', function(_, _, value) rebuildTags(value) end)

CreateThread(function()
    while not exports.qbx_core:GetPlayerData() do Wait(250) end
    rebuildTags()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() rebuildTags() end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearTagZones() end
end)
