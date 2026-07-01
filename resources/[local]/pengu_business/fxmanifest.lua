fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pengu_business'
author 'PenguRP'
description 'Business Ownership (Phase 4.2) - buy admin-registered businesses; employee mgmt + bank via qbx'
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
    'ox_target',
    'qbx_management',
    'Renewed-Banking',
}
