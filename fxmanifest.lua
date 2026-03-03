fx_version 'cerulean'
game 'gta5'

author 'Wafflez'
description 'Police Jail Script for NDCore using ox_lib and ox_inventory'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    '@ND_Core/init.lua'
}

client_scripts {
    'client.lua',
}

server_scripts {
    'server.lua',
}

dependencies {
    'ox_lib',
    'ox_inventory',
}
