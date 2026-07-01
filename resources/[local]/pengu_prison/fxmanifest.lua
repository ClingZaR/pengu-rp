fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pengu_prison'
author 'PenguRP'
description 'PenguRP - Jail & Court: prison labor (sentence reduction), bail, and judicial court powers'
version '1.0.0'

-- ox_lib loaded once here so `lib`, `cache` and the shared `Config` (config.lua)
-- are available on BOTH client and server.
shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',   -- shared helpers (PP.*)  [SPINE]
    'client/labor.lua',  -- ox_target work stations + progress
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',   -- labor reward, bail, judicial commands  [HUB]
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_target',
    'pengu_core', -- the real jail lives in pengu_core/server/jail.lua (not xt-prison)
}
