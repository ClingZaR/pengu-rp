fx_version 'cerulean'
game 'common'

name 'qbx_chat_theme'
description 'mantine-styled theme for the chat resource.'
version '1.0.0'
author 'um - d4 | <qbox team>'
repository 'https://github.com/Qbox-project/qbx_chat_theme'

-- we need chat to be able to access this resource's callbacks
nui_callback_strict_mode 'false'

shared_scripts {
    '@ox_lib/init.lua',
}

client_scripts {
    'client/config.lua',
    'client/rp-commands.lua',
    'client/chat-persist.lua',
}

server_scripts {
    'server/join-messages.lua',
    'server/user.lua',
    'server/rp-commands.lua',
}

files {
    'theme/**',
}

-- All RP templates use 4 positional args:
--   {0} = timestamp  [HH:MM:SS]
--   {1} = name  (underscore for /me /do, plain for others)
--   {2} = serverId
--   {3} = message text
--
-- Note: extra spans around {0}/{1} in some templates work around a fivem
-- chat bug - https://github.com/citizenfx/fivem/pull/3705
chat_theme 'qbox_chat' {
    styleSheet = 'theme/app.css',
    script = 'theme/app.js',
    msgTemplates = {
        -- system / console messages
        default    = '<p class="message-wrapper"><span class="author alt"><span>{0}</span></span><span><span>{1}</span></span></p>',
        defaultAlt = '<p class="message-wrapper"><span class="alt"><span>{0}</span></span></p>',
        print      = '<p class="message-wrapper"><span class="author console">Console</span><span class="print color-7"><span>{0}</span></span></p>',
        join       = '<p class="message-wrapper"><span class="join"><span>{0}</span></span></p>',
        quit       = '<p class="message-wrapper"><span class="quit"><span>{0}</span></span></p>',

        -- normal player chat:  [14:06:35] Samuel White (106): message
        user = '<div class="rp-line rp-user"><span class="ts">[{0}]</span> <span class="rp-n">{1}</span><span class="uid"> ({2})</span>: {3}</div>',

        -- proximity speech with a verb before the colon (says / says quietly / shouts / whispers /
        -- says in the car). args: {0}=ts {1}=name {2}=id {3}=verb {4}=text
        ['rp:say'] = '<div class="rp-line rp-user"><span class="ts">[{0}]</span> <span class="rp-n">{1}</span><span class="uid"> ({2})</span> <span class="say-verb">{3}</span>: {4}</div>',

        -- /me:  [14:06:35] * Samuel_White (5) lights a cigarette
        ['rp:me'] = '<div class="rp-line rp-me"><span class="ts">[{0}]</span> * <span class="rp-n">{1}</span> ({2}) {3}</div>',

        -- /do:  [14:06:35] * The room smells of smoke (( Samuel_White (5) ))
        ['rp:do'] = '<div class="rp-line rp-do"><span class="ts">[{0}]</span> * {3} (( <span class="rp-n">{1}</span> ({2}) ))</div>',

        -- /ooc /o /b:  [14:06:35] (( Samuel White (106): text ))
        ['rp:ooc'] = '<div class="rp-line rp-ooc"><span class="ts">[{0}]</span> (( {1} ({2}): {3} ))</div>',

        -- [DISPATCH]:  [14:06:35] *** [DISPATCH] message ***  (blue)
        ['rp:dispatch'] = '<div class="rp-line rp-dispatch"><span class="ts">[{0}]</span> <span class="acc">***</span> <span class="dtag">[DISPATCH]</span> {3} <span class="acc">***</span></div>',

        -- [SUCCESS]:  [14:06:35] [SUCCESS] message
        ['rp:success'] = '<div class="rp-line rp-success"><span class="ts">[{0}]</span> <span class="stag">[SUCCESS]</span> {3}</div>',

        -- Faction/job:  [14:06:35] [Police | Officer III] Name: message
        -- args: {0}=ts  {1}=factionLabel  {2}=name  {3}=text
        ['rp:faction'] = '<div class="rp-line rp-faction"><span class="ts">[{0}]</span> <span class="ftag">[{1}]</span> <span class="fn">{2}</span><span class="fcolon">:</span> {3}</div>',

        -- Faction OOC (/f):  [14:06:35] [LSPD | Chief] David Loan: (( text ))
        -- The colon and the (( )) brackets are tinted with the faction colour; inner text stays body.
        -- args: {0}=ts  {1}=factionLabel  {2}=name  {3}=text (NO brackets - the template adds them)
        ['rp:faction:ooc'] = '<div class="rp-line rp-faction"><span class="ts">[{0}]</span> <span class="ftag">[{1}]</span> <span class="fn">{2}</span><span class="fcolon">:</span> <span class="fooc">((</span> {3} <span class="fooc">))</span></div>',

        -- Gang OOC (/f for criminal gangs): same layout but colour is per-gang via inline style.
        -- args: {0}=ts  {1}=gangLabel  {2}=name  {3}=text  {4}=hexColour (e.g. #9b59b6)
        ['pengu:gang:ooc'] = '<div class="rp-line rp-faction"><span class="ts">[{0}]</span> <span class="ftag" style="color:{4}">[{1}]</span> <span class="fn" style="color:{4}">{2}</span><span class="fcolon" style="color:{4}">:</span> <span class="fooc" style="color:{4}">((</span> {3} <span class="fooc" style="color:{4}">))</span></div>',

        -- [LAW] (kept for backward compat with other resources using sendLaw)
        ['rp:law'] = '<div class="rp-line rp-faction"><span class="ts">[{0}]</span> <span class="ftag">[LAW]</span> <span class="fn">{1}</span> ({2}): {3}</div>',

        -- /stats - bracketed character stat block (no background, outlined)
        -- args: {0}=name {1}=vehicles {2}=houses {3}=job {4}=phone {5}=bank {6}=cash {7}=debt {8}=salary
        ['pengu:stats'] = '<div class="rp-line rp-stats"><span class="st-head">PLAYER STATS - {0}</span><span class="st-b">[ Vehicles <b>{1}</b> ]</span><span class="st-b">[ Houses <b>{2}</b> ]</span><span class="st-b">[ Job <b>{3}</b> ]</span><span class="st-b">[ Phone <b>{4}</b> ]</span><span class="st-b">[ Bank <b class="money">${5}</b> ]</span><span class="st-b">[ Cash <b class="money">${6}</b> ]</span><span class="st-b">[ Debt <b class="money">${7}</b> ]</span><span class="st-b">[ Salary <b class="money">${8}</b> ]</span></div>',

        -- [Status Check] death / medical status line (qbx_medical, qbx_ambulancejob)
        -- args: {0}=label ("Status Check")  {1}=reason ("Committed suicide" / "Bled out" / ...)
        ['rp:status'] = '<div class="rp-line rp-status"><span class="stag">[{0}]</span> {1}</div>',

        -- Admin / system command output (e.g. /pdloc). args: {0}=tag {1}=message {2}=kind(ok|err|info)
        ['pengu:admin'] = '<div class="rp-line rp-admin rp-admin-{2}"><span class="atag">[{0}]</span> {1}</div>',
    },
}
