-- Automatic /me broadcast for physical actions (seatbelt, harness).
-- Routes through the chat theme's RP command so it shows proximity text + above the head.
local lastBelt, lastHarness = false, false

local function autoMe(text)
    TriggerServerEvent('qbx_chat_theme:rpcmd', 'me', text)
end

-- qbx_seatbelt fires this on every B-press (seatbelt) and harness toggle.
AddEventHandler('seatbelt:client:ToggleSeatbelt', function()
    Wait(50) -- let the statebag settle before reading
    local belt    = LocalPlayer.state.seatbelt == true
    local harness = LocalPlayer.state.harness == true

    if harness ~= lastHarness then
        lastHarness = harness
        autoMe(harness and 'tightens their racing harness' or 'unclips their racing harness')
    elseif belt ~= lastBelt then
        lastBelt = belt
        autoMe(belt and 'buckles their seatbelt' or 'unbuckles their seatbelt')
    end
end)

-- Leaving a vehicle clears the belt silently, so reset trackers to re-announce on re-entry.
lib.onCache('vehicle', function(value)
    if not value then
        lastBelt, lastHarness = false, false
    end
end)

-- qbx_vehiclekeys fires this locally whenever the player toggles a vehicle lock
-- with K. 2 = locked, 1 = unlocked. Mirror the seatbelt /me so others see it.
AddEventHandler('pengu:vehicleLock', function(lockstate)
    autoMe(lockstate == 2 and 'locks the vehicle' or 'unlocks the vehicle')
end)

