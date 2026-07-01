-- Force the system chat into "always show" so the engine never fades it.
-- theme/app.js then handles reveal-on-new-message and the 60s idle hide.
local function forceVisible()
    ExecuteCommand('toggleChat visible')
end

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(2500)
        forceVisible()
    end)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    CreateThread(function()
        Wait(1000)
        forceVisible()
    end)
end)
