local isLoaded  = false
local lastFuel  = 100
local fuelTimer = 0

local function pd()
    local ok, data = pcall(function() return exports.qbx_core:GetPlayerData() end)
    return ok and data or nil
end

-- /aduty (admin duty) indicator. Event-driven for instant toggle, seeded from
-- metadata on load/restart. The status tick also carries it so it self-corrects.
local adutyOn = false

local function pushAduty()
    SendNUIMessage({ action = 'aduty', on = adutyOn })
end

local function refreshAduty()
    local data = pd()
    adutyOn = (data and data.metadata and data.metadata.optin == true) or false
    pushAduty()
end

RegisterNetEvent('qbx_core:client:onSetMetaData', function(meta, _, value)
    if meta == 'optin' then
        adutyOn = value == true
        pushAduty()
    end
end)

-- --- MINIMAP: square map raised so the HUD/voice sit below it ---
-- posY: MORE NEGATIVE = higher on screen (less negative = lower).
-- posX: MORE NEGATIVE = further left. Tune per resolution.
local MAP_RAISE = -0.02
local MAP_LEFT  = -0.005

local function positionMinimap()
    local resX, resY = GetActiveScreenResolution()
    local aspect = resX / resY
    local off = 0.0
    if aspect > (1920 / 1080) then
        off = ((1920 / 1080 - aspect) / 3.6) - 0.008
    end
    SetMinimapComponentPosition('minimap',      'L', 'B', 0.0 + off + MAP_LEFT,   -0.047 + MAP_RAISE, 0.1638, 0.183)
    SetMinimapComponentPosition('minimap_mask', 'L', 'B', 0.0 + off + MAP_LEFT,    0.0   + MAP_RAISE, 0.128,  0.20)
    SetMinimapComponentPosition('minimap_blur', 'L', 'B', -0.01 + off + MAP_LEFT,  0.025 + MAP_RAISE, 0.262,  0.300)
end

local function setupMinimap()
    RequestStreamedTextureDict('squaremap', false)
    local tries = 0
    while not HasStreamedTextureDictLoaded('squaremap') and tries < 200 do
        Wait(10)
        tries = tries + 1
    end
    SetMinimapClipType(0)
    AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', 'squaremap', 'radarmasksm')
    AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', 'squaremap', 'radarmasksm')
    positionMinimap()
    SetBlipAlpha(GetNorthRadarBlip(), 0)
    SetBigmapActive(true, false)
    Wait(50)
    SetBigmapActive(false, false)
end

CreateThread(function()
    Wait(1500)
    setupMinimap()
    while true do
        Wait(2000)
        positionMinimap()  -- keep it pinned (cheap, no flicker)
    end
end)

-- Hide the health/armour bars the game draws on the minimap (golf mode = 3)
CreateThread(function()
    local minimap = RequestScaleformMovie('minimap')
    while not HasScaleformMovieLoaded(minimap) do Wait(0) end
    while true do
        Wait(0)
        BeginScaleformMovieMethod(minimap, 'SETUP_HEALTH_ARMOUR')
        ScaleformMovieMethodAddParamInt(3)
        EndScaleformMovieMethod()
    end
end)

-- --- STATUS TICK -------------------------------------
local breathMax = nil
CreateThread(function()
    while true do
        Wait(500)
        if isLoaded then
            local ped  = cache.ped
            local data = pd()
            local meta = data and data.metadata or {}

            -- oxygen: real underwater breath (only depletes while submerged)
            local oxygen = 100
            if IsPedSwimmingUnderWater(ped) then
                local remaining = GetPlayerUnderwaterTimeRemaining(cache.playerId)
                if not breathMax or remaining > breathMax then breathMax = remaining end
                if breathMax and breathMax > 0 then
                    oxygen = math.floor(math.max(0, math.min(100, (remaining / breathMax) * 100)))
                end
            else
                breathMax = nil
            end

            -- stamina: 0 = rested -> full bar (native returns depletion, so invert)
            local stamina = math.floor(math.max(0, math.min(100, 100 - GetPlayerSprintStaminaRemaining(cache.playerId))))

            SendNUIMessage({
                action  = 'status',
                health  = math.max(0, GetEntityHealth(ped) - 100),
                armor   = GetPedArmour(ped),
                hunger  = math.floor(meta.hunger or 100),
                thirst  = math.floor(meta.thirst or 100),
                stress  = math.floor(meta.stress or 0),
                oxygen  = oxygen,
                stamina = stamina,
                aduty   = adutyOn,
            })
        end
    end
end)

-- --- VEHICLE TICK ------------------------------------
CreateThread(function()
    local shown = false -- whether the speedo HUD is currently shown
    while true do
        Wait(250)
        if isLoaded and cache.vehicle then
            -- per-frame loop while inside any vehicle (driver or passenger)
            while cache.vehicle do
                local veh  = cache.vehicle
                local spd  = GetEntitySpeed(veh)
                local unit = LocalPlayer.state.pengu_speedUnit or 'MPH'
                local val  = unit == 'KPH' and math.floor(spd * 3.6) or math.floor(spd * 2.237)

                if GetGameTimer() - fuelTimer > 1000 then
                    local ok, f = pcall(function() return exports.ox_fuel:GetFuel(veh) end)
                    if ok and f then lastFuel = math.floor(f) end
                    fuelTimer = GetGameTimer()
                end

                SendNUIMessage({
                    action   = 'vehicle',
                    show     = true,
                    speed    = val,
                    unit     = unit,
                    fuel     = lastFuel,
                    gear     = GetVehicleCurrentGear(veh),
                    seatbelt = LocalPlayer.state.seatbelt == true,
                    engine   = math.floor(GetVehicleEngineHealth(veh)),
                })
                shown = true
                Wait(0)
            end
        end
        -- On foot (or just exited): make sure the speedo HUD is hidden. Re-asserted every outer
        -- tick instead of once-on-exit, so a missed/raced hide (e.g. exit + immediately press L to
        -- lock) can't leave the speedometer / seatbelt icon stuck on screen.
        if shown and not cache.vehicle then
            SendNUIMessage({ action = 'vehicle', show = false })
            shown = false
        end
    end
end)

-- --- VOICE TICK (pma-voice proximity + talking) ------
CreateThread(function()
    while true do
        Wait(150)
        if isLoaded then
            local prox  = LocalPlayer.state.proximity
            local level = (prox and prox.index) or 2
            SendNUIMessage({
                action  = 'voice',
                level   = level,
                talking = MumbleIsPlayerTalking(PlayerId()) == 1,
            })
        end
    end
end)

-- Update the meter the instant the proximity range is cycled
AddEventHandler('pma-voice:setTalkingMode', function(mode)
    SendNUIMessage({
        action  = 'voice',
        level   = mode,
        talking = MumbleIsPlayerTalking(PlayerId()),
    })
end)

-- --- QBX EVENTS --------------------------------------
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    isLoaded = true
    SendNUIMessage({ action = 'show', visible = true })
    refreshAduty()
    CreateThread(setupMinimap)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    isLoaded = false
    SendNUIMessage({ action = 'show', visible = false })
end)

-- --- SETTINGS (F7) -----------------------------------
RegisterKeyMapping('pengu_hud_settings', 'Toggle HUD Settings', 'keyboard', 'F7')
RegisterCommand('pengu_hud_settings', function()
    SendNUIMessage({ action = 'toggleSettings', unit = LocalPlayer.state.pengu_speedUnit or 'MPH' })
    SetNuiFocus(true, true)
end, false)

RegisterNUICallback('closeSettings', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Release NUI focus if the resource stops/restarts while the settings panel is open - otherwise the
-- player's input stays frozen until they rejoin. (Unconditional: SetNuiFocus(false,false) is a no-op
-- when focus isn't held.)
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then SetNuiFocus(false, false) end
end)

RegisterNUICallback('saveSettings', function(data, cb)
    if data.speedUnit then
        LocalPlayer.state:set('pengu_speedUnit', data.speedUnit, false)
    end
    cb('ok')
end)

-- --- INIT ON RESOURCE RESTART ------------------------
AddEventHandler('onClientResourceStart', function(rsc)
    if rsc ~= GetCurrentResourceName() then return end
    local data = pd()
    if data and data.citizenid then
        isLoaded = true
        SendNUIMessage({ action = 'show', visible = true })
        refreshAduty()
    end
end)
