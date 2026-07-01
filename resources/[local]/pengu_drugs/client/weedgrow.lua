-- PenguRP Drug Supply Chain (pengu_drugs) - qbx_weed GROW bridge.
-- qbx_weed ships placePlant/foodPlant exports but the seed/nutrition items were never wired to them,
-- so the grow loop was unreachable (you could not plant). These thin wrappers adapt ox_inventory's
-- item-use convention (called as (data, slot)) to qbx_weed's export signatures, completing the chain
-- GROW (plant -> water -> harvest buds) -> PRESS (pengu_drugs weed_press) -> SELL (qbx_drugs).
--
-- CONSUME semantics (set in ox_inventory items.lua):
--   * seeds use consume = 0 here because qbx_weed's placePlant fires qbx_weed:server:removeSeed on a
--     SUCCESSFUL plant (and not at all on a failed one), so the seed is removed exactly once and a
--     failed plant keeps it. (consume = 1 would double-remove / lose it on failure.)
--   * weed_nutrition keeps the default consume = 1: qbx_weed's foodPlant does NOT remove it, so
--     ox_inventory consumes one fertilizer per feed.
-- ASCII only. luac clean.

-- seed item name -> qbx_weed plant 'sort' (config/shared.lua plants keys)
local SEED_TO_SORT = {
    ['weed_og-kush_seed']     = 'og_kush',
    ['weed_amnesia_seed']     = 'amnesia',
    ['weed_skunk_seed']       = 'skunk',
    ['weed_ak47_seed']        = 'ak47',
    ['weed_purple-haze_seed'] = 'purple_haze',
    ['weed_white-widow_seed'] = 'white_widow',
}

exports('plantSeed', function(data, slot)
    -- ox_inventory (client.lua:511-519) calls a use export as (itemDef, {name, slot, metadata}) and
    -- sets itemDef.slot = the slot number first. The GUARANTEED name source is the 2nd arg; read both
    -- defensively so this works whether or not the item definition carries .name.
    local info   = type(slot) == 'table' and slot or nil
    local name   = (info and info.name) or (data and data.name)
    local slotNo = (data and data.slot) or (info and info.slot)
    local sort   = name and SEED_TO_SORT[name]
    if not sort then return end
    -- qbx_weed placePlant(type, item) reads item.slot + item.name for removeSeed.
    exports.qbx_weed:placePlant(sort, { slot = slotNo, name = name })
end)

exports('feedPlant', function()
    exports.qbx_weed:foodPlant()
end)
