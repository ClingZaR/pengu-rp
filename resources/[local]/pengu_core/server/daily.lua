-- PenguRP Daily Login Bonus (pengu_core) - SERVER. Tracks last login date in player metadata.
-- On first login of each calendar day (server timezone), awards dirty money + gang rep.
-- Streak: consecutive days give escalating rewards up to day 7 (then resets). ASCII only. luac clean.

local qbx = exports.qbx_core
local ox  = exports.ox_inventory

local DIRTY = 'black_money'

-- Streak table: day -> { dirty, rep }. Day 1 is the baseline; day 7 is the jackpot.
local STREAK = {
    [1] = { dirty = 500,  rep = 50  },
    [2] = { dirty = 750,  rep = 75  },
    [3] = { dirty = 1000, rep = 100 },
    [4] = { dirty = 1250, rep = 125 },
    [5] = { dirty = 1500, rep = 150 },
    [6] = { dirty = 2000, rep = 200 },
    [7] = { dirty = 3000, rep = 300 },
}

local function todayStamp()
    local t = os.date('*t')
    return ('%04d-%02d-%02d'):format(t.year, t.month, t.mday)
end

local function yesterdayStamp()
    local t = os.date('*t', os.time() - 86400)
    return ('%04d-%02d-%02d'):format(t.year, t.month, t.mday)
end

local function notify(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Daily Bonus', description = msg,
        type = kind or 'success', duration = 8000,
    })
end

AddEventHandler('QBCore:Server:PlayerLoaded', function()
    local src = source
    CreateThread(function()
        Wait(2000) -- let player data settle
        local p = qbx:GetPlayer(src)
        if not p then return end
        local meta    = p.PlayerData.metadata or {}
        local today   = todayStamp()
        local lastDay = tostring(meta.lastLoginDay or '')
        if lastDay == today then return end -- already claimed today

        -- calculate streak
        local streak = tonumber(meta.loginStreak) or 0
        if lastDay == yesterdayStamp() then
            streak = math.min(7, streak + 1)
        else
            streak = 1  -- streak broken
        end

        local reward = STREAK[streak] or STREAK[1]

        p.Functions.SetMetaData('lastLoginDay', today)
        p.Functions.SetMetaData('loginStreak',  streak)

        -- give dirty money (non-criminals get cash instead)
        local gang = p.PlayerData.gang
        local isCrim = gang and gang.name and gang.name ~= 'none' and Factions.isCriminal(gang.name)

        if isCrim then
            ox:AddItem(src, DIRTY, reward.dirty)
            pcall(function()
                exports.pengu_gangs:AddRep(gang.name, reward.rep)
            end)
            pcall(function()
                -- streak day gives escalating Criminal XP (50 base + 25 per day)
                exports.pengu_xp:Award(src, 'criminal', 50 + (streak - 1) * 25)
            end)
            notify(src,
                ('Day %d streak! +$%d dirty money +%d gang rep%s'):format(
                    streak, reward.dirty, reward.rep,
                    streak == 7 and ' (MAX STREAK!)' or ''),
                'success')
        else
            p.Functions.AddMoney('cash', reward.dirty, 'daily-bonus')
            pcall(function()
                exports.pengu_xp:Award(src, 'criminal', 25 + (streak - 1) * 10)
            end)
            notify(src,
                ('Day %d login streak! +$%d cash'):format(streak, reward.dirty),
                'success')
        end
    end)
end)
