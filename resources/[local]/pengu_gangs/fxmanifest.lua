fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pengu_gangs'
author 'PenguRP'
description 'Gang Reputation & Level - underworld progression foundation (rep -> level -> imports/perks)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@pengu_core/shared/factions.lua',
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
    'pengu_core',
}
