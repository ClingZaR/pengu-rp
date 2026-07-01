fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pengu_mdt'
author 'PenguRP'
description 'Standalone Qbox MDT (vehicle/person lookup, penal code, authoritative arrest calculator)'
version '1.1.0'

-- ox_lib is loaded ONCE here so `lib`, `cache` and the global `PenalCode`
-- (from shared/penalcode.lua) are available in BOTH client and server.
-- Do not re-list @ox_lib/init.lua in client_scripts/server_scripts.
shared_scripts {
    '@ox_lib/init.lua',
    'shared/penalcode.lua', -- external build; provides global PenalCode (client + server)
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'xt-prison',
    'screenshot-basic',
}
