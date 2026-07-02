-- PenguRP Illegal Dealers (pengu_dealers) - CLIENT.
-- Streams dealer peds (distance-based spawn/despawn), attaches ox_target on each.
-- Mechanic: shows wanted cars + sell parts. Drug dealer: sell drugs. Doctor: buy buffs.
-- ASCII only. luac clean.

local peds    = {} -- dealerId -> entity handle (or false if spawn failed / out of range)
local dealers = {} -- dealerId -> dealer table (full data)
local busy    = false

local STREAM_IN  = 80.0
local STREAM_OUT = 100.0

-- ===================== menus =====================
local function gangLevel()
    local pd = exports.qbx_core:GetPlayerData()
    local g  = pd and pd.gang and pd.gang.name
    if not g or g == 'none' then return 1 end
    local gp    = GlobalState.penguGangProgress
    local entry = gp and gp[g]
    return (entry and tonumber(entry.level)) or 1
end

local function myGangName()
    local pd = exports.qbx_core:GetPlayerData()
    local g  = pd and pd.gang and pd.gang.name
    return (g and g ~= 'none') and g or nil
end

-- current chop wanted-car set (for part provenance), from GlobalState (set by pengu_chopshop).
local function wantedSet()
    local set = {}
    local w = GlobalState.penguChopWanted
    if type(w) == 'table' then for _, m in ipairs(w) do set[m] = true end end
    return set
end

-- units of `item` the player holds. If `wanted` is given, only count parts whose source car
-- (metadata.model) is currently wanted.
local function heldCount(item, wanted)
    local slots = exports.ox_inventory:Search('slots', item) or {}
    local n = 0
    for _, s in ipairs(slots) do
        if not wanted then
            n = n + (s.count or 0)
        else
            local mdl = s.metadata and s.metadata.model
            if mdl and wanted[mdl] then n = n + (s.count or 0) end
        end
    end
    return n
end

local function dirtyMoney()
    return exports.ox_inventory:Search('count', Config.dirtyItem) or 0
end

-- PenguRP demand: server-wide demand factor for a drug item (GlobalState.penguDrugDemand,
-- published rounded by pengu_drugs) mapped to a street-talk hint for the dealer menu.
local function demandHint(item)
    local d = GlobalState.penguDrugDemand
    local f = (type(d) == 'table' and tonumber(d[item])) or 1.0
    if f >= 1.15 then
        return 'The streets are HUNGRY for this'
    elseif f >= 1.0 then
        return 'Steady demand'
    elseif f >= 0.8 then
        return 'Market cooling off'
    else
        return 'Market FLOODED'
    end
end

-- info rows: every gang's influence on this dealer (x/max), control marker, your gang noted.
local function standingRows(dealer)
    local info = lib.callback.await('pengu_dealers:getStandings', false, dealer.id)
    local rows = {}
    local mine = myGangName()
    if info and info.standings and #info.standings > 0 then
        local s   = info.standings -- server returns these ordered by influence DESC
        local thr = info.threshold or 80
        -- the controller is the STRICT leader that is also >= threshold (matches GetControlledDealers);
        -- a tie at the top means nobody controls, so no crown is shown.
        local leaderIdx
        if s[1] and s[1].influence >= thr and (not s[2] or s[1].influence > s[2].influence) then
            leaderIdx = 1
        end
        for i, st in ipairs(s) do
            local controls = (i == leaderIdx)
            rows[#rows + 1] = {
                title       = ('%s  %d/%d%s'):format(st.gang, st.influence, info.max or 100, controls and '  [CONTROLS]' or ''),
                description = (st.gang == mine) and 'Your gang' or nil,
                icon        = controls and 'fa-solid fa-crown' or 'fa-solid fa-users',
                disabled    = true, -- info line
            }
        end
    else
        rows[#rows + 1] = { title = 'No gang has any influence here yet', icon = 'fa-solid fa-users', disabled = true }
    end
    return rows
end

-- generic sell menu. opts = { wantedOnly = bool, header = {extra info rows} }
local function openSellMenu(dealer, def, cbName, opts)
    opts = opts or {}
    local wanted  = opts.wantedOnly and wantedSet() or nil
    local options = {}
    if opts.header then for _, r in ipairs(opts.header) do options[#options + 1] = r end end
    for _, acc in ipairs(def.accepts or {}) do
        local accRef   = acc
        local have     = heldCount(acc.item, wanted)
        local disabled = have < 1
        local desc
        if disabled then
            desc = opts.wantedOnly and 'None from a currently-wanted car' or 'You have none of these'
        else
            desc = ('$%d each  -  you have %d%s'):format(acc.price or 0, have, opts.wantedOnly and ' sellable' or '')
        end
        -- PenguRP demand: append the server-wide market signal on every drug row
        if opts.demandHints then
            desc = desc .. '  |  ' .. demandHint(acc.item)
        end
        options[#options + 1] = {
            title       = acc.label or acc.item,
            description = desc,
            icon        = def.icon or 'fa-solid fa-hand-holding-dollar',
            disabled    = disabled, -- show but grey out what you can't sell
            onSelect    = function()
                if busy then return end
                busy = true
                local ok = lib.callback.await(cbName, false, dealer.id, accRef.item)
                if not ok then lib.notify({ title = dealer.label or 'Dealer', description = 'Nothing sellable or transaction failed.', type = 'error' }) end
                busy = false
            end,
        }
    end
    lib.registerContext({ id = 'pengu_dealer_sell_' .. dealer.id, title = 'Sell to ' .. (dealer.label or 'Dealer'), options = options })
    lib.showContext('pengu_dealer_sell_' .. dealer.id)
end

local function openMechanicMenu(dealer, def)
    local wanted  = GlobalState.penguChopWanted or {}
    local carLine = #wanted > 0 and table.concat(wanted, ', ') or 'Nothing wanted right now - check back soon.'
    local untilT  = GlobalState.penguChopWantedUntil or 0
    local now     = GetCloudTimeAsInt()
    if untilT > 0 and now > 0 and untilT > now then
        carLine = carLine .. (' (refreshes in ~%dm)'):format(math.floor((untilT - now) / 60))
    end
    local options = standingRows(dealer) -- gang influence standings at the top
    options[#options + 1] = {
        title = 'Wanted Cars', description = carLine, icon = 'fa-solid fa-car', disabled = true,
    }
    options[#options + 1] = {
        title       = 'Sell Car Parts',
        description = 'Offload parts stripped from a wanted car',
        icon        = 'fa-solid fa-screwdriver-wrench',
        onSelect    = function() openSellMenu(dealer, def, 'pengu_dealers:sellParts', { wantedOnly = true }) end,
    }
    lib.registerContext({ id = 'pengu_dealer_mech_' .. dealer.id, title = dealer.label or 'Chop Mechanic', options = options })
    lib.showContext('pengu_dealer_mech_' .. dealer.id)
end

-- generic BUY menu for any sells-type dealer (doctor, armor, general): buy items with dirty money.
local function openSellsMenu(dealer, def)
    local myLevel = gangLevel()
    local money   = dirtyMoney()
    local options = standingRows(dealer) -- gang influence standings at the top
    for idx, item in ipairs(def.sells or {}) do
        local locked   = (item.minLevel or 1) > myLevel
        local tooPoor  = (item.price or 0) > money
        local disabled = locked or tooPoor
        local idxRef   = idx
        local qty      = (item.count and item.count > 1) and (' (x' .. item.count .. ')') or ''
        local desc
        if locked then       desc = ('Gang Level %d required'):format(item.minLevel)
        elseif tooPoor then  desc = ('$%d dirty - not enough on you'):format(item.price or 0)
        else                 desc = ('$%d dirty%s'):format(item.price or 0, qty) end
        options[#options + 1] = {
            title       = item.label or item.item,
            description = desc,
            icon        = def.icon or 'fa-solid fa-box',
            disabled    = disabled, -- grey out level-locked or unaffordable
            onSelect    = function()
                if busy then return end
                busy = true
                local ok = lib.callback.await('pengu_dealers:buyGoods', false, dealer.id, idxRef)
                if not ok then lib.notify({ title = dealer.label or 'Dealer', description = 'Transaction failed.', type = 'error' }) end
                busy = false
            end,
        }
    end
    lib.registerContext({ id = 'pengu_dealer_sells_' .. dealer.id, title = dealer.label or def.label or 'Dealer', options = options })
    lib.showContext('pengu_dealer_sells_' .. dealer.id)
end

-- Arms dealer: the catalog lives in pengu_blackmarket; buying a weapon schedules a CRATE DROP.
local function openWeaponsMenu(dealer, def)
    local catalog = lib.callback.await('pengu_dealers:weaponCatalog', false) or {}
    local myLevel = gangLevel()
    local options = standingRows(dealer) -- gang influence standings at the top
    for i, e in ipairs(catalog) do
        local locked = (e.minLevel or 1) > myLevel
        local idxRef = i
        local desc
        if locked then
            desc = ('Gang Level %d required'):format(e.minLevel or 1)
        elseif e.weapon then
            desc = ('$%d dirty - drops as a crate you collect + pry open'):format(e.price or 0)
        else
            desc = ('$%d dirty%s'):format(e.price or 0, e.count and (' (x' .. e.count .. ')') or '')
        end
        options[#options + 1] = {
            title       = e.label or e.item,
            description = desc,
            icon        = e.weapon and 'fa-solid fa-gun' or 'fa-solid fa-box',
            disabled    = locked, -- grey out level-locked items
            onSelect    = function()
                if busy then return end
                busy = true
                local ok = lib.callback.await('pengu_dealers:buyWeapon', false, dealer.id, idxRef)
                if not ok then lib.notify({ title = dealer.label or 'Arms Dealer', description = 'No deal.', type = 'error' }) end
                busy = false
            end,
        }
    end
    lib.registerContext({ id = 'pengu_dealer_arms_' .. dealer.id, title = dealer.label or 'Arms Dealer', options = options })
    lib.showContext('pengu_dealer_arms_' .. dealer.id)
end

local function openDealer(dealer)
    local def = Config.dealerTypes[dealer.type]
    if not def then return end
    if     dealer.type == 'mechanic'    then openMechanicMenu(dealer, def)
    elseif dealer.type == 'drug_dealer' then openSellMenu(dealer, def, 'pengu_dealers:sellDrugs', { header = standingRows(dealer), demandHints = true }) -- PenguRP demand hints
    elseif dealer.type == 'weapons'     then openWeaponsMenu(dealer, def)
    elseif def.sells                    then openSellsMenu(dealer, def) -- doctor / armor / general
    end
end

-- Apply a gang's configured outfit components to a spawned dealer ped.
-- Reads GlobalState.penguDealerControl (dealerId->gang) and GlobalState.penguDealerOutfits (gang->type->comps).
local function applyOutfit(ped, dealerId, dealerType)
    local ctrl    = GlobalState.penguDealerControl
    local outfits = GlobalState.penguDealerOutfits
    if not ctrl or not outfits or not ped or ped == 0 then return end
    local gang = ctrl[tostring(dealerId)]
    if not gang then return end
    local comps = outfits[gang] and outfits[gang][dealerType]
    if not comps or #comps == 0 then return end
    for _, c in ipairs(comps) do
        SetPedComponentVariation(ped, c.comp, c.draw, c.tex, 0)
    end
end

-- ===================== ped lifecycle =====================
local function spawnPed(dealer)
    if peds[dealer.id] ~= nil then return end
    peds[dealer.id] = false -- mark as spawning to prevent duplicate threads

    local def  = Config.dealerTypes[dealer.type]
    if not def then peds[dealer.id] = nil; return end
    local model = def.model or 'a_m_y_business_01'
    local hash  = joaat(model)
    if not IsModelValid(hash) then
        print(('[pengu_dealers] model "%s" for type "%s" is INVALID - using fallback a_m_y_business_01')
            :format(tostring(model), tostring(dealer.type)))
        hash = joaat('a_m_y_business_01')
        if not IsModelValid(hash) then peds[dealer.id] = nil; return end
    end
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) and GetGameTimer() - t < 5000 do Wait(50) end
    if not HasModelLoaded(hash) or not dealers[dealer.id] then peds[dealer.id] = nil; return end

    -- z - 1.0 matches every other ped-spawning resource: GetEntityCoords on the placing admin returns
    -- ~1m above ground (player centre), so the ped's feet land on the ground.
    local ped = CreatePed(4, hash, dealer.x + 0.0, dealer.y + 0.0, dealer.z - 1.0, dealer.h + 0.0, false, true)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then peds[dealer.id] = nil; return end
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    peds[dealer.id] = ped

    local dealerRef = dealer
    exports.ox_target:addLocalEntity(ped, {
        {
            name     = 'pengu_dealer_' .. dealer.id,
            icon     = def.icon or 'fa-solid fa-person',
            label    = 'Talk to ' .. (dealer.label or def.label or 'Dealer'),
            distance = Config.interactDist or 2.5,
            onSelect = function() openDealer(dealerRef) end,
        },
    })
    applyOutfit(ped, dealer.id, dealer.type)
end

local function removePed(id)
    local ped = peds[id]
    if ped and ped ~= false then
        exports.ox_target:removeLocalEntity(ped)
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    peds[id] = nil
end

-- distance-stream: spawn when close, despawn when far
CreateThread(function()
    while true do
        Wait(2000)
        local pc = GetEntityCoords(PlayerPedId())
        for id, d in pairs(dealers) do
            local dist = #(pc - vector3(d.x + 0.0, d.y + 0.0, d.z + 0.0))
            if dist < STREAM_IN and peds[id] == nil then
                CreateThread(function() spawnPed(d) end)
            elseif dist > STREAM_OUT and peds[id] then
                removePed(id)
            end
        end
    end
end)

-- ===================== list management =====================
local function rebuild(list)
    local incoming = {}
    for _, d in ipairs(list or {}) do incoming[d.id] = d end
    -- remove gone dealers
    for id in pairs(dealers) do
        if not incoming[id] then removePed(id); dealers[id] = nil end
    end
    -- add new
    for id, d in pairs(incoming) do
        dealers[id] = d
    end
end

RegisterNetEvent('pengu_dealers:updated', function(list) rebuild(list) end)

CreateThread(function()
    while not exports.qbx_core:GetPlayerData() do Wait(250) end
    local list = lib.callback.await('pengu_dealers:get', false) or {}
    rebuild(list)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local list = lib.callback.await('pengu_dealers:get', false) or {}
    rebuild(list)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(dealers) do removePed(id) end
    dealers, peds = {}, {}
end)

-- Re-skin nearby peds live when dealer control shifts (gang reaches/loses control threshold).
AddStateBagChangeHandler('penguDealerControl', 'global', function(_, _, ctrl)
    if not ctrl then return end
    local outfits = GlobalState.penguDealerOutfits
    for id, ped in pairs(peds) do
        if ped and ped ~= false and DoesEntityExist(ped) then
            local d = dealers[id]
            if d then
                SetPedDefaultComponentVariation(ped)
                local gang = ctrl[tostring(id)]
                if gang and outfits then
                    local comps = outfits[gang] and outfits[gang][d.type]
                    if comps then
                        for _, c in ipairs(comps) do SetPedComponentVariation(ped, c.comp, c.draw, c.tex, 0) end
                    end
                end
            end
        end
    end
end)

-- Re-skin nearby peds when an admin adds or removes a gang outfit (/gangoutfit set/clear).
AddStateBagChangeHandler('penguDealerOutfits', 'global', function(_, _, outfits)
    if not outfits then return end
    local ctrl = GlobalState.penguDealerControl
    for id, ped in pairs(peds) do
        if ped and ped ~= false and DoesEntityExist(ped) then
            local d = dealers[id]
            if d then
                SetPedDefaultComponentVariation(ped)
                if ctrl then
                    local gang = ctrl[tostring(id)]
                    if gang then
                        local comps = outfits[gang] and outfits[gang][d.type]
                        if comps then
                            for _, c in ipairs(comps) do SetPedComponentVariation(ped, c.comp, c.draw, c.tex, 0) end
                        end
                    end
                end
            end
        end
    end
end)

TriggerEvent('chat:addSuggestion', '/dealeradd',       'Place an illegal dealer (admin)',          { { name = 'type', help = 'mechanic | drug_dealer | doctor | weapons | armor | general' }, { name = 'label', help = 'optional' } })
TriggerEvent('chat:addSuggestion', '/dealerremove',    'Remove a dealer ped (admin)',              { { name = 'id',   help = 'from /dealerlist' } })
TriggerEvent('chat:addSuggestion', '/dealerlist',      'List all dealer peds + auto-linked zones', {})
TriggerEvent('chat:addSuggestion', '/dealerinfluence', 'Show gang dealer influence (admin)',       { { name = 'gang', help = 'gang name' } })
TriggerEvent('chat:addSuggestion', '/gangoutfit',      'Set dealer ped outfit per gang (admin)',   { { name = 'subcommand', help = 'set | clear | list' } })
