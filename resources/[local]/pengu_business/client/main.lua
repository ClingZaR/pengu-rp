-- PenguRP Business Ownership (pengu_business) - CLIENT. A "Buy" ox_target + a map blip on each
-- business management point. Owned businesses are managed via qbx_management's own boss-menu zone
-- (registered server-side) + the owner's bank account; this client only handles discovery + purchase.
-- ASCII only. luac clean.

local zoneIds = {}
local blips = {}
local list = {}

local function clearAll()
    for _, zid in pairs(zoneIds) do if zid then exports.ox_target:removeZone(zid) end end
    zoneIds = {}
    for _, b in pairs(blips) do if b and DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end

local function buyBusiness(biz)
    local ok = lib.alertDialog({
        header = biz.label,
        content = ('Buy this business for **$%d** (from your bank)?\n\nYou become the owner and can hire staff at the front desk.'):format(biz.price or 0),
        centered = true,
        cancel = true,
    })
    if ok ~= 'confirm' then return end
    local done = lib.callback.await('pengu_business:buy', false, biz.id)
    if not done then lib.notify({ title = 'Business', description = 'Purchase did not go through.', type = 'error' }) end
end

local function rebuild(businesses)
    list = businesses or {}
    clearAll()
    if type(list) ~= 'table' then return end
    for _, biz in ipairs(list) do
        local ref = biz
        -- map blip (sprite 375 = building/store-ish; colour green if for sale, grey if owned)
        local blip = AddBlipForCoord(biz.x + 0.0, biz.y + 0.0, biz.z + 0.0)
        SetBlipSprite(blip, 375)
        SetBlipColour(blip, biz.owned and 0 or 2)
        SetBlipScale(blip, 0.8)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(biz.label .. (biz.owned and '' or ' (For Sale)'))
        EndTextCommandSetBlipName(blip)
        blips[biz.id] = blip

        -- buy target: only meaningful while the business is unowned (canInteract re-checks live state)
        zoneIds[biz.id] = exports.ox_target:addSphereZone({
            coords = vector3(biz.x + 0.0, biz.y + 0.0, biz.z + 0.0),
            radius = 2.5,
            debug = false,
            options = {
                {
                    name = 'pengu_business_buy_' .. biz.id,
                    icon = 'fa-solid fa-store',
                    label = ('Buy %s ($%d)'):format(biz.label, biz.price or 0),
                    canInteract = function()
                        for _, x in ipairs(list) do if x.id == ref.id then return not x.owned end end
                        return false
                    end,
                    onSelect = function() buyBusiness(ref) end,
                },
            },
        })
    end
end

RegisterNetEvent('pengu_business:updated', function(businesses) rebuild(businesses) end)

CreateThread(function()
    rebuild(lib.callback.await('pengu_business:getBusinesses', false))
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    rebuild(lib.callback.await('pengu_business:getBusinesses', false))
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearAll() end
end)

TriggerEvent('chat:addSuggestion', '/bizloc', 'Manage businesses (admin)', {
    { name = 'subcommand', help = 'register <key> <price> [label] | setowner | setprice | remove | list' },
})
