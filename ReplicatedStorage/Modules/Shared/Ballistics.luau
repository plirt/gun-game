local Ballistics = {}

function Ballistics.position_at_time(origin, initial_velocity, acceleration, time)
	return origin + initial_velocity * time + 0.5 * acceleration * time * time
end

function Ballistics.velocity_at_time(initial_velocity, acceleration, time)
	return initial_velocity + acceleration * time
end

function Ballistics.cast(origin, direction, config, raycast_params, on_step)
	local initial_velocity = direction.Unit * config.muzzle_velocity
	local acceleration = config.gravity
	local previous_position = origin
	local traveled = 0
	local elapsed = 0
	local max_distance = config.max_distance
	local step_time = config.step_time or 1 / 120
	local max_flight_time = max_distance / math.max(config.muzzle_velocity, 1) + 2
	local max_steps = math.ceil(max_flight_time / step_time)

	for _ = 1, max_steps do
		elapsed += step_time
		local position = Ballistics.position_at_time(origin, initial_velocity, acceleration, elapsed)
		local segment = position - previous_position
		local segment_length = segment.Magnitude

		if segment_length <= 0 then
			previous_position = position
			continue
		end

		local result = workspace:Raycast(previous_position, segment, raycast_params)
		if on_step then
			on_step(previous_position, result and result.Position or position)
		end

		traveled += segment_length

		if result then
			local segment_hit_distance = (result.Position - previous_position).Magnitude
			local hit_alpha = math.clamp(segment_hit_distance / segment_length, 0, 1)
			local hit_time = elapsed - step_time + step_time * hit_alpha
			return {
				hit = result,
				distance = traveled - segment_length + segment_hit_distance,
				position = result.Position,
				time = hit_time,
				velocity = Ballistics.velocity_at_time(initial_velocity, acceleration, hit_time),
			}
		end

		if traveled >= max_distance then
			break
		end

		previous_position = position
	end
	return {
		hit = nil,
		distance = traveled,
		position = previous_position,
		time = elapsed,
		velocity = Ballistics.velocity_at_time(initial_velocity, acceleration, elapsed),
	}
end
return Ballistics
