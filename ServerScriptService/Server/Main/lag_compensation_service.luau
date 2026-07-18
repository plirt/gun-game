local RunService = game:GetService("RunService")

local constants = require(script.Parent.server_constants)

local lag_compensation_service = {}

local history = {}
local history_start = 1
local snapshot_cache = {}
local tracked_humanoids = {}
local tracked_connections = {}
local accumulator = 0

local function sample_character(character)
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local parts = {}
	-- Character hitboxes are direct body parts; accessories, held weapons, and nested effects are not valid rewind targets.
	for _, descendant in character:GetChildren() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 and descendant.CanQuery then
			table.insert(parts, {
				part = descendant,
				cframe = descendant.CFrame,
				size = descendant.Size,
			})
		end
	end
	if #parts <= 0 then
		return nil
	end
	return {
		character = character,
		humanoid = humanoid,
		parts = parts,
	}
end

local function add_character_sample(characters, entity, character)
	local sample = sample_character(character)
	if not sample then
		return
	end
	sample.entity = entity or character
	table.insert(characters, sample)
end

local function take_sample(ctx)
	local characters = {}
	local character_lookup = {}
	local sampled_characters = {}
	for _, player in ctx.Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		sampled_characters[character] = true
		add_character_sample(characters, player, character)
	end
	for humanoid in tracked_humanoids do
		local character = humanoid.Parent
		if humanoid.Health <= 0 or not character or not character:IsA("Model") or sampled_characters[character] then
			continue
		end
		sampled_characters[character] = true
		add_character_sample(characters, character, character)
	end
	for _, character_sample in characters do
		character_lookup[character_sample.character] = character_sample
	end
	table.insert(history, {
		time = workspace:GetServerTimeNow(),
		characters = characters,
		character_lookup = character_lookup,
	})
	table.clear(snapshot_cache)
	local cutoff = workspace:GetServerTimeNow() - constants.LAG_COMPENSATION_HISTORY_SECONDS
	while history[history_start] and history[history_start].time < cutoff do
		history[history_start] = nil
		history_start += 1
	end
	if history_start > 64 then
		local next_history = {}
		for index = history_start, #history do
			table.insert(next_history, history[index])
		end
		history = next_history
		history_start = 1
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

local function find_samples_at(target_time)
	local before = nil
	local after = nil
	for index = history_start, #history do
		local sample = history[index]
		if sample.time <= target_time then
			before = sample
		elseif sample.time > target_time then
			after = sample
			break
		end
	end
	return before or after, after or before
end

local function interpolate_parts(before_character, after_character, alpha)
	if not before_character then
		return after_character and after_character.parts or nil
	end
	if not after_character then
		return before_character.parts
	end
	local after_parts = {}
	for _, part_sample in after_character.parts do
		after_parts[part_sample.part] = part_sample
	end
	local parts = {}
	for _, before_part in before_character.parts do
		local after_part = after_parts[before_part.part]
		if not after_part then
			table.insert(parts, before_part)
			continue
		end
		table.insert(parts, {
			part = before_part.part,
			cframe = before_part.cframe:Lerp(after_part.cframe, alpha),
			size = before_part.size:Lerp(after_part.size, alpha),
		})
	end
	return parts
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

local function ray_box_distance(origin, direction, cframe, size, padding)
	local local_origin = cframe:PointToObjectSpace(origin)
	local local_direction = cframe:VectorToObjectSpace(direction)
	local min_time = -math.huge
	local max_time = math.huge
	local half_size = size * 0.5 + Vector3.new(padding, padding, padding)
	for _, axis in {
		{ local_origin.X, local_direction.X, half_size.X },
		{ local_origin.Y, local_direction.Y, half_size.Y },
		{ local_origin.Z, local_direction.Z, half_size.Z },
	} do
		local next_min_time, next_max_time = get_axis_distance(axis[1], axis[2], axis[3], min_time, max_time)
		if not next_min_time then
			return nil
		end
		min_time = next_min_time
		max_time = next_max_time
	end
	if max_time < 0 then
		return nil
	end
	return math.max(min_time, 0)
end

local function get_part_hit(segment_origin, direction, length, part_sample, padding)
	if not part_sample.part.Parent then
		return nil
	end
	local distance = ray_box_distance(segment_origin, direction, part_sample.cframe, part_sample.size, padding)
	if not distance or distance > length then
		return nil
	end
	return {
		distance = distance,
		part = part_sample.part,
		position = segment_origin + direction * distance,
	}
end

local function get_closest_hit(best_hit, hit)
	if not hit then
		return best_hit
	end
	if best_hit and best_hit.distance <= hit.distance then
		return best_hit
	end
	return hit
end

local function get_sample_lookup(sample)
	return sample and sample.character_lookup or {}
end

local function add_snapshot_character(snapshot_characters, character, before_lookup, after_lookup, alpha)
	local before_character = before_lookup[character]
	local after_character = after_lookup[character]
	local entity = before_character and before_character.entity or after_character and after_character.entity
	local parts = interpolate_parts(before_character, after_character, alpha)
	if not entity or not parts then
		return
	end
	table.insert(snapshot_characters, {
		entity = entity,
		parts = parts,
	})
end

local function build_snapshot_characters(before, after, alpha)
	local characters = {}
	local before_lookup = get_sample_lookup(before)
	local after_lookup = get_sample_lookup(after)
	for character in before_lookup do
		add_snapshot_character(characters, character, before_lookup, after_lookup, alpha)
	end
	for character in after_lookup do
		if before_lookup[character] then
			continue
		end
		add_snapshot_character(characters, character, before_lookup, after_lookup, alpha)
	end
	return characters
end

local function get_snapshot_key(target_time, before, after, alpha)
	local before_time = before and before.time or 0
	local after_time = after and after.time or 0
	return `{math.floor(target_time * 1000)}:{before_time}:{after_time}:{math.floor(alpha * 1000)}`
end

local function copy_snapshot(snapshot)
	return {
		time = snapshot.time,
		before = snapshot.before,
		after = snapshot.after,
		alpha = snapshot.alpha,
		characters = snapshot.characters,
	}
end

local function find_segment_hit(snapshot, shooter, segment_origin, segment, hitbox_padding)
	local length = segment.Magnitude
	if length <= 0 then
		return nil
	end
	local direction = segment.Unit
	local best_hit = nil
	local padding = math.max(hitbox_padding or constants.LAG_COMPENSATION_HITBOX_PADDING, 0)
	for _, character_sample in snapshot.characters do
		if character_sample.entity == shooter then
			continue
		end
		for _, part_sample in character_sample.parts do
			best_hit = get_closest_hit(best_hit, get_part_hit(segment_origin, direction, length, part_sample, padding))
		end
	end
	return best_hit
end

function lag_compensation_service.get_snapshot(fire_time)
	local target_time = clamp_target_time(fire_time)
	local before, after = find_samples_at(target_time)
	if not before and not after then
		return nil
	end
	local alpha = 0
	if before and after and after.time > before.time then
		alpha = math.clamp((target_time - before.time) / (after.time - before.time), 0, 1)
	end
	local cache_key = get_snapshot_key(target_time, before, after, alpha)
	local cached_snapshot = snapshot_cache[cache_key]
	if cached_snapshot then
		return copy_snapshot(cached_snapshot)
	end
	local snapshot = {
		time = target_time,
		before = before,
		after = after,
		alpha = alpha,
		characters = build_snapshot_characters(before, after, alpha),
	}
	snapshot_cache[cache_key] = snapshot
	return copy_snapshot(snapshot)
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

local function track_humanoid(humanoid)
	if tracked_humanoids[humanoid] or not humanoid.Parent or not humanoid.Parent:IsA("Model") then
		return
	end
	tracked_humanoids[humanoid] = true
	tracked_connections[humanoid] = humanoid.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end
		tracked_humanoids[humanoid] = nil
		local connection = tracked_connections[humanoid]
		tracked_connections[humanoid] = nil
		if connection then
			connection:Disconnect()
		end
	end)
end

local function track_existing_humanoids()
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("Humanoid") then
			track_humanoid(descendant)
		end
	end
end

function lag_compensation_service.setup(ctx)
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
		accumulator = 0
		take_sample(ctx)
	end)
	take_sample(ctx)
end

return lag_compensation_service
