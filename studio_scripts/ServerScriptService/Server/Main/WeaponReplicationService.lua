local weapon_replication_service = {}

local MAX_REPLICATION_DISTANCE = 180
local MAX_REPLICATION_DISTANCE_SQUARED = MAX_REPLICATION_DISTANCE * MAX_REPLICATION_DISTANCE
local MAX_VISUAL_DIRECTIONS = 2
local MAX_SHOTS_PER_BATCH = 10
local MAX_PENDING_SHOTS_PER_PLAYER = 16
local REPLICATION_FLUSH_INTERVAL = 1 / 20

export type Dependencies = {
	Players: Players,
	weapon_replicate_remote: UnreliableRemoteEvent,
}

local pending_states = setmetatable({}, { __mode = "k" })

local function get_player_root(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function get_visual_directions(directions: { Vector3 }, limit: number): { Vector3 }
	local visual_directions = {}
	for index = 1, math.min(#directions, limit) do
		table.insert(visual_directions, directions[index])
	end
	return visual_directions
end

local function flush(dependencies, state)
	state.scheduled = false
	local remote = dependencies.weapon_replicate_remote
	for player, shots in state.by_player do
		state.by_player[player] = nil
		if player.Parent and #shots > 0 then
			local first_index = math.max(#shots - MAX_SHOTS_PER_BATCH + 1, 1)
			local batch = {}
			for shot_index = first_index, #shots do
				table.insert(batch, shots[shot_index])
			end
			remote:FireClient(player, batch)
		end
	end
end

local function get_state(dependencies)
	local state = pending_states[dependencies]
	if state then
		return state
	end
	state = {
		by_player = setmetatable({}, { __mode = "k" }),
		scheduled = false,
	}
	pending_states[dependencies] = state
	return state
end

function weapon_replication_service.queue_fire(
	dependencies: Dependencies,
	shooter: Instance,
	gun_name: string,
	origin: Vector3,
	directions: { Vector3 },
	play_sound: boolean?
)
	if #directions == 0 then
		return
	end
	local state = get_state(dependencies)
	local direction_limit = shooter:IsA("Player") and MAX_VISUAL_DIRECTIONS or 1
	local visual_directions = get_visual_directions(directions, direction_limit)
	local queued_for_recipient = false
	for _, player in dependencies.Players:GetPlayers() do
		if player ~= shooter then
			local root = get_player_root(player)
			local offset = root and root.Position - origin
			if offset and offset:Dot(offset) <= MAX_REPLICATION_DISTANCE_SQUARED then
				local shots = state.by_player[player]
				if not shots then
					shots = {}
					state.by_player[player] = shots
				end
				if #shots >= MAX_PENDING_SHOTS_PER_PLAYER then
					table.remove(shots, 1)
				end
				table.insert(shots, { shooter, gun_name, visual_directions, play_sound ~= false })
				queued_for_recipient = true
			end
		end
	end
	if queued_for_recipient and not state.scheduled then
		state.scheduled = true
		task.delay(REPLICATION_FLUSH_INTERVAL, flush, dependencies, state)
	end
end

function weapon_replication_service.replicate_fire(
	dependencies: Dependencies,
	player: Player,
	gun_name: string,
	origin: Vector3,
	directions: { Vector3 }
)
	weapon_replication_service.queue_fire(dependencies, player, gun_name, origin, directions, true)
end

return weapon_replication_service

