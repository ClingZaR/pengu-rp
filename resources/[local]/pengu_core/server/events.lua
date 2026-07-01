-- PenguRP World Events (pengu_core) - SERVER. Periodically announces server-wide events
-- (hot zone, gang war, bounty hunt, drug bust, prison riot, vip transport, arms deal).
-- Events run for a fixed window; some carry a lootable crate (GlobalState.penguEventCrate)
-- or set cross-resource boost flags (penguDrugBust / penguPrisonRiot read by pengu_drugs /
-- pengu_prison). Admin can /startevent manually. ASCII only. luac clean.

local qbx = exports.qbx_core
local ox  = exports.ox_inventory
local ACE = 'pengu.admin'
local LAW = { police = true, bcso = true, sasp = true }

-- ===================== helpers =====================
local function onDutyLeos()
    local out = {}
    for src, p in pairs(qbx:GetQBPlayers() or {}) do
        local job = p.PlayerData and p.PlayerData.job
        if job and job.onduty and LAW[job.name] then out[#out + 1] = src end
    end
    return out
end

local function gangMembers()
    local out = {}
    for src, p in pairs(qbx:GetQBPlayers() or {}) do
        local g = p.PlayerData and p.PlayerData.gang
        if g and g.name and g.name ~= 'none' and Factions.isCriminal(g.name) then out[#out + 1] = src end
    end
    return out
end

local function evNotify(src, msg, typ, title)
    TriggerClientEvent('ox_lib:notify', src, {
        title = title or 'World Event', description = msg, type = typ or 'inform', duration = 10000,
    })
end

local function notifyList(list, msg, typ, title)
    for _, src in ipairs(list) do evNotify(src, msg, typ, title) end
end

local function dispatch(x, y, z, data)
    pcall(function() exports.pengu_core:Dispatch(vector3(x + 0.0, y + 0.0, z + 0.0), data) end)
end

-- ===================== active event tracking =====================
local activeEvent = nil
local seq = 0

-- clear stale bags left by a previous resource lifetime (in-memory state resets on restart)
GlobalState.penguWorldEvent = nil
GlobalState.penguEventCrate = nil
GlobalState.penguDrugBust   = nil
GlobalState.penguPrisonRiot = nil

-- No server-wide chat blasts on an RP server. The GlobalState change triggers the client's
-- applyEvent() which shows a personal ox_lib notify + blip for each player individually.
-- ev.show gates client visibility: 'all' | 'leo' | 'gang' | 'none'.
local function publishEvent()
    if not activeEvent then GlobalState.penguWorldEvent = nil return end
    GlobalState.penguWorldEvent = {
        id = activeEvent.id, title = activeEvent.title, desc = activeEvent.desc,
        x = activeEvent.x, y = activeEvent.y, z = activeEvent.z,
        label = activeEvent.label, radius = activeEvent.radius,
        duration = activeEvent.duration, endsAt = activeEvent.endsAt,
        sprite = activeEvent.sprite, colour = activeEvent.colour,
        show = activeEvent.show,
    }
end

local function endEvent(reason)
    if not activeEvent then return end
    local ev = activeEvent
    activeEvent = nil
    GlobalState.penguWorldEvent = nil
    GlobalState.penguEventCrate = nil
    if ev.def and ev.def.onEnd then pcall(ev.def.onEnd, ev, reason or 'expired') end
end

-- ===================== event content pools =====================
local CONVOY_STOP_SECS  = 180   -- 3 min per waypoint
local CONVOY_LOOT_MIN   = 3000  -- dirty money payout range
local CONVOY_LOOT_MAX   = 6000
local CONVOY_GUARD_PAY  = 500   -- per on-duty LEO if the window expires unlooted
local DIRTY_ITEM        = 'black_money'

local CONVOY_ROUTES = {
    {
        { x = -88.0,  y = -1953.0, z = 21.0,  label = 'LSIA Perimeter' },
        { x = 347.0,  y = -2077.0, z = 21.0,  label = 'Elysian Docks' },
        { x = 152.0,  y = -3206.0, z = 5.9,   label = 'Terminal docks' },
    },
    {
        { x = 2549.0, y = 2585.0,  z = 37.9,  label = 'Davis Quarry' },
        { x = 2348.0, y = 3133.0,  z = 48.2,  label = 'Sandy Shores airfield' },
        { x = 1700.0, y = 4920.0,  z = 42.0,  label = 'Grapeseed back road' },
    },
    {
        { x = 852.0,  y = -1869.0, z = 28.0,  label = 'LS Docks Bay' },
        { x = 418.0,  y = -726.0,  z = 28.9,  label = 'Downtown East' },
        { x = -669.0, y = -856.0,  z = 24.0,  label = 'Little Seoul' },
    },
}

local ARMS_SITES = {
    { x = -445.0, y = -1690.0, z = 19.0, label = 'La Mesa rail yard' },
    { x = 24.0,   y = -1750.0, z = 29.0, label = 'Davis back alley' },
    { x = 1237.0, y = -3110.0, z = 5.0,  label = 'Elysian Island container yard' },
    { x = 2348.0, y = 3133.0,  z = 48.2, label = 'Sandy Shores airfield' },
}

-- fallback if the pengu_blackmarket catalog export is unavailable (mid-tier weapons)
local ARMS_FALLBACK = {
    { item = 'WEAPON_APPISTOL',    label = 'AP Pistol' },
    { item = 'WEAPON_PUMPSHOTGUN', label = 'Pump Shotgun' },
    { item = 'WEAPON_MICROSMG',    label = 'Micro SMG' },
    { item = 'WEAPON_SMG',         label = 'SMG' },
}

local PRISON_YARD = { x = 1761.0, y = 2483.0, z = 45.7, label = 'Bolingbroke Penitentiary' }

-- move the convoy crate to waypoint i of the active vip_transport event
local function setConvoyStop(a, i)
    local wp = a.route[i]
    a.stop  = i
    a.x, a.y, a.z = wp.x + 0.0, wp.y + 0.0, wp.z + 0.0
    a.label = wp.label or 'Unknown'
    a.desc  = ('The convoy is holding at %s (stop %d of %d). Hit the cargo crate before it moves.')
        :format(a.label, i, #a.route)
    a.crate = { key = a.token .. '-' .. i, kind = 'convoy', x = a.x, y = a.y, z = a.z, claim = nil, locked = false }
    if i > 1 then publishEvent() end -- stop 1 was just published by startEvent (avoid a double notify)
    GlobalState.penguEventCrate = { key = a.crate.key, kind = 'convoy', x = a.x, y = a.y, z = a.z, label = 'Convoy Crate' }
end

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
    {
        -- police raid window on a random ACTIVE drug lab group (DB pengu_drug_labs).
        -- Self-skips when no active labs exist. No blip for anyone: LEO get a ps-dispatch
        -- alert at the lab, criminals only a vague warning. pengu_drugs reads
        -- GlobalState.penguDrugBust to pay double drug XP + risk dispatch pings.
        id      = 'drug_bust',
        title   = 'Drug Bust',
        desc    = 'A police raid window is open on a drug lab.',
        colour  = 1,
        sprite  = 51,
        radius  = 0.0,
        duration = 600,
        show    = 'none',

        prepare = function()
            local okQ, rows = pcall(function()
                return MySQL.query.await('SELECT id, label, x, y, z, group_name FROM pengu_drug_labs WHERE active = 1')
            end)
            if not okQ or type(rows) ~= 'table' or #rows == 0 then return nil, 'no active drug labs' end
            local byGroup, keys = {}, {}
            for _, r in ipairs(rows) do
                local gkey = (r.group_name and r.group_name ~= '' and r.group_name) or tostring(r.id)
                if not byGroup[gkey] then byGroup[gkey] = r; keys[#keys + 1] = gkey end
            end
            local gkey = keys[math.random(#keys)]
            local r = byGroup[gkey]
            local label = (r.label and r.label ~= '') and r.label or gkey
            return { x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0, label = label }, { bustGroup = gkey }
        end,
        onStart = function(a)
            GlobalState.penguDrugBust = { group = a.bustGroup, endsAt = a.endsAt, bonusXP = 30 }
            dispatch(a.x, a.y, a.z, {
                message = 'Narcotics Raid Window - Suspected Drug Lab', code = '10-15',
                icon = 'fas fa-pills', priority = 2,
            })
            notifyList(gangMembers(),
                'Word on the street: heat incoming. The labs are hot - big risk, big reward.',
                'inform', 'Word on the Street')
        end,
        onEnd = function()
            GlobalState.penguDrugBust = nil
        end,
    },
    {
        -- riot at Bolingbroke: LEO alerted (blip + dispatch), prisoners notified. Labor
        -- pays double sentence reduction while GlobalState.penguPrisonRiot is live
        -- (read by pengu_prison). No door mechanics; xt-prison checkout unaffected.
        id      = 'prison_riot',
        title   = 'Prison Riot',
        desc    = 'A riot has broken out in the yard. All available units respond.',
        colour  = 1,
        sprite  = 161,
        radius  = 120.0,
        duration = 480,
        show    = 'leo',

        sites   = { PRISON_YARD },

        onStart = function(a)
            GlobalState.penguPrisonRiot = { endsAt = a.endsAt, mult = 2 }
            dispatch(a.x, a.y, a.z, {
                message = 'Prison Riot in Progress - Bolingbroke', code = '10-99',
                icon = 'fas fa-exclamation-triangle', priority = 1,
            })
            for src in pairs(qbx:GetQBPlayers() or {}) do
                local okJ, mins = pcall(function() return exports.pengu_core:GetJailMinutes(src) end)
                if okJ and (tonumber(mins) or 0) > 0 then
                    evNotify(src, 'The block is rioting - the guards are distracted. Yard labor works off DOUBLE time while it lasts.', 'inform', 'Prison Riot')
                end
            end
        end,
        onEnd = function()
            GlobalState.penguPrisonRiot = nil
            for src in pairs(qbx:GetQBPlayers() or {}) do
                local okJ, mins = pcall(function() return exports.pengu_core:GetJailMinutes(src) end)
                if okJ and (tonumber(mins) or 0) > 0 then
                    evNotify(src, 'The guards have restored order. Labor is back to normal rates.', 'inform', 'Prison Riot')
                end
            end
        end,
    },
    {
        -- armored convoy: a lootable cargo crate holds 3 min at each of 3 route waypoints
        -- (no NPC driving AI - the crate IS the convoy). Looting: 60s skillcheck-gated
        -- action, pays dirty money, pings dispatch immediately. If the whole window
        -- expires unlooted, every on-duty LEO gets a guard bonus.
        id      = 'vip_transport',
        title   = 'VIP Transport',
        desc    = 'An armored convoy is moving valuables across the state.',
        colour  = 5,
        sprite  = 225,
        radius  = 60.0,
        duration = 570,
        show    = 'all',

        prepare = function()
            local route = CONVOY_ROUTES[math.random(#CONVOY_ROUTES)]
            local first = route[1]
            return { x = first.x, y = first.y, z = first.z, label = first.label },
                { route = route, stop = 1, looted = false }
        end,
        onStart = function(a)
            setConvoyStop(a, 1)
            local token = a.token
            CreateThread(function()
                for i = 1, #a.route do
                    if i > 1 then
                        if not (activeEvent and activeEvent.token == token) then return end
                        setConvoyStop(activeEvent, i)
                    end
                    local untilT = os.time() + CONVOY_STOP_SECS
                    while os.time() < untilT do
                        Wait(1000)
                        if not (activeEvent and activeEvent.token == token) then return end
                    end
                end
                if activeEvent and activeEvent.token == token then endEvent('expired') end
            end)
        end,
        onEnd = function(a, reason)
            if a.looted or reason ~= 'expired' then return end
            local paid = 0
            for _, src in ipairs(onDutyLeos()) do
                local p = qbx:GetPlayer(src)
                if p and p.Functions.AddMoney('bank', CONVOY_GUARD_PAY, 'convoy-guard') then
                    paid = paid + 1
                    evNotify(src, ('The transport arrived untouched. $%d guard bonus paid to your bank.'):format(CONVOY_GUARD_PAY), 'success', 'Convoy Secured')
                end
            end
            print(('[pengu_core] events: vip_transport expired unlooted; paid %d officer(s)'):format(paid))
        end,
    },
    {
        -- arms deal: exact meet blip to criminal gang members only (show='gang'); LEO get a
        -- DELAYED (3 min) dispatch tip with an OFFSET 150m radius circle, never the exact
        -- point. One-time crate with a mid-tier blackmarket weapon + ammo; 15s timed open,
        -- no crowbar needed.
        id      = 'arms_deal',
        title   = 'Arms Deal',
        desc    = 'A weapons buy is going down. First crew to crack the crate keeps the merchandise.',
        colour  = 1,
        sprite  = 478,
        radius  = 0.0,
        duration = 600,
        show    = 'gang',

        prepare = function()
            local site = ARMS_SITES[math.random(#ARMS_SITES)]
            local pool = {}
            pcall(function()
                for _, e in ipairs(exports.pengu_blackmarket:GetCatalog() or {}) do
                    local lvl = e.minLevel or 1
                    if e.weapon and lvl >= 3 and lvl <= 4 then
                        pool[#pool + 1] = { item = e.item, label = e.label }
                    end
                end
            end)
            if #pool == 0 then pool = ARMS_FALLBACK end
            local pick = pool[math.random(#pool)]
            local ammoItem = 'ammo-9'
            pcall(function()
                local def = ox:Items(pick.item)
                if def and def.ammoname then ammoItem = def.ammoname end
            end)
            return { x = site.x, y = site.y, z = site.z, label = site.label },
                { armsItem = pick.item, armsLabel = pick.label, ammoItem = ammoItem, ammoCount = 30, looted = false }
        end,
        onStart = function(a)
            a.crate = { key = a.token .. '-arms', kind = 'arms', x = a.x, y = a.y, z = a.z, claim = nil, locked = false }
            GlobalState.penguEventCrate = { key = a.crate.key, kind = 'arms', x = a.x, y = a.y, z = a.z, label = 'Arms Crate' }
            local token = a.token
            SetTimeout(180000, function() -- delayed + offset LEO tip
                if not (activeEvent and activeEvent.token == token) then return end
                local ang  = math.random() * 6.28318
                local dist = 40.0 + math.random() * 70.0 -- true point stays inside the 150m circle
                local tx, ty = a.x + math.cos(ang) * dist, a.y + math.sin(ang) * dist
                dispatch(tx, ty, a.z, {
                    message = 'Tip-Off: Arms Deal Somewhere In The Area', code = '10-57',
                    icon = 'fas fa-gun', priority = 2,
                })
                for _, src in ipairs(onDutyLeos()) do
                    TriggerClientEvent('pengu_core:events:leoTip', src, { x = tx, y = ty, z = a.z, radius = 150.0 })
                end
            end)
        end,
    },
}

-- ===================== start / rotate =====================
local function startEvent(evDef, site, extra)
    if activeEvent then return false end
    seq = seq + 1
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
        sprite   = evDef.sprite,
        colour   = evDef.colour,
        icon     = evDef.icon,
        show     = evDef.show or 'all',
        endsAt   = os.time() + evDef.duration,
        token    = ('%d-%d'):format(os.time(), seq),
        def      = evDef,
    }
    if extra then
        for k, v in pairs(extra) do activeEvent[k] = v end
    end
    publishEvent()
    if evDef.onStart then
        local okS, err = pcall(evDef.onStart, activeEvent)
        if not okS then print('[pengu_core] events: onStart failed for ' .. evDef.id .. ': ' .. tostring(err)) end
    end
    print(('[pengu_core] events: started %s at %s'):format(activeEvent.id, activeEvent.label))
    return true
end

-- prepare (if any) then start. Returns true if started; false means the event self-skipped
-- (no eligible content, e.g. drug_bust with an empty pengu_drug_labs table).
local function tryStart(evDef)
    if activeEvent then return false end
    local site, extra
    if evDef.prepare then
        local okP
        okP, site, extra = pcall(evDef.prepare)
        if not okP then print('[pengu_core] events: prepare failed for ' .. evDef.id .. ': ' .. tostring(site)); return false end
        if not site then
            print(('[pengu_core] events: %s self-skipped (%s); rotating to another event'):format(evDef.id, tostring(extra or 'no eligible content')))
            return false
        end
    else
        site = evDef.sites[math.random(#evDef.sites)]
    end
    return startEvent(evDef, site, extra)
end

-- pick events in shuffled order until one actually starts (skips self-skipping events)
local function startRandomEvent()
    local order = {}
    for i = 1, #EVENTS do order[i] = i end
    for i = #order, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    for _, idx in ipairs(order) do
        if tryStart(EVENTS[idx]) then return true end
    end
    return false
end

-- ===================== auto-rotate: pick a random event every ~30 min =====================
CreateThread(function()
    Wait(300000) -- wait 5 min after startup before first event
    while true do
        if not activeEvent then startRandomEvent() end
        Wait(1800000) -- try again every 30 min
    end
end)

-- auto-end when the window expires (event threads end sooner where relevant; safety net here)
CreateThread(function()
    while true do
        Wait(60000)
        if activeEvent and os.time() >= activeEvent.endsAt then endEvent('expired') end
    end
end)

-- ===================== event crate (vip_transport / arms_deal) =====================
local crateBusy = {}

local function crateOf(key)
    local a = activeEvent
    local c = a and a.crate
    if not c or c.key ~= key then return nil end
    return a, c
end

-- role + proximity gate, server-authoritative (client canInteract is cosmetic only)
local function crateAccess(src, c)
    local p = qbx:GetPlayer(src)
    if not p then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    if #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) > 6.0 then
        return false, 'You are not at the crate.'
    end
    if c.kind == 'convoy' then
        local job = p.PlayerData.job
        if job and job.onduty and LAW[job.name] then
            return false, 'You are supposed to be guarding this convoy.'
        end
    else
        local g = p.PlayerData.gang
        if not (g and g.name and Factions.isCriminal(g.name)) then
            return false, 'You have no business with that crate.'
        end
    end
    return true
end

-- step 1: stake a claim before the client runs its skillcheck/progress (blackmarket pattern:
-- server-side timing so a scripted client cannot jump straight to a finished grab).
lib.callback.register('pengu_core:events:crateBegin', function(src, key)
    if crateBusy[src] then return false end
    local _, c = crateOf(tostring(key or ''))
    if not c then evNotify(src, 'The crate is gone.', 'error'); return false end
    local ok, msg = crateAccess(src, c)
    if not ok then if msg then evNotify(src, msg, 'error') end return false end
    local window = (c.kind == 'convoy') and 75 or 30
    if c.claim and c.claim.src ~= src and (os.time() - c.claim.at) < window then
        evNotify(src, 'Someone else is already working that crate.', 'error'); return false
    end
    c.claim = { src = src, at = os.time() }
    if c.kind == 'convoy' then -- hitting the convoy pings dispatch immediately
        dispatch(c.x, c.y, c.z, {
            message = 'Armored Convoy Being Hit', code = '10-31',
            icon = 'fas fa-truck', priority = 1,
        })
    end
    return true
end)

-- step 2: complete the loot (validates claim + minimum elapsed time + a fresh re-check)
lib.callback.register('pengu_core:events:crateFinish', function(src, key)
    if crateBusy[src] then return false end
    local a, c = crateOf(tostring(key or ''))
    if not c then evNotify(src, 'The crate is gone.', 'error'); return false end
    local ok, msg = crateAccess(src, c)
    if not ok then if msg then evNotify(src, msg, 'error') end return false end
    local minSecs = (c.kind == 'convoy') and 55 or 13
    if not c.claim or c.claim.src ~= src or (os.time() - c.claim.at) < minSecs then
        evNotify(src, 'Not so fast.', 'error'); return false
    end
    if c.locked then return false end

    crateBusy[src] = true
    c.locked = true
    local result = false
    if c.kind == 'convoy' then
        local amount = math.random(CONVOY_LOOT_MIN, CONVOY_LOOT_MAX)
        if not ox:CanCarryItem(src, DIRTY_ITEM, amount) then
            evNotify(src, 'You cannot carry the take - free up space. The crate is still here.', 'error')
        elseif ox:AddItem(src, DIRTY_ITEM, amount) then
            a.looted = true
            evNotify(src, ('You cracked the convoy crate: $%d in dirty money.'):format(amount), 'success')
            TriggerEvent('pengu_xp:onCrime', src, 100)
            result = true
        else
            evNotify(src, 'The grab failed.', 'error')
        end
    else
        if not (ox:CanCarryItem(src, a.armsItem, 1) and ox:CanCarryItem(src, a.ammoItem, a.ammoCount)) then
            evNotify(src, 'You cannot carry the goods - free up space. The crate is still here.', 'error')
        elseif ox:AddItem(src, a.armsItem, 1) then
            a.looted = true
            if not ox:AddItem(src, a.ammoItem, a.ammoCount) then
                evNotify(src, 'The ammo box spilled - you only got the weapon.', 'error')
            end
            evNotify(src, ('You cracked the crate: %s.'):format(a.armsLabel or 'a weapon'), 'success')
            TriggerEvent('pengu_xp:onCrime', src, 100)
            result = true
        else
            evNotify(src, 'The grab failed.', 'error')
        end
    end
    c.locked = false
    crateBusy[src] = nil
    if result then endEvent('looted') end
    return result
end)

-- ===================== drug_bust dispatch pings =====================
-- pengu_drugs fires this on every boosted process during a bust window; a fraction of
-- those pings actually reach dispatch (rate-limited so LEO are not spammed).
local bustPingAt = 0
AddEventHandler('pengu_core:server:drugBustPing', function(_, x, y, z)
    if not activeEvent or activeEvent.id ~= 'drug_bust' then return end
    if not (tonumber(x) and tonumber(y) and tonumber(z)) then return end
    if math.random() >= 0.25 then return end
    local now = os.time()
    if (now - bustPingAt) < 30 then return end
    bustPingAt = now
    dispatch(x, y, z, {
        message = 'Drug Lab Activity Confirmed', code = '10-15',
        icon = 'fas fa-pills', priority = 1,
    })
end)

-- ===================== cleanup =====================
AddEventHandler('playerDropped', function()
    local src = source
    crateBusy[src] = nil
    local c = activeEvent and activeEvent.crate
    if c and c.claim and c.claim.src == src then c.claim = nil end
end)

AddEventHandler('onResourceStop', function(rsc)
    if rsc ~= GetCurrentResourceName() then return end
    GlobalState.penguWorldEvent = nil
    GlobalState.penguEventCrate = nil
    GlobalState.penguDrugBust   = nil
    GlobalState.penguPrisonRiot = nil
end)

-- ===================== /startevent admin command =====================
RegisterCommand('startevent', function(src, args)
    if src > 0 and not IsPlayerAceAllowed(src, ACE) then
        TriggerClientEvent('ox_lib:notify', src, { title='Error', description='No permission.', type='error' })
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
    if evDef then
        if tryStart(evDef) then
            if src > 0 then TriggerClientEvent('ox_lib:notify', src, { title='Event', description='Started.', type='success' }) end
        elseif src > 0 then
            TriggerClientEvent('ox_lib:notify', src, { title='Event', description=('%s self-skipped (no eligible content, e.g. no active drug labs).'):format(evDef.id), type='error' })
        end
        return
    end
    if startRandomEvent() then
        if src > 0 then TriggerClientEvent('ox_lib:notify', src, { title='Event', description='Started.', type='success' }) end
    end
end, false)

RegisterCommand('endevent', function(src)
    if src > 0 and not IsPlayerAceAllowed(src, ACE) then return end
    endEvent('admin')
end, false)
