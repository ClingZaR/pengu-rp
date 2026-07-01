-- PenguRP: scrapyard gunsmith bench (replaces the stock ox 'debug_crafting' sample,
-- whose only recipe used 'scrapmetal' - an item that does not exist on this server).
-- All ingredients below are obtainable in the live economy:
--   metalscrap / iron  -> pengu_jobs mining ('Mine ore')
--   copper / aluminum  -> pengu_jobs mining ('Deep vein')
--   steel              -> pengu_jobs smelting (3x metalscrap)
--   chop_catalytic     -> pengu_chopshop (precious-metal catalytic converter)
-- Low-tier weapons only (pistol is the ceiling, per roadmap). No map blip: this is an
-- illegal bench players learn about in RP. Coords are script config - move freely.
-- NOTE: ox crafting has no built-in XP/level gate (only job 'groups'); gating by
-- pengu_xp would need a 'craftItem' ox hook in pengu_core (not done - minimal scope).
return {
	{
		name = 'pengu_scrapyard_gunsmith', -- PenguRP
		items = {
			{
				name = 'WEAPON_KNIFE',
				ingredients = {
					metalscrap = 4,
					steel = 1,
				},
				duration = 30000,
			},
			{
				name = 'ammo-9',
				ingredients = {
					metalscrap = 2,
					copper = 1,
				},
				duration = 30000,
				count = 12,
			},
			{
				name = 'WEAPON_SNSPISTOL',
				ingredients = {
					metalscrap = 8,
					steel = 3,
					aluminum = 2,
				},
				duration = 45000,
			},
			{
				name = 'WEAPON_PISTOL',
				ingredients = {
					steel = 5,
					iron = 4,
					copper = 2,
					chop_catalytic = 1,
				},
				duration = 60000,
			},
		},
		-- Rogers Salvage & Scrap yard (south LS). points = fallback when ox_target is
		-- disabled; zones = ox_target box. Only one of the two is used at runtime.
		points = {
			vec3(-424.90, -1728.42, 19.78),
		},
		zones = {
			{
				coords = vec3(-424.90, -1728.42, 19.78),
				size = vec3(2.0, 1.5, 1.2),
				distance = 2.0,
				rotation = 290.0,
				label = 'Use scrapyard workbench',
			},
		},
	},
}
