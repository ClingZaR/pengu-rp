-- PenguRP - FACTION REGISTRY (single source of truth, loaded shared: client + server).
--
-- Two tiers:
--   * LEGAL factions  = qbx JOBS. Full feature set (locations / fleet / clothing / armoury)
--     is layered on top by server/pd.lua. `kind` mirrors the qbx job.type.
--   * CRIMINAL factions = qbx GANGS. NOTHING extra - only the shared faction chat (/f)
--     and the rank/roster menu (/faction), exactly like every other faction.
--
-- Both tiers share the chat + ranking system (server/factions.lua). Adding a faction is a
-- one-line edit here; nothing else hard-codes the member list. ASCII only. luac clean.

Factions = {}

-- Legal factions (jobs). Keyed by qbx job name. label is the faction-chat / menu tag.
-- `locker` overrides the personal-locker stash id (defaults to 'pengu_locker_<job>'); the LEO
-- agencies keep the legacy qbx 'policelocker' so existing officer lockers are preserved.
Factions.legal = {
    police    = { label = 'LSPD', kind = 'leo',  locker = 'policelocker' },
    bcso      = { label = 'BCSO', kind = 'leo',  locker = 'policelocker' },
    sasp      = { label = 'SASP', kind = 'leo',  locker = 'policelocker' },
    ambulance = { label = 'EMS',  kind = 'ems' },
    fire      = { label = 'LSFD', kind = 'fire' },
}

-- Criminal factions (gangs). Keyed by qbx gang name. Chat + ranks ONLY.
-- chatColour = hex used for the gang's /f chat tag, name, and OOC brackets.
Factions.criminal = {
    lostmc   = { label = 'The Lost MC', chatColour = '#e8890b' }, -- amber/orange (biker gold)
    ballas   = { label = 'Ballas',      chatColour = '#9b59b6' }, -- purple
    vagos    = { label = 'Vagos',       chatColour = '#a8d740' }, -- yellow-green
    cartel   = { label = 'Cartel',      chatColour = '#e74c3c' }, -- red
    families = { label = 'Families',    chatColour = '#2ecc71' }, -- green
    triads   = { label = 'Triads',      chatColour = '#3498db' }, -- blue
}

-- True if the given job name is a legal faction.
function Factions.isLegal(jobName)
    return jobName ~= nil and Factions.legal[jobName] ~= nil
end

-- True if the given gang name is a criminal faction.
function Factions.isCriminal(gangName)
    return gangName ~= nil and Factions.criminal[gangName] ~= nil
end

-- The label for a faction key in a given scope ('legal' | 'criminal'), or the key itself.
function Factions.labelOf(scope, key)
    local t = scope == 'criminal' and Factions.criminal or Factions.legal
    local f = key and t[key]
    return (f and f.label) or key or '?'
end

-- The personal-locker stash id for a legal faction (per-faction so each agency has its own,
-- instead of every legal faction borrowing the police locker). nil if not a legal faction.
function Factions.lockerOf(jobName)
    local def = jobName and Factions.legal[jobName]
    if not def then return nil end
    return def.locker or ('pengu_locker_' .. jobName)
end
