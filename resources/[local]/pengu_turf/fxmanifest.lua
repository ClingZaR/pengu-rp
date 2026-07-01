fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pengu_turf'
author 'PenguRP'
description 'Gang Territory (Phase 2) - influence-based control: core bases, dealing/graffiti influence, perks, gang rep'
version '1.0.0'

-- Factions (gang registry) is reused from pengu_core so there is a single gang list; the dependency
-- below guarantees pengu_core loads first.
shared_scripts {
    '@ox_lib/init.lua',
    '@pengu_core/shared/factions.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/gangs.lua',
    'server/main.lua',
    'server/influence.lua',
    'server/graffiti.lua',
    'server/bonus.lua',
    'server/territory.lua',
    'server/stash.lua',
    'server/admin.lua',
}

client_scripts {
    'client/main.lua',
    'client/capture_hud.lua',
    'client/graffiti.lua',
    'client/stash.lua',
}

-- DUI page (+ bundled graffiti fonts) that renders a tag's text as a runtime texture painted on the wall.
files {
    'ui/graffiti.html',
    'ui/fonts/*.ttf',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'pengu_core',
    'pengu_gangs',    -- influence.lua awards gang rep (zoneCaptured / perZoneTick / drugSaleInTurf)
    'ox_inventory',   -- graffiti.lua consumes the spraycan item
    'ox_target',      -- client/graffiti.lua (paint-over / police-remove)
    -- NOTE: territory.lua calls exports.pengu_dealers:GetControlledDealers, but pengu_dealers already
    -- depends on pengu_turf (RecomputeDealerTurf) - declaring it here too would be circular. The call is
    -- pcall-guarded and only runs on a timer well after boot, so a runtime-only reference is correct.
}
