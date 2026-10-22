fx_version 'cerulean'
game 'gta5'

author 'fvsgamers'
description 'SAMU NPC - Versão QB-Core + OX'
version '1.0.0'

dependencies {
    'qb-core',
    'ox_lib'
}

shared_scripts {
    '@ox_lib/init.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}
