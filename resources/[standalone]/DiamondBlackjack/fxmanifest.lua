fx_version 'adamant'

game "gta5"

description "DiamondBlackjack created by Robbster"

-- PenguRP: removed streamed casino peds (stream/Peds + peds.meta) and dlc_vinewood
-- PenguRP: audio data files from the original release. This server enforces game
-- PenguRP: build 3751, where all casino DLC peds/audio/anims ship with the base
-- PenguRP: game; re-streaming them can conflict with the built-in assets.
-- PenguRP: RageUI src (rubbertoe98/RageUI fork) is bundled under src/ per the README.

client_scripts {
	"src/RMenu.lua",
	"src/menu/RageUI.lua",
	"src/menu/Menu.lua",
	"src/menu/MenuController.lua",
	"src/components/*.lua",
	"src/menu/elements/*.lua",
	"src/menu/items/*.lua",
	"src/menu/panels/*.lua",
	"src/menu/windows/*.lua",
	"cl_blackjack.lua",
	"cl_casinoteleporter.lua",
}

server_script "sv_blackjack.lua"
