fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name         'pengu_nightclub'
version      '1.0.0'
description  'PenguRP - Nightclub: URL DJ booth (xsound), drinks bar, pulse lights at the Galaxy afterhours club.'

shared_scripts { '@ox_lib/init.lua', 'shared/config.lua' }
server_scripts { 'server/main.lua' }
client_scripts { 'client/main.lua' }

dependencies { 'ox_lib', 'ox_target', 'qbx_core', 'xsound' }
