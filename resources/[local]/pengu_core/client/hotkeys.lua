local shown = false

local function setHotkeys(state)
    shown = state
    SendNUIMessage({ action = 'toggle', visible = shown })
    -- focus so the page receives Escape + click-out; release when closed
    SetNuiFocus(shown, shown)
end

local function toggleHotkeys()
    setHotkeys(not shown)
end

-- F1 toggles the hotkey overlay
RegisterKeyMapping('pengu_hotkeys', 'Show / hide keybind help', 'keyboard', 'F1')
RegisterCommand('pengu_hotkeys', toggleHotkeys, false)

-- Close via click-out / Escape from the page
RegisterNUICallback('close', function(_, cb)
    setHotkeys(false)
    cb('ok')
end)

-- Release NUI focus if the resource stops/restarts while the overlay is open - otherwise the player's
-- keyboard + cursor stay frozen (SetNuiFocus state survives the Lua threads dying) until they rejoin.
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and shown then SetNuiFocus(false, false) end
end)

-- Robust Escape close (and stop the pause menu opening) while the menu is up
CreateThread(function()
    while true do
        if shown then
            DisableControlAction(0, 200, true) -- INPUT_FRONTEND_PAUSE (Esc)
            DisableControlAction(0, 322, true) -- Esc key
            if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322) then
                setHotkeys(false)
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)
