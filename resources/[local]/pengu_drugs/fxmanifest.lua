fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pengu_drugs'
author 'PenguRP'
description 'Drug Supply Chain (Phase 3.2) - admin-placeable, minigame-gated processing/packaging labs'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/fields.lua',
}

client_scripts {
    'client/main.lua',
    'client/weedgrow.lua',
    'client/fields.lua',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'ox_target',
    'qbx_weed',
}
