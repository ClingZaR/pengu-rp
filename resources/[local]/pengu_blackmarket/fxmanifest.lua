fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pengu_blackmarket'
author 'PenguRP'
description 'Black Market (Phase 3.4) - weapon catalog + crate-drop delivery (sold via pengu_dealers arms dealer)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@pengu_core/shared/factions.lua',
    'shared/config.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'pengu_core',
    'pengu_gangs',
    'pengu_turf',
}
