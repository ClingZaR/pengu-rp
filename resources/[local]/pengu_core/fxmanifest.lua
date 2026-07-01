fx_version 'cerulean'
game 'gta5'

name 'pengu_core'
description 'PenguRP core - stats, hotkey overlay, jail, PD/legal-faction systems, faction chat + ranks'

shared_scripts {
    'shared/factions.lua',
}

client_scripts {
    '@ox_lib/init.lua',
    'client/stats.lua',
    'client/hotkeys.lua',
    'client/cursor.lua',
    'client/actions.lua',
    'client/voice.lua',
    'client/armory.lua',
    'client/jail.lua',
    'client/sirens.lua',
    'client/factions.lua',
    'client/dispatch.lua',  -- shared dispatch relay (ps-dispatch:CustomAlert handler)
    'client/marriage.lua',
    'client/events.lua',
}

server_scripts {
    '@ox_lib/init.lua',
    '@oxmysql/lib/MySQL.lua',
    'server/stats.lua',
    'server/pd.lua',
    'server/jail.lua',
    'server/factions.lua',
    'server/factionlock.lua', -- gang <-> legal-faction mutual exclusivity
    'server/dispatch.lua',    -- shared dispatch relay (exports.pengu_core:Dispatch)
    'server/marriage.lua',
    'server/events.lua',
    'server/daily.lua',
}

ui_page 'html/hotkeys.html'
files {
    'html/hotkeys.html',
    'html/hotkeys.css',
    'html/pdmenu.v3.css',
    'html/pdmenu.v3.js',
    'html/cloth.js',
    'html/faction.css',
    'html/faction.js',
}

lua54 'yes'
