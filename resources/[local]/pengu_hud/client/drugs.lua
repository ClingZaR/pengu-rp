-- PenguRP: DRUG EFFECTS (pengu_hud CLIENT). Consuming a drug applies timed BUFFS (run faster, take
-- less damage, combat edge, endless stamina) AND NERFS (impairment: blur + drunk sway via the shared
-- effects.lua pipeline). Active effects show in the HUD as icon chips with a countdown ring.
--
-- Hooks the EXISTING qbx_consumables client events (no fork): consumables:client:meth / Cokebaggy /
-- Crackbaggy / EcstasyBaggy / oxy / UseJoint. Buff magnitudes/durations are config below (admin-
-- tunable: edit + restart pengu_hud). ASCII only. luac clean.
--
-- NOTE on "less recoil": GTA has no clean recoil native, so the meth/coke combat buff is implemented
-- as a weapon-DAMAGE boost (SetPlayerWeaponDamageModifier) - a real combat edge - shown as "Combat".

-- ============================ config (tune freely) ============================
-- buffs: speed (sprint mult add, capped so total <= 1.49), resist (fraction of damage healed back =
--        "take less damage"), weaponDamage (outgoing dmg add), stamina (true = endless sprint).
-- nerf:  impairment (0-100 fed to the shared impairment pipeline -> blur/sway).
-- icon:  one of the keys in the NUI ICONS map (app.js): bolt, snow, fire, heart, pill, leaf.
-- Balance note: buffs are an EDGE, not a win-button. speed = sprint only (capped 1.49). resist =
-- fraction of incoming damage healed back (kept moderate so drugs don't trivialize gunfights).
-- weaponDamage is a small combat nudge. Tune all of this freely.
local DRUG_EFFECTS = {
    meth = {
        label = 'Meth', icon = 'bolt', duration = 90000,
        buffs = { speed = 0.28, resist = 0.20, weaponDamage = 0.10, stamina = true },
        nerf = { impairment = 25 },
    },
    cokebaggy = {
        label = 'Cocaine', icon = 'snow', duration = 60000,
        buffs = { speed = 0.25, resist = 0.15, weaponDamage = 0.08, stamina = true },
        nerf = { impairment = 15 },
    },
    crack_baggy = {
        label = 'Crack', icon = 'fire', duration = 45000,
        buffs = { speed = 0.32, resist = 0.12, stamina = true },
        nerf = { impairment = 35 },
    },
    xtcbaggy = {
        label = 'Ecstasy', icon = 'heart', duration = 120000,
        buffs = { speed = 0.15, resist = 0.20 },
        nerf = { impairment = 30 },
    },
    oxy = {
        label = 'Oxy', icon = 'pill', duration = 90000,
        buffs = { resist = 0.30 },
        nerf = { impairment = 40 },
    },
    joint = {
        label = 'High', icon = 'leaf', duration = 60000,
        buffs = { resist = 0.12 },
        nerf = { impairment = 45 },
    },
}
local SPRINT_CAP = 1.49 -- engine max for SetRunSprintMultiplierForPlayer

-- ============================ state ============================
local active = {} -- drugKey -> { def, expires (GetGameTimer ms) }

local function anyActive()
    return next(active) ~= nil
end

-- combined buffs = the strongest of each across all active effects.
local function combinedBuffs()
    local b = { speed = 0.0, resist = 0.0, weaponDamage = 0.0, stamina = false }
    for _, a in pairs(active) do
        local bf = a.def.buffs or {}
        if (bf.speed or 0) > b.speed then b.speed = bf.speed end
        if (bf.resist or 0) > b.resist then b.resist = bf.resist end
        if (bf.weaponDamage or 0) > b.weaponDamage then b.weaponDamage = bf.weaponDamage end
        if bf.stamina then b.stamina = true end
    end
    return b
end

-- push the active-effect chips (with countdown) to the NUI.
local function pushNui()
    local now = GetGameTimer()
    local list = {}
    for key, a in pairs(active) do
        local remaining = a.expires - now
        if remaining > 0 then
            list[#list + 1] = {
                key = key,
                icon = a.def.icon or 'pill',
                label = a.def.label or key,
                secs = math.ceil(remaining / 1000),
                pct = math.max(0.0, math.min(1.0, remaining / (a.def.duration or 1))),
            }
        end
    end
    SendNUIMessage({ action = 'effects', list = list })
end

-- ============================ apply / clear ============================
local function clearBuffModifiers()
    local pid = PlayerId()
    SetRunSprintMultiplierForPlayer(pid, 1.0)
    SetPlayerWeaponDamageModifier(pid, 1.0)
end

local function expire(key)
    active[key] = nil
    exports.pengu_hud:SetImpairment(key, 0) -- drop this drug's nerf from the impairment pipeline
end

local function applyDrug(key)
    local def = DRUG_EFFECTS[key]
    if not def then return end
    active[key] = { def = def, expires = GetGameTimer() + (def.duration or 60000) }
    if def.nerf and def.nerf.impairment then
        exports.pengu_hud:SetImpairment(key, def.nerf.impairment)
    end
    lib.notify({ title = def.label or 'Drug', description = 'You feel it kick in...', type = 'inform', position = 'top' })
    pushNui()
end

-- ============================ main loop ============================
CreateThread(function()
    local lastHealth = nil
    while true do
        if not anyActive() then
            if lastHealth ~= nil then clearBuffModifiers(); SendNUIMessage({ action = 'effects', list = {} }); lastHealth = nil end
            Wait(700)
        else
            local now = GetGameTimer()
            -- expire finished effects
            local changed = false
            for key, a in pairs(active) do
                if now >= a.expires then expire(key); changed = true end
            end

            local ped = PlayerPedId()
            local dead = IsEntityDead(ped) or IsPedFatallyInjured(ped)

            if anyActive() and not dead then
                local b = combinedBuffs()
                local pid = PlayerId()
                -- run faster (sprint), persists but cheap to reassert
                SetRunSprintMultiplierForPlayer(pid, math.min(SPRINT_CAP, 1.0 + (b.speed or 0)))
                -- combat edge (outgoing weapon damage)
                SetPlayerWeaponDamageModifier(pid, 1.0 + (b.weaponDamage or 0))
                -- endless stamina
                if b.stamina then RestorePlayerStamina(pid, 1.0) end
                -- take less damage: heal back a fraction of any damage taken since the last tick
                local cur = GetEntityHealth(ped)
                if (b.resist or 0) > 0 and lastHealth and cur > 0 and cur < lastHealth then
                    local heal = math.floor((lastHealth - cur) * b.resist)
                    if heal > 0 then SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), cur + heal)) end
                end
                lastHealth = GetEntityHealth(ped)
            else
                lastHealth = nil
            end

            if changed or anyActive() then pushNui() end
            Wait(250)
        end
    end
end)

-- ============================ qbx_consumables hooks (no fork) ============================
RegisterNetEvent('consumables:client:meth',        function() applyDrug('meth') end)
RegisterNetEvent('consumables:client:Cokebaggy',   function() applyDrug('cokebaggy') end)
RegisterNetEvent('consumables:client:Crackbaggy',  function() applyDrug('crack_baggy') end)
RegisterNetEvent('consumables:client:EcstasyBaggy',function() applyDrug('xtcbaggy') end)
RegisterNetEvent('consumables:client:oxy',         function() applyDrug('oxy') end)
RegisterNetEvent('consumables:client:UseJoint',    function() applyDrug('joint') end)

-- safety: never leave modifiers stuck if the resource stops.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearBuffModifiers()
    for key in pairs(active) do exports.pengu_hud:SetImpairment(key, 0) end
end)
