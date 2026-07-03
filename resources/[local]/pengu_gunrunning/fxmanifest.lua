fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'pengu_gunrunning'
description 'Gang-gated gun parts scavenging and tiered weapon crafting.'
author      'PenguRP'
version     '1.0.0'

shared_scripts { '@ox_lib/init.lua', 'shared/config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }
client_scripts { 'client/main.lua' }

dependencies { 'ox_lib', 'ox_inventory', 'ox_target', 'qbx_core', 'oxmysql' }
