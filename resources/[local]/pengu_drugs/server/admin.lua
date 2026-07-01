-- PenguRP Drug Supply Chain (pengu_drugs) - admin in-game setup (/drugloc). Reuses the pdloc RECIPE:
-- NEW ace 'pengu.drugs' (separate from pengu.placement / pengu.turf) + qbx /aduty optin, server-side
-- live ped capture, live broadcast with no restart. ASCII only. luac clean.

local ACE = 'pengu.drugs'

local function usage(src)
    DrugNotify(src, '/drugloc add <type> [label]  - add a lab at your position', 'inform')
    DrugNotify(src, '/drugloc remove <id>          - delete a lab', 'inform')
    DrugNotify(src, '/drugloc list                 - list labs', 'inform')
    local types = {}
    for k in pairs(Config.labTypes) do types[#types + 1] = k end
    DrugNotify(src, 'valid types: ' .. table.concat(types, ', '), 'inform')
end

local function cmdAdd(src, args)
    if src <= 0 then DrugNotify(src, 'run this in-game (it needs your position).', 'error'); return end
    local ltype = tostring(args[2] or ''):lower()
    if not Config.labTypes[ltype] then DrugNotify(src, ('invalid lab type "%s".'):format(ltype), 'error'); return end
    local label
    if #args >= 3 then label = table.concat({ table.unpack(args, 3) }, ' '):sub(1, 64)
    else label = Config.labTypes[ltype].label or Config.defaultLabel end

    local c = GetEntityCoords(GetPlayerPed(src))
    local ok = pcall(MySQL.insert.await,
        'INSERT INTO pengu_drug_labs (lab_type, label, x, y, z) VALUES (?, ?, ?, ?, ?)',
        { ltype, label, c.x + 0.0, c.y + 0.0, c.z + 0.0 })
    if not ok then DrugNotify(src, 'could not add lab (db error).', 'error'); return end
    LoadLabs(); BroadcastLabs()
    DrugNotify(src, ('added %s lab "%s" at your position.'):format(ltype, label), 'success')
end

local function cmdRemove(src, args)
    local id = tonumber(args[2])
    if not id then DrugNotify(src, 'usage: /drugloc remove <id>', 'error'); return end
    local affected = MySQL.update.await('DELETE FROM pengu_drug_labs WHERE id = ?', { id })
    if affected and affected > 0 then
        LoadLabs(); BroadcastLabs()
        DrugNotify(src, ('removed lab #%d.'):format(id), 'success')
    else
        DrugNotify(src, 'no lab with that id.', 'error')
    end
end

local function cmdList(src)
    local any = false
    for _, l in pairs(LABS) do
        any = true
        DrugNotify(src, ('#%d %s "%s" (%.0f,%.0f,%.0f)'):format(l.id, l.type, l.label, l.x, l.y, l.z), 'inform')
    end
    if not any then DrugNotify(src, 'no labs placed.', 'inform') end
end

RegisterCommand('drugloc', function(src, args)
    if not IsPlayerAceAllowed(src, ACE) then DrugNotify(src, 'you are not allowed to manage labs.', 'error'); return end
    if not exports.qbx_core:IsOptin(src) then DrugNotify(src, 'you must /aduty before using /drugloc.', 'error'); return end
    local sub = tostring(args[1] or ''):lower()
    if     sub == 'add'    then cmdAdd(src, args)
    elseif sub == 'remove' or sub == 'delete' then cmdRemove(src, args)
    elseif sub == 'list'   then cmdList(src)
    else usage(src) end
end, false)
