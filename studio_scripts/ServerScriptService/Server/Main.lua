local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Framework = ReplicatedStorage.Modules.Shared.Framework
local NetworkProtocol = require(Framework.NetworkProtocol)
local RuntimeGraph = require(Framework.RuntimeGraph)

local Main = {}

local constants = require(script.ServerConstants)

function Main.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote_map = NetworkProtocol.ensure_server(remotes)

	local ctx = {
		Players = Players,
		ReplicatedStorage = ReplicatedStorage,
		ServerStorage = ServerStorage,
		remotes = remotes,
		remote_map = remote_map,
		network_protocol = NetworkProtocol,

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

	-- The graph is the authoritative lifecycle. Dependencies below are executable design
	-- decisions, so changing service order cannot silently create a half-initialized game.
	local runtime = RuntimeGraph.new(ctx)
	ctx.runtime = runtime
	local function register(name, dependencies, module)
		runtime:register(name, dependencies, function()
			module.setup(ctx)
			return module
		end)
	end

	runtime:register("CombatAuthority", {}, function()
		local authority = require(script.CombatAuthority).new()
		ctx.combat_authority = authority
		return authority
	end)
	register("PlayerState", {}, require(script.PlayerState))
	register("ShopService", { "PlayerState" }, require(script.ShopService))
	register("PlayerCharacterWeaponService", { "PlayerState" }, require(script.PlayerCharacterWeaponService))
	register("PseudoSpawnService", {}, require(script.PseudoSpawnService))
	register("PlayerMovementService", { "PseudoSpawnService" }, require(script.PlayerMovementService))
	register("RagdollService", { "PlayerMovementService" }, require(script.RagdollService))
	register("LagCompensationService", {}, require(script.LagCompensationService))
	runtime:register("CombatEventStream", {}, function()
		return require(script.Combat.CombatEventStream).new(1024)
	end)
	runtime:register("CombatDamageService", { "CombatAuthority", "CombatEventStream" }, function()
		return require(script.Combat.CombatDamageService)
	end)
	runtime:register("CombatActorRegistry", { "PlayerState", "PlayerCharacterWeaponService" }, function()
		return require(script.Combat.CombatActorRegistry).new({
			Players = Players,
			player_state = require(script.PlayerState),
			player_character_weapon_service = require(script.PlayerCharacterWeaponService),
		})
	end)
	runtime:register("WeaponDriverRegistry", {}, function()
		return require(script.Combat.WeaponDriverRegistry).new()
	end)
	runtime:register("CombatPipeline", {
		"CombatEventStream",
		"CombatActorRegistry",
		"WeaponDriverRegistry",
	}, function()
		return require(script.Combat.CombatPipeline).new(
			runtime:get("CombatActorRegistry"),
			runtime:get("WeaponDriverRegistry"),
			runtime:get("CombatEventStream")
		)
	end)
	register("WeaponService", {
		"CombatAuthority",
		"CombatDamageService",
		"CombatPipeline",
		"CombatEventStream",
		"WeaponDriverRegistry",
		"PlayerState",
		"PlayerCharacterWeaponService",
		"LagCompensationService",
	}, require(script.WeaponService))
	register("NpcFillService", {
		"CombatAuthority",
		"CombatActorRegistry",
		"CombatPipeline",
		"PlayerState",
		"PlayerCharacterWeaponService",
		"WeaponService",
	}, require(script.NpcFillService))
	register("MatchService", { "CombatAuthority", "PlayerState", "NpcFillService" }, require(script.MatchService))
	register("ReplayService", { "CombatEventStream", "MatchService" }, require(script.ReplayService))
	register("GrenadeService", {
		"CombatAuthority",
		"CombatDamageService",
		"CombatEventStream",
		"CombatPipeline",
		"PlayerState",
		"RagdollService",
		"WeaponDriverRegistry",
	}, require(script.GrenadeService))
	register("MissionService", { "PlayerMovementService", "NpcFillService" }, require(script.MissionService))
	runtime:start_all()
end

return Main
