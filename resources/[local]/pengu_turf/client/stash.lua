-- PenguRP Gang Territory - STASH perk (client). Renders an ox_target interaction inside every
-- stash-perk zone the player's gang controls. The server callback validates access before the
-- inventory is opened. Rebuilds whenever penguTurf changes or gang membership changes.
-- ASCII only. luac clean.

local stashZones = {}  -- zone key (string) -> ox_target zone id

local function myGang()
    local pd = exports.qbx_core:GetPlayerData()
    local n  = pd and pd.gang and pd.gang.name
    return (n and n ~= 'none' and Factions.isCriminal(n)) and n or nil
end

local function clearStashes()
    for _, zid in pairs(stashZones) do
        if zid then exports.ox_target:removeZone(zid) end
    end
    stashZones = {}
end

local function rebuildStashes()
    clearStashes()
    local gang = myGang()
    if not gang then return end
    local turf = GlobalState.penguTurf
    if type(turf) ~= 'table' then return end
    for _, z in pairs(turf) do
        if (z.perk or '') == 'stash' and (z.owner or '') == gang then
            local zkey = tostring(z.key or '')
            local zid = exports.ox_target:addSphereZone({
                coords  = vector3(z.x + 0.0, z.y + 0.0, z.z + 0.0),
                radius  = 3.0,
                debug   = false,
                options = {
                    {
                        name     = 'pengu_stash_zone_' .. zkey,
                        icon     = 'fa-solid fa-box-archive',
                        label    = 'Gang Safehouse',
                        onSelect = function()
                            local stashId = lib.callback.await('pengu_turf:openStash', false)
                            if stashId then
                                exports.ox_inventory:openInventory('stash', stashId)
                            else
                                lib.notify({ title = 'Turf', description = 'Access denied.', type = 'error' })
                            end
                        end,
                    },
                },
            })
            stashZones[zkey] = zid
        end
    end
end

AddStateBagChangeHandler('penguTurf', 'global', function() rebuildStashes() end)

CreateThread(function()
    while not exports.qbx_core:GetPlayerData() do Wait(250) end
    rebuildStashes()
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate',   function() rebuildStashes() end)
RegisterNetEvent('qbx_core:client:onGangUpdate', function() rebuildStashes() end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearStashes() end
end)
