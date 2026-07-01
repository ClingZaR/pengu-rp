fx_version 'cerulean'
games { 'gta5' }

author "Swkeep#7049"

-- PenguRP: '@qb-core/shared/locale.lua' replaced with a vendored copy (locales/locale.lua)
-- PenguRP: so the resource works on Qbox (qbx_core provides 'qb-core' via bridge but does not
-- PenguRP: expose that file to other resources).
shared_scripts {
     'locales/locale.lua', -- PenguRP
     'locales/en.lua',
     'config.lua',
     'shared/shared.lua',
     'shared/util.lua',
     'shared/badwords.lua' }

client_scripts {
     'client/animator.lua',
     'client/functions.lua',
     'client/client.lua',
     'client/menu.lua',
     'client/c_util.lua'
}

server_scripts {
     '@oxmysql/lib/MySQL.lua',
     'server/functions.lua',
     'server/server.lua'
}

-- PenguRP: stream the bundled add-on K9 ped (was in unreferenced K9addon/ subfolder upstream;
-- PenguRP: moved to stream/ + data/peds.meta so the a_c_k9 model actually loads).
files {
     'data/peds.meta'
}

data_file 'PED_METADATA_FILE' 'data/peds.meta'

dependencies {
     'qbx_core',
     'ox_lib',
     'ox_inventory',
     'ox_target',
     'qb-menu',
     'qb-input'
}
