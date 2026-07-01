-- PenguRP Nightclub (pengu_nightclub) - CLIENT.
-- ox_target box zones for DJ booths (URL+volume input dialog, pulse-lights toggle) and bars
-- (drink purchase menu). /djstop stops the nearest booth (server re-validates proximity).
-- Pulse lights: cheap client-side DrawLightWithRange color cycle that runs only while the
-- booth track is audible (xsound soundExists) and dies with the toggle/track/resource.
-- ASCII only. luac clean.

local zoneIds  = {}
local lightsOn = {} -- boothIdx -> true while the pulse loop runs
local busy     = false

local function soundId(idx)
    local booth = Config.booths[idx]
    return 'pengu_nightclub_' .. ((booth and booth.id) or tostring(idx))
end

local function notify(title, msg, ok)
    lib.notify({ title = title, description = msg, type = ok and 'success' or 'error' })
end

-- ===================== DJ booth =====================
local function openDJ(idx)
    local booth = Config.booths[idx]
    local input = lib.inputDialog(booth.label or 'DJ Booth', {
        { type = 'input',  label = 'Track URL', description = 'YouTube / direct audio link (http or https)',
          required = true, max = Config.maxUrlLen or 512 },
        { type = 'slider', label = 'Volume', min = 5, max = 100, step = 5, default = 50 },
    })
    if not input or not input[1] then return end
    if busy then return end
    busy = true
    local res = lib.callback.await('pengu_nightclub:play', false, idx, input[1], input[2])
    notify(booth.label or 'DJ Booth', (res and res.msg) or 'No response.', res and res.ok)
    busy = false
end

local function stopBooth(idx)
    if busy then return end
    busy = true
    local booth = Config.booths[idx]
    local res = lib.callback.await('pengu_nightclub:stop', false, idx)
    notify((booth and booth.label) or 'DJ Booth', (res and res.msg) or 'No response.', res and res.ok)
    busy = false
end

-- ===================== pulse lights =====================
local function pulseLoop(idx)
    local booth   = Config.booths[idx]
    local id      = soundId(idx)
    local L       = Config.lights or {}
    local colors  = L.colors or { { 255, 0, 128 } }
    local offsets = L.offsets or { vec3(0.0, 0.0, 3.0) }
    local points  = {}
    for i = 1, #offsets do points[i] = booth.coords + offsets[i] end
    local range     = L.range or 12.0
    local intensity = L.intensity or 2.0
    local cycleMs   = L.cycleMs or 450
    local drawDist  = L.drawDist or 60.0
    local ci, lastSwap, lastCheck = 1, GetGameTimer(), 0

    while lightsOn[idx] do
        local now = GetGameTimer()
        -- poll the music state ~1/s (export calls are not free); lights die with the track
        if now - lastCheck > 1000 then
            lastCheck = now
            if not exports.xsound:soundExists(id) then lightsOn[idx] = nil break end
        end
        if now - lastSwap >= cycleMs then
            ci = (ci % #colors) + 1
            lastSwap = now
        end
        if #(GetEntityCoords(cache.ped or PlayerPedId()) - booth.coords) < drawDist then
            for i = 1, #points do
                local c = colors[((ci + i - 2) % #colors) + 1] -- phase-shift per light
                DrawLightWithRange(points[i].x, points[i].y, points[i].z, c[1], c[2], c[3], range, intensity)
            end
            Wait(0)
        else
            Wait(500) -- too far to see them; idle cheaply
        end
    end
    lightsOn[idx] = nil
end

local function toggleLights(idx)
    if lightsOn[idx] then
        lightsOn[idx] = nil
        notify('Pulse Lights', 'Lights off.', true)
        return
    end
    if not exports.xsound:soundExists(soundId(idx)) then
        notify('Pulse Lights', 'The lights pulse to the music - start a track first.', false)
        return
    end
    lightsOn[idx] = true
    notify('Pulse Lights', 'Lights on - they stop with the music.', true)
    CreateThread(function() pulseLoop(idx) end)
end

-- ===================== bar =====================
local function openBar(idx)
    local bar = Config.bars[idx]
    local options = {}
    for di, drink in ipairs(bar.drinks or {}) do
        local diRef = di
        options[#options + 1] = {
            title       = drink.label or drink.item,
            description = ('$%d'):format(drink.price or 0),
            icon        = drink.icon or 'fa-solid fa-martini-glass',
            onSelect    = function()
                if busy then return end
                busy = true
                local res = lib.callback.await('pengu_nightclub:buyDrink', false, idx, diRef)
                notify(bar.label or 'Bar', (res and res.msg) or 'No response.', res and res.ok)
                busy = false
            end,
        }
    end
    lib.registerContext({ id = 'pengu_nightclub_bar_' .. idx, title = bar.label or 'Bar', options = options })
    lib.showContext('pengu_nightclub_bar_' .. idx)
end

-- ===================== target zones (static config points) =====================
for idx, booth in ipairs(Config.booths) do
    local i = idx
    zoneIds[#zoneIds + 1] = exports.ox_target:addBoxZone({
        coords   = booth.coords,
        size     = booth.targetSize or vec3(3.0, 3.0, 3.0),
        rotation = booth.rotation or 0,
        debug    = false,
        options  = {
            {
                name     = 'pengu_nc_dj_' .. i,
                icon     = 'fa-solid fa-compact-disc',
                label    = 'DJ Booth',
                distance = Config.interactDist or 2.5,
                onSelect = function() openDJ(i) end,
            },
            {
                name     = 'pengu_nc_lights_' .. i,
                icon     = 'fa-solid fa-lightbulb',
                label    = 'Pulse Lights',
                distance = Config.interactDist or 2.5,
                onSelect = function() toggleLights(i) end,
            },
        },
    })
end

for idx, bar in ipairs(Config.bars) do
    local i = idx
    zoneIds[#zoneIds + 1] = exports.ox_target:addBoxZone({
        coords   = bar.coords,
        size     = bar.targetSize or vec3(4.0, 3.0, 3.0),
        rotation = bar.rotation or 0,
        debug    = false,
        options  = {
            {
                name     = 'pengu_nc_bar_' .. i,
                icon     = 'fa-solid fa-champagne-glasses',
                label    = 'Bar',
                distance = Config.interactDist or 2.5,
                onSelect = function() openBar(i) end,
            },
        },
    })
end

-- ===================== /djstop =====================
RegisterCommand('djstop', function()
    local pc = GetEntityCoords(cache.ped or PlayerPedId())
    local nearest, nd = nil, 10.0
    for idx, booth in ipairs(Config.booths) do
        local d = #(pc - booth.coords)
        if d < nd then nearest, nd = idx, d end
    end
    if not nearest then
        notify('DJ Booth', 'Stand at the DJ booth to stop the music.', false)
        return
    end
    stopBooth(nearest)
end, false)
TriggerEvent('chat:addSuggestion', '/djstop', 'Stop the nightclub music (stand at the DJ booth)', {})

-- ===================== late-joiner music sync =====================
local synced = 0
local function requestActive()
    local now = GetGameTimer()
    if now - synced < 10000 then return end -- OnPlayerLoaded can fire alongside the boot thread
    synced = now
    TriggerServerEvent('pengu_nightclub:server:requestActive')
end

CreateThread(function()
    while not exports.qbx_core:GetPlayerData() do Wait(500) end
    requestActive()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() requestActive() end)

-- ===================== cleanup =====================
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for idx in pairs(lightsOn) do lightsOn[idx] = nil end
    for _, id in ipairs(zoneIds) do exports.ox_target:removeZone(id) end
end)
