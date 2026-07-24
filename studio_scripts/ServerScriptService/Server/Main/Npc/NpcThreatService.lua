local npc_threat_service = {}

local constants = require(script.Parent.Parent.ServerConstants)
local player_character_weapon_service = require(script.Parent.Parent.PlayerCharacterWeaponService)
local player_state = require(script.Parent.Parent.PlayerState)
local npc_line_of_sight = require(script.Parent.NpcLineOfSight)
local npc_spawn_controller = require(script.Parent.NpcSpawnController)
local npc_values = require(script.Parent.NpcValues)

local AIM_RANGE = 180
local AIM_STALE_TIME = 0.7
local DEFAULT_FAKE_FRIGHT_MIN = 1.25
local DEFAULT_FAKE_FRIGHT_MAX = 3.5
local COMMAND_RANGE = 180
local NPC_COMMAND_INTERVAL = constants.NPC_COMMAND_INTERVAL

local COMPLIANCE_LOCKED_STATES = {
	hands_up = true,
	kneeling = true,
	restrained = true,
	ragdolled = true,
}

local random = Random.new()
local tracked_npcs = setmetatable({}, { __mode = "k" })
local npc_states = setmetatable({}, { __mode = "k" })
local last_aim_updates = setmetatable({}, { __mode = "k" })
local last_command_updates = setmetatable({}, { __mode = "k" })

local function get_character_origin(player)
	local character = player.Character
	if not character then
		return nil, nil
	end

	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or humanoid.Health <= 0 or not root then
		return nil, nil
	end
	return character, head or root
end

function npc_threat_service.get_state_data(npc: Model)
	local state = npc_states[npc]

	if state then
		return state
	end

	state = {
		name = "idle",
		threatened_by = nil,
		threatened_at = 0,
		threatened_until = 0,
		hostile_at = 0,
		fake_fright_hostile_at = 0,
		version = 0,
	}

	npc_states[npc] = state
	return state
end

function npc_threat_service.get_state(npc: Model): string
	return npc_threat_service.get_state_data(npc).name
end

function npc_threat_service.is_stunned(npc: Model): boolean
	local state_name = npc_threat_service.get_state(npc)
	if state_name == "stunned" or state_name == "ragdolled" then
		return true
	end
	if npc_values.read_bool(npc, "stunned", false) then
		return true
	end
	local humanoid = npc:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then
		return true
	end
	local humanoid_state = humanoid:GetState()
	return humanoid.PlatformStand
		or humanoid_state == Enum.HumanoidStateType.Physics
		or humanoid_state == Enum.HumanoidStateType.Ragdoll
end

function npc_threat_service.set_state(npc: Model, state_name: string, player: Player?)
	local state = npc_threat_service.get_state_data(npc)

	if state.name == "ragdolled" and state_name ~= "ragdolled" then
		return state
	end

	if state.name == "restrained" and state_name ~= "ragdolled" then
		return state
	end

	local previous_name = state.name

	state.name = state_name
	state.threatened_by = player
	state.threatened_at = os.clock()
	state.threatened_until = state.threatened_at + AIM_STALE_TIME

	tracked_npcs[npc] = state

	return state
end

local function is_terrorist(npc)
	local npc_type = string.lower(npc_values.read_string(npc, "npc_type", ""))

	return npc_type == "terrorist" or npc_type == "default"
end

local function schedule_fake_fright_turn(npc)
	local state = npc_threat_service.get_state_data(npc)

	state.version += 1

	local version = state.version

	local min_delay = npc_values.read_number(npc, "fake_fright_min_time", DEFAULT_FAKE_FRIGHT_MIN)
	local max_delay = npc_values.read_number(npc, "fake_fright_max_time", DEFAULT_FAKE_FRIGHT_MAX)

	if max_delay < min_delay then
		max_delay = min_delay
	end

	local delay_time = random:NextNumber(min_delay, max_delay)

	state.fake_fright_hostile_at = os.clock() + delay_time

	task.delay(delay_time, function()
		local humanoid = npc:FindFirstChildWhichIsA("Humanoid")
		local latest_state = npc_states[npc]

		if not humanoid or humanoid.Health <= 0 or not npc.Parent or not latest_state then
			return
		end

		if latest_state.version ~= version or latest_state.name ~= "fake_fright" then
			return
		end

		npc_threat_service.set_state(npc, "hostile")
		latest_state.hostile_at = os.clock()
	end)
end

local function threaten_npc(player, npc)
	local state = npc_threat_service.get_state_data(npc)

	if COMPLIANCE_LOCKED_STATES[state.name] then
		return
	end

	if is_terrorist(npc) then
		if state.name ~= "fake_fright" and state.name ~= "hostile" then
			npc_threat_service.set_state(npc, "fake_fright", player)
			schedule_fake_fright_turn(npc)
		else
			npc_threat_service.set_state(npc, state.name, player)
		end
		return
	end

	if state.name ~= "hands_up" and state.name ~= "kneeling" then
		npc_threat_service.set_state(npc, "frightened", player)
	end
end

local function clear_player_threats(player)
	for npc, state in tracked_npcs do
		if npc.Parent and state.threatened_by == player then
			state.threatened_until = os.clock()
		end
	end
end

local function validate_weapon_command(ctx, player, gun_name, origin, direction)
	if type(gun_name) ~= "string" or typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return nil, nil, nil
	end

	local state = player_state.ensure_player_state(player)

	if not state.inventory[gun_name] or not player_state.is_in_loadout(state, gun_name) then
		return nil, nil, nil
	end
	if not player_character_weapon_service.is_equipped(player, gun_name) then
		return nil, nil, nil
	end

	if direction.Magnitude < constants.VALID_DIRECTION_MIN_MAGNITUDE or direction.Magnitude > constants.VALID_DIRECTION_MAX_MAGNITUDE then
		return nil, nil, nil
	end

	local character, origin_part = get_character_origin(player)

	if not character then
		return nil, nil, nil
	end

	if (origin - origin_part.Position).Magnitude > constants.MAX_REMOTE_ORIGIN_DISTANCE then
		origin = origin_part.Position
	end
	return character, origin, direction.Unit
end

local function can_update_aim(player)
	local now = os.clock()
	local last_update = last_aim_updates[player] or 0
	if now - last_update < constants.WEAPON_AIM_UPDATE_INTERVAL then
		return false
	end
	last_aim_updates[player] = now
	return true
end

local function raycast_npc(ctx, character, origin, direction, range)
	return npc_line_of_sight.first_npc_in_direction(ctx, origin, direction, range, { character })
end

local function on_weapon_aim(ctx, player, gun_name, aiming, origin, direction)
	if type(gun_name) ~= "string"
		or type(aiming) ~= "boolean"
		or not can_update_aim(player)
	then
		return
	end
	if not aiming then
		clear_player_threats(player)
		return
	end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end

	local character, safe_origin, safe_direction = validate_weapon_command(ctx, player, gun_name, origin, direction)

	if not character then
		return
	end

	local npc = raycast_npc(ctx, character, safe_origin, safe_direction, AIM_RANGE)

	if npc then
		threaten_npc(player, npc)
	end
end

local function on_npc_command(ctx, player, gun_name, origin, direction)
	local now = os.clock()
	if now - (last_command_updates[player] or 0) < NPC_COMMAND_INTERVAL then
		return
	end
	last_command_updates[player] = now
	local character, safe_origin, safe_direction = validate_weapon_command(ctx, player, gun_name, origin, direction)

	if not character then
		return
	end

	local npc = raycast_npc(ctx, character, safe_origin, safe_direction, COMMAND_RANGE)

	if not npc then
		return
	end

	local state = npc_threat_service.get_state_data(npc)

	if state.name == "ragdolled" or state.name == "restrained" then
		return
	end

	if is_terrorist(npc) then
		npc_threat_service.set_state(npc, "hostile", player)
		state.hostile_at = os.clock()
		return
	end

	if state.name == "hands_up" then
		npc_threat_service.set_state(npc, "kneeling", player)
	elseif state.name == "kneeling" then
		npc_threat_service.set_state(npc, "kneeling", player)
	else
		npc_threat_service.set_state(npc, "hands_up", player)
	end
end

local function expire_stale_threats()
	local now = os.clock()

	for npc, state in tracked_npcs do
		if not npc.Parent then
			tracked_npcs[npc] = nil
			npc_states[npc] = nil
		elseif state.name == "frightened" and state.threatened_until <= now then
			state.name = "idle"
			state.threatened_by = nil
		end
	end
end

function npc_threat_service.setup(ctx)
	local weapon_aim_remote = ctx.remote_map.WeaponAim
	weapon_aim_remote.OnServerEvent:Connect(function(player, gun_name, aiming, origin, direction)
		on_weapon_aim(ctx, player, gun_name, aiming, origin, direction)
	end)

	ctx.remotes.NpcCommand.OnServerEvent:Connect(function(player, gun_name, origin, direction)
		on_npc_command(ctx, player, gun_name, origin, direction)
	end)

	ctx.Players.PlayerRemoving:Connect(function(player)
		last_aim_updates[player] = nil
		last_command_updates[player] = nil
	end)

	task.spawn(function()
		while true do
			expire_stale_threats()
			task.wait(0.2)
		end
	end)
end

return npc_threat_service

