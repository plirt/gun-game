local npc_map_profiles = {}

npc_map_profiles.Default = {
	spawn_origin = Vector3.new(0, 4.5, -42),

	agents = {
		{ id = "Default_1", npc_type = "Default", gun_id = "REMINGTON" },
		{ id = "Default_2", npc_type = "Default", gun_id = "MUTANT" },
		{ id = "Default_3", npc_type = "Default", gun_id = "GLOCK" },
		{ id = "Default_4", npc_type = "Default", gun_id = "GLOCK" },
		{ id = "Default_5", npc_type = "Default", gun_id = "MUTANT" },
	},
}

return npc_map_profiles
