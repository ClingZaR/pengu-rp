fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name         'pengu_court'
version      '1.0.0'
description  'PenguRP - Court sessions: docket, trials, pleas, verdicts, optional jury.'

shared_scripts { '@ox_lib/init.lua', 'shared/config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }
client_scripts { 'client/main.lua' }

dependencies { 'ox_lib', 'oxmysql', 'qbx_core', 'pengu_mdt', 'xt-prison' }
