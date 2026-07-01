-- PenguRP shared dispatch relay. Any pengu resource calls exports.pengu_core:Dispatch(coords, data)
-- server-side. This helper finds one on-duty LEO and fires a client event on them, which calls
-- ps-dispatch:CustomAlert exactly once (same pattern as pengu_fire). ASCII only. luac clean.

local qbx = exports.qbx_core
local LAW  = { police = true, bcso = true, sasp = true }

exports('Dispatch', function(coords, data)
    local officers = {}
    for src, p in pairs(qbx:GetQBPlayers() or {}) do
        local job = p.PlayerData and p.PlayerData.job
        if job and job.onduty and LAW[job.name] then
            officers[#officers + 1] = src
        end
    end
    if #officers == 0 then return end  -- no police online; no alert
    TriggerClientEvent('pengu_core:dispatchAlert', officers[math.random(#officers)], {
        message  = data.message  or 'Suspicious Activity',
        code     = data.code     or '10-10',
        icon     = data.icon     or 'fas fa-exclamation-triangle',
        priority = data.priority or 2,
        coords   = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        jobs     = data.jobs     or { 'police', 'bcso', 'sasp' },
    })
end)
