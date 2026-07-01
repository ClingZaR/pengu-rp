-- PenguRP: gang <-> legal-faction MUTUAL EXCLUSIVITY (pengu_core SERVER).
-- A player is EITHER in a legal faction (police / bcso / sasp / ambulance / fire) OR a criminal gang -
-- never both. Whichever they most recently joined wins; the conflicting membership is cleared. This
-- makes gangs a true faction (you cannot be LSPD AND a gangster at once). Regular civilian jobs
-- (mechanic / taxi / businesses) are NOT factions, so a gang member may still hold one.
--
-- Hooks the qbx job/gang change events. No recursion: clearing to 'unemployed'/'none' is not a legal
-- job / real gang, so the partner handler takes no further action. ASCII only. luac clean.

local qbx = exports.qbx_core

local function notify(src, msg)
    if not src or src <= 0 then return end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'pengu:admin',
        args = { 'FACTION', msg, 'info' },
    })
end

-- Joining a real CRIMINAL gang clears any legal-faction job.
AddEventHandler('QBCore:Server:OnGangUpdate', function(src, gang)
    local gangName = gang and gang.name
    if not gangName or not Factions.isCriminal(gangName) then return end -- gang cleared / not a real gang
    local p = qbx:GetPlayer(src)
    local job = p and p.PlayerData and p.PlayerData.job
    if job and Factions.isLegal(job.name) then
        local label = Factions.labelOf('legal', job.name)
        qbx:SetJob(src, 'unemployed', 0)
        notify(src, ('You left %s - you cannot be in a gang and a law faction at the same time.'):format(label))
    end
end)

-- Joining a LEGAL faction clears any criminal gang.
AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job)
    local jobName = job and job.name
    if not jobName or not Factions.isLegal(jobName) then return end -- not a legal faction / unemployed
    local p = qbx:GetPlayer(src)
    local gang = p and p.PlayerData and p.PlayerData.gang
    if gang and Factions.isCriminal(gang.name) then
        local label = Factions.labelOf('criminal', gang.name)
        qbx:SetGang(src, 'none', 0)
        notify(src, ('You left %s - you cannot be in a law faction and a gang at the same time.'):format(label))
    end
end)
