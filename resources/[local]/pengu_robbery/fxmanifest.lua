fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'pengu_robbery'
description 'Back-room safe cracking (safecracker minigame). Store register robbery is handled by qbx_storerobbery.'
author      'PenguRP'
version     '1.0.0'

shared_scripts { '@ox_lib/init.lua', 'shared/config.lua' }
server_scripts { 'server/main.lua' }
client_scripts { 'client/main.lua' }

dependencies { 'ox_lib', 'ox_inventory', 'ox_target', 'qbx_core', 'ps-dispatch', 'safecracker' }
