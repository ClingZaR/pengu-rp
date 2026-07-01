-- PenguRP World Events (pengu_core) - SERVER. Periodically announces server-wide events
-- (hot zone, gang war, bounty hunt). Events run for a fixed window; completing the objective
-- (being in a hot zone or winning a turf contest) awards bonus rep. Admin can /startevent manually.
-- ASCII only. luac clean.

local qbx = exports.qbx_core
local ACE  = 'pengu.admin'

-- ===================== event pool =====================
local EVENTS = {
    {
        id      = 'hot_zone',
        title   = 'Hot Zone',
        desc    = 'A police operation has locked down this area. Gang activity here awards double rep.',
        icon    = 'fas fa-fire',
        colour  = 1,   -- red blip
        sprite  = 161,
        radius  = 80.0,
        duration = 600,  -- seconds

        sites   = {
            { x = -88.0,   y = -1953.0, z = 21.0,  label = 'LSIA Perimeter' },
            { x = 108.0,   y = -1962.0, z = 21.0,  label = 'Terminal Gate' },
            { x = 2549.0,  y = 2585.0,  z = 37.9,  label = 'Davis Quarry'  },
            { x = 347.0,   y = -2077.0, z = 21.0,  label = 'Elysian Docks' },
            { x = -1228.0, y = -1574.0, z = 4.6,   label = 'Vespucci Canals' },
        },
    },
    {
        id      = 'gang_war',
        title   = 'Gang War',
        desc    = 'A turf battle has broken out. Hold your ground for bonus rep.',
        icon    = 'fas fa-skull-crossbones',
        colour  = 5,   -- orange blip
        sprite  = 84,
        radius  = 120.0,
        duration = 480,

        sites   = {
            { x = 119.0,   y = -1898.0, z = 21.0,  label = 'Davis Ave'     },
            { x = -356.0,  y = -1742.0, z = 28.3,  label = 'Strawberry'    },
            { x = 418.0,   y = -726.0,  z = 28.9,  label = 'Downtown East' },
            { x = -669.0,  y = -856.0,  z = 24.0,  label = 'Little Seoul'  },
        },
    },
    {
        id      = 'bounty_delivery',
        title   = 'Contraband Run',
        desc    = 'A stash of contraband is up for grabs. Reach the drop site first.',
        icon    = 'fas fa-box',
        colour  = 28,  -- yellow blip
        sprite  = 478,
        radius  = 60.0,
        duration = 360,

        sites   = {
            { x = 852.0,   y = -1869.0, z = 28.0,  label = 'LS Docks Bay'  },
            { x = -1839.0, y = 2062.0,  z = 140.6, label = 'Mount Chilliad' },
            { x = 2758.0,  y = 3475.0,  z = 55.6,  label = 'Sandy Airfield' },
        },
    },
}

-- ===================== active event tracking =====================
local activeEvent = nil

-- No server-wide chat blasts on an RP server. The GlobalState change triggers the client's
-- applyEvent() which shows a personal ox_lib notify + blip for each player individually.
local function startEvent(evDef, site)
    if activeEvent then return false end
    activeEvent = {
        id       = evDef.id,
        title    = evDef.title,
        desc     = evDef.desc,
        x        = site.x + 0.0,
        y        = site.y + 0.0,
        z        = site.z + 0.0,
        label    = site.label or 'Unknown',
        radius   = evDef.radius,
        duration = evDef.duration,
        rep      = evDef.rep,
        sprite   = evDef.sprite,
        colour   = evDef.colour,
        icon     = evDef.icon,
        endsAt   = os.time() + evDef.duration,
    }
    GlobalState.penguWorldEvent = {
        id = activeEvent.id, title = activeEvent.title, desc = activeEvent.desc,
        x = activeEvent.x, y = activeEvent.y, z = activeEvent.z,
        label = activeEvent.label, radius = activeEvent.radius,
        duration = activeEvent.duration, endsAt = activeEvent.endsAt,
        sprite = activeEvent.sprite, colour = activeEvent.colour,
    }
    return true
end

local function endEvent()
    if not activeEvent then return end
    activeEvent = nil
    GlobalState.penguWorldEvent = nil
end

-- ===================== auto-rotate: pick a random event every ~30 min =====================
CreateThread(function()
    Wait(300000) -- wait 5 min after startup before first event
    while true do
        if not activeEvent then
            local evDef = EVENTS[math.random(#EVENTS)]
            local sites = evDef.sites
            local site  = sites[math.random(#sites)]
            startEvent(evDef, site)
        end
        Wait(1800000) -- try again every 30 min
    end
end)

-- auto-end when timer expires (checked in the zone loop above). Also a safety net:
CreateThread(function()
    while true do
        Wait(60000)
        if activeEvent and os.time() >= activeEvent.endsAt then endEvent() end
    end
end)

-- ===================== /startevent admin command =====================
RegisterCommand('startevent', function(src, args)
    if src > 0 and not IsPlayerAceAllowed(src, ACE) then
        if src > 0 then TriggerClientEvent('ox_lib:notify', src, { title='Error', description='No permission.', type='error' }) end
        return
    end
    if activeEvent then
        local msg = ('Event already active: %s at %s.'):format(activeEvent.title, activeEvent.label)
        if src > 0 then TriggerClientEvent('ox_lib:notify', src, { title='Event', description=msg, type='inform' }) end
        return
    end
    local evKey = tostring(args[1] or ''):lower()
    local evDef
    for _, e in ipairs(EVENTS) do if e.id == evKey then evDef = e; break end end
    if not evDef then evDef = EVENTS[math.random(#EVENTS)] end
    local sites = evDef.sites
    local site  = sites[math.random(#sites)]
    if startEvent(evDef, site) then
        if src > 0 then TriggerClientEvent('ox_lib:notify', src, { title='Event', description='Started.', type='success' }) end
    end
end, false)

RegisterCommand('endevent', function(src)
    if src > 0 and not IsPlayerAceAllowed(src, ACE) then return end
    endEvent()
end, false)
