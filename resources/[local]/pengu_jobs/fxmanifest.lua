fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pengu_jobs'
author 'PenguRP'
description 'Civilian Gathering Jobs (Phase 4.1) - admin-placeable gather + sell points (mining v1)'
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
}
