fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pengu_chopshop'
author 'PenguRP'
description 'Chop Shop (Phase 3.5) - strip non-owned vehicles for dirty money + parts at admin-placeable chop points'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'ox_target',
    'pengu_xp',    -- server/main.lua awards criminal XP on a chop (pcall-guarded)
    'pengu_gangs', -- server/main.lua awards gang rep on a chop (pcall-guarded)
}
