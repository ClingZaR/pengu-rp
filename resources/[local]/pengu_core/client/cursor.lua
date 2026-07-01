-- Free mouse cursor (F6) so you can interact with / copy from NUI windows.
-- While the cursor is up the NUI holds keyboard focus, so the game can't see a
-- second F6 press. The release is driven from the focused page (hotkeys.html):
-- F6 / Esc keydown OR clicking the on-screen "release" button -> closeCursor.
local cursorOn = false

local function setCursor(state)
    if cursorOn == state then return end
    cursorOn = state
    SetNuiFocus(state, state)
    SendNUIMessage({ action = 'cursorMode', on = state })
end

RegisterKeyMapping('pengu_cursor', 'Toggle mouse cursor', 'keyboard', 'F6')
RegisterCommand('pengu_cursor', function()
    if not cursorOn then setCursor(true) end
end, false)

RegisterNUICallback('closeCursor', function(_, cb)
    setCursor(false)
    cb('ok')
end)

-- Release NUI focus if the resource stops/restarts while the cursor is up - otherwise the player's
-- keyboard stays frozen (SetNuiFocus state survives the resource stop) until they rejoin.
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and cursorOn then SetNuiFocus(false, false) end
end)
