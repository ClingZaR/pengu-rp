-- PenguRP Character XP (pengu_xp) - CLIENT. /myxp context menu with category progress bars.
-- ASCII only. luac clean.

local xpData = {}  -- [category] = xp total (kept live via sync event)

local function calcLevel(xp, thresholds)
    local level = 1
    for i = #thresholds, 2, -1 do
        if xp >= thresholds[i] then level = i; break end
    end
    return level
end

-- build unicode block progress bar (10 chars wide)
local function progressBar(pct)
    local filled = math.floor(pct / 10)
    return string.rep('\xe2\x96\x88', filled) .. string.rep('\xe2\x96\x91', 10 - filled)
end

-- server pushes live updates on every XP award
RegisterNetEvent('pengu_xp:sync', function(data)
    xpData = data or {}
end)

-- which categories have job perks (derived from the ptype->category maps in shared config)
local gatherCats, sellCats = {}, {}
for _, m in pairs(Config.jobsXP or {}) do gatherCats[m.category] = true end
for _, m in pairs(Config.sellXP or {}) do sellCats[m.category] = true end

-- perk tables live in pengu_jobs Config.perks; pcall in case it is not running
local function getPerks()
    local ok, perks = pcall(function() return exports.pengu_jobs:GetPerks() end)
    if ok and type(perks) == 'table' then return perks end
    return nil
end

local function perkLine(key, level, perks)
    if not perks then return nil end
    local bits = {}
    local cd = perks.gatherCooldownMult
    if gatherCats[key] and type(cd) == 'table' and #cd > 0 then
        local i = math.min(level, #cd)
        bits[#bits + 1] = ('-%d%% gather cooldown'):format(math.floor((1.0 - (cd[i] or 1.0)) * 100 + 0.5))
    end
    local sb = perks.sellBonusPct
    if sellCats[key] and type(sb) == 'table' and #sb > 0 then
        local i = math.min(level, #sb)
        bits[#bits + 1] = ('+%d%% sell prices'):format(math.floor((sb[i] or 0) * 100 + 0.5))
    end
    local dv = perks.deliveryBonusPct
    if key == (Config.deliveryXP and Config.deliveryXP.category) and type(dv) == 'table' and #dv > 0 then
        local i = math.min(level, #dv)
        bits[#bits + 1] = ('+%d%% delivery pay'):format(math.floor((dv[i] or 0) * 100 + 0.5))
    end
    if #bits == 0 then return nil end
    return ('Level %d: %s'):format(level, table.concat(bits, ', '))
end

RegisterCommand('myxp', function()
    -- fetch latest from server (also updates local cache)
    local data = lib.callback.await('pengu_xp:getData', false)
    if data then xpData = data end

    local options = {}
    local perks = getPerks()
    -- define display order
    local order = { 'criminal', 'drugs', 'mining', 'fishing', 'farming', 'hunting', 'cooking', 'lumberjack', 'delivery', 'fitness' }
    for _, key in ipairs(order) do
        local cat = Config.categories[key]
        if cat then
            local xp      = tonumber((xpData or {})[key]) or 0
            local level   = calcLevel(xp, cat.thresholds)
            local maxLvl  = #cat.thresholds
            local nextXP  = cat.thresholds[level + 1]
            local prevXP  = cat.thresholds[level] or 0
            local pct, desc
            if nextXP then
                local span = nextXP - prevXP
                local done = xp - prevXP
                pct  = math.floor((done / span) * 100)
                desc = ('Lv %d  %d / %d XP  [%s] %d%%'):format(level, xp, nextXP, progressBar(pct), pct)
            else
                pct  = 100
                desc = ('Lv %d (MAX)  %d XP  [%s]'):format(level, xp, progressBar(100))
            end
            local pline = perkLine(key, level, perks)
            if pline then desc = desc .. '\n' .. pline end
            options[#options + 1] = {
                title       = cat.label,
                description = desc,
                icon        = cat.icon,
                progress    = pct,
                readOnly    = true,
            }
        end
    end

    lib.registerContext({
        id      = 'pengu_myxp',
        title   = 'My Character XP',
        options = options,
    })
    lib.showContext('pengu_myxp')
end, false)

TriggerEvent('chat:addSuggestion', '/myxp', 'View your character XP across all skill categories', {})
