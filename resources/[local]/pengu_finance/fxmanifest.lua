fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name         'pengu_finance'
version      '1.0.0'
description  'PenguRP - Finance: bank loans, credit score, income tax collection, business payroll.'

shared_scripts { '@ox_lib/init.lua', 'shared/config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }
client_scripts { 'client/main.lua' }

dependencies { 'ox_lib', 'oxmysql', 'qbx_core', 'Renewed-Banking', 'pengu_business' }
