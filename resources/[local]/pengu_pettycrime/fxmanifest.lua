fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pengu_pettycrime'
author 'PenguRP'
description 'Petty Crime (Phase 3) - ATM hacking (trojan_usb -> dirty money) and parking meter theft (lockpick -> cash) against world props. Server-authoritative.'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
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
}
