local EnableCayoMiniMap = false

-- PenguRP: apply the colored map zoom-ladder + radar zoom in one place so we can fire it the INSTANT
-- the radar is ready, instead of waiting for the original 10s maintenance tick (which is why the
-- colored radar used to take ~10s to appear on connect).
local function ApplyMapZoom()
    SetMapZoomDataLevel(0, 2.75, 0.9, 0.08, 0.0, 0.0) -- Level 0
    SetMapZoomDataLevel(1, 2.8, 0.9, 0.08, 0.0, 0.0) -- Level 1
    SetMapZoomDataLevel(2, 8.0, 0.9, 0.08, 0.0, 0.0) -- Level 2
    SetMapZoomDataLevel(3, 20.0, 0.9, 0.08, 0.0, 0.0) -- Level 3
    SetMapZoomDataLevel(4, 35.0, 0.9, 0.08, 0.0, 0.0) -- Level 4
    SetMapZoomDataLevel(5, 55.0, 0.0, 0.1, 2.0, 1.0) -- ZOOM_LEVEL_GOLF_COURSE
    SetMapZoomDataLevel(6, 450.0, 0.0, 0.1, 1.0, 1.0) -- ZOOM_LEVEL_INTERIOR
    SetMapZoomDataLevel(7, 4.5, 0.0, 0.0, 0.0, 0.0) -- ZOOM_LEVEL_GALLERY
    SetMapZoomDataLevel(8, 11.0, 0.0, 0.0, 2.0, 3.0) -- ZOOM_LEVEL_GALLERY_MAXIMIZE
    SetRadarZoom(1100)
end

-- startup: wait until the player is actually active in the world (radar exists), then apply at once and
-- re-apply rapidly for a couple of seconds to beat any first-frame revert -> colored radar is ~instant.
CreateThread(function()
    local tries = 0
    while not NetworkIsPlayerActive(PlayerId()) and tries < 400 do Wait(50); tries = tries + 1 end
    for _ = 1, 8 do
        ApplyMapZoom()
        Wait(250)
    end
    -- slow maintenance loop (some clients revert the radar zoom over time)
    while true do
        ApplyMapZoom()
        Wait(10000)
    end
end)

-- also re-apply the moment the character (re)loads or respawns, so it's instant on every spawn too
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', ApplyMapZoom)
RegisterNetEvent('qbx_core:client:playerLoaded', ApplyMapZoom)
AddEventHandler('playerSpawned', ApplyMapZoom)

if EnableCayoMiniMap then
    local function CreateBlip()
        local BlipCoords = {
            vec3(4800.85, -6159.22, 0.0),
            vec3(6420.60, -5169.87, 37.43),
        }
        for coords=1, #BlipCoords do
            local coords = BlipCoords[coords]
            local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
            SetBlipSprite(blip, 1)
            SetBlipAlpha(blip, 0)
            SetBlipScale(blip, 0.1)
            SetBlipAsShortRange(blip, true)
        end
    end
    CreateThread(function()
        CreateBlip()
        while true do
            SetRadarAsExteriorThisFrame()
            local coords = vec(4700.0, -5145.0)
            SetRadarAsInteriorThisFrame(`h4_fake_islandx`, coords.x, coords.y, 0, 0)
            Wait(0)
        end
    end)
end