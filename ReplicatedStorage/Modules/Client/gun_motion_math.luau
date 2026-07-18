local gun_motion_math = {}

local max_spring_delta_time = 1 / 20
local base_spring_step_rate = 120
local minimum_spring_steps_per_cycle = 16

function gun_motion_math.get_camera_delta(last_camera_cframe, camera_cframe)
	local object_space = last_camera_cframe:ToObjectSpace(camera_cframe)
	local x, y = object_space:ToOrientation()
	return Vector2.new(x, y)
end

function gun_motion_math.smoothstep(value)
	value = math.clamp(value, 0, 1)
	return value * value * (3 - 2 * value)
end

function gun_motion_math.smootherstep(value)
	value = math.clamp(value, 0, 1)
	return value * value * value * (value * (value * 6 - 15) + 10)
end

function gun_motion_math.clamp_vector(vector, max_magnitude)
	if vector.Magnitude <= max_magnitude then
		return vector
	end
	return vector.Unit * max_magnitude
end

function gun_motion_math.get_unequip_motion(config, elapsed)
	local duration = math.max(config.unequip_time or 0.38, 0.05)
	local alpha = math.clamp(elapsed / duration, 0, 1)
	local curve = gun_motion_math.smootherstep(alpha)
	local lift = math.sin(alpha * math.pi) * (config.unequip_lift or 0.08)
	local side = (config.unequip_side or 0.34) * curve
	local drop = -(config.unequip_drop or 1.05) * curve + lift
	local back = (config.unequip_back or 0.58) * curve
	local pitch = math.rad((config.unequip_pitch or -18) * curve)
	local yaw = math.rad((config.unequip_yaw or 8) * curve)
	local roll = math.rad((config.unequip_roll or -15) * curve)
	return CFrame.new(side, drop, back) * CFrame.Angles(pitch, yaw, roll), alpha
end

function gun_motion_math.update_spring(current, velocity, target, frequency, damping, delta_time, max_magnitude)
	local remaining_time = math.min(delta_time, max_spring_delta_time)
	local step_rate = math.max(base_spring_step_rate, frequency * minimum_spring_steps_per_cycle)
	local step_time = 1 / step_rate
	while remaining_time > 0 do
		local step = math.min(remaining_time, step_time)
		local omega = 2 * math.pi * frequency
		local acceleration = (target - current) * omega * omega - 2 * damping * omega * velocity
		velocity += acceleration * step
		current += velocity * step
		if max_magnitude then
			current = gun_motion_math.clamp_vector(current, max_magnitude)
			velocity = gun_motion_math.clamp_vector(velocity, max_magnitude * math.max(frequency, 1) * 4)
		end
		remaining_time -= step
	end
	return current, velocity
end

function gun_motion_math.update_number_spring(current, velocity, target, frequency, damping, delta_time, min_value, max_value)
	local remaining_time = math.min(delta_time, max_spring_delta_time)
	local step_rate = math.max(base_spring_step_rate, frequency * minimum_spring_steps_per_cycle)
	local step_time = 1 / step_rate
	while remaining_time > 0 do
		local step = math.min(remaining_time, step_time)
		local omega = 2 * math.pi * frequency
		local acceleration = (target - current) * omega * omega - 2 * damping * omega * velocity
		velocity += acceleration * step
		current += velocity * step
		current = math.clamp(current, min_value, max_value)
		velocity = math.clamp(velocity, -max_value * math.max(frequency, 1) * 4, max_value * math.max(frequency, 1) * 4)
		remaining_time -= step
	end
	return current, velocity
end

return gun_motion_math
