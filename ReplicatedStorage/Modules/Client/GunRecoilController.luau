local gun_recoil_controller = {}

local function clamp_vector(vector: Vector3, max_magnitude: number): Vector3
	if vector.Magnitude <= max_magnitude then
		return vector
	end
	return vector.Unit * max_magnitude
end

local function get_random_sign(random_source: Random): number
	return random_source:NextInteger(0, 1) == 0 and -1 or 1
end

function gun_recoil_controller.add_recoil(manager)
	local config = manager.config
	local recoil_strength = config.recoil_strength_multiplier or 1
	local aim_multiplier = (manager.aiming and config.recoil_aim_multiplier or 1) * recoil_strength
	local ads_position_multiplier = manager.aiming and (config.recoil_ads_position_multiplier or 1) or 1
	local ads_arms_multiplier = manager.aiming and (config.recoil_ads_arms_push_multiplier or 1) or 1
	local kickback = (config.recoil_viewmodel_kickback or 0.18) * aim_multiplier * ads_position_multiplier
	local rise = (config.recoil_viewmodel_rise or 0.045) * aim_multiplier * ads_position_multiplier
	local side = manager.random:NextNumber(-1, 1) * (config.recoil_viewmodel_side or 0.035) * aim_multiplier * ads_position_multiplier
	local climb = math.rad((config.recoil_viewmodel_climb or config.recoil_viewmodel_pitch or 2.2) * aim_multiplier)
	local yaw = math.rad(manager.random:NextNumber(-1, 1) * (config.recoil_viewmodel_yaw or 0.7) * aim_multiplier)
	local roll = math.rad(manager.random:NextNumber(-1, 1) * (config.recoil_viewmodel_roll or 0.55) * aim_multiplier)

	local viewmodel_position_kick = Vector3.new(side, rise, kickback)
	local viewmodel_rotation_kick = Vector3.new(climb, yaw, roll)
	local extra_rotation_kick = Vector3.new(
		math.rad((config.recoil_gun_rotation_kick_pitch or 0.45) * aim_multiplier),
		math.rad(manager.random:NextNumber(-1, 1) * (config.recoil_gun_rotation_kick_yaw or 0.18) * aim_multiplier),
		math.rad(manager.random:NextNumber(-1, 1) * (config.recoil_gun_rotation_kick_roll or 0.55) * aim_multiplier)
	)
	local camera_kick = Vector3.new(
		math.rad((config.recoil_camera_pitch or 0) * aim_multiplier),
		math.rad(manager.random:NextNumber(-1, 1) * (config.recoil_camera_yaw or 0) * aim_multiplier),
		math.rad(manager.random:NextNumber(-1, 1) * (config.recoil_camera_roll or 0) * aim_multiplier)
	)
	local screen_shake_min = config.screen_shake_min or 0.55
	local screen_shake_kick = Vector3.new(
		math.rad(get_random_sign(manager.random) * manager.random:NextNumber(screen_shake_min, 1) * (config.screen_shake_pitch or 0.18) * aim_multiplier),
		math.rad(get_random_sign(manager.random) * manager.random:NextNumber(screen_shake_min, 1) * (config.screen_shake_yaw or 0.24) * aim_multiplier),
		math.rad(get_random_sign(manager.random) * manager.random:NextNumber(screen_shake_min, 1) * (config.screen_shake_roll or 0.12) * aim_multiplier)
	)

	manager.last_recoil_time = os.clock()
	local camera_direct = config.recoil_camera_direct or 0.12
	local camera_smoothness = config.recoil_camera_smoothness or 0.75
	local viewmodel_direct = config.recoil_viewmodel_direct or 0.5
	local viewmodel_smoothness = config.recoil_viewmodel_smoothness or 0.75

	local camera_max_angle = math.rad(config.recoil_camera_max_angle or 2)
	local camera_velocity_limit = camera_max_angle * math.max(config.recoil_camera_velocity_damping or 18, 1) * 4
	local camera_velocity_retention = math.clamp(config.recoil_camera_velocity_retention or 0, 0, 1)
	local camera_impulse = camera_kick * (config.recoil_camera_impulse or 8) * camera_smoothness

	manager.camera_recoil_rotation = clamp_vector(manager.camera_recoil_rotation + camera_kick * camera_direct, camera_max_angle)
	manager.camera_recoil_velocity = clamp_vector(
		manager.camera_recoil_velocity * camera_velocity_retention + camera_impulse,
		camera_velocity_limit
	)
	manager.camera_recoil_yaw_queued = camera_kick.Y * (config.recoil_camera_horizontal_direct or 1)
	manager.viewmodel_recoil_position_queued += viewmodel_position_kick * viewmodel_direct
	manager.viewmodel_recoil_position_velocity += viewmodel_position_kick * (config.recoil_viewmodel_impulse or 18) * (1 - viewmodel_smoothness)
	manager.viewmodel_recoil_rotation += viewmodel_rotation_kick * (config.recoil_viewmodel_punch_direct or 0.35)
	manager.viewmodel_recoil_rotation_queued += viewmodel_rotation_kick * viewmodel_direct
	manager.viewmodel_recoil_rotation_velocity += viewmodel_rotation_kick * (config.recoil_viewmodel_impulse or 18) * (1 - viewmodel_smoothness)
	manager.gun_rotation_kick += extra_rotation_kick
	manager.arms_push_out += (config.recoil_arms_push_out or 0.05) * aim_multiplier * ads_arms_multiplier
	manager.arms_push_out_velocity += (config.recoil_arms_push_out_impulse or 7) * aim_multiplier * ads_arms_multiplier
	local screen_shake_max_angle = math.rad(config.screen_shake_max_angle or 1.2)
	local screen_shake_velocity_limit = screen_shake_max_angle * math.max(config.screen_shake_frequency or 16, 1) * 4
	local screen_shake_rotation_retention = math.clamp(config.screen_shake_rotation_retention or 0, 0, 1)
	local screen_shake_velocity_retention = math.clamp(config.screen_shake_velocity_retention or 0, 0, 1)
	local screen_shake_impulse = screen_shake_kick * (config.screen_shake_impulse or 18)

	manager.screen_shake_rotation = clamp_vector(
		manager.screen_shake_rotation * screen_shake_rotation_retention + screen_shake_kick,
		screen_shake_max_angle
	)
	manager.screen_shake_velocity = clamp_vector(
		manager.screen_shake_velocity * screen_shake_velocity_retention + screen_shake_impulse,
		screen_shake_velocity_limit
	)
	local fov_kick = config.recoil_fov_kick or 0
	local fov_max = config.recoil_fov_max or 9
	local fov_frequency = config.recoil_fov_recovery_frequency or 5
	manager.recoil_fov_offset = math.clamp(
		manager.recoil_fov_offset + fov_kick * (config.recoil_fov_direct or 0.45),
		0,
		fov_max
	)
	manager.recoil_fov_velocity = math.clamp(
		manager.recoil_fov_velocity + fov_kick * (config.recoil_fov_impulse or 16),
		-fov_max * fov_frequency * 4,
		fov_max * fov_frequency * 4
	)
	manager.viewmodel_recoil_position_queued = clamp_vector(manager.viewmodel_recoil_position_queued, config.recoil_viewmodel_max_offset or 0.45)
	manager.viewmodel_recoil_rotation_queued = clamp_vector(manager.viewmodel_recoil_rotation_queued, math.rad(config.recoil_viewmodel_max_angle or 14))
	manager.gun_rotation_kick = clamp_vector(manager.gun_rotation_kick, math.rad(config.recoil_gun_rotation_kick_max_angle or 1.25))
	manager.arms_push_out = math.clamp(manager.arms_push_out, 0, config.recoil_arms_push_out_max or 0.18)
end

return gun_recoil_controller
