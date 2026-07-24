local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BodyCameraMotion = require(ReplicatedStorage.Modules.Client.BodyCameraMotion)
local WeaponConfig = require(ReplicatedStorage.Modules.Shared.WeaponConfig)
local gun_motion_math = require(ReplicatedStorage.Modules.Client.GunMotionMath)
local gun_viewmodel_motion = require(ReplicatedStorage.Modules.Client.GunViewmodelMotion)

local utility_viewmodel_motion = {}

local body_camera_config = WeaponConfig.get_defaults()

local utility_config = {
	procedural_enabled = true,
	procedural_walk_speed = 14,
	procedural_move_smoothing = 10,
	procedural_idle_amount = 0.025,
	procedural_idle_speed = 1.2,
	procedural_walk_amount = 0.055,
	procedural_walk_bob_speed = 8,
	procedural_walk_roll = 0.45,
	procedural_idle_pitch = 0.12,
	procedural_idle_yaw = 0.1,
	body_camera_viewmodel_offset = Vector3.new(-0.08, -0.38, 2.85),
	sway_amount = 1.1,
	sway_limit = 2.2,
	sway_speed = 10,
	sprint_pose_x = 0.22,
	sprint_pose_y = 0.22,
	sprint_pose_z = -0.28,
	sprint_pose_pitch = -13,
	sprint_pose_yaw = 8,
	sprint_pose_roll = -9,
	sprint_bob_x = 0.01,
	sprint_bob_y = 0.014,
	sprint_bob_pitch = 0.28,
	sprint_bob_yaw = 0.16,
	sprint_bob_roll = 0.38,
}

function utility_viewmodel_motion.new(movement_state, camera)
	return {
		movement_state = movement_state,
		last_camera_cframe = camera and camera.CFrame or CFrame.identity,
		sway_current = Vector2.zero,
		procedural_time = 0,
		procedural_move_alpha = 0,
		directional_tilt = Vector3.zero,
		sprint_pose_alpha = 0,
		sprint_bob_alpha = 0,
	}
end

function utility_viewmodel_motion.update(state, movement_state, camera, delta_time)
	state.movement_state = movement_state
	local camera_cframe = BodyCameraMotion.update(
		state,
		body_camera_config,
		movement_state,
		camera.CFrame,
		UserInputService:GetMouseDelta(),
		delta_time
	)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = camera_cframe
	local camera_delta = gun_motion_math.get_camera_delta(state.last_camera_cframe, camera_cframe)
	state.last_camera_cframe = camera_cframe
	local sway_x = math.clamp(
		-camera_delta.Y * utility_config.sway_amount,
		-math.rad(utility_config.sway_limit),
		math.rad(utility_config.sway_limit)
	)
	local sway_y = math.clamp(
		-camera_delta.X * utility_config.sway_amount,
		-math.rad(utility_config.sway_limit),
		math.rad(utility_config.sway_limit)
	)
	state.sway_current = state.sway_current:Lerp(
		Vector2.new(sway_x, sway_y),
		math.clamp(delta_time * utility_config.sway_speed, 0, 1)
	)
	local sway = CFrame.Angles(state.sway_current.X, state.sway_current.Y, 0)
	local procedural = gun_viewmodel_motion.get_procedural_motion(utility_config, state, delta_time, 0)
	local viewmodel_camera_cframe = BodyCameraMotion.get_viewmodel_cframe(
		state,
		body_camera_config,
		camera_cframe
	)
	local viewmodel_lean_cframe = BodyCameraMotion.get_viewmodel_lean_cframe(state)
	return viewmodel_camera_cframe * CFrame.new(utility_config.body_camera_viewmodel_offset) * viewmodel_lean_cframe,
		sway * procedural
end

return utility_viewmodel_motion

