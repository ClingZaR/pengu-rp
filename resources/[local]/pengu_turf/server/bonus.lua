-- PenguRP Gang Territory (pengu_turf) - drug-spot bonus (Phase 2, NO qbx_drugs fork).
-- Drug sales inside a turf zone alert police and award a perk cash cut when the gang CONTROLS
-- the zone. Turf INFLUENCE is driven solely by dealer control (pengu_dealers) and graffiti tags
-- (graffiti.lua) -- drug sales no longer build influence directly. ASCII only. luac clean.

local qbx = exports.qbx_core
local SALE_REASONS = { ['sold-cornerdrugs'] = true, ['drug-delivery'] = true }

-- per-zone dispatch cooldown so police aren't spammed on every individual sale
local drugDispatchAt = {}  -- zoneId -> os.time() of last alert
local DRUG_DISPATCH_CD = 300  -- 5 min between alerts per zone

-- The in-memory BLOCK containing a world position, or nil. Delegates to the rectangle resolver in
-- influence.lua (block zones have no .radius, so the old circle test always failed -> bonuses never fired).
local function zoneAt(coords)
    return ZoneAtCoords(coords)
end

AddEventHandler('QBCore:Server:OnMoneyChange', function(src, _moneyType, amount, _actionType, reason)
    if not SALE_REASONS[reason] then return end
    amount = tonumber(amount) or 0
    if amount <= 0 then return end

    local gang = GangOf(src)
    if not gang then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local z = zoneAt(GetEntityCoords(ped))
    if not z then return end

    -- dispatch: alert police to drug activity in this zone (rate-limited per zone)
    local now = os.time()
    if not drugDispatchAt[z.id] or (now - drugDispatchAt[z.id]) >= DRUG_DISPATCH_CD then
        drugDispatchAt[z.id] = now
        pcall(function()
            exports.pengu_core:Dispatch(
                vector3(z.x, z.y, z.z),
                { message = 'Drug Activity Reported', code = '10-15', icon = 'fas fa-pills',
                  priority = 2, jobs = { 'police', 'bcso', 'sasp' } }
            )
        end)
    end

    -- owned-turf perks: extra cash cut + territory rep
    if z.owner == gang then
        local pct = Config.saleBonusPct or 0
        if z.perk == 'drug_bonus' and Config.perks.drug_bonus then
            pct = pct + (Config.perks.drug_bonus.saleBonus or 0)
        end
        local bonus = math.floor(amount * pct)
        local p = qbx:GetPlayer(src)
        if bonus > 0 and p and p.Functions and p.Functions.AddMoney then
            p.Functions.AddMoney('cash', bonus, 'turf-bonus')
            TurfNotify(src, ('Turf bonus: +$%d for dealing on %s turf.'):format(bonus, LabelOf(gang)), 'success')
        end
        AwardTurfRep(gang, 'drugSaleInTurf')
    end
end)
