fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pengu_launder'
author 'PenguRP'
description 'Money Laundering (Phase 3.3) - async, contestable laundromats: black_money -> clean CASH over time'
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
