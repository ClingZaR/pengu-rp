local function commas(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    return s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

RegisterNetEvent('pengu_core:requestStats', function()
    local src    = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local pd  = player.PlayerData
    local cid = pd.citizenid

    local vehicles, houses = 0, 0

    local ok1, vRows = pcall(function()
        return MySQL.query.await('SELECT COUNT(*) AS n FROM player_vehicles WHERE citizenid = ?', { cid })
    end)
    if ok1 and vRows and vRows[1] then vehicles = vRows[1].n or 0 end

    local ok2, pRows = pcall(function()
        return MySQL.query.await('SELECT COUNT(*) AS n FROM properties WHERE owner = ?', { cid })
    end)
    if ok2 and pRows and pRows[1] then houses = pRows[1].n or 0 end

    local debt = 0
    if GetResourceState('Renewed-Banking') == 'started' then
        local ok, d = pcall(function() return exports['Renewed-Banking']:getAccountDebt(cid) end)
        if ok and d then debt = d end
    end

    local name = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname

    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:stats',
        args = {
            name,                                          -- {0}
            vehicles .. '/22',                             -- {1}
            houses .. '/4',                                -- {2}
            pd.job.label or 'Unemployed',                  -- {3}
            tostring(pd.charinfo.phone or 'N/A'),          -- {4}
            commas(pd.money.bank or 0),                    -- {5}
            commas(pd.money.cash or 0),                    -- {6}
            commas(debt),                                  -- {7}
            commas(pd.job.payment or 0),                   -- {8}
        },
    })
end)
