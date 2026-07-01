-- PenguRP Gang Territory (pengu_turf) - SERVER dealer-driven influence feed.
-- "Keeping dealers happy" = CONTROLLING dealers via pengu_dealers (their influence/decay system). Every
-- Config.dealerFeedMs, each dealer a gang CONTROLS that physically sits INSIDE a turf zone feeds
-- Config.dealerInfluencePerFeed into that gang's influence in that zone (via AddInfluence, so the gang's
-- level cap on number of zones still applies). This is the dealer half of "take turf through dealers +
-- graffiti"; graffiti.lua is the other half. No more cosmetic dealer boxes. ASCII only. luac clean.

local function feedDealers()
    local ok, dlist = pcall(function() return exports.pengu_dealers:GetControlledDealers() end)
    if not ok or type(dlist) ~= 'table' then return end
    for _, d in ipairs(dlist) do
        if d and d.gang and IsValidGang(d.gang) then
            local dx, dy, dz = (d.x or 0.0) + 0.0, (d.y or 0.0) + 0.0, (d.z or 0.0) + 0.0
            local zone = ZoneAtCoords(vector3(dx, dy, dz))
            -- a controlled dealer on OPEN ground claims a fresh block for its gang (capped by level)
            if not zone and CanClaimNewZone(d.gang) then zone = EnsureCellAt(dx, dy, dz) end
            -- only feed contested (non-core) zones; a dealer parked in someone's core does nothing.
            if zone and (zone.core or '') == '' then
                AddInfluence(zone.id, d.gang, Config.dealerInfluencePerFeed or 18)
            end
        end
    end
end

CreateThread(function()
    GlobalState.penguTurfDealers = {} -- clear the retired cosmetic dealer-box layer (stale from old builds)
    while next(ZONES) == nil do Wait(1000) end
    while true do
        Wait(Config.dealerFeedMs or 60000)
        local ok, err = pcall(feedDealers)
        if not ok then print('[pengu_turf] dealer feed error: ' .. tostring(err)) end
    end
end)

-- pengu_dealers calls this after add/remove/reset/influence-decay so a control change is reflected in
-- turf without waiting a full feed tick.
exports('RecomputeDealerTurf', function()
    local ok, err = pcall(feedDealers)
    if not ok then print('[pengu_turf] dealer feed (recompute) error: ' .. tostring(err)) end
end)
