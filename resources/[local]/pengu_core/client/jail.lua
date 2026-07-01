-- PenguRP: SELF-CONTAINED JAIL (CLIENT).
--
-- All authority is server-side (server/jail.lua). This script only renders the sentence and
-- enforces confinement:
--   * on 'enter'   -> fade out, teleport the prisoner onto the pdloc 'cell' marker, show a
--                     remaining-time banner, and keep them within CONFINE_RADIUS of the cell;
--   * on 'tick'    -> refresh the banner each minute;
--   * on 'release' -> fade out, drop them at the pdloc 'lobby' marker, clear the banner.
-- On (re)spawn it asks the server whether it still owes time, so a relog/crash can't skip jail.
-- ASCII only. luac clean.

local CONFINE_RADIUS = 30.0 -- how far a prisoner may roam from the cell before being pulled back

local jailed      = false
local cell        = nil -- vec3 of the active cell
local minutesLeft = 0

local function showBanner()
    if jailed and minutesLeft > 0 then
        lib.showTextUI(('Jailed  -  %d min remaining'):format(minutesLeft), {
            position = 'top-center',
            icon = 'handcuffs',
        })
    end
end

-- Teleport helper: fade, move the ped, freeze until collision loads, fade back in.
local function teleport(x, y, z, w)
    DoScreenFadeOut(600)
    local t = GetGameTimer()
    while not IsScreenFadedOut() and GetGameTimer() - t < 1500 do Wait(10) end

    local ped = cache.ped
    SetEntityCoords(ped, x, y, z, false, false, false, false)
    SetEntityHeading(ped, w or 0.0)

    FreezeEntityPosition(ped, true)
    local t2 = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() - t2 < 5000 do Wait(50) end
    FreezeEntityPosition(ped, false)

    DoScreenFadeIn(600)
end

RegisterNetEvent('pengu_jail:client:enter', function(data)
    if not data or not data.cell then return end
    cell = vec3(data.cell.x + 0.0, data.cell.y + 0.0, data.cell.z + 0.0)
    minutesLeft = tonumber(data.minutes) or 0

    local wasJailed = jailed
    jailed = true

    teleport(cell.x, cell.y, cell.z, data.cell.w)
    showBanner()

    -- one confinement thread per jail session (guard against double-start on re-entry)
    if wasJailed then return end
    CreateThread(function()
        while jailed do
            if cell then
                local p = GetEntityCoords(cache.ped)
                if #(p - cell) > CONFINE_RADIUS then
                    SetEntityCoords(cache.ped, cell.x, cell.y, cell.z, false, false, false, false)
                    lib.notify({ title = 'You cannot leave the jail.', type = 'error' })
                end
            end
            Wait(2000)
        end
    end)
end)

RegisterNetEvent('pengu_jail:client:tick', function(left)
    minutesLeft = tonumber(left) or 0
    showBanner()
end)

RegisterNetEvent('pengu_jail:client:release', function(lobby)
    jailed = false
    cell = nil
    minutesLeft = 0
    lib.hideTextUI()

    if lobby then
        teleport(lobby.x + 0.0, lobby.y + 0.0, lobby.z + 0.0, lobby.w)
    end
end)

-- Ask the server if we still owe time (covers relog, crash, and resource restart).
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('pengu_jail:server:checkStatus')
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    TriggerServerEvent('pengu_jail:server:checkStatus')
end)
