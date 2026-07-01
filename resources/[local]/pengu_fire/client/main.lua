-- PenguRP - Fire Department mechanic CLIENT. Renders active fires (looped fire particles, so the
-- scene is fully server-controlled and never spreads/auto-clears), shows a fire-job blip, relays
-- the ps-dispatch alert, and handles spray-to-extinguish (proximity + fire extinguisher). The
-- server is authoritative over a fire's HP and the reward. ASCII only.

local fires = {} -- [id] = { coords = vec3, ptfx = { handles }, blip }
local lastSpray = 0

local PTFX_DICT = 'core'
local PTFX_NAME = 'ent_amb_fire'

local function isFirefighter()
    local pd = exports.qbx_core:GetPlayerData()
    local job = pd and pd.job
    return job ~= nil and Config.fireJobs[job.name] == true and job.onduty == true
end

local function drawHint(text)
    SetTextFont(4) SetTextScale(0.4, 0.4) SetTextColour(255, 255, 255, 220)
    SetTextOutline() SetTextCentre(true)
    SetTextEntry('STRING') AddTextComponentString(text)
    DrawText(0.5, 0.85)
end

local function loadPtfx(dict)
    if HasNamedPtfxAssetLoaded(dict) then return true end
    RequestNamedPtfxAsset(dict)
    local t = 0
    while not HasNamedPtfxAssetLoaded(dict) and t < 100 do Wait(50); t = t + 1 end
    return HasNamedPtfxAssetLoaded(dict)
end

local function addFireBlip(f)
    if not f or f.blip then return end
    local c = f.coords
    local b = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(b, 1)
    SetBlipColour(b, 1)        -- red
    SetBlipScale(b, 1.1)
    SetBlipFlashes(b, true)
    SetBlipAsShortRange(b, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Structure Fire')
    EndTextCommandSetBlipName(b)
    f.blip = b
end

local function removeFireBlip(f)
    if f and f.blip then RemoveBlip(f.blip); f.blip = nil end
end

local function startFireVisual(id, coords)
    if fires[id] then return end
    local handles = {}
    if loadPtfx(PTFX_DICT) then
        for _ = 1, (Config.fireCluster or 4) do
            local ox, oy = (math.random() - 0.5) * 4.0, (math.random() - 0.5) * 4.0
            local scale = 1.2 + math.random() * 0.9
            UseParticleFxAssetNextCall(PTFX_DICT)
            handles[#handles + 1] = StartParticleFxLoopedAtCoord(
                PTFX_NAME, coords.x + ox, coords.y + oy, coords.z, 0.0, 0.0, 0.0, scale, false, false, false, false)
        end
    end

    fires[id] = { coords = coords, ptfx = handles }
    if isFirefighter() then addFireBlip(fires[id]) end
end

local function stopFireVisual(id)
    local f = fires[id]
    if not f then return end
    for i = 1, #f.ptfx do StopParticleFxLooped(f.ptfx[i], 0) end
    if f.blip then RemoveBlip(f.blip) end
    fires[id] = nil
end

RegisterNetEvent('pengu_fire:client:start', function(id, coords)
    startFireVisual(id, vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0))
end)

RegisterNetEvent('pengu_fire:client:stop', function(id)
    stopFireVisual(id)
end)

-- Server picks one client to raise the ps-dispatch alert (so it fires exactly once).
RegisterNetEvent('pengu_fire:client:dispatch', function(coords)
    pcall(function()
        exports['ps-dispatch']:CustomAlert({
            message = 'Structure Fire',
            dispatchCode = 'FIRE',
            code = '10-70',
            icon = 'fas fa-fire',
            priority = 1,
            coords = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0),
            jobs = { 'fire' },
            sprite = 1, color = 1, scale = 0.9, length = 6, flash = true,
        })
    end)
end)

-- Extinguish loop: an on-duty firefighter near a fire who sprays an extinguisher damages it.
CreateThread(function()
    while true do
        local wait = 1000
        if isFirefighter() and next(fires) ~= nil then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local nearId, nearDist
            for id, f in pairs(fires) do
                local d = #(pos - f.coords)
                if d <= Config.extinguishRadius and (not nearDist or d < nearDist) then
                    nearId, nearDist = id, d
                end
            end
            if nearId then
                wait = 0
                local _, weapon = GetCurrentPedWeapon(ped, true)
                if weapon == Config.extinguishWeapon then
                    drawHint('Spray to extinguish the fire')
                    if IsPedShooting(ped) then
                        local now = GetGameTimer()
                        if (now - lastSpray) >= Config.sprayIntervalMs then
                            lastSpray = now
                            TriggerServerEvent('pengu_fire:server:damage', nearId)
                        end
                    end
                else
                    drawHint('Equip a fire extinguisher to fight this fire')
                end
            end
        end
        Wait(wait)
    end
end)

-- A firefighter who clocks ON after a fire spawned still gets its map blip; clocking OFF removes it.
RegisterNetEvent('QBCore:Client:SetDuty', function()
    local on = isFirefighter()
    for _, f in pairs(fires) do
        if on then addFireBlip(f) else removeFireBlip(f) end
    end
end)

-- Backfill fires that spawned before this client connected / before the resource (re)started.
AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    TriggerServerEvent('pengu_fire:server:requestActive')
end)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('pengu_fire:server:requestActive')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(fires) do stopFireVisual(id) end
end)
