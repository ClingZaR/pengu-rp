fx_version 'cerulean'
game 'gta5'

name 'pengu_hud'
description 'PenguRP Custom HUD'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

client_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'client/main.lua',
    'client/effects.lua', -- shared impairment pipeline (nerf side: blur/sway)
    'client/stress.lua',
    'client/drugs.lua',   -- drug buff/nerf effects + HUD icon chips
}

server_scripts {
    'server/stress.lua',
}

lua54 'yes'
