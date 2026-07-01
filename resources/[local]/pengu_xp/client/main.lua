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

RegisterCommand('myxp', function()
    -- fetch latest from server (also updates local cache)
    local data = lib.callback.await('pengu_xp:getData', false)
    if data then xpData = data end

    local options = {}
    -- define display order
    local order = { 'criminal', 'drugs', 'mining', 'fishing', 'farming', 'hunting', 'cooking', 'lumberjack', 'fitness' }
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
