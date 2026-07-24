local mission_service = {}

local constants = require(script.Parent.ServerConstants)
local RemoteRateLimiter = require(script.Parent.RemoteRateLimiter)
local npc_folder = script.Parent.Npc
local npc_threat_service = require(npc_folder.NpcThreatService)
local npc_values = require(npc_folder.NpcValues)
local pseudo_spawn_service = require(script.Parent.PseudoSpawnService)

local active_mission = nil
local mission_status = nil
local mission_start_limiter = RemoteRateLimiter.new(
	constants.MISSION_START_REMOTE_RATE,
	constants.MISSION_START_REMOTE_BURST
)

local function get_npcs_folder()
	local npcs = workspace:FindFirstChild("Npcs")

	if npcs then
		return npcs
	end

	npcs = Instance.new("Folder")
	npcs.Name = "Npcs"
	npcs.Parent = workspace

	return npcs
end

local function is_mission_npc(npc, map_id)
	return npc:IsA("Model")
		and npc_values.read_bool(npc, "managed_npc", false) == true
		and npc_values.read_string(npc, "map_id", "") == map_id
end

local function get_npc_type(npc)
	return string.lower(npc_values.read_string(npc, "npc_type", "civilian"))
end

local function is_enemy_npc(npc)
	local npc_type = get_npc_type(npc)

	return npc_type == "terrorist" or npc_type == "default"
end

local function is_dead(npc)
	local humanoid = npc:FindFirstChildWhichIsA("Humanoid")

	return not humanoid or humanoid.Health <= 0
end

local function is_restrained(_, npc)
	return npc_threat_service.get_state(npc) == "restrained"
end

local function scan(ctx, mission)
	local npcs = get_npcs_folder()
	local status = {
		map_id = mission.map_id,
		complete = false,
		npcs_total = 0,
		civilians_total = 0,
		civilians_restrained = 0,
		terrorists_total = 0,
		terrorists_killed = 0,
	}

	for _, npc in npcs:GetChildren() do
		if is_mission_npc(npc, mission.map_id) then
			status.npcs_total += 1

			if is_enemy_npc(npc) then
				status.terrorists_total += 1

				if is_dead(npc) then
					status.terrorists_killed += 1
				end
			else
				status.civilians_total += 1

				if is_restrained(ctx, npc) then
					status.civilians_restrained += 1
				end
			end
		end
	end

	status.complete = status.npcs_total > 0
		and status.civilians_restrained == status.civilians_total
		and status.terrorists_killed == status.terrorists_total

	return status
end

local function set_status(status)
	mission_status = status
end

local function broadcast(ctx, state, status)
	ctx.remotes.MissionUpdate:FireAllClients(state, status or mission_status or {})
end

local function check_completion(ctx)
	while true do
		task.wait(constants.MISSION_CHECK_INTERVAL)

		local mission = active_mission

		if mission and not mission.complete then
			local status = scan(ctx, mission)

			set_status(status)

			if status.complete then
				mission.complete = true
				broadcast(ctx, "completed", status)
			end
		end
	end
end

function mission_service.start(ctx, map_id, player)
	local teleported = false

	if player then
		teleported = pseudo_spawn_service.teleport_player(player)
		if teleported then
			ctx.runtime:get("PlayerMovementService").resync_player(player)
		end
	end

	local resolved_map_id = type(map_id) == "string" and map_id ~= "" and map_id or constants.DEFAULT_MAP_ID
	-- active_mission is the worker's source of truth; previously only mission_status was
	-- assigned, leaving the completion loop permanently inert.
	active_mission = {
		map_id = resolved_map_id,
		complete = false,
		started_at = os.clock(),
		started_by = player,
	}
	mission_status = {
		map_id = resolved_map_id,
		complete = false,
		pvp = true,
		teleported = teleported,
	}

	return mission_status
end

function mission_service.get_status(ctx)
	if active_mission then
		set_status(scan(ctx, active_mission))
	end

	return mission_status
end

function mission_service.setup(ctx)
	ctx.remotes.MissionStart.OnServerInvoke = function(player, map_id)
		if not RemoteRateLimiter.allow(mission_start_limiter, player) then
			return mission_status
		end
		return mission_service.start(ctx, map_id, player)
	end

	task.spawn(check_completion, ctx)
end

return mission_service
