RegisterNUICallback('config', function(_data, cb)
    cb({
        mainColor = GetConvar('qbx_chat:mainColor', '#141517'),
        borderColor = GetConvar('qbx_chat:borderColor', '#373a40'),
        textColor = GetConvar('qbx_chat:textColor', '#ffffff'),
        faintColor = GetConvar('qbx_chat:faintColor', '#c1c2c5'),

        fontFamily = GetConvar('qbx_chat:fontFamily', "Arial, 'Helvetica Neue', Helvetica, sans-serif"),
        consoleFontFamily = GetConvar('qbx_chat:consoleFontFamily', 'monospace'),
        suggestionFontFamily = GetConvar('qbx_chat:suggestionFontFamily', 'monospace'),

        inputIconUrl = GetConvar('qbx_chat:inputIconUrl', 'https://cfx-nui-qbx_chat_theme/theme/icons/duck.png'),
        messageIconUrl = GetConvar('qbx_chat:messageIconUrl', 'https://cfx-nui-qbx_chat_theme/theme/icons/message.svg'),
        consoleIconUrl = GetConvar('qbx_chat:consoleIconUrl', 'https://cfx-nui-qbx_chat_theme/theme/icons/console.svg'),
        joinIconUrl = GetConvar('qbx_chat:joinIconUrl', 'https://cfx-nui-qbx_chat_theme/theme/icons/join.svg'),
        quitIconUrl = GetConvar('qbx_chat:quitIconUrl', 'https://cfx-nui-qbx_chat_theme/theme/icons/quit.svg'),
        userIconUrl = GetConvar('qbx_chat:userIconUrl', 'https://cfx-nui-qbx_chat_theme/theme/icons/user.svg'),
    })
end)

-- PenguRP: give the chat a MOUSE CURSOR while the input is open so you can click the input box and
-- click/drag to select message text. The system 'chat' resource only sets KEYBOARD focus
-- (SetNuiFocus(true)) on the frame the chat key is released. Pure-Lua (no theme-JS dependency, so a
-- simple `restart qbx_chat_theme` redeploys it): we watch the chat key ourselves, wait for it to
-- release + 2 frames (so the chat's focus call has happened), and then -- only if the chat actually
-- opened -- add the cursor so OURS sticks. Closing the chat (its own SetNuiFocus(false)) releases it.
CreateThread(function()
    local CHAT_INPUT = 245 -- INPUT_MP_TEXT_CHAT_ALL (the control that opens chat, default 'T')
    while true do
        Wait(0)
        if IsControlJustPressed(0, CHAT_INPUT) and not IsNuiFocused() then
            while IsControlPressed(0, CHAT_INPUT) do Wait(0) end -- wait for the key to release
            Wait(2)                                              -- let the chat set its keyboard focus
            if IsNuiFocused() then                               -- chat actually opened
                SetNuiFocus(true, true)                          -- add the mouse cursor
            end
        end
    end
end)
