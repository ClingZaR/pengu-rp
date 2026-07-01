-- PenguRP: emergency LIGHTS + SIREN control (E / Q). The GTA music radio is disabled server-wide
-- (qbx_vehicleradio disableRadioByDefault), which frees Q.
--
-- Controls (driver of any vehicle that has a siren):
--   E -> master toggle: everything OFF  <->  lights + siren (FULL).
--          - from OFF            -> lights + siren on
--          - from lights or full -> all off
--   Q -> lights / siren:
--          - from OFF            -> lights only (no siren)
--          - while lights are on -> toggle the siren on/off (lights stay on)
--
-- The state lives on a REPLICATED vehicle statebag (penguSiren) and every client applies it locally,
-- so "lights only" is silent for everyone (the siren-mute is a per-client setting that does not
-- otherwise network). ASCII only. luac clean.

local STATE_OFF, STATE_LIGHTS, STATE_FULL = 0, 1, 2

-- veh handle -> last state we applied locally, so the reconcile loop only touches a vehicle when
-- its state actually changes (and catches stream-in within one short tick).
local applied = {}

-- Apply a state to a vehicle on THIS client: lightbar via SetVehicleSiren, audio via mute.
local function apply(veh, s)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if s == STATE_OFF then
        SetVehicleHasMutedSirens(veh, false) -- clear any stale lights-only mute
        SetVehicleSiren(veh, false)
    else
        -- mute the wail unless we are in FULL (lights + siren); lights still flash when muted.
        SetVehicleHasMutedSirens(veh, s ~= STATE_FULL)
        SetVehicleSiren(veh, true)
    end
end

-- Every client renders a vehicle's siren when its statebag changes (covers the owner too).
AddStateBagChangeHandler('penguSiren', nil, function(bagName, _key, value)
    local netId = bagName:match('^entity:(%d+)$')
    if not netId then return end
    netId = tonumber(netId)

    local function tryApply()
        local veh = NetworkGetEntityFromNetworkId(netId)
        if veh and veh ~= 0 and DoesEntityExist(veh) then
            local s = value or STATE_OFF
            apply(veh, s)
            applied[veh] = s
            return true
        end
        return false
    end

    if tryApply() then return end
    -- entity may not have streamed in yet; retry briefly
    CreateThread(function()
        local tries = 0
        while tries < 50 do
            Wait(100)
            if tryApply() then return end
            tries = tries + 1
        end
    end)
end)

-- Reconcile streamed-in vehicles (statebag change handlers do NOT fire on stream-in). A short
-- tick keeps "lights only" silent for an observer a vehicle streams in to, and only touches a
-- vehicle when its desired state differs from what we last applied.
CreateThread(function()
    while true do
        Wait(250)
        local pool = GetGamePool('CVehicle')
        local seen = {}
        for i = 1, #pool do
            local veh = pool[i]
            seen[veh] = true
            local desired = Entity(veh).state.penguSiren or STATE_OFF
            if applied[veh] ~= desired then
                apply(veh, desired)
                applied[veh] = desired
            end
        end
        for veh in pairs(applied) do
            if not seen[veh] then applied[veh] = nil end
        end
    end
end)

-- ============================ driver controls ============================

local function emergencyVehicle()
    local veh = cache.vehicle
    if not veh or veh == 0 then return nil end
    if cache.seat ~= -1 then return nil end           -- driver seat only
    if not DoesVehicleHaveSiren(veh) then return nil end -- emergency vehicles only
    return veh
end

local function getState(veh)
    return Entity(veh).state.penguSiren or STATE_OFF
end

local function setState(veh, s)
    Entity(veh).state:set('penguSiren', s, true) -- replicated -> every client's handler renders it
end

-- E: OFF <-> FULL.
RegisterCommand('+pengu_emerg_master', function()
    local veh = emergencyVehicle()
    if not veh then return end
    setState(veh, getState(veh) == STATE_OFF and STATE_FULL or STATE_OFF)
end, false)
RegisterCommand('-pengu_emerg_master', function() end, false)
RegisterKeyMapping('+pengu_emerg_master', 'Emergency: lights + siren (toggle all)', 'keyboard', 'E')

-- Q: OFF -> lights only ; lights on -> toggle siren.
RegisterCommand('+pengu_emerg_siren', function()
    local veh = emergencyVehicle()
    if not veh then return end
    local s = getState(veh)
    if s == STATE_OFF then
        setState(veh, STATE_LIGHTS)        -- lights only, no siren
    elseif s == STATE_LIGHTS then
        setState(veh, STATE_FULL)          -- add siren
    else
        setState(veh, STATE_LIGHTS)        -- drop siren, keep lights
    end
end, false)
RegisterCommand('-pengu_emerg_siren', function() end, false)
RegisterKeyMapping('+pengu_emerg_siren', 'Emergency: siren (lights-only / siren toggle)', 'keyboard', 'Q')

-- While driving an emergency vehicle, suppress the native horn (E) and the radio wheel so E/Q
-- only drive our lights/siren logic.
CreateThread(function()
    while true do
        if emergencyVehicle() then
            DisableControlAction(0, 86, true) -- INPUT_VEH_HORN (E)
            DisableControlAction(2, 86, true)
            SetUserRadioControlEnabled(false) -- no radio wheel on Q
            Wait(0)
        else
            Wait(100)
        end
    end
end)
