-- PenguRP shared dispatch client. Receives pengu_core:dispatchAlert from the server and calls
-- ps-dispatch:CustomAlert exactly once. Only one officer receives this event per alert. ASCII only.

RegisterNetEvent('pengu_core:dispatchAlert', function(data)
    if not data then return end
    pcall(function()
        exports['ps-dispatch']:CustomAlert({
            message      = data.message,
            dispatchCode = data.code,
            code         = '10-10',
            icon         = data.icon,
            priority     = data.priority or 2,
            coords       = vector3(data.coords.x, data.coords.y, data.coords.z),
            jobs         = data.jobs,
            sprite       = 1, color = 3, scale = 0.9, length = 4,
        })
    end)
end)
