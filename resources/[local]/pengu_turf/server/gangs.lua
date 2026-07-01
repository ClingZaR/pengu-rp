-- PenguRP Gang Territory (pengu_turf) - SERVER gang/util foundation. ASCII only. luac clean.
-- pengu_core's resolveFaction/membersOf are file-local + not exported, so this re-derives gang
-- membership from the live qbx Player object (the same data those helpers read). All functions are
-- GLOBAL so the other server files in this resource (capture/income/bonus/admin/main) can call them.

local qbx = exports.qbx_core

-- chat feedback via the cross-resource qbx_chat_theme 'pengu:admin' template (ok=green/err=red/info=lavender).
local KIND = { success = 'ok', error = 'err', inform = 'info' }
function TurfNotify(src, msg, kind, tag)
    if not src or src <= 0 then print('[pengu_turf] ' .. tostring(msg)); return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { tag or 'TURF', msg, KIND[kind or 'inform'] or 'info' },
    })
end

-- The gang key a source belongs to (or nil). Mirrors pengu_core resolveFaction's criminal path.
-- Returns: gangName, gradeLevel, isBoss.
function GangOf(src)
    local p = qbx:GetPlayer(src)
    local g = p and p.PlayerData and p.PlayerData.gang
    local name = g and g.name
    if not name or name == 'none' then return nil end
    if not Factions.isCriminal(name) then return nil end
    return name, (g.grade and g.grade.level) or 0, g.isboss == true
end

-- A gang key is a real ownable gang (not nil/none/'' and a known criminal faction).
function IsValidGang(key)
    return key ~= nil and key ~= '' and key ~= 'none' and Factions.isCriminal(key) == true
end

-- Pause-map fill colour for an owner key ('' / unknown -> neutral grey).
function ColourOf(owner)
    local g = owner and Config.gangs[owner]
    return (g and g.colour) or Config.neutralColour
end

-- Display label for a gang key ('' -> 'Neutral').
function LabelOf(owner)
    if not owner or owner == '' or owner == 'none' then return 'Neutral' end
    local g = Config.gangs[owner]
    return (g and g.label) or owner
end

-- Send a TURF chat line to every ONLINE member of a gang.
function NotifyGang(gang, msg, kind)
    if not gang or gang == '' or gang == 'none' then return end
    for src, p in pairs(qbx:GetQBPlayers() or {}) do
        local g = p.PlayerData and p.PlayerData.gang
        if g and g.name == gang then TurfNotify(src, msg, kind, 'TURF') end
    end
end
