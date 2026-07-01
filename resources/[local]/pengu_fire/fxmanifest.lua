fx_version 'cerulean'
game 'gta5'

name 'pengu_fire'
description 'PenguRP - Fire Department mechanic: fightable structure fires, /firecall, extinguish-for-pay'
version '1.0.0'

shared_script 'config.lua'

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

lua54 'yes'
