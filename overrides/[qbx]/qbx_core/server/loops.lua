local config = require 'config.server'

local function removeHungerAndThirst(src, player)
    local playerState = Player(src).state
    if not playerState.isLoggedIn then return end
    local newHunger = playerState.hunger - config.player.hungerRate
    local newThirst = playerState.thirst - config.player.thirstRate

    player.Functions.SetMetaData('thirst', newThirst)
    player.Functions.SetMetaData('hunger', newHunger)

    player.Functions.Save()
end

CreateThread(function()
    local interval = 60000 * config.updateInterval
    while true do
        Wait(interval)
        for src, player in pairs(QBX.Players) do
            removeHungerAndThirst(src, player)
        end
    end
end)

local function pay(player)
    local job = player.PlayerData.job
    local payment = GetJob(job.name).grades[job.grade.level].payment or job.payment
    if payment <= 0 then return end
    if not GetJob(job.name).offDutyPay and not job.onduty then return end
    -- PenguRP edit (pengu_finance): income tax. Rate read from GlobalState.penguTaxRate
    -- (pengu_gov owns setting it; default 0.05), clamped 0-0.25. The tax is only deducted
    -- if the deposit into the 'government' Renewed-Banking society account (created on
    -- pengu_finance boot) actually succeeds, so money is never destroyed and a banking
    -- hiccup can never block paychecks (pcall-guarded).
    local taxRate = tonumber(GlobalState.penguTaxRate) or 0.05
    if taxRate < 0 then taxRate = 0 elseif taxRate > 0.25 then taxRate = 0.25 end
    local tax = math.floor(payment * taxRate)
    if tax > 0 then
        local okTax, deposited = pcall(function()
            return exports['Renewed-Banking']:addAccountMoney('government', tax)
        end)
        if okTax and deposited then
            payment = payment - tax
            if payment <= 0 then return end
        end
    end
    -- PenguRP edit end
    if not config.money.paycheckSociety then
        config.sendPaycheck(player, payment)
        return
    end
    local account = config.getSocietyAccount(job.name)
    if not account then -- Checks if player is employed by a society
        config.sendPaycheck(player, payment)
        return
    end
    if account < payment then -- Checks if company has enough money to pay society
        Notify(player.PlayerData.source, locale('error.company_too_poor'), 'error')
        return
    end
    config.removeSocietyMoney(job.name, payment)
    config.sendPaycheck(player, payment)
end

CreateThread(function()
    local interval = 60000 * config.money.paycheckTimeout
    while true do
        Wait(interval)
        for _, player in pairs(QBX.Players) do
            pay(player)
        end
    end
end)
