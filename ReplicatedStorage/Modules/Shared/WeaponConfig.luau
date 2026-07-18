local WeaponConfig = {}

local DEFAULT = {
	name = "Rifle",
	automatic = true,
	fire_rate = 650,

	magazine_size = 30,
	reserve_ammo = 120,
	reload_time = 2.15,
	tactical_reload_time = 1.65,
	reload_style = "magazine",
	reload_start_time = 0,
	reload_insert_time = 0.65,
	reload_end_time = 0,
	reload_insert_animation = "TacticalReload",

	damage = 24,
	headshot_multiplier = 2,
	limb_multiplier = 0.75,
	damage_falloff_start = 120,
	damage_falloff_end = 360,
	minimum_damage_multiplier = 0.45,

	muzzle_velocity = 900,
	gravity = Vector3.new(0, -38, 0),
	max_distance = 650,
	step_time = 1 / 240,

	spread_hip = 1.45,
	spread_aim = 0.35,
	spread_per_shot = 0.18,
	spread_max = 4,
	spread_recovery = 7,
	moving_spread_bonus = 0.8,

	recoil_pitch = 2.4,
	recoil_yaw = 0.85,
	recoil_roll = 0.25,
	recoil_snap_speed = 32,
	recoil_recovery_speed = 11,
	recoil_aim_multiplier = 0.58,
	recoil_strength_multiplier = 1.1,
	recoil_fov_kick = 5,
	recoil_fov_direct = 0.45,
	recoil_fov_impulse = 16,
	recoil_fov_recovery_frequency = 5,
	recoil_fov_recovery_damping = 0.82,
	recoil_fov_max = 9,

	sway_amount = 0.85,
	sway_horizontal_amount = 1.25,
	ads_sway_stability = 0.08,
	ads_movement_stability = 0.06,
	sway_speed = 14,
	sway_limit = 5,

	position_offset = Vector3.zero,
	aim_position_offset = Vector3.zero,
	ads_sight_y_offset = 0,
	rotation_offset = Vector3.new(0, 0, 0),
	aim_speed = 2,
	aim_spring_frequency = 1.7,
	aim_spring_damping = 0.96,
	aim_fov = 86,
	default_fov = 100,

	body_camera_enabled = true,
	body_camera_ads_lock = false,
	body_camera_mount_offset = Vector3.new(1, 1.15, -0.55),
	body_camera_viewmodel_mount_offset = Vector3.new(0, .75, .85),
	body_camera_base_height = 1,
	body_camera_crouch_drop = 0.9,
	body_camera_position_smoothing = 42,
	body_camera_sensitivity = 0.0025,
	body_camera_rotation_smoothing = 18,
	body_camera_min_pitch = -82,
	body_camera_max_pitch = 82,
	body_camera_base_roll = 0,
	body_camera_viewmodel_offset = Vector3.new(-0.08, -0.46, 0.34),
	body_camera_ads_viewmodel_offset = Vector3.new(0.14, -0.23, 0.42),
	body_camera_ads_rotation = Vector3.new(-0.7, 2, -0.55),
	body_camera_lag_speed = 30,
	body_camera_arm_follow = 1,
	body_camera_ads_follow = 1,
	body_camera_pitch_response = 0,
	body_camera_yaw_response = 0,
	body_camera_roll_response = 0,
	body_camera_pitch_limit = 1.35,
	body_camera_yaw_limit = 0.85,
	body_camera_roll_limit = 2.2,
	body_camera_rotation_frequency = 4.5,
	body_camera_rotation_damping = 0.86,
	body_camera_rotation_limit = 2.4,
	camera_idle_bob_amount = 0,
	camera_walk_bob_amount = 0,
	camera_walk_roll = 0,
	camera_walk_pitch = 0,
	camera_bob_smoothing = 12,
	body_camera_weapon_input_smoothing = 16,
	body_camera_weapon_side_response = 0.0024,
	body_camera_weapon_lift_response = 0.0018,
	body_camera_weapon_pitch_response = 0.009,
	body_camera_weapon_yaw_response = 0.011,
	body_camera_weapon_roll_response = 0.005,
	body_camera_weapon_pitch_limit = 9,
	body_camera_weapon_yaw_limit = 11,
	body_camera_weapon_side_limit = 0.12,
	body_camera_weapon_lift_limit = 0.08,
	body_camera_weapon_roll_limit = 7,
	body_camera_weapon_frequency = 15,
	body_camera_weapon_damping = 0.96,
	body_camera_weapon_rotation_frequency = 18,
	body_camera_weapon_rotation_damping = 0.94,
	body_camera_weapon_rotation_limit = 13,
	body_camera_ads_weapon_follow = 1,
	body_camera_weapon_limit = 0.16,
	body_camera_laser_enabled = true,
	body_camera_laser_size = 0.42,
	body_camera_laser_transparency = 0.05,
	body_camera_laser_color = Color3.fromRGB(255, 35, 35),

	procedural_enabled = true,
	procedural_walk_amount = 0.055,
	procedural_walk_bob_speed = 8,
	procedural_ads_walk_bob_multiplier = 0.85,
	procedural_ads_walk_pitch = 0.11,
	procedural_ads_walk_roll_multiplier = 0.85,
	procedural_ads_locked_amount = 0,
	procedural_ads_turn_limit = 0.08,
	procedural_ads_turn_pitch = 0.015,
	procedural_ads_turn_yaw = 0.02,
	procedural_ads_turn_roll = 0.025,
	procedural_ads_recoil_roll = 0.04,

	muzzle_flash_time = 0.045,
	tracer_lifetime = 0.045,
	impact_lifetime = 0.18,
}

local function merge(base, overrides)
	local result = table.clone(base)

	if overrides then
		for key, value in overrides do
			result[key] = value
		end
	end
	return result
end

function WeaponConfig.get_defaults()
	return table.clone(DEFAULT)
end

function WeaponConfig.normalize(config)
	local normalized = merge(DEFAULT, config)

	normalized.seconds_per_shot = 60 / math.max(normalized.fire_rate, 1)
	normalized.reload_empty_time = normalized.reload_time
	normalized.reload_tactical_time = normalized.tactical_reload_time or normalized.reload_time
	return normalized
end
return WeaponConfig

