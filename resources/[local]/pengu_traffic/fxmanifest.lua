fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pengu_traffic'
author 'PenguRP'
description 'PenguRP - Traffic & Pursuit: spike strips, radar gun, traffic cones, speed cameras, parking tickets, carjacking'
version '1.0.0'

-- ox_lib loaded once here so `lib` and `cache` and the shared `Config`
-- (config.lua) are available on BOTH client and server. Do NOT re-list
-- @ox_lib/init.lua in the client/server blocks.
shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',     -- shared client helpers (PT.*), /fines UI  [SPINE]
    'client/spikes.lua',   -- spike strip deploy / burst / pickup
    'client/radar.lua',    -- radar gun readout + issue fine
    'client/cones.lua',    -- traffic cone place / pickup
    'client/speedcam.lua', -- automated speed cameras
    'client/carjack.lua',  -- carjacking (pull driver out)
    'client/parking.lua',  -- parking-ticket ox_target option
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',     -- fines DB + callbacks/events + dispatch relay  [SPINE]
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_target',
    'ps-dispatch',
}
