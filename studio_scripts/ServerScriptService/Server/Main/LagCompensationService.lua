-- Server-side historical collision service for latency-compensated hitscan.
-- It records bounded root snapshots in a preallocated ring and caches character parts only
-- when descendants change; firing never walks every character descendant at 30 Hz.
--
-- Rewind is intentionally capped by LAG_COMPENSATION_HISTORY_SECONDS. Requests outside that
-- trust window are clamped, and interpolation reconstructs transient hitboxes without moving
-- live characters or transferring network ownership.

local RunService = game:GetService("RunService")

local constants = require(script.Parent.ServerConstants)

local lag_compensation_service = {}

type CharacterSample = {
	entity: Instance,
	character: Model,
	humanoid: Humanoid,
	root_cframe: CFrame,
}

type HistorySlot = {
	time: number,
	characters: { CharacterSample },
	character_lookup: { [Model]: CharacterSample },
	character_count: number,
}

type TrackedCharacter = {
	humanoid: Humanoid,
	character: Model,
	root: BasePart?,
	parts: { BasePart },
	part_count: number,
	dirty: boolean,
	child_added: RBXScriptConnection,
	child_removed: RBXScriptConnection,
	ancestry_changed: RBXScriptConnection,
}

export type Snapshot = {
	time: number,
	before: HistorySlot,
	after: HistorySlot,
	alpha: number,
	projectile_elapsed: number?,
	view_delay: number?,
}

local history_capacity = math.max(
	4,
	math.ceil(constants.LAG_COMPENSATION_HISTORY_SECONDS / constants.LAG_COMPENSATION_SAMPLE_INTERVAL) + 3
)
local history: { HistorySlot } = table.create(history_capacity)
local history_count = 0
local history_write_index = 0
local tracked_humanoids: { [Humanoid]: TrackedCharacter } = {}
local sampled_characters: { [Model]: boolean } = {}
local accumulator = 0

local function refresh_tracked_parts(tracked: TrackedCharacter)
	if not tracked.dirty then
		return
	end

	local part_count = 0
	local fallback_root = nil
	for _, child in tracked.character:GetChildren() do
		if child:IsA("BasePart") then
			fallback_root = fallback_root or child
			if child.Transparency < 1 and child.CanQuery then
				part_count += 1
				tracked.parts[part_count] = child
			end
		end
	end
	for index = part_count + 1, tracked.part_count do
		tracked.parts[index] = nil
	end
	local humanoid_root = tracked.character:FindFirstChild("HumanoidRootPart")
	tracked.root = humanoid_root and humanoid_root:IsA("BasePart") and humanoid_root or tracked.character.PrimaryPart or fallback_root
	tracked.part_count = part_count
	tracked.dirty = false
end

local function untrack_humanoid(humanoid: Humanoid)
	local tracked = tracked_humanoids[humanoid]
	if not tracked then
		return
	end
	tracked_humanoids[humanoid] = nil
	tracked.child_added:Disconnect()
	tracked.child_removed:Disconnect()
	tracked.ancestry_changed:Disconnect()
end

local function track_humanoid(humanoid: Humanoid): TrackedCharacter?
	local existing = tracked_humanoids[humanoid]
	if existing then
		return existing
	end
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return nil
	end

	local tracked = {
		humanoid = humanoid,
		character = character,
		root = nil,
		parts = {},
		part_count = 0,
		dirty = true,
		child_added = nil,
		child_removed = nil,
		ancestry_changed = nil,
	}
	tracked_humanoids[humanoid] = tracked
	tracked.child_added = character.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then
			tracked.dirty = true
		end
	end)
	tracked.child_removed = character.ChildRemoved:Connect(function(child)
		if child:IsA("BasePart") then
			tracked.dirty = true
		end
	end)
	tracked.ancestry_changed = humanoid.AncestryChanged:Connect(function(_, parent)
		if not parent then
			untrack_humanoid(humanoid)
		end
	end)
	return tracked
end

local function get_or_create_slot(slot_index: number): HistorySlot
	local slot = history[slot_index]
	if slot then
		return slot
	end
	slot = {
		time = 0,
		characters = {},
		character_lookup = {},
		character_count = 0,
	}
	history[slot_index] = slot
	return slot
end

local function write_character_sample(slot: HistorySlot, entity: Instance, tracked: TrackedCharacter)
	if tracked.humanoid.Health <= 0 or not tracked.character.Parent then
		return
	end
	refresh_tracked_parts(tracked)
	local root = tracked.root
	if not root or not root.Parent or tracked.part_count <= 0 then
		return
	end

	local next_index = slot.character_count + 1
	local character_sample = slot.characters[next_index]
	if not character_sample then
		character_sample = {
			entity = entity,
			character = tracked.character,
			humanoid = tracked.humanoid,
			root_cframe = root.CFrame,
		}
		slot.characters[next_index] = character_sample
	end

	character_sample.entity = entity
	character_sample.character = tracked.character
	character_sample.humanoid = tracked.humanoid
	character_sample.root_cframe = root.CFrame
	slot.character_count = next_index
	slot.character_lookup[tracked.character] = character_sample
end

local function add_character_sample(slot: HistorySlot, entity: Instance, character: Model)
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then
		return
	end
	local tracked = track_humanoid(humanoid)
	if tracked then
		write_character_sample(slot, entity, tracked)
	end
end

local function take_sample(players: Players)
	history_write_index = history_write_index % history_capacity + 1
	history_count = math.min(history_count + 1, history_capacity)

	local slot = get_or_create_slot(history_write_index)
	slot.time = workspace:GetServerTimeNow()
	slot.character_count = 0
	table.clear(slot.character_lookup)
	table.clear(sampled_characters)

	for _, player in players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		sampled_characters[character] = true
		add_character_sample(slot, player, character)
	end

	for humanoid, tracked in tracked_humanoids do
		local character = tracked.character
		if humanoid.Health <= 0 or not character.Parent or sampled_characters[character] then
			continue
		end
		sampled_characters[character] = true
		write_character_sample(slot, character, tracked)
	end
end

local function clamp_target_time(target_time)
	local now = workspace:GetServerTimeNow()
	if type(target_time) ~= "number" then
		return now
	end
	if target_time > now + constants.LAG_COMPENSATION_FUTURE_GRACE then
		return now
	end
	return math.clamp(target_time, now - constants.LAG_COMPENSATION_HISTORY_SECONDS, now)
end

local function get_history_slot(logical_index: number): HistorySlot
	local oldest_index = (history_write_index - history_count) % history_capacity + 1
	local physical_index = (oldest_index + logical_index - 2) % history_capacity + 1
	return history[physical_index]
end

local function find_samples_at(target_time): (HistorySlot?, HistorySlot?)
	if history_count <= 0 then
		return nil, nil
	end

	local oldest = get_history_slot(1)
	local newest = get_history_slot(history_count)
	if target_time <= oldest.time then
		return oldest, oldest
	end
	if target_time >= newest.time then
		return newest, newest
	end

	local low = 1
	local high = history_count
	while low <= high do
		local middle = math.floor((low + high) * 0.5)
		if get_history_slot(middle).time <= target_time then
			low = middle + 1
		else
			high = middle - 1
		end
	end
	return get_history_slot(math.max(low - 1, 1)), get_history_slot(math.min(low, history_count))
end

local function get_axis_distance(origin_axis, direction_axis, half_axis, min_time, max_time)
	if math.abs(direction_axis) < 1e-6 then
		if origin_axis < -half_axis or origin_axis > half_axis then
			return nil
		end
		return min_time, max_time
	end
	local near_time = (-half_axis - origin_axis) / direction_axis
	local far_time = (half_axis - origin_axis) / direction_axis
	if near_time > far_time then
		near_time, far_time = far_time, near_time
	end
	min_time = math.max(min_time, near_time)
	max_time = math.min(max_time, far_time)
	if min_time > max_time then
		return nil
	end
	return min_time, max_time
end

local function ray_box_distance(origin: Vector3, direction: Vector3, cframe: CFrame, size: Vector3, padding: number): number?
	local local_origin = cframe:PointToObjectSpace(origin)
	local local_direction = cframe:VectorToObjectSpace(direction)
	local min_time = -math.huge
	local max_time = math.huge
	local half_size = size * 0.5 + Vector3.new(padding, padding, padding)

	local next_min_time, next_max_time = get_axis_distance(
		local_origin.X,
		local_direction.X,
		half_size.X,
		min_time,
		max_time
	)
	if not next_min_time then
		return nil
	end
	min_time = next_min_time
	max_time = next_max_time

	next_min_time, next_max_time = get_axis_distance(
		local_origin.Y,
		local_direction.Y,
		half_size.Y,
		min_time,
		max_time
	)
	if not next_min_time then
		return nil
	end
	min_time = next_min_time
	max_time = next_max_time

	next_min_time, next_max_time = get_axis_distance(
		local_origin.Z,
		local_direction.Z,
		half_size.Z,
		min_time,
		max_time
	)
	if not next_min_time then
		return nil
	end
	min_time = next_min_time
	max_time = next_max_time

	if max_time < 0 then
		return nil
	end
	return math.max(min_time, 0)
end

local function test_character(
	before_character: CharacterSample?,
	after_character: CharacterSample?,
	alpha: number,
	shooter: Instance,
	segment_origin: Vector3,
	direction: Vector3,
	length: number,
	padding: number,
	best_distance: number,
	best_part: BasePart?
): (number, BasePart?)
	local character_sample = before_character or after_character
	if not character_sample or character_sample.entity == shooter then
		return best_distance, best_part
	end

	local tracked = tracked_humanoids[character_sample.humanoid]
	if not tracked then
		return best_distance, best_part
	end
	refresh_tracked_parts(tracked)
	local current_root = tracked.root
	if not current_root or not current_root.Parent then
		return best_distance, best_part
	end

	local rewound_root_cframe = character_sample.root_cframe
	if before_character and after_character then
		rewound_root_cframe = before_character.root_cframe:Lerp(after_character.root_cframe, alpha)
	end
	local root_delta = rewound_root_cframe * current_root.CFrame:Inverse()
	for index = 1, tracked.part_count do
		local part = tracked.parts[index]
		if part.Parent ~= tracked.character or part.Transparency >= 1 or not part.CanQuery then
			continue
		end
		local rewound_cframe = root_delta * part.CFrame
		local distance = ray_box_distance(segment_origin, direction, rewound_cframe, part.Size, padding)
		if distance and distance <= length and distance < best_distance then
			best_distance = distance
			best_part = part
		end
	end
	return best_distance, best_part
end

local function find_segment_hit(
	snapshot: Snapshot,
	shooter: Instance,
	segment_origin: Vector3,
	segment: Vector3,
	hitbox_padding: number?
)
	local length = segment.Magnitude
	if length <= 0 then
		return nil
	end

	local before = snapshot.before
	local after = snapshot.after
	local direction = segment.Unit
	local padding = math.max(hitbox_padding or constants.LAG_COMPENSATION_HITBOX_PADDING, 0)
	local best_distance = math.huge
	local best_part = nil

	for index = 1, before.character_count do
		local before_character = before.characters[index]
		local after_character = after.character_lookup[before_character.character]
		best_distance, best_part = test_character(
			before_character,
			after_character,
			snapshot.alpha,
			shooter,
			segment_origin,
			direction,
			length,
			padding,
			best_distance,
			best_part
		)
	end

	for index = 1, after.character_count do
		local after_character = after.characters[index]
		if before.character_lookup[after_character.character] then
			continue
		end
		best_distance, best_part = test_character(
			nil,
			after_character,
			snapshot.alpha,
			shooter,
			segment_origin,
			direction,
			length,
			padding,
			best_distance,
			best_part
		)
	end

	if not best_part then
		return nil
	end
	return {
		distance = best_distance,
		part = best_part,
		position = segment_origin + direction * best_distance,
	}
end

function lag_compensation_service.get_snapshot(fire_time): Snapshot?
	local target_time = clamp_target_time(fire_time)
	local before, after = find_samples_at(target_time)
	if not before or not after then
		return nil
	end
	local alpha = 0
	if after.time > before.time then
		alpha = math.clamp((target_time - before.time) / (after.time - before.time), 0, 1)
	end
	return {
		time = target_time,
		before = before,
		after = after,
		alpha = alpha,
	}
end

function lag_compensation_service.get_shooter_view_delay(player): number
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return 0
	end
	local ping = 0
	local ok, result = pcall(function()
		return player:GetNetworkPing()
	end)
	if ok and type(result) == "number" then
		ping = result
	end
	local view_delay = ping + constants.LAG_COMPENSATION_VIEW_INTERPOLATION_SECONDS
	return math.clamp(view_delay, 0, constants.LAG_COMPENSATION_MAX_VIEW_DELAY_SECONDS)
end

function lag_compensation_service.get_projectile_snapshot(fire_time, projectile_elapsed, view_delay)
	if type(fire_time) ~= "number" then
		return lag_compensation_service.get_snapshot(nil)
	end
	local target_time = fire_time + math.max(projectile_elapsed or 0, 0) - math.max(view_delay or 0, 0)
	local now = workspace:GetServerTimeNow()
	if target_time > now + constants.LAG_COMPENSATION_FUTURE_GRACE then
		return nil
	end
	if target_time < now - constants.LAG_COMPENSATION_HISTORY_SECONDS then
		return nil
	end
	local snapshot = lag_compensation_service.get_snapshot(target_time)
	if snapshot then
		snapshot.projectile_elapsed = math.max(projectile_elapsed or 0, 0)
		snapshot.view_delay = math.max(view_delay or 0, 0)
	end
	return snapshot
end

function lag_compensation_service.find_segment_hit(snapshot, shooter, segment_origin, segment, hitbox_padding)
	if not snapshot then
		return nil
	end
	return find_segment_hit(snapshot, shooter, segment_origin, segment, hitbox_padding)
end

local function track_existing_humanoids()
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("Humanoid") then
			track_humanoid(descendant)
		end
	end
end

function lag_compensation_service.setup(ctx)
	local players: Players = ctx.Players
	track_existing_humanoids()
	workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Humanoid") then
			track_humanoid(descendant)
		end
	end)
	RunService.Heartbeat:Connect(function(delta_time)
		accumulator += delta_time
		if accumulator < constants.LAG_COMPENSATION_SAMPLE_INTERVAL then
			return
		end
		accumulator %= constants.LAG_COMPENSATION_SAMPLE_INTERVAL
		take_sample(players)
	end)
	take_sample(players)
end

return lag_compensation_service

