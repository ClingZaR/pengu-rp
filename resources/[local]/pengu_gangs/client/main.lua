-- PenguRP Gang Reputation & Level (pengu_gangs) - CLIENT.
-- Reads GlobalState.penguGangProgress for live rep/level; shows level-up toasts and
-- a /gangstatus display. ASCII only. luac clean.

TriggerEvent('chat:addSuggestion', '/ganginfo',   'Show your gang level and reputation', {})
TriggerEvent('chat:addSuggestion', '/gangstatus', 'Show your gang level and reputation', {})

local lastKnownLevel = 0  -- tracked to detect level-ups without a server event

local function myGang()
    local pd = exports.qbx_core:GetPlayerData()
    local n  = pd and pd.gang and pd.gang.name
    return (n and n ~= 'none' and Factions.isCriminal(n)) and n or nil
end

local function gangProgress(gang)
    if not gang then return nil end
    local gp = GlobalState.penguGangProgress
    return gp and gp[gang]
end

-- Show a brief level-up toast when our gang's level increases.
AddStateBagChangeHandler('penguGangProgress', 'global', function(_, _, value)
    if not value then return end
    local gang = myGang()
    if not gang then return end
    local p = value[gang]
    if not p then return end
    local newLevel = tonumber(p.level) or 1
    if lastKnownLevel > 0 and newLevel > lastKnownLevel then
        lib.notify({
            title       = 'Gang Level Up!',
            description = ('Your crew reached Level %d - new imports and perks unlocked.'):format(newLevel),
            type        = 'success',
            duration    = 8000,
            position    = 'top',
        })
    end
    lastKnownLevel = newLevel
end)

-- /gangstatus: display a context-style ox_lib alert with progress info.
RegisterCommand('gangstatus', function()
    local gang = myGang()
    if not gang then
        lib.notify({ title = 'Gang', description = 'You are not in a gang.', type = 'error' })
        return
    end
    local p = gangProgress(gang)
    if not p then
        lib.notify({ title = 'Gang', description = 'No progress data yet.', type = 'inform' })
        return
    end
    local level = tonumber(p.level) or 1
    local rep   = tonumber(p.rep) or 0
    local cfg   = Config.levels
    local next  = cfg and cfg[level + 1]
    local label = Factions.labelOf('criminal', gang)
    local body
    if next then
        local pct = math.floor((rep / next) * 100)
        body = ('Level %d  |  Rep %d / %d  (%d%% to Lv %d)'):format(level, rep, next, pct, level + 1)
    else
        body = ('Level %d (MAX)  |  Rep %d'):format(level, rep)
    end
    lib.notify({ title = label, description = body, type = 'inform', duration = 6000 })
end, false)

CreateThread(function()
    -- wait for player data to be ready, then seed lastKnownLevel
    while not exports.qbx_core:GetPlayerData() do Wait(250) end
    local gang = myGang()
    if gang then
        local p = gangProgress(gang)
        lastKnownLevel = p and (tonumber(p.level) or 1) or 1
    end
end)

-- /gangranking — sorted leaderboard of all gangs by rep
RegisterCommand('gangranking', function()
    local gp = GlobalState.penguGangProgress
    if not gp then
        lib.notify({ title = 'Gang Ranking', description = 'No data yet.', type = 'inform' }); return
    end
    local rows = {}
    for gang, p in pairs(gp) do
        rows[#rows + 1] = { gang = gang, rep = tonumber(p.rep) or 0, level = tonumber(p.level) or 1 }
    end
    table.sort(rows, function(a, b) return a.rep > b.rep end)
    local options = {}
    for i, r in ipairs(rows) do
        local label = Factions.labelOf('criminal', r.gang) or r.gang
        options[#options + 1] = {
            title       = ('#%d  %s'):format(i, label),
            description = ('Level %d  |  %d Rep'):format(r.level, r.rep),
            icon        = 'fa-solid fa-ranking-star',
            readOnly    = true,
        }
    end
    if #options == 0 then
        lib.notify({ title = 'Gang Ranking', description = 'No gangs tracked yet.', type = 'inform' }); return
    end
    lib.registerContext({ id = 'pengu_gang_ranking', title = 'Gang Rankings', options = options })
    lib.showContext('pengu_gang_ranking')
end, false)

TriggerEvent('chat:addSuggestion', '/gangranking', 'Show the gang reputation leaderboard', {})
