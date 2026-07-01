-- PenguRP Drug Supply Chain (pengu_drugs) - SERVER: respawning PLANT-NODE fields (field=true lab types:
-- coca_field, weed_field). Each ACTIVE field group keeps up to def.maxPlants plant nodes scattered within
-- def.radius of its placed anchor(s). Harvesting a node consumes it (server-authoritative yield) and,
-- after a random regrowMin..regrowMax delay, a fresh node grows at a NEW random spot, back up to max.
-- Nodes are runtime-only (no DB) and published to clients via GlobalState.penguDrugNodes (client/fields.lua
-- renders + reconciles them). Reads LABS + DrugNotify + Config from server/main.lua (same Lua state).
-- ASCII only. luac clean.

local ox = exports.ox_inventory

NODES = {} -- id -> { id, key, type, x, y, z }   (global so this file owns it across calls)
local nodeSeq = 0
local busy = {}
local seeded = {} -- field key -> true once it has had its INITIAL fill (so admin edits don't insta-refill)

-- publish only what clients need to render each plant
local function publishNodes()
    local out = {}
    for id, n in pairs(NODES) do
        out[tostring(id)] = { type = n.type, x = n.x, y = n.y, z = n.z }
    end
    GlobalState.penguDrugNodes = out
end
publishNodes() -- clear any stale bag from a previous resource lifetime on (re)start

-- group nodes by (group_name, lab_type) so maxPlants is enforced PER GROUP per field type
local function fieldKey(groupName, ltype)
    return ((groupName and groupName ~= '') and groupName or 'solo') .. '|' .. ltype
end

-- map of every ACTIVE field anchor, grouped: key -> { type, def, points = { {x,y,z}, ... } }
local function fieldDefs()
    local fields = {}
    for _, lab in pairs(LABS or {}) do
        local def = Config.labTypes[lab.type]
        if def and def.field and lab.active then
            local key = fieldKey(lab.group_name, lab.type)
            local f = fields[key]
            if not f then f = { type = lab.type, def = def, points = {} }; fields[key] = f end
            f.points[#f.points + 1] = { x = lab.x + 0.0, y = lab.y + 0.0, z = lab.z + 0.0 }
        end
    end
    return fields
end

local function countNodes(key)
    local n = 0
    for _, nd in pairs(NODES) do if nd.key == key then n = n + 1 end end
    return n
end

-- spawn ONE node at a random offset (uniform over the disk) around a random anchor point of the field
local function spawnNode(key, f)
    if #f.points == 0 then return end
    local p     = f.points[math.random(#f.points)]
    local ang   = math.random() * 6.2831853
    local dist  = math.sqrt(math.random()) * (f.def.radius or 12.0) -- sqrt => uniform disk, not centre-biased
    nodeSeq = nodeSeq + 1
    NODES[nodeSeq] = {
        id   = nodeSeq, key = key, type = f.type,
        x    = p.x + math.cos(ang) * dist,
        y    = p.y + math.sin(ang) * dist,
        z    = p.z, -- approximate; the client ground-snaps the prop on spawn
    }
end

-- after a harvest, regrow ONE node for that field after a random delay (the RNG the user asked for)
local function scheduleRegrow(key)
    local f0 = fieldDefs()[key]
    if not f0 then return end -- field removed/disabled meanwhile
    local def = f0.def
    local delay = math.random(def.regrowMin or 30000, def.regrowMax or 90000)
    SetTimeout(delay, function()
        local f = fieldDefs()[key]
        if f and countNodes(key) < (f.def.maxPlants or 6) then
            spawnNode(key, f)
            publishNodes()
        end
    end)
end

-- (re)sync nodes to the current set of active field anchors: drop orphans, top each field up to max.
-- Called on boot + whenever labs change (BroadcastLabs -> 'pengu_drugs:labsChanged').
function RebuildFieldNodes()
    local fields = fieldDefs()
    -- drop nodes whose field no longer exists or was disabled
    for id, nd in pairs(NODES) do
        if not fields[nd.key] then NODES[id] = nil end
    end
    -- forget fields that are gone, so re-enabling one later counts as a fresh INITIAL fill
    for key in pairs(seeded) do
        if not fields[key] then seeded[key] = nil end
    end
    -- INITIAL fill only (boot / newly added / re-enabled field). Post-harvest gaps are owned by
    -- scheduleRegrow's RNG timer - we must NOT instant-refill them here, or any admin lab command would
    -- snap every field back to full and defeat the timed respawn.
    for key, f in pairs(fields) do
        if not seeded[key] then
            local guard = 0
            while countNodes(key) < (f.def.maxPlants or 6) and guard < 100 do
                spawnNode(key, f); guard = guard + 1
            end
            seeded[key] = true
        end
    end
    publishNodes()
end

AddEventHandler('pengu_drugs:labsChanged', function() RebuildFieldNodes() end)

-- safety: rebuild a few seconds after boot too, in case LABS settled after the first labsChanged
CreateThread(function()
    Wait(4000)
    RebuildFieldNodes()
end)

-- ===================== harvest (server-authoritative) =====================
lib.callback.register('pengu_drugs:harvestNode', function(src, nodeId)
    if busy[src] then return false end
    local node = NODES[tonumber(nodeId) or -1]
    if not node then return false end -- already harvested (the node IS the anti-double-spend lock)
    local def = Config.labTypes[node.type]
    if not def or not def.field then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    -- HORIZONTAL distance (+ a generous vertical band): node.z is the anchor z, but the plant prop is
    -- ground-snapped client-side, so on slopes a full 3D check against node.z would wrongly reject a
    -- player standing right on the plant.
    local pc = GetEntityCoords(ped)
    local dx, dy = pc.x - node.x, pc.y - node.y
    if math.sqrt(dx * dx + dy * dy) > (Config.interactDist + 3.0) or math.abs(pc.z - node.z) > 12.0 then
        DrugNotify(src, 'You are too far from the plant.', 'error'); return false
    end

    local y = def.yield or {}
    local amount = math.random(y.min or 1, y.max or 1)
    if not y.item or not ox:CanCarryItem(src, y.item, amount) then
        DrugNotify(src, 'You cannot carry that - free up space.', 'error'); return false
    end

    busy[src] = true
    NODES[node.id] = nil -- consume the plant (synchronous: also blocks a second harvester of this node)
    ox:AddItem(src, y.item, amount)
    publishNodes()
    scheduleRegrow(node.key)
    busy[src] = nil

    DrugNotify(src, ('Harvested %dx %s.'):format(amount, y.item), 'success')
    pcall(function() TriggerEvent('pengu_xp:onDrugProcess', src) end)
    return true
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)
