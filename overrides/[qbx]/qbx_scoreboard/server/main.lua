local config = require 'config.server'
GlobalState.illegalActions = config.illegalActions

lib.callback.register('qbx_scoreboard:server:getScoreboardData', function()
    local totalPlayers = 0
    local policeCount = 0
    local onDutyAdmins = {}
    local dutyCounts = {} -- PenguRP: on-duty count per job name

    for _, v in pairs(exports.qbx_core:GetQBPlayers()) do
        if v then
            totalPlayers += 1

            if v.PlayerData.job.type == 'leo' and v.PlayerData.job.onduty then
                policeCount += 1
            end

            if v.PlayerData.job.onduty then -- PenguRP
                local jobName = v.PlayerData.job.name
                dutyCounts[jobName] = (dutyCounts[jobName] or 0) + 1
            end

            onDutyAdmins[v.PlayerData.source] = IsPlayerAceAllowed(v.PlayerData.source, 'admin') and v.PlayerData.metadata.optin and true or nil
        end
    end

    -- PenguRP: ordered list for the NUI, driven by config.dutyJobs
    local dutyList = {}
    for i = 1, #(config.dutyJobs or {}) do
        local job = config.dutyJobs[i]
        dutyList[i] = {label = job.label, count = dutyCounts[job.name] or 0}
    end

    return totalPlayers, policeCount, onDutyAdmins, dutyList
end)

local function setActivityBusy(name, bool)
    local illegalActions = GlobalState.illegalActions
    illegalActions[name].busy = bool
    GlobalState.illegalActions = illegalActions
end

---@deprecated use the setActivityBusy export instead
RegisterNetEvent('qb-scoreboard:server:SetActivityBusy', setActivityBusy)
exports('SetActivityBusy', setActivityBusy)
