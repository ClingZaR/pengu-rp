-- PenguRP Gun Progression (pengu_gunrunning) - SERVER.
-- Gang grade gates: grade >= 0 gather parts, grade >= N craft at tier N.
-- Every money/item flow is server-authoritative. Client sends requests;
-- server re-validates gang membership + grade, inventory contents, and
-- per-location / per-player cooldowns before acting. ASCII only. luac clean.

local qbx = exports.qbx_core
local inv  = exports.ox_inventory

----------------------------------------------------------------------
-- SQL
----------------------------------------------------------------------

local CREATE_SPOTS_SQL = [[
CREATE TABLE IF NOT EXISTS pengu_gun_spots (
    id       INT AUTO_INCREMENT PRIMARY KEY,
    x        FLOAT NOT NULL,
    y        FLOAT NOT NULL,
    z        FLOAT NOT NULL,
    label    VARCHAR(64)  DEFAULT 'Part Spot',
    heading  FLOAT        DEFAULT 0.0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]

local CREATE_BENCHES_SQL = [[
CREATE TABLE IF NOT EXISTS pengu_gun_benches (
    id    INT AUTO_INCREMENT PRIMARY KEY,
    tier  TINYINT NOT NULL,
    x     FLOAT NOT NULL,
    y     FLOAT NOT NULL,
    z     FLOAT NOT NULL,
    label VARCHAR(64)  DEFAULT '',
    heading FLOAT      DEFAULT 0.0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]

----------------------------------------------------------------------
-- In-memory state
----------------------------------------------------------------------

local spots   = {}  -- id -> {id,x,y,z,label,heading}
local benches = {}  -- id -> {id,tier,x,y,z,label,heading}

-- cooldowns[type][key] = expiry os.time()
local cooldowns = { spot = {}, player = {} }

local function cooldownKey(src, spotId)
    return tostring(src) .. '_' .. tostring(spotId)
end

local function isCooled(tbl, key)
    return not cooldowns[tbl][key] or os.time() > cooldowns[tbl][key]
end

local function setCooldown(tbl, key, seconds)
    cooldowns[tbl][key] = os.time() + seconds
end

----------------------------------------------------------------------
-- Gang helpers
----------------------------------------------------------------------

local function getGang(src)
    local p = qbx:GetPlayer(src)
    if not p then return nil, -1 end
    local g = p.PlayerData.gang
    if not g or g.name == 'none' or g.name == '' then return nil, -1 end
    return g.name, g.grade and g.grade.level or 0
end

----------------------------------------------------------------------
-- Weighted random part pick
----------------------------------------------------------------------

local partTotal = 0
for _, e in ipairs(Config.partPool) do partTotal = partTotal + e.weight end

local function randomPart()
    local r = math.random(partTotal)
    local acc = 0
    for _, e in ipairs(Config.partPool) do
        acc = acc + e.weight
        if r <= acc then return e.item end
    end
    return Config.partPool[1].item
end

----------------------------------------------------------------------
-- Load locations from DB
----------------------------------------------------------------------

local function loadLocations()
    local rows = MySQL.query.await('SELECT * FROM pengu_gun_spots') or {}
    spots = {}
    for _, r in ipairs(rows) do spots[r.id] = r end

    rows = MySQL.query.await('SELECT * FROM pengu_gun_benches') or {}
    benches = {}
    for _, r in ipairs(rows) do benches[r.id] = r end

    TriggerClientEvent('pengu_gunrunning:sync', -1, spots, benches, Config.benches)
end

----------------------------------------------------------------------
-- Admin placement: /gunpartloc add|remove|list
----------------------------------------------------------------------

RegisterCommand('gunpartloc', function(src, args)
    if not IsPlayerAceAllowed(src, 'pengu.guns') then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='No permission.' })
        return
    end
    local sub = tostring(args[1] or ''):lower()

    if sub == 'list' then
        local msg = 'Gun part spots:\n'
        for id, s in pairs(spots) do
            msg = msg .. ('  #%d %s (%.1f, %.1f, %.1f)\n'):format(id, s.label, s.x, s.y, s.z)
        end
        if next(spots) == nil then msg = msg .. '  (none placed)' end
        TriggerClientEvent('chat:addMessage', src, { args = { '[GunParts]', msg } })
        return
    end

    if sub == 'remove' then
        local id = tonumber(args[2])
        if not id or not spots[id] then
            TriggerClientEvent('ox_lib:notify', src, { type='error', description='Unknown spot id.' })
            return
        end
        MySQL.query.await('DELETE FROM pengu_gun_spots WHERE id = ?', { id })
        spots[id] = nil
        TriggerClientEvent('pengu_gunrunning:sync', -1, spots, benches, Config.benches)
        TriggerClientEvent('ox_lib:notify', src, { type='success', description='Spot removed.' })
        return
    end

    -- add: use player position
    TriggerClientEvent('pengu_gunrunning:requestPos', src, 'spot', tostring(args[2] or 'Part Spot'))
end, false)

----------------------------------------------------------------------
-- Admin placement: /gunbenchloc add [tier]|remove|list
----------------------------------------------------------------------

RegisterCommand('gunbenchloc', function(src, args)
    if not IsPlayerAceAllowed(src, 'pengu.guns') then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='No permission.' })
        return
    end
    local sub = tostring(args[1] or ''):lower()

    if sub == 'list' then
        local msg = 'Gun benches:\n'
        for id, b in pairs(benches) do
            local tier = Config.benches[b.tier] or {}
            msg = msg .. ('  #%d Tier-%d %s (%.1f, %.1f, %.1f)\n'):format(id, b.tier, tier.label or '?', b.x, b.y, b.z)
        end
        if next(benches) == nil then msg = msg .. '  (none placed)' end
        TriggerClientEvent('chat:addMessage', src, { args = { '[GunBench]', msg } })
        return
    end

    if sub == 'remove' then
        local id = tonumber(args[2])
        if not id or not benches[id] then
            TriggerClientEvent('ox_lib:notify', src, { type='error', description='Unknown bench id.' })
            return
        end
        MySQL.query.await('DELETE FROM pengu_gun_benches WHERE id = ?', { id })
        benches[id] = nil
        TriggerClientEvent('pengu_gunrunning:sync', -1, spots, benches, Config.benches)
        TriggerClientEvent('ox_lib:notify', src, { type='success', description='Bench removed.' })
        return
    end

    -- add
    local tier = tonumber(args[2]) or 1
    if not Config.benches[tier] then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Invalid tier (1-' .. #Config.benches .. ').' })
        return
    end
    TriggerClientEvent('pengu_gunrunning:requestPos', src, 'bench', tostring(tier))
end, false)

----------------------------------------------------------------------
-- Client reports its position for placement
----------------------------------------------------------------------

RegisterNetEvent('pengu_gunrunning:placeSpot', function(x, y, z, heading, label)
    local src = source
    if not IsPlayerAceAllowed(src, 'pengu.guns') then return end
    local id = MySQL.insert.await('INSERT INTO pengu_gun_spots (x,y,z,heading,label) VALUES (?,?,?,?,?)',
        { x, y, z, heading, label })
    spots[id] = { id=id, x=x, y=y, z=z, heading=heading, label=label }
    TriggerClientEvent('pengu_gunrunning:sync', -1, spots, benches, Config.benches)
    TriggerClientEvent('ox_lib:notify', src, { type='success', description=('Part spot #%d placed.'):format(id) })
end)

RegisterNetEvent('pengu_gunrunning:placeBench', function(x, y, z, heading, tier)
    local src = source
    tier = tonumber(tier) or 1
    if not IsPlayerAceAllowed(src, 'pengu.guns') then return end
    if not Config.benches[tier] then return end
    local label = Config.benches[tier].label
    local id = MySQL.insert.await('INSERT INTO pengu_gun_benches (tier,x,y,z,heading,label) VALUES (?,?,?,?,?,?)',
        { tier, x, y, z, heading, label })
    benches[id] = { id=id, tier=tier, x=x, y=y, z=z, heading=heading, label=label }
    TriggerClientEvent('pengu_gunrunning:sync', -1, spots, benches, Config.benches)
    TriggerClientEvent('ox_lib:notify', src, { type='success', description=('Tier-%d bench #%d placed.'):format(tier, id) })
end)

----------------------------------------------------------------------
-- Gang stash
----------------------------------------------------------------------

RegisterNetEvent('pengu_gunrunning:openStash', function(gangName)
    local src = source
    local gang, grade = getGang(src)
    if not gang or gang ~= gangName or grade < 0 then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Not in this gang.' })
        return
    end
    local stashId = 'gunstash_' .. gang
    inv:RegisterStash(stashId, gang .. ' Gun Stash', Config.stashSlots, Config.stashWeight)
    TriggerClientEvent('ox_lib:openInventory', src, { type='stash', id=stashId })
end)

----------------------------------------------------------------------
-- Part gathering
----------------------------------------------------------------------

RegisterNetEvent('pengu_gunrunning:gather', function(spotId)
    local src = source
    local spot = spots[tonumber(spotId)]
    if not spot then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Invalid spot.' })
        return
    end

    -- Validate proximity (anti-spoof: client cannot lie about which spot)
    local ped = GetPlayerPed(src)
    local px, py, pz = table.unpack(GetEntityCoords(ped, true))
    local dist = #(vector3(px,py,pz) - vector3(spot.x, spot.y, spot.z))
    if dist > 6.0 then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Too far from the spot.' })
        return
    end

    -- Gang check
    local gang, grade = getGang(src)
    if not gang or grade < Config.gatherGrade then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='You need to be in a gang to do this.' })
        return
    end

    -- Cooldowns
    local pKey   = tostring(src)
    local spKey  = tostring(spot.id)
    if not isCooled('spot', spKey) then
        local rem = cooldowns.spot[spKey] - os.time()
        TriggerClientEvent('ox_lib:notify', src, { type='error', description=('This spot was recently searched. %d min left.'):format(math.ceil(rem/60)) })
        return
    end
    if not isCooled('player', pKey) then
        local rem = cooldowns.player[pKey] - os.time()
        TriggerClientEvent('ox_lib:notify', src, { type='error', description=('You need to wait %d min before searching again.'):format(math.ceil(rem/60)) })
        return
    end

    -- Set cooldowns
    setCooldown('spot',   spKey, Config.gatherCooldownSpot)
    setCooldown('player', pKey,  Config.gatherCooldownPly)

    -- Give parts
    local count = math.random(Config.gatherMin, Config.gatherMax)
    local given = {}
    for _ = 1, count do
        local item = randomPart()
        local ok = inv:AddItem(src, item, 1)
        if ok then given[#given+1] = item end
    end

    if #given == 0 then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description="Your pockets are full." })
    else
        local names = {}
        for _, it in ipairs(given) do names[#names+1] = it:gsub('_', ' ') end
        TriggerClientEvent('ox_lib:notify', src, { type='success',
            description='Found: ' .. table.concat(names, ', ') .. '.' })
    end
end)

----------------------------------------------------------------------
-- Weapon crafting
----------------------------------------------------------------------

RegisterNetEvent('pengu_gunrunning:craft', function(benchId, recipeIdx)
    local src = source
    benchId   = tonumber(benchId)
    recipeIdx = tonumber(recipeIdx)
    local bench = benches[benchId]
    if not bench then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Invalid bench.' })
        return
    end

    -- Proximity
    local ped = GetPlayerPed(src)
    local px, py, pz = table.unpack(GetEntityCoords(ped, true))
    local dist = #(vector3(px,py,pz) - vector3(bench.x, bench.y, bench.z))
    if dist > 6.0 then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Too far from the bench.' })
        return
    end

    -- Gang grade check
    local gang, grade = getGang(src)
    local tierCfg = Config.benches[bench.tier]
    if not gang or not tierCfg or grade < tierCfg.gradeRequired then
        TriggerClientEvent('ox_lib:notify', src, { type='error',
            description=('Your gang rank is too low for this bench (need grade %d).'):format(tierCfg and tierCfg.gradeRequired or '?') })
        return
    end

    local recipe = tierCfg.recipes[recipeIdx]
    if not recipe then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Invalid recipe.' })
        return
    end

    -- Check all ingredients are present (read-only; we remove atomically below)
    for item, needed in pairs(recipe.ingredients) do
        local count = inv:GetItemCount(src, item)
        if (count or 0) < needed then
            TriggerClientEvent('ox_lib:notify', src, { type='error',
                description=('Missing: %dx %s.'):format(needed - (count or 0), item:gsub('_',' ')) })
            return
        end
    end

    -- Remove ingredients
    for item, needed in pairs(recipe.ingredients) do
        local ok = inv:RemoveItem(src, item, needed)
        if not ok then
            -- Partial removal already happened; notify and stop (rare edge case)
            TriggerClientEvent('ox_lib:notify', src, { type='error', description='Inventory error during crafting. Some parts may have been lost.' })
            return
        end
    end

    -- Give weapon
    local ok = inv:AddItem(src, recipe.result, 1)
    if ok then
        TriggerClientEvent('ox_lib:notify', src, { type='success',
            description=('Crafted: %s.'):format(recipe.label) })
    else
        -- Couldn't add — give parts back to avoid silent loss
        for item, needed in pairs(recipe.ingredients) do
            inv:AddItem(src, item, needed)
        end
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Inventory full — parts returned.' })
    end
end)

----------------------------------------------------------------------
-- Sync on player connect
----------------------------------------------------------------------

AddEventHandler('playerJoining', function()
    TriggerClientEvent('pengu_gunrunning:sync', source, spots, benches, Config.benches)
end)

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------

CreateThread(function()
    MySQL.query.await(CREATE_SPOTS_SQL)
    MySQL.query.await(CREATE_BENCHES_SQL)
    loadLocations()
    print('[pengu_gunrunning] Ready. Spots: ' .. (function() local n=0 for _ in pairs(spots) do n=n+1 end return n end)()
        .. ', Benches: ' .. (function() local n=0 for _ in pairs(benches) do n=n+1 end return n end)())
end)
