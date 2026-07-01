-- PenguRP Gang Territory (pengu_turf) - CLIENT map + block rendering.
-- Renders gang turf blocks from GlobalState.penguTurf (tiny CORE bases + contested ZONES) as gang-
-- coloured RECTANGLES: a named centre blip on the map, plus a translucent floor fill drawn in-world when
-- you are near (so turf reads as a BLOCK, not a circle). Only criminal-gang members see turf. The old
-- cosmetic dealer-box layer was retired - dealers now feed real zone influence server-side. ASCII only.

local centreBlips = {}  -- key -> blip handle
local blocks      = {}  -- key -> { x1,y1,x2,y2, cx,cy,cz, owner, label, colour }
local inBlockKey  = nil -- key of the block the player currently stands in (enter-toast tracking)
local amCriminal  = false -- cached: refreshed by rebuild() (state-bag / gang-update driven), read per frame

-- approx RGB per gang for the floor fill (Config colour is a blip index, not RGB).
local GANG_RGB = {
    lostmc = { 245, 205, 50 }, ballas = { 155, 85, 205 }, vagos = { 235, 150, 45 },
    cartel = { 210, 60, 60 },  families = { 70, 180, 95 }, triads = { 70, 140, 235 },
}
local NEUTRAL_RGB = { 190, 190, 190 }
local DRAW_DIST   = 90.0  -- draw the floor fill when within this of a block edge

local function gangLabel(key)
    if not key or key == '' then return 'Neutral' end
    local g = Config.gangs[key]
    return (g and g.label) or key
end

-- turf is an underworld layer: only criminal-gang members see it.
local function isCriminal()
    local pd = exports.qbx_core:GetPlayerData()
    local g  = pd and pd.gang
    local n  = g and g.name
    return n and n ~= 'none' and Factions.isCriminal(n) and true or false
end

local function clearAll()
    for _, b in pairs(centreBlips) do if b and DoesBlipExist(b) then RemoveBlip(b) end end
    centreBlips = {}
    blocks      = {}
    inBlockKey  = nil
end

-- turf shows as a translucent gang-coloured RECTANGLE matching the block bounds (map + minimap), NOT a
-- centre pin - so the map highlights the exact territory shape without pinpointing the gang's HQ/dealers.
-- Blocks tile edge-to-edge, so adjacent same-gang turf joins into one even-coloured region (no overlap).
local function makeBlip(key, nb)
    local w = nb.x2 - nb.x1
    local h = nb.y2 - nb.y1
    local b = AddBlipForArea(nb.cx, nb.cy, nb.cz, w, h)
    SetBlipColour(b, nb.colour)
    SetBlipAlpha(b, Config.blipAlpha or 128)
    SetBlipAsShortRange(b, false)
    centreBlips[key] = b
end

-- build the block set from penguTurf (cores + contested zones), diff-aware on blips.
-- `base` is the new value handed to us by the state-bag change handler. Inside a change handler the
-- GlobalState GETTER still returns the PREVIOUS value, so re-reading it here renders one update behind
-- (that was the "map says neutral / tag not visible until I spray again" lag). Use the passed value;
-- fall back to the getter only for the non-handler callers (boot / player-loaded / gang-update).
local function rebuild(base)
    amCriminal = isCriminal()
    if not amCriminal then clearAll(); return end

    local newBlocks = {}

    if type(base) ~= 'table' then base = GlobalState.penguTurf end
    if type(base) == 'table' then
        for gid, t in pairs(base) do
            local x1 = (t.x1 or 0.0) + 0.0; local y1 = (t.y1 or 0.0) + 0.0
            local x2 = (t.x2 or 0.0) + 0.0; local y2 = (t.y2 or 0.0) + 0.0
            newBlocks['b' .. tostring(gid)] = {
                x1 = x1, y1 = y1, x2 = x2, y2 = y2,
                cx = (x1 + x2) / 2, cy = (y1 + y2) / 2, cz = (t.z or 0.0) + 0.0,
                owner = t.owner or '', label = t.label or 'Turf', colour = t.colour or Config.neutralColour,
            }
        end
    end

    -- skip the area blip for any block fully contained inside a LARGER block of the SAME owner (e.g. a
    -- core sitting inside a same-gang zone): drawing both would stack the alpha and darken the overlap.
    -- A different-owner contained block is kept (a rival core inside your turf should still read).
    for ka, a in pairs(newBlocks) do
        a.noBlip = false
        for kb, b in pairs(newBlocks) do
            if ka ~= kb and a.owner == b.owner
               and a.x1 >= b.x1 and a.x2 <= b.x2 and a.y1 >= b.y1 and a.y2 <= b.y2
               and ((b.x2 - b.x1) * (b.y2 - b.y1)) > ((a.x2 - a.x1) * (a.y2 - a.y1)) then
                a.noBlip = true
                break
            end
        end
    end

    -- remove blips for blocks that disappeared
    for key, b in pairs(centreBlips) do
        if not newBlocks[key] then
            if DoesBlipExist(b) then RemoveBlip(b) end
            centreBlips[key] = nil
        end
    end
    -- add new blips / update existing. Area blips bake their size at creation, so recreate if the block
    -- moved OR resized; refresh colour/alpha live otherwise. Contained same-owner blocks draw no blip.
    for key, nb in pairs(newBlocks) do
        local old = blocks[key]
        local b   = centreBlips[key]
        if nb.noBlip then
            if b and DoesBlipExist(b) then RemoveBlip(b) end
            centreBlips[key] = nil
        elseif not b or not old or old.cx ~= nb.cx or old.cy ~= nb.cy or old.cz ~= nb.cz
           or old.x1 ~= nb.x1 or old.x2 ~= nb.x2 or old.y1 ~= nb.y1 or old.y2 ~= nb.y2 then
            if b and DoesBlipExist(b) then RemoveBlip(b); centreBlips[key] = nil end
            makeBlip(key, nb)
        else
            SetBlipColour(b, nb.colour)
            SetBlipAlpha(b, Config.blipAlpha or 128)
        end
    end

    blocks = newBlocks
end

-- ===================== in-world floor fill (the rectangle) =====================
local function drawFloor(blk)
    local rgb = GANG_RGB[blk.owner] or NEUTRAL_RGB
    local z   = blk.cz - 1.0
    local x1, y1, x2, y2 = blk.x1, blk.y1, blk.x2, blk.y2
    local a = 90
    -- two triangles cover the rectangle; draw both windings so it is visible from above and below.
    DrawPoly(x1, y1, z, x2, y1, z, x2, y2, z, rgb[1], rgb[2], rgb[3], a)
    DrawPoly(x1, y1, z, x2, y2, z, x1, y2, z, rgb[1], rgb[2], rgb[3], a)
    DrawPoly(x2, y2, z, x2, y1, z, x1, y1, z, rgb[1], rgb[2], rgb[3], a)
    DrawPoly(x1, y2, z, x2, y2, z, x1, y1, z, rgb[1], rgb[2], rgb[3], a)
end

CreateThread(function()
    while true do
        local sleep = 1000
        if amCriminal and next(blocks) ~= nil then
            local pc = GetEntityCoords(PlayerPedId())
            local px, py = pc.x, pc.y
            local here = nil
            for key, blk in pairs(blocks) do
                -- in-world floor fill is opt-in (Config.drawTurfFloor) - off by default so turf does not
                -- paint the ground while you just run around. Enter/exit detection always runs.
                if Config.drawTurfFloor then
                    -- distance to the nearest point on the rectangle (handles large + small blocks)
                    local nx = math.max(blk.x1, math.min(px, blk.x2))
                    local ny = math.max(blk.y1, math.min(py, blk.y2))
                    local ddx = nx - px; local ddy = ny - py
                    if (ddx * ddx + ddy * ddy) <= (DRAW_DIST * DRAW_DIST) then
                        sleep = 0
                        drawFloor(blk)
                    end
                end
                if px >= blk.x1 and px <= blk.x2 and py >= blk.y1 and py <= blk.y2 then here = key end
            end
            if here ~= inBlockKey then
                inBlockKey = here
                if here then
                    local blk = blocks[here]
                    lib.notify({
                        title = blk.label,
                        description = blk.owner ~= '' and ('Controlled by ' .. gangLabel(blk.owner)) or 'Neutral / uncontrolled turf',
                        type = 'inform', position = 'top',
                    })
                end
            end
        elseif inBlockKey then
            inBlockKey = nil
        end
        Wait(sleep)
    end
end)

-- ===================== wiring =====================
AddStateBagChangeHandler('penguTurf', 'global', function(_, _, value) rebuild(value) end)

CreateThread(function()
    local tries = 0
    while GlobalState.penguTurf == nil and tries < 50 do Wait(200); tries = tries + 1 end
    rebuild()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() rebuild() end)
RegisterNetEvent('QBCore:Client:OnGangUpdate', function() rebuild() end)
RegisterNetEvent('qbx_core:client:onGangUpdate', function() rebuild() end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearAll() end
end)

TriggerEvent('chat:addSuggestion', '/turf', 'Manage gang turf blocks (admin)', {
    { name = 'subcommand', help = 'mark | add | core | remove | setcore | setperk | setowner | setdefault | reset | list | here' },
})
TriggerEvent('chat:addSuggestion', '/turflist', 'List all turf blocks (admin)', {})
