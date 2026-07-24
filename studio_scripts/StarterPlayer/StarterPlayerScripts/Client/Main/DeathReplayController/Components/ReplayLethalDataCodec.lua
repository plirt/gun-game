local replay_lethal_data_codec = {}

local VALID_EVENT_TYPES = {
	weapon_activated = true,
	throwable_activated = true,
	throwable_created = true,
	throwable_detonated = true,
	damage_applied = true,
}

local function sanitize_camera_samples(payload, max_samples)
	local camera_samples = {}
	if type(payload) ~= "table" then
		return camera_samples
	end
	for index = 1, math.min(#payload, max_samples) do
		local sample = payload[index]
		if type(sample) == "table"
			and type(sample.offset) == "number"
			and typeof(sample.camera_cframe) == "CFrame"
			and type(sample.field_of_view) == "number"
		then
			table.insert(camera_samples, {
				offset = sample.offset,
				camera_cframe = sample.camera_cframe,
				field_of_view = math.clamp(sample.field_of_view, 30, 100),
				viewmodel_offset = typeof(sample.viewmodel_offset) == "CFrame" and sample.viewmodel_offset or nil,
			})
		end
	end
	table.sort(camera_samples, function(first, second)
		return first.offset < second.offset
	end)
	return camera_samples
end

local function sanitize_combat_events(payload, max_events)
	local combat_events = {}
	if type(payload) ~= "table" then
		return combat_events
	end
	for index = 1, math.min(#payload, max_events) do
		local event = payload[index]
		if type(event) == "table"
			and VALID_EVENT_TYPES[event.type]
			and type(event.offset) == "number"
		then
			local directions = nil
			if type(event.directions) == "table" then
				directions = {}
				for direction_index = 1, math.min(#event.directions, 16) do
					local direction = event.directions[direction_index]
					if typeof(direction) == "Vector3" and direction.Magnitude > 0 then
						table.insert(directions, direction.Unit)
					end
				end
			end
			table.insert(combat_events, {
				type = event.type,
				sequence = type(event.sequence) == "number" and event.sequence or index,
				offset = event.offset,
				actor_user_id = type(event.actor_user_id) == "number" and event.actor_user_id or nil,
				actor_name = type(event.actor_name) == "string" and event.actor_name or nil,
				item_id = type(event.item_id) == "string" and event.item_id or nil,
				origin = typeof(event.origin) == "Vector3" and event.origin or nil,
				position = typeof(event.position) == "Vector3" and event.position or nil,
				direction = typeof(event.direction) == "Vector3" and event.direction or nil,
				directions = directions,
				muzzle_velocity = type(event.muzzle_velocity) == "number" and event.muzzle_velocity or nil,
				max_distance = type(event.max_distance) == "number" and event.max_distance or nil,
				damage = type(event.damage) == "number" and event.damage or nil,
			})
		end
	end
	table.sort(combat_events, function(first, second)
		if first.offset == second.offset then
			return first.sequence < second.sequence
		end
		return first.offset < second.offset
	end)
	return combat_events
end

function replay_lethal_data_codec.sanitize(payload, max_camera_samples, max_combat_events)
	if type(payload) ~= "table"
		or typeof(payload.origin) ~= "Vector3"
		or typeof(payload.hit_position) ~= "Vector3"
		or typeof(payload.direction) ~= "Vector3"
		or payload.direction.Magnitude <= 0
	then
		return nil
	end
	return {
		received_at = os.clock(),
		lethal_time = type(payload.lethal_time) == "number" and payload.lethal_time or nil,
		killer_user_id = type(payload.killer_user_id) == "number" and payload.killer_user_id or nil,
		killer_name = type(payload.killer_name) == "string" and payload.killer_name or "UNKNOWN",
		gun_name = type(payload.gun_name) == "string" and payload.gun_name or nil,
		origin = payload.origin,
		hit_position = payload.hit_position,
		direction = payload.direction.Unit,
		camera_samples = sanitize_camera_samples(payload.camera_samples, max_camera_samples),
		combat_events = sanitize_combat_events(payload.combat_events, max_combat_events),
	}
end

return replay_lethal_data_codec

