fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'pengu_robbery'
description 'Store register robberies (mhacking) and back-room safe cracks (safecracker). Dirty money feeds into the launder pipeline.'
author      'PenguRP'
version     '1.0.0'

shared_scripts { '@ox_lib/init.lua', 'shared/config.lua' }
server_scripts { 'server/main.lua' }
client_scripts { 'client/main.lua' }

dependencies { 'ox_lib', 'ox_inventory', 'ox_target', 'qbx_core', 'ps-dispatch', 'mhacking', 'safecracker' }
