local gun_motion_state = {}

local VECTOR3_ZERO_FIELDS = {
	"camera_recoil_rotation",
	"camera_recoil_velocity",
	"camera_recoil_queued",
	"viewmodel_recoil_position",
	"viewmodel_recoil_position_velocity",
	"viewmodel_recoil_position_queued",
	"viewmodel_recoil_rotation",
	"viewmodel_recoil_rotation_velocity",
	"viewmodel_recoil_rotation_queued",
	"gun_rotation_kick",
	"gun_rotation_kick_velocity",
	"screen_shake_rotation",
	"screen_shake_velocity",
	"body_camera_rotation",
	"body_camera_rotation_velocity",
	"body_camera_deadzone",
	"body_camera_deadzone_velocity",
	"body_camera_weapon_rotation",
	"body_camera_weapon_rotation_velocity",
	"directional_tilt",
	"body_camera_position",
	"body_camera_viewmodel_position",
}

local NUMBER_ZERO_FIELDS = {
	"camera_recoil_yaw_queued",
	"arms_push_out",
	"arms_push_out_velocity",
	"camera_move_alpha",
	"camera_bob_phase",
	"camera_sprint_alpha",
	"camera_crouch_target",
	"camera_crouch_alpha",
	"camera_crouch_impulse",
	"viewmodel_crouch_target",
	"viewmodel_crouch_alpha",
	"viewmodel_crouch_impulse",
	"sprint_pose_alpha",
	"sprint_bob_alpha",
	"aim_velocity",
	"recoil_fov_offset",
	"recoil_fov_velocity",
}

function gun_motion_state.reset(manager)
	for _, field in VECTOR3_ZERO_FIELDS do
		manager[field] = Vector3.zero
	end
	for _, field in NUMBER_ZERO_FIELDS do
		manager[field] = 0
	end
	manager.camera_effect_cframe = CFrame.identity
	manager.body_camera_cframe = nil
	manager.body_camera_yaw = nil
	manager.body_camera_pitch = nil
	manager.body_camera_target_yaw = nil
	manager.body_camera_target_pitch = nil
	manager.laser_dot_screen_position = nil
	manager.ads_alignment_position = nil
	manager.sway_current = Vector2.zero
	manager.body_camera_mouse_delta = Vector2.zero
end

function gun_motion_state.ensure(manager)
	for _, field in VECTOR3_ZERO_FIELDS do
		manager[field] = manager[field] or Vector3.zero
	end
	for _, field in NUMBER_ZERO_FIELDS do
		manager[field] = manager[field] or 0
	end
	manager.camera_effect_cframe = manager.camera_effect_cframe or CFrame.identity
	manager.last_recoil_time = manager.last_recoil_time or 0
	manager.body_camera_mouse_delta = manager.body_camera_mouse_delta or Vector2.zero
end

function gun_motion_state.is_recoil_settled(manager): boolean
	local config = manager.config
	local position_epsilon = config.recoil_settle_position_epsilon or 0.004
	local rotation_epsilon = math.rad(config.recoil_settle_rotation_epsilon or 0.08)
	local velocity_epsilon = math.rad(config.recoil_settle_velocity_epsilon or 0.12)
	local arms_epsilon = config.recoil_settle_arms_epsilon or 0.003

	return manager.viewmodel_recoil_position_queued.Magnitude <= position_epsilon
		and manager.viewmodel_recoil_rotation_queued.Magnitude <= rotation_epsilon
		and math.abs(manager.camera_recoil_yaw_queued or 0) <= rotation_epsilon
		and manager.viewmodel_recoil_position.Magnitude <= position_epsilon
		and manager.viewmodel_recoil_rotation.Magnitude <= rotation_epsilon
		and manager.camera_recoil_rotation.Magnitude <= rotation_epsilon
		and manager.camera_recoil_velocity.Magnitude <= velocity_epsilon
		and manager.screen_shake_rotation.Magnitude <= rotation_epsilon
		and manager.screen_shake_velocity.Magnitude <= velocity_epsilon
		and math.abs(manager.arms_push_out or 0) <= arms_epsilon
		and math.abs(manager.arms_push_out_velocity or 0) <= arms_epsilon
end

return gun_motion_state
