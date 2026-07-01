-- PenguRP Gang Territory (pengu_turf) - admin in-game setup (/turf). Block-based zone placement.
-- Workflow: /turf mark (corner A) -> walk to corner B -> /turf add <key> [label]
-- ASCII only. luac clean.

local ACE = 'pengu.turf'
local marks = {} -- src -> { x, y, z }  (corner A pending)

local USAGE = {
    '/turf mark                             - mark corner A of the new block at your position',
    '/turf add <key> [label]                - mark corner B + create block from A to here',
    '/turf core <gang> [label]              - drop a TINY permanent gang base at your feet',
    '/turf remove <id|key>                  - delete a block',
    '/turf setcore <id|key> <gang|none>     - mark an EXISTING block as a permanent gang base',
    '/turf setperk <id|key> <perk|none>     - set zone perk',
    '/turf setowner <id|key> <gang|neutral> - force control now',
    '/turf setdefault <id|key> <gang|none>  - set /turf reset baseline',
    '/turf reset [id|key]                   - restore default/core owner + clear influence',
    '/turf list                             - list every block',
    '/turf here                             - show which block you are in',
}

local function resolveZone(arg)
    if not arg then return nil end
    local id = tonumber(arg)
    if id and ZONES[id] then return ZONES[id] end
    local key = tostring(arg):lower()
    for _, z in pairs(ZONES) do if z.key == key then return z end end
    return nil
end

local function normGang(arg)
    local g = tostring(arg or ''):lower()
    if g == '' or g == 'neutral' or g == 'none' then return '' end
    if IsValidGang(g) then return g end
    return nil
end

local function normPerk(arg)
    local k = tostring(arg or ''):lower()
    if k == '' or k == 'none' then return '' end
    if Config.perks[k] then return k end
    return nil
end

local function cmdMark(src)
    if src <= 0 then TurfNotify(src, 'run this in-game (needs your position).', 'error'); return end
    local c = GetEntityCoords(GetPlayerPed(src))
    marks[src] = { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0 }
    TurfNotify(src, ('corner A marked at %.1f, %.1f — walk to the opposite corner then /turf add <key>.'):format(c.x, c.y), 'success')
end

local function cmdAdd(src, args)
    if src <= 0 then TurfNotify(src, 'run this in-game.', 'error'); return end
    local key = tostring(args[2] or ''):lower():gsub('[^%w_]', ''):sub(1, 32)
    if key == '' then TurfNotify(src, 'usage: /turf mark  then  /turf add <key> [label]', 'error'); return end
    if key:match('^%d+$') then TurfNotify(src, 'keys cannot be all digits.', 'error'); return end
    local mark = marks[src]
    if not mark then TurfNotify(src, 'no corner marked — use /turf mark first.', 'error'); return end
    for _, z in pairs(ZONES) do
        if z.key == key then TurfNotify(src, ('zone "%s" already exists.'):format(key), 'error'); return end
    end
    local label
    if #args >= 3 then label = table.concat({ table.unpack(args, 3) }, ' '):sub(1, 64)
    else label = key:gsub('^%l', string.upper) .. ' Block' end

    local c  = GetEntityCoords(GetPlayerPed(src))
    local x1 = math.min(mark.x, c.x + 0.0)
    local y1 = math.min(mark.y, c.y + 0.0)
    local x2 = math.max(mark.x, c.x + 0.0)
    local y2 = math.max(mark.y, c.y + 0.0)
    local z  = ((mark.z + c.z) / 2) + 0.0

    if (x2 - x1) < 5.0 or (y2 - y1) < 5.0 then
        TurfNotify(src, ('block too small (%.0fx%.0fm) - mark two more distant corners.'):format(x2-x1, y2-y1), 'error'); return
    end

    local ok = pcall(MySQL.insert.await,
        'INSERT INTO pengu_turf_zones (zone_key, label, x1, y1, x2, y2, z, owner, default_owner) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { key, label, x1, y1, x2, y2, z, '', '' })
    if not ok then TurfNotify(src, ('could not add block "%s" (duplicate key?).'):format(key), 'error'); return end
    marks[src] = nil
    LoadZones(); BroadcastTurf()
    TurfNotify(src, ('block "%s" (%s) created: (%.0f,%.0f) to (%.0f,%.0f) — %.0fx%.0fm.'):format(
        key, label, x1, y1, x2, y2, x2-x1, y2-y1), 'success')
end

local function cmdRemove(src, args)
    local z = resolveZone(args[2])
    if not z then TurfNotify(src, 'usage: /turf remove <id|key>', 'error'); return end
    local id = z.id
    MySQL.update.await('DELETE FROM pengu_turf_zones WHERE id = ?', { id })
    ClearZoneInfluence(id)
    TurfRuntime[id] = nil
    LoadZones(); BroadcastTurf()
    TurfNotify(src, ('removed block "%s".'):format(z.key), 'success')
end

-- /turf core <gang> [label]  - drop a TINY permanent core base for a gang at the admin's feet.
-- A gang has ONE core (keyed core_<gang>); re-running it moves the base. Uncapturable.
local function cmdCore(src, args)
    if src <= 0 then TurfNotify(src, 'run this in-game (needs your position).', 'error'); return end
    local g = normGang(args[2])
    if not g or g == '' then TurfNotify(src, 'usage: /turf core <gang> [label]', 'error'); return end
    local label
    if #args >= 3 then label = table.concat({ table.unpack(args, 3) }, ' '):sub(1, 64)
    else label = LabelOf(g) .. ' HQ' end
    local c    = GetEntityCoords(GetPlayerPed(src))
    local half = (Config.coreSize or 12.0) / 2.0
    local key  = 'core_' .. g
    -- replace any existing core for this gang (clear its influence + delete the old row first)
    local old = resolveZone(key)
    if old then ClearZoneInfluence(old.id); TurfRuntime[old.id] = nil end
    MySQL.update.await('DELETE FROM pengu_turf_zones WHERE zone_key = ?', { key })
    local ok = pcall(MySQL.insert.await,
        'INSERT INTO pengu_turf_zones (zone_key, label, x1, y1, x2, y2, z, owner, default_owner, core_gang) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { key, label, (c.x - half) + 0.0, (c.y - half) + 0.0, (c.x + half) + 0.0, (c.y + half) + 0.0, c.z + 0.0, g, g, g })
    if not ok then TurfNotify(src, 'could not set core (db error).', 'error'); return end
    LoadZones(); BroadcastTurf()
    TurfNotify(src, ('dropped %s CORE base "%s" (%.0fx%.0fm) at your position. Expand out via dealers + graffiti.')
        :format(LabelOf(g), key, Config.coreSize or 12.0, Config.coreSize or 12.0), 'success')
end

local function cmdSetCore(src, args)
    local z = resolveZone(args[2])
    if not z then TurfNotify(src, 'usage: /turf setcore <id|key> <gang|none>', 'error'); return end
    local g = normGang(args[3])
    if g == nil then TurfNotify(src, ('invalid gang "%s".'):format(tostring(args[3])), 'error'); return end
    MySQL.update.await('UPDATE pengu_turf_zones SET core_gang = ?, owner = ?, default_owner = ? WHERE id = ?',
        { g, g, g, z.id })
    ClearZoneInfluence(z.id)
    LoadZones(); BroadcastTurf()
    if g == '' then TurfNotify(src, ('"%s" is no longer a core base.'):format(z.key), 'success')
    else TurfNotify(src, ('"%s" is now the permanent CORE base of %s.'):format(z.key, LabelOf(g)), 'success') end
end

local function cmdSetPerk(src, args)
    local z = resolveZone(args[2])
    if not z then TurfNotify(src, 'usage: /turf setperk <id|key> <perk|none>', 'error'); return end
    local k = normPerk(args[3])
    if k == nil then
        TurfNotify(src, ('invalid perk. valid: %s'):format(table.concat(Config.perkList, ', ')), 'error'); return
    end
    MySQL.update.await('UPDATE pengu_turf_zones SET perk = ? WHERE id = ?', { k, z.id })
    LoadZones(); BroadcastTurf()
    if k == '' then TurfNotify(src, ('cleared perk on "%s".'):format(z.key), 'success')
    else TurfNotify(src, ('"%s" now grants "%s" to its controller.'):format(z.key, k), 'success') end
end

local function cmdSetOwner(src, args)
    local z = resolveZone(args[2])
    if not z then TurfNotify(src, 'usage: /turf setowner <id|key> <gang|neutral>', 'error'); return end
    local g = normGang(args[3])
    if g == nil then TurfNotify(src, ('invalid gang "%s".'):format(tostring(args[3])), 'error'); return end
    ForceZoneOwner(z, g)
    if (z.core or '') ~= '' and z.core ~= g then
        TurfNotify(src, ('"%s" is a %s CORE — control stays with them.'):format(z.key, LabelOf(z.core)), 'inform')
    else
        TurfNotify(src, ('%s now controls "%s".'):format(LabelOf(g), z.key), 'success')
    end
end

local function cmdSetDefault(src, args)
    local z = resolveZone(args[2])
    if not z then TurfNotify(src, 'usage: /turf setdefault <id|key> <gang|none>', 'error'); return end
    local g = normGang(args[3])
    if g == nil then TurfNotify(src, ('invalid gang "%s".'):format(tostring(args[3])), 'error'); return end
    MySQL.update.await('UPDATE pengu_turf_zones SET default_owner = ? WHERE id = ?', { g, z.id })
    LoadZones(); BroadcastTurf()
    TurfNotify(src, ('default owner for "%s" set to %s.'):format(z.key, LabelOf(g)), 'success')
end

local function cmdReset(src, args)
    if args[2] then
        local z = resolveZone(args[2])
        if not z then TurfNotify(src, 'no such block.', 'error'); return end
        ForceZoneOwner(z, z.default_owner or '')
        TurfNotify(src, ('reset "%s" to default/core owner.'):format(z.key), 'success')
    else
        for _, z in pairs(ZONES) do ForceZoneOwner(z, z.default_owner or '') end
        TurfNotify(src, 'reset ALL blocks.', 'success')
    end
end

local function influenceStr(zoneId)
    local rt = TurfRuntime[zoneId]
    local s = rt and rt.standings
    if not s or next(s) == nil then return '-' end
    local parts = {}
    for g, n in pairs(s) do parts[#parts + 1] = ('%s=%d'):format(g, n) end
    return table.concat(parts, ', ')
end

local function cmdList(src)
    local any = false
    for _, z in pairs(ZONES) do
        any = true
        TurfNotify(src, ('#%d %s "%s" (%.0fx%.0fm) owner=%s core=%s perk=%s'):format(
            z.id, z.key, z.label, z.x2 - z.x1, z.y2 - z.y1,
            z.owner == '' and 'neutral' or z.owner,
            (z.core or '') == '' and '-' or z.core,
            (z.perk or '') == '' and '-' or z.perk), 'inform')
    end
    if not any then TurfNotify(src, 'no blocks defined. use /turf mark then /turf add <key>.', 'inform') end
end

local function cmdHere(src)
    if src <= 0 then return end
    local c = GetEntityCoords(GetPlayerPed(src))
    local cx, cy = c.x, c.y
    for _, z in pairs(ZONES) do
        if cx >= z.x1 and cx <= z.x2 and cy >= z.y1 and cy <= z.y2 then
            TurfNotify(src, ('in "%s" (%s) owner=%s core=%s perk=%s size=%.0fx%.0fm'):format(
                z.key, z.label,
                z.owner == '' and 'neutral' or z.owner,
                (z.core or '') == '' and '-' or z.core,
                (z.perk or '') == '' and '-' or z.perk,
                z.x2 - z.x1, z.y2 - z.y1), 'inform')
            TurfNotify(src, 'influence: ' .. influenceStr(z.id), 'inform')
            return
        end
    end
    TurfNotify(src, ('not in any turf block (%.0f, %.0f). use /turf mark + /turf add to define blocks.'):format(cx, cy), 'inform')
end

local function turfCommand(src, args)
    if not IsPlayerAceAllowed(src, ACE) then
        TurfNotify(src, 'not allowed to manage turf.', 'error'); return
    end
    if not exports.qbx_core:IsOptin(src) then
        TurfNotify(src, '/aduty required.', 'error'); return
    end
    local sub = tostring(args[1] or ''):lower()
    if     sub == 'mark'       then cmdMark(src)
    elseif sub == 'add'        then cmdAdd(src, args)
    elseif sub == 'core'       then cmdCore(src, args)
    elseif sub == 'remove' or sub == 'delete' then cmdRemove(src, args)
    elseif sub == 'setcore'    then cmdSetCore(src, args)
    elseif sub == 'setperk'    then cmdSetPerk(src, args)
    elseif sub == 'setowner'   then cmdSetOwner(src, args)
    elseif sub == 'setdefault' then cmdSetDefault(src, args)
    elseif sub == 'reset'      then cmdReset(src, args)
    elseif sub == 'list'       then cmdList(src)
    elseif sub == 'here'       then cmdHere(src)
    else
        for _, l in ipairs(USAGE) do TurfNotify(src, l, 'inform') end
        TurfNotify(src, 'perks: ' .. table.concat(Config.perkList, ', '), 'inform')
    end
end

RegisterCommand('turf', turfCommand, false)
-- alias so /turflist works directly
RegisterCommand('turflist', function(src) turfCommand(src, { 'list' }) end, false)
