local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Main = {}

local constants = require(script.server_constants)

function Main.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	local ctx = {
		Players = Players,
		ReplicatedStorage = ReplicatedStorage,
		ServerStorage = ServerStorage,
		remotes = remotes,

		BACKPACK_COLUMNS = constants.BACKPACK_COLUMNS,
		BACKPACK_ROWS = constants.BACKPACK_ROWS,

		gun_catalog = require(ReplicatedStorage.Modules.Shared.GunCatalog),
		weapon_config = require(ReplicatedStorage.Modules.Shared.WeaponConfig),
		weapon_math = require(ReplicatedStorage.Modules.Shared.WeaponMath),
		Ballistics = require(ReplicatedStorage.Modules.Shared.Ballistics),
		gun_configs = ReplicatedStorage:WaitForChild("GunConfigs"),

		active_map_id = constants.DEFAULT_MAP_ID,
		npc_hit_data = setmetatable({}, { __mode = "k" }),
	}

	require(script.player_state).setup(ctx)
	require(script.shop_service).setup(ctx)
	require(script.player_character_weapon_service).setup(ctx)
	require(script.player_movement_service).setup(ctx)
	require(script.ragdoll_service).setup(ctx)
	require(script.lag_compensation_service).setup(ctx)
	require(script.npc_fill_service).setup(ctx)
	require(script.match_service).setup(ctx)
	require(script.grenade_service).setup(ctx)
	require(script.weapon_service).setup(ctx)
	require(script.mission_service).setup(ctx)
end

return Main