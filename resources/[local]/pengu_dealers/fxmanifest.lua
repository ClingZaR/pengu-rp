fx_version 'cerulean'
game 'gta5'

name         'pengu_dealers'
version      '1.0.0'
description  'PenguRP - Illegal dealer peds: chop mechanic, street drug dealer, black market doctor, arms dealer.'

shared_scripts { '@ox_lib/init.lua', '@pengu_core/shared/factions.lua', 'shared/config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }
client_scripts { 'client/main.lua' }

dependencies { 'ox_lib', 'ox_target', 'oxmysql', 'qbx_core', 'pengu_core', 'pengu_xp', 'pengu_gangs', 'pengu_turf', 'pengu_blackmarket' }
