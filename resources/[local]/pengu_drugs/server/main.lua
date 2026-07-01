-- PenguRP Drug Supply Chain (pengu_drugs) - SERVER core: lab persistence, live replication, and the
-- server-authoritative PROCESS callback (consume inputs -> produce outputs). The client minigame is
-- only a skill gate; the economy (item removal/grant + proximity) is enforced here. ASCII only.

local ox = exports.ox_inventory

-- in-memory authoritative lab list, rebuilt from DB by LoadLabs() (boot + admin edits).
-- ALL labs sent to clients (with active flag) so props always render; interaction is gated client-side.
LABS = {} -- id -> { id, type, label, x, y, z, active, group_name }
local ACE = 'pengu.drugs'

-- chat feedback via the cross-resource qbx_chat_theme 'pengu:admin' template.
local KIND = { success = 'ok', error = 'err', inform = 'info' }
function DrugNotify(src, msg, kind, tag)
    if not src or src <= 0 then print('[pengu_drugs] ' .. tostring(msg)); return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { tag or 'DRUGS', msg, KIND[kind or 'inform'] or 'info' },
    })
end

local function ensureColumn(tbl, col, ddl)
    local ex = MySQL.scalar.await(
        'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tbl, col })
    if not ex then MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(tbl, ddl)) end
end

function LoadLabs()
    local rows = MySQL.query.await('SELECT id, lab_type, label, x, y, z, active, group_name FROM pengu_drug_labs ORDER BY id') or {}
    local t = {}
    for _, r in ipairs(rows) do
        t[r.id] = {
            id         = r.id,
            type       = r.lab_type,
            label      = r.label,
            x          = r.x + 0.0,
            y          = r.y + 0.0,
            z          = r.z + 0.0,
            active     = (tonumber(r.active) or 1) == 1,
            group_name = r.group_name or '',
        }
    end
    LABS = t
    return t
end

-- all labs (active + disabled) sent so props/visuals always render client-side; active flag gates interaction
local function labArray()
    local arr = {}
    for _, l in pairs(LABS) do
        arr[#arr + 1] = l
    end
    return arr
end

function BroadcastLabs()
    TriggerClientEvent('pengu_drugs:labsUpdated', -1, labArray())
    TriggerEvent('pengu_drugs:labsChanged') -- let server/fields.lua resync plant nodes for field types
end

lib.callback.register('pengu_drugs:getLabs', function(_)
    return labArray()
end)

-- ===================== boot =====================
local function labCount()
    local n = 0; for _ in pairs(LABS) do n = n + 1 end; return n
end

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pengu_drug_labs (
                id         INT AUTO_INCREMENT PRIMARY KEY,
                lab_type   VARCHAR(32) NOT NULL,
                label      VARCHAR(64) NOT NULL DEFAULT '',
                x          FLOAT       NOT NULL,
                y          FLOAT       NOT NULL,
                z          FLOAT       NOT NULL,
                active     TINYINT(1)  NOT NULL DEFAULT 1,
                group_name VARCHAR(32) NOT NULL DEFAULT '',
                created_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ]])
        ensureColumn('pengu_drug_labs', 'label',      "`label`      VARCHAR(64) NOT NULL DEFAULT ''")
        ensureColumn('pengu_drug_labs', 'active',     '`active`     TINYINT(1)  NOT NULL DEFAULT 1')
        ensureColumn('pengu_drug_labs', 'group_name', "`group_name` VARCHAR(32) NOT NULL DEFAULT ''")

        local cnt = MySQL.scalar.await('SELECT COUNT(*) FROM pengu_drug_labs')
        if (tonumber(cnt) or 0) == 0 then
            local seeded = 0
            for _, grp in ipairs(Config.labGroups or {}) do
                for _, tbl in ipairs(grp.tables or {}) do
                    if Config.labTypes[tbl.type] then
                        MySQL.insert.await(
                            'INSERT INTO pengu_drug_labs (lab_type, label, x, y, z, active, group_name) VALUES (?, ?, ?, ?, ?, 1, ?)',
                            { tbl.type, tbl.label or Config.defaultLabel,
                              grp.x + (tbl.dx or 0.0) + 0.0,
                              grp.y + (tbl.dy or 0.0) + 0.0,
                              grp.z + 0.0, grp.group_name or '' })
                        seeded = seeded + 1
                    end
                end
            end
            print(('[pengu_drugs] seeded %d table(s) across lab groups'):format(seeded))
        end

        LoadLabs()
    end)
    if not ok then print('[pengu_drugs] BOOT FAILED: ' .. tostring(err)) end
    BroadcastLabs()
    print(('[pengu_drugs] %s (%d labs).'):format(ok and 'ready' or 'DEGRADED', labCount()))
end)

-- ===================== process (server-authoritative) =====================
local busy = {}      -- src -> true while a process is mid-flight (anti double-spend)
local cooldowns = {} -- src -> { ['labId|recipeIdx'] = expiryGameTimer } (rate-limits gathers/recipes)

lib.callback.register('pengu_drugs:process', function(src, labId, recipeIdx)
    if busy[src] then return false end
    local lid, ridx = tonumber(labId), tonumber(recipeIdx)
    local lab = lid and LABS[lid]
    if not lab or not lab.active then return false end -- reject if lab is disabled
    local def = Config.labTypes[lab.type]
    local recipe = def and def.recipes and ridx and def.recipes[ridx]
    if not recipe then return false end

    -- per-recipe cooldown (server-enforced; the real gate on empty-input GATHER recipes)
    local cdKey, now = ('%d|%d'):format(lid, ridx), GetGameTimer()
    if recipe.cooldown and recipe.cooldown > 0 then
        local mine = cooldowns[src]
        local untilT = mine and mine[cdKey]
        if untilT and now < untilT then
            DrugNotify(src, ('Wait %ds before doing that again.'):format(math.ceil((untilT - now) / 1000)), 'error')
            return false
        end
    end

    -- proximity (server-side ped coords; small slack over the client radius)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    if #(GetEntityCoords(ped) - vector3(lab.x, lab.y, lab.z)) > (Config.interactDist + 2.0) then
        DrugNotify(src, 'You are too far from the lab.', 'error'); return false
    end

    busy[src] = true
    local okDone = false
    local result = (function()
        -- has all inputs?
        for item, qty in pairs(recipe.input) do
            if (ox:Search(src, 'count', item) or 0) < qty then
                DrugNotify(src, 'You do not have the required materials.', 'error'); return false
            end
        end
        -- room for outputs?
        for item, qty in pairs(recipe.output) do
            if not ox:CanCarryItem(src, item, qty) then
                DrugNotify(src, 'You cannot carry the result - free up space.', 'error'); return false
            end
        end
        -- consume inputs; if any removal fails, REFUND what was already taken (protects future
        -- multi-input recipes from partial-consume item loss).
        local removed = {}
        for item, qty in pairs(recipe.input) do
            if ox:RemoveItem(src, item, qty) then
                removed[item] = (removed[item] or 0) + qty
            else
                for ritem, rqty in pairs(removed) do ox:AddItem(src, ritem, rqty) end
                DrugNotify(src, 'Processing failed.', 'error'); return false
            end
        end
        -- grant outputs
        for item, qty in pairs(recipe.output) do
            ox:AddItem(src, item, qty)
        end
        okDone = true
        return true
    end)()

    busy[src] = nil
    if okDone then
        if recipe.cooldown and recipe.cooldown > 0 then
            cooldowns[src] = cooldowns[src] or {}
            cooldowns[src][cdKey] = GetGameTimer() + recipe.cooldown
        end
        DrugNotify(src, ('Produced %s.'):format(recipe.label or 'product'), 'success')
        TriggerEvent('pengu_xp:onDrugProcess', src)
    end
    return result
end)

AddEventHandler('playerDropped', function() busy[source] = nil; cooldowns[source] = nil end)

-- ===================== lab-hold gang rep (every 30 min) =====================
-- Criminal gang members present at an active lab earn rep for their gang.
-- Rewards sustained presence at the lab, not just visits.
-- XP from actual drug processing (above) stacks with this separately.
local LAB_HOLD_REP    = 200   -- rep per gang per lab per 30-min tick
local LAB_HOLD_RADIUS = 25.0  -- metres from the lab point

CreateThread(function()
    Wait(1800000) -- first tick 30 min after boot
    while true do
        local qbx = exports.qbx_core
        -- collect gangs present per lab GROUP (dedup by group_name so a 3-table cluster only
        -- awards rep once per gang per tick, not 3x). Key = group_name or string(id) if ungrouped.
        local groupGangs  = {} -- groupKey -> { gangName = true }
        local groupRefLab = {} -- groupKey -> one LABS entry used as proximity centre for XP check
        for _, lab in pairs(LABS) do
            if not lab.active then goto nextLab end
            local gkey = (lab.group_name and lab.group_name ~= '' and lab.group_name) or tostring(lab.id)
            groupRefLab[gkey] = groupRefLab[gkey] or lab
            local labPos = vector3(lab.x, lab.y, lab.z)
            for src, p in pairs(qbx:GetQBPlayers() or {}) do
                local gang = p.PlayerData and p.PlayerData.gang
                if gang and gang.name and gang.name ~= 'none' then
                    local ped = GetPlayerPed(src)
                    if ped and ped ~= 0 then
                        local d = #(GetEntityCoords(ped) - labPos)
                        if d <= LAB_HOLD_RADIUS then
                            groupGangs[gkey] = groupGangs[gkey] or {}
                            groupGangs[gkey][gang.name] = true
                        end
                    end
                end
            end
            ::nextLab::
        end
        -- award rep once per gang per lab GROUP (not per table)
        for gkey, gangs in pairs(groupGangs) do
            for gangName in pairs(gangs) do
                pcall(function()
                    exports.pengu_gangs:AddRep(gangName, LAB_HOLD_REP)
                end)
                -- XP to each member near any table in the group (+10m slack covers table spread)
                local refLab = groupRefLab[gkey]
                if refLab then
                    local refPos = vector3(refLab.x, refLab.y, refLab.z)
                    for src, p in pairs(exports.qbx_core:GetQBPlayers() or {}) do
                        local g = p.PlayerData and p.PlayerData.gang
                        if g and g.name == gangName then
                            local ped = GetPlayerPed(src)
                            if ped and ped ~= 0 and #(GetEntityCoords(ped) - refPos) <= (LAB_HOLD_RADIUS + 10.0) then
                                pcall(function()
                                    exports.pengu_xp:Award(src, 'criminal', 75)
                                    exports.pengu_xp:Award(src, 'drugs',    50)
                                end)
                            end
                        end
                    end
                end
            end
        end
        Wait(1800000)
    end
end)

-- ===================== lab admin commands (/lab) =====================
local function labAdmin(src)
    if src > 0 and not IsPlayerAceAllowed(src, ACE) then
        DrugNotify(src, 'you are not allowed to manage labs.', 'error'); return false
    end
    if src > 0 and not exports.qbx_core:IsOptin(src) then
        DrugNotify(src, 'you must /aduty before using /lab.', 'error'); return false
    end
    return true
end

-- /labenable <group_name>  — enables all tables in a lab group
RegisterCommand('labenable', function(src, args)
    if not labAdmin(src) then return end
    local grp = tostring(args[1] or ''):lower()
    if grp == '' then DrugNotify(src, 'usage: /labenable <group_name>', 'error'); return end
    local found = false
    for _, lab in pairs(LABS) do if lab.group_name == grp then found = true; break end end
    if not found then DrugNotify(src, ('no labs in group "%s". use /lablist to see groups.'):format(grp), 'error'); return end
    MySQL.update.await('UPDATE pengu_drug_labs SET active = 1 WHERE group_name = ?', { grp })
    for _, lab in pairs(LABS) do if lab.group_name == grp then lab.active = true end end
    BroadcastLabs()
    DrugNotify(src, ('lab group "%s" is now ENABLED.'):format(grp), 'success', 'LAB')
end, false)

-- /labdisable <group_name>  — disables all tables in a lab group (props stay visible; interaction shows "closed")
RegisterCommand('labdisable', function(src, args)
    if not labAdmin(src) then return end
    local grp = tostring(args[1] or ''):lower()
    if grp == '' then DrugNotify(src, 'usage: /labdisable <group_name>', 'error'); return end
    local found = false
    for _, lab in pairs(LABS) do if lab.group_name == grp then found = true; break end end
    if not found then DrugNotify(src, ('no labs in group "%s". use /lablist to see groups.'):format(grp), 'error'); return end
    MySQL.update.await('UPDATE pengu_drug_labs SET active = 0 WHERE group_name = ?', { grp })
    for _, lab in pairs(LABS) do if lab.group_name == grp then lab.active = false end end
    BroadcastLabs()
    DrugNotify(src, ('lab group "%s" is now DISABLED. Props remain; players see "lab closed".'):format(grp), 'error', 'LAB')
end, false)

-- /labadd <type> <group_name> [label]  — places a new table in a group at the admin's position
RegisterCommand('labadd', function(src, args)
    if not labAdmin(src) then return end
    local ltype = tostring(args[1] or ''):lower()
    if not Config.labTypes[ltype] then
        local valid = {}
        for k in pairs(Config.labTypes) do valid[#valid + 1] = k end
        DrugNotify(src, 'invalid type. valid: ' .. table.concat(valid, ', '), 'error'); return
    end
    local grp = tostring(args[2] or ''):lower()
    if grp == '' then DrugNotify(src, 'usage: /labadd <type> <group_name> [label]', 'error'); return end
    table.remove(args, 1); table.remove(args, 1)
    local label = (#args > 0) and table.concat(args, ' ') or Config.defaultLabel
    local ped = GetPlayerPed(src)
    local c   = GetEntityCoords(ped)
    local newId = MySQL.insert.await(
        'INSERT INTO pengu_drug_labs (lab_type, label, x, y, z, active, group_name) VALUES (?, ?, ?, ?, ?, 1, ?)',
        { ltype, label, c.x + 0.0, c.y + 0.0, c.z + 0.0, grp })
    LABS[newId] = { id = newId, type = ltype, label = label, x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0, active = true, group_name = grp }
    BroadcastLabs()
    DrugNotify(src, ('added %s table #%d to group "%s" at your position.'):format(ltype, newId, grp), 'success', 'LAB')
end, false)

-- /labremove <id>  — permanently deletes a single lab table
RegisterCommand('labremove', function(src, args)
    if not labAdmin(src) then return end
    local id = tonumber(args[1])
    if not id then DrugNotify(src, 'usage: /labremove <id>', 'error'); return end
    local lab = LABS[id]
    if not lab then DrugNotify(src, ('no lab table with id %d.'):format(id), 'error'); return end
    MySQL.query.await('DELETE FROM pengu_drug_labs WHERE id = ?', { id })
    LABS[id] = nil
    BroadcastLabs()
    DrugNotify(src, ('removed table #%d "%s" from group "%s".'):format(id, lab.label, lab.group_name), 'success', 'LAB')
end, false)

-- /lablist  — show all lab groups with table count and status
RegisterCommand('lablist', function(src)
    if not labAdmin(src) then return end
    local groups = {}
    for _, lab in pairs(LABS) do
        local g = (lab.group_name and lab.group_name ~= '') and lab.group_name or ('(id=' .. lab.id .. ')')
        groups[g] = groups[g] or { active = lab.active, count = 0 }
        groups[g].count = groups[g].count + 1
    end
    local any = false
    for gname, info in pairs(groups) do
        local status = info.active and 'ON ' or 'OFF'
        DrugNotify(src, ('[%s] %s  (%d table(s))'):format(status, gname, info.count), 'inform', 'LAB')
        any = true
    end
    if not any then DrugNotify(src, 'no labs registered.', 'inform', 'LAB') end
end, false)
