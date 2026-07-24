local replay_event_archive = {}
replay_event_archive.__index = replay_event_archive

local INCLUDED_TYPES = {
	weapon_activated = true,
	throwable_activated = true,
	throwable_created = true,
	throwable_detonated = true,
	damage_applied = true,
}

function replay_event_archive.new(event_stream, history_seconds, max_events)
	return setmetatable({
		event_stream = event_stream,
		history_seconds = history_seconds,
		max_events = max_events,
	}, replay_event_archive)
end

local function get_actor_fields(actor)
	if typeof(actor) ~= "Instance" then
		return nil, nil
	end
	if actor:IsA("Player") then
		return actor.UserId, actor.DisplayName
	end
	return nil, actor.Name
end

function replay_event_archive:serialize(lethal_time)
	local events = self.event_stream:get_since(lethal_time - self.history_seconds, function(event)
		return INCLUDED_TYPES[event.type] == true
	end)
	local first_index = math.max(#events - self.max_events + 1, 1)
	local serialized = {}
	for index = first_index, #events do
		local event = events[index]
		local actor_user_id, actor_name = get_actor_fields(event.actor)
		local payload = {
			type = event.type,
			sequence = event.sequence,
			offset = event.time - lethal_time,
			actor_user_id = actor_user_id,
			actor_name = actor_name,
			item_id = event.item_id,
			origin = event.origin,
			position = event.position,
			direction = event.direction,
			directions = event.directions,
			muzzle_velocity = event.muzzle_velocity,
			max_distance = event.max_distance,
			damage = event.damage,
			health_before = event.health_before,
			health_after = event.health_after,
		}
		table.insert(serialized, payload)
	end
	return serialized
end

return replay_event_archive

