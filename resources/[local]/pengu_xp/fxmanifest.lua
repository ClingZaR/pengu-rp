fx_version 'cerulean'
game 'gta5'

name 'pengu_xp'
description 'PenguRP Character XP - categorised skill progression with daily playtime tracking'

shared_scripts {
    'shared/config.lua',
}

server_scripts {
    '@ox_lib/init.lua',
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    '@ox_lib/init.lua',
    'client/main.lua',
}

lua54 'yes'
