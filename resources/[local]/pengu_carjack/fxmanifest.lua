fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'pengu_carjack'
description 'Hotwire unoccupied vehicles and carjack occupied ones. Feeds stolen cars into the chopshop.'
author      'PenguRP'
version     '1.0.0'

shared_scripts { '@ox_lib/init.lua' }
server_scripts { 'server/main.lua' }
client_scripts { 'client/main.lua' }

dependencies { 'ox_lib', 'ox_inventory', 'ox_target', 'qbx_core', 'qbx_vehiclekeys', 'ps-dispatch' }
