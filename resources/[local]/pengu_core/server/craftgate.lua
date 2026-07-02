-- PenguRP Gun Bench Level Gate (pengu_core) - SERVER. ox_inventory 'craftItem'
-- hook: crafting a WEAPON_* recipe at a gated bench requires pengu_xp criminal
-- level 3+. Ammo recipes (ammo-9 etc.) stay ungated. The pengu_xp call is
-- pcall-guarded and FAIL-OPEN: if pengu_xp is down or misbehaves, crafting
-- proceeds (never soft-lock the bench on a dependency).
-- Hook payload (ox_inventory modules/crafting/server.lua TriggerEventHooks):
-- { source, benchId, benchIndex, recipe, toInventory, toSlot }; returning false
-- rejects the craft. ASCII only. luac clean.

local REQUIRED_LEVEL = 3

-- benches whose WEAPON_* recipes are criminal-gated (a future legal armory
-- bench would simply not be listed here)
local GATED_BENCHES = {
    pengu_scrapyard_gunsmith = true,
}

local function craftGate(payload)
    local recipe = payload and payload.recipe
    local name = recipe and recipe.name
    if type(name) ~= 'string' or name:sub(1, 7) ~= 'WEAPON_' then return end
    if not GATED_BENCHES[tostring(payload.benchId)] then return end

    local src = payload.source
    local ok, level = pcall(function()
        return exports.pengu_xp:GetLevel(src, 'criminal')
    end)
    if not ok or type(level) ~= 'number' then return end -- fail-open: pengu_xp unavailable

    if level < REQUIRED_LEVEL then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Workbench',
            description = ('You lack the criminal know-how for this. (Criminal level %d)'):format(REQUIRED_LEVEL),
            type = 'error',
            duration = 6000,
        })
        return false
    end
end

local registered = false

local function registerGate()
    local ok = pcall(function()
        exports.ox_inventory:registerHook('craftItem', craftGate)
    end)
    if ok then
        registered = true
    else
        print('[pengu_core] craftgate: could not register ox_inventory craftItem hook')
    end
end

-- ox_inventory wipes registered hooks when IT restarts, so re-register then;
-- the flag guards against a double-add within one ox_inventory lifetime
AddEventHandler('onServerResourceStart', function(res)
    if res == 'ox_inventory' then
        registered = false
        registerGate()
    end
end)

CreateThread(function()
    if not registered and GetResourceState('ox_inventory') == 'started' then
        registerGate()
    end
end)
