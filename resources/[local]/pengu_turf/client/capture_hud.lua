-- PenguRP Gang Territory (pengu_turf) - CLIENT influence HUD (Phase 2; file kept as capture_hud.lua).
-- While the local ped stands in a zone that has live INFLUENCE (GlobalState.penguTurfLive), show an
-- ox_lib textUI: who controls it, the leading gang's influence vs the control threshold, and YOUR
-- gang's share. Pure display; all authority is server. ASCII only. luac clean.

local shown = false

local function gangLabel(key)
    if not key or key == '' then return 'Neutral' end
    local g = Config.gangs[key]
    return (g and g.label) or key
end

-- only criminal-gang members see the turf influence HUD.
local function myGang()
    local pd = exports.qbx_core:GetPlayerData()
    local g = pd and pd.gang
    local n = g and g.name
    if not n or n == 'none' or not Factions.isCriminal(n) then return nil end
    return n
end

CreateThread(function()
    while true do
        Wait(500)
        local live   = GlobalState.penguTurfLive
        local stable = GlobalState.penguTurf
        local hud
        local mg = myGang()

        if mg and type(live) == 'table' and type(stable) == 'table' then
            local pc = GetEntityCoords(PlayerPedId())
            for id, l in pairs(live) do
                local s = stable[id]
                if s and pc.x >= (s.x1 or 0.0) and pc.x <= (s.x2 or 0.0) and pc.y >= (s.y1 or 0.0) and pc.y <= (s.y2 or 0.0) then
                    hud = {
                        label = s.label or 'Turf', owner = s.owner or '',
                        leader = l.leader or '', leaderPts = l.leaderPts or 0,
                        threshold = l.threshold or 0, standings = l.standings or {},
                    }
                    break
                end
            end
        end

        if hud then
            local line = hud.owner ~= ''
                and ('%s  -  held by %s'):format(hud.label, gangLabel(hud.owner))
                or  ('%s  -  uncontrolled'):format(hud.label)
            if hud.leader ~= '' then
                line = line .. ('  |  top: %s %d/%d'):format(gangLabel(hud.leader), hud.leaderPts, hud.threshold)
            end
            line = line .. ('  |  you: %d'):format(hud.standings[mg] or 0)

            lib.showTextUI(line, { position = 'bottom-center', icon = 'spray-can' })
            shown = true
        elseif shown then
            lib.hideTextUI()
            shown = false
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and shown then lib.hideTextUI() end
end)
