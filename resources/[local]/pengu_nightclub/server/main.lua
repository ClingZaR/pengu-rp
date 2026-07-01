-- PenguRP Nightclub (pengu_nightclub) - SERVER.
-- Authoritative DJ booth (URL validation, proximity, optional job/gang gate, per-booth 20s
-- rate limit) driving xsound PlayUrlPos with distance falloff, plus a clean-money drinks bar
-- (return-checked RemoveMoney/AddItem with refund, per-player busy lock). No DB - booth/bar
-- points are script config and the now-playing state is runtime-only. ASCII only. luac clean.

local qbx    = exports.qbx_core
local ox     = exports.ox_inventory
local xsound = exports.xsound

local active    = {} -- boothIdx -> { url, volume, startedAt (os.time) }
local lastTrack = {} -- boothIdx -> GetGameTimer() ms of last accepted track change
local busy      = {} -- src -> true while a money/inventory flow is in flight

local function soundId(idx)
    local booth = Config.booths[idx]
    return 'pengu_nightclub_' .. ((booth and booth.id) or tostring(idx))
end

-- Server-authoritative proximity: never trust the client's claimed position.
local function nearCoords(src, coords, maxDist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - coords) <= maxDist
end

-- Optional job/gang gate for the decks. Both lists empty (the default) = open to everyone.
local function djAllowed(p)
    local jobs  = Config.djAccess and Config.djAccess.jobs or {}
    local gangs = Config.djAccess and Config.djAccess.gangs or {}
    if next(jobs) == nil and next(gangs) == nil then return true end
    local pd = p.PlayerData
    if pd.job and pd.job.name and jobs[pd.job.name] then return true end
    if pd.gang and pd.gang.name and gangs[pd.gang.name] then return true end
    return false
end

-- Accept only printable-ASCII http(s) URLs (xsound's NUI resolves youtube/soundcloud/direct
-- audio itself). Rejects whitespace/control chars and javascript:/file:/etc schemes outright.
local function sanitizeUrl(url)
    if type(url) ~= 'string' then return nil end
    url = url:gsub('%s+', '')
    if #url < 12 or #url > (Config.maxUrlLen or 512) then return nil end
    if url:find('[^!-~]') then return nil end -- printable ASCII only
    local lower = url:lower()
    if lower:sub(1, 7) ~= 'http://' and lower:sub(1, 8) ~= 'https://' then return nil end
    return url
end

-- ===================== DJ booth: play a track =====================
lib.callback.register('pengu_nightclub:play', function(src, boothIdx, url, volumePct)
    if busy[src] then return { ok = false, msg = 'Hold on - finish what you are doing first.' } end
    busy[src] = true
    local res = { ok = false, msg = 'Could not start the track.' }
    pcall(function()
        boothIdx = tonumber(boothIdx) or -1
        local booth = Config.booths[boothIdx]
        if not booth then res.msg = 'Unknown booth.' return end
        local p = qbx:GetPlayer(src)
        if not p then return end
        if not nearCoords(src, booth.coords, (Config.interactDist or 2.5) + 4.0) then
            res.msg = 'You are not at the DJ booth.' return
        end
        if not djAllowed(p) then res.msg = 'You are not allowed behind these decks.' return end

        local now  = GetGameTimer()
        local last = lastTrack[boothIdx]
        local cd   = Config.trackCooldownMs or 20000
        if last and (now - last) < cd then
            res.msg = ('The deck was just used - wait %ds between track changes.')
                :format(math.ceil((cd - (now - last)) / 1000))
            return
        end

        local clean = sanitizeUrl(url)
        if not clean then res.msg = 'That does not look like a valid http(s) URL.' return end

        local vol = math.floor(tonumber(volumePct) or 50)
        if vol < 5 then vol = 5 elseif vol > 100 then vol = 100 end
        local volume = math.min(Config.maxVolume or 1.0, vol / 100)

        lastTrack[boothIdx] = now
        local id = soundId(boothIdx)
        xsound:Destroy(-1, id) -- clear any previous booth track (client-side no-op if absent)
        xsound:PlayUrlPos(-1, id, clean, volume, booth.coords, false)
        xsound:Distance(-1, id, booth.musicDistance or 40.0)
        active[boothIdx] = { url = clean, volume = volume, startedAt = os.time() }
        res.ok, res.msg = true, 'Track sent to the club speakers.'
    end)
    busy[src] = nil
    return res
end)

-- ===================== DJ booth: stop (/djstop or booth target) =====================
lib.callback.register('pengu_nightclub:stop', function(src, boothIdx)
    boothIdx = tonumber(boothIdx) or -1
    local booth = Config.booths[boothIdx]
    if not booth then return { ok = false, msg = 'Unknown booth.' } end
    if not qbx:GetPlayer(src) then return { ok = false, msg = 'Not loaded.' } end
    if not nearCoords(src, booth.coords, (Config.interactDist or 2.5) + 6.0) then
        return { ok = false, msg = 'You need to be at the DJ booth to stop the music.' }
    end
    if not active[boothIdx] then return { ok = false, msg = 'Nothing is playing on this booth.' } end
    active[boothIdx] = nil
    xsound:Destroy(-1, soundId(boothIdx))
    return { ok = true, msg = 'Music stopped.' }
end)

-- ===================== late-joiner sync =====================
-- A client that loads in while a track is up asks for it; we replay positionally to just that
-- client and best-effort seek to the elapsed offset. Entries older than staleTrackSecs are
-- dropped (the track has long finished client-side; sounds self-destroy on finish).
RegisterNetEvent('pengu_nightclub:server:requestActive', function()
    local src = source
    for idx, a in pairs(active) do
        local elapsed = os.time() - a.startedAt
        if elapsed > (Config.staleTrackSecs or 900) then
            active[idx] = nil
        else
            local booth = Config.booths[idx]
            if booth then
                local id = soundId(idx)
                xsound:PlayUrlPos(src, id, a.url, a.volume, booth.coords, false)
                xsound:Distance(src, id, booth.musicDistance or 40.0)
                if elapsed > 3 then xsound:setTimeStamp(src, id, elapsed) end
            end
        end
    end
end)

-- ===================== bar: buy a drink (CLEAN money) =====================
-- Pays from cash when it covers the price, else bank. Return-checked RemoveMoney -> AddItem,
-- refund on AddItem failure, CanCarry checked before any money moves.
lib.callback.register('pengu_nightclub:buyDrink', function(src, barIdx, drinkIdx)
    if busy[src] then return { ok = false, msg = 'Hold on - finish what you are doing first.' } end
    busy[src] = true
    local res = { ok = false, msg = 'Purchase failed.' }
    pcall(function()
        local bar   = Config.bars[tonumber(barIdx) or -1]
        local drink = bar and bar.drinks and bar.drinks[tonumber(drinkIdx) or -1]
        if not drink then return end
        local price = tonumber(drink.price) or 0
        if price <= 0 then return end
        if not nearCoords(src, bar.coords, (Config.interactDist or 2.5) + 5.0) then
            res.msg = 'You are not at the bar.' return
        end
        local p = qbx:GetPlayer(src)
        if not p then return end
        if not ox:CanCarryItem(src, drink.item, 1) then
            res.msg = 'You cannot carry that right now.' return
        end
        local acct
        if (p.Functions.GetMoney('cash') or 0) >= price then acct = 'cash'
        elseif (p.Functions.GetMoney('bank') or 0) >= price then acct = 'bank'
        else res.msg = ('You need $%d.'):format(price) return end
        if not p.Functions.RemoveMoney(acct, price, 'nightclub-drink') then
            res.msg = ('You need $%d.'):format(price) return
        end
        if not ox:AddItem(src, drink.item, 1) then
            p.Functions.AddMoney(acct, price, 'nightclub-drink-refund') -- rollback
            res.msg = 'The bartender could not hand it over.' return
        end
        res.ok  = true
        res.msg = ('%s - $%d (%s).'):format(drink.label or drink.item, price, acct)
    end)
    busy[src] = nil
    return res
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)

-- Kill any live booth sounds if this resource is stopped so music does not orphan on clients.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for idx in pairs(active) do
        pcall(function() xsound:Destroy(-1, soundId(idx)) end)
    end
end)

print(('[pengu_nightclub] ready (%d booth(s), %d bar(s)).'):format(#Config.booths, #Config.bars))
