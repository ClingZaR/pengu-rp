-- PenguRP Petty Crime (pengu_pettycrime) - CLIENT. ox_target options bound to WORLD PROP MODELS
-- (ATMs + parking meters), no placement needed. The client only runs the minigame and reports the
-- result; the server validates the prop, proximity, cooldowns, tools and pays out. The tool cost /
-- cooldowns / dispatch are committed at BEGIN, so cancelling the progress bar does not undo them.
-- ASCII only. luac clean.

local busy = false

local FLAVOR = {
    atm   = { label = 'Uploading trojan...',       icon = 'fa-solid fa-credit-card',
              anim = { dict = 'anim@heists@ornate_bank@hack', clip = 'hack_loop' } },
    meter = { label = 'Jimmying the coin box...',  icon = 'fa-solid fa-coins',
              anim = { dict = 'mini@repair', clip = 'fixing_a_player' } },
}

local function attempt(kind, entity)
    if busy then return end
    busy = true

    local cfg = Config[kind]
    local fl  = FLAVOR[kind]
    if not cfg or not fl or not entity or not DoesEntityExist(entity) then busy = false; return end

    local model  = GetEntityModel(entity)
    local coords = GetEntityCoords(entity)

    -- server validates everything and commits the attempt (tool + cooldowns + dispatch)
    local ok = lib.callback.await('pengu_pettycrime:begin', false, kind, model, coords.x, coords.y, coords.z)
    if not ok then busy = false; return end

    -- minigame: skillcheck first, then the timed work
    local success = lib.skillCheck(cfg.skill, { 'w', 'a', 's', 'd' }) == true
    if success then
        success = lib.progressCircle({
            label = fl.label,
            duration = cfg.progressMs or 5000,
            position = 'bottom',
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = fl.anim,
        }) == true
    end

    -- always report back so the server closes the session (it pays only on a plausible success)
    lib.callback.await('pengu_pettycrime:finish', false, success)
    busy = false
end

-- ===================== targets on the world props =====================
exports.ox_target:addModel(Config.atm.models, {
    {
        name = 'pengu_pettycrime_atm',
        icon = FLAVOR.atm.icon,
        label = 'Hack ATM',
        items = Config.atm.item, -- option only shows if the player carries a trojan_usb
        distance = Config.interactDist or 2.0,
        onSelect = function(d) attempt('atm', d.entity) end,
    },
})

exports.ox_target:addModel(Config.meter.models, {
    {
        name = 'pengu_pettycrime_meter',
        icon = FLAVOR.meter.icon,
        label = 'Break into Meter',
        items = Config.meter.item, -- option only shows if the player carries a lockpick
        distance = Config.interactDist or 2.0,
        onSelect = function(d) attempt('meter', d.entity) end,
    },
})
