-- PenguRP Gang Territory - STASH perk (server). One shared gang stash per criminal gang is
-- registered with ox_inventory at boot. Access is gated by a callback: the player must be in their
-- gang, standing inside a stash-perk zone their gang controls. ASCII only. luac clean.

local ox  = exports.ox_inventory
local qbx = exports.qbx_core

-- Register one permanent shared stash per criminal gang at boot. Idempotent - safe to re-call.
CreateThread(function()
    while next(ZONES) == nil do Wait(1000) end -- wait for main.lua zones to be loaded
    local slots = (Config.perks.stash and Config.perks.stash.slots) or 50
    local n = 0
    -- ox_inventory RegisterStash is POSITIONAL: (id, label, slots, maxWeight, owner, groups, coords).
    -- owner omitted = a shared stash; access is gated by the pengu_turf:openStash callback below.
    for gang in pairs(Factions.criminal or {}) do
        ox:RegisterStash('pengu_stash_' .. gang, LabelOf(gang) .. ' Safehouse', slots, 100000)
        n = n + 1
    end
    print(('[pengu_turf] stash: %d gang stashes registered.'):format(n))
end)

-- Validate and return the stash ID. Player must be:
--   1. In a criminal gang
--   2. Standing inside a zone that gang controls with perk = 'stash'
lib.callback.register('pengu_turf:openStash', function(src)
    local gang = GangOf(src)
    if not gang then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local z = ZoneAtCoords(GetEntityCoords(ped))
    if not z or z.owner ~= gang or z.perk ~= 'stash' then return nil end
    return 'pengu_stash_' .. gang
end)
