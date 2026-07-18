local Players = game:GetService("Players")

local gun_viewmodel_motion = {}

local local_player = Players.LocalPlayer

local function get_character_motion(): (number, Vector3)
	local character = local_player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	if not root or not humanoid or humanoid.MoveDirection.Magnitude <= 0.05 then
		return 0, Vector3.zero
	end
	local horizontal_velocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	if horizontal_velocity.Magnitude <= 0.05 then
		return 0, Vector3.zero
	end
	return horizontal_velocity.Magnitude, root.CFrame:VectorToObjectSpace(horizontal_velocity.Unit)
end

local function get_sprint_alpha(state, delta_time: number, aim_alpha: number, move_speed: number): number
	local movement_state = state.movement_state
	local wants_sprint = movement_state and movement_state.sprinting and movement_state.moving and move_speed > 0.08 and aim_alpha <= 0.05
	local target = wants_sprint and 1 or 0
	state.sprint_pose_alpha = math.clamp(state.sprint_pose_alpha or 0, 0, 1)
	state.sprint_bob_alpha = math.clamp(state.sprint_bob_alpha or 0, 0, 1)
	state.sprint_pose_alpha += (target - state.sprint_pose_alpha) * math.clamp(delta_time * 4, 0, 1)
	state.sprint_pose_alpha = math.clamp(state.sprint_pose_alpha, 0, 1)
	if target == 0 and state.sprint_pose_alpha < 0.001 then
		state.sprint_pose_alpha = 0
	end
	local bob_target = state.sprint_pose_alpha * state.sprint_pose_alpha * (3 - 2 * state.sprint_pose_alpha) * target
	state.sprint_bob_alpha += (bob_target - state.sprint_bob_alpha) * math.clamp(delta_time * 5, 0, 1)
	state.sprint_bob_alpha = math.clamp(state.sprint_bob_alpha, 0, 1)
	if bob_target == 0 and state.sprint_bob_alpha < 0.001 then
		state.sprint_bob_alpha = 0
	end
	return state.sprint_pose_alpha
end

function gun_viewmodel_motion.get_camera_motion(config, state, delta_time: number, aim_alpha: number): CFrame
	if config.camera_bob_enabled == false then
		return CFrame.identity
	end

	local hip_weight = 1 - aim_alpha
	local ads_stability = config.ads_movement_stability or 0.05
	local ads_motion_weight = ads_stability + (1 - ads_stability) * hip_weight
	local character_speed = get_character_motion()
	local move_speed = math.clamp(character_speed / math.max(config.camera_bob_walk_speed or config.procedural_walk_speed or 14, 1), 0, 1.5)
	state.camera_move_alpha += (move_speed - state.camera_move_alpha) * math.clamp(delta_time * (config.camera_bob_smoothing or 10), 0, 1)
	if move_speed == 0 and state.camera_move_alpha < 0.001 then
		state.camera_move_alpha = 0
	end

	local time = state.procedural_time
	state.camera_sprint_alpha = math.clamp(state.camera_sprint_alpha or 0, 0, 1)
	local camera_target = math.clamp(state.sprint_bob_alpha or 0, 0, 1)
	state.camera_sprint_alpha += (camera_target - state.camera_sprint_alpha) * math.clamp(delta_time * (config.camera_sprint_bob_smoothing or 5), 0, 1)
	state.camera_sprint_alpha = math.clamp(state.camera_sprint_alpha, 0, 1)
	if camera_target == 0 and state.camera_sprint_alpha < 0.001 then
		state.camera_sprint_alpha = 0
	end
	local sprint_alpha = state.camera_sprint_alpha * state.camera_sprint_alpha * (3 - 2 * state.camera_sprint_alpha)
	local sprint_amount = 1 + sprint_alpha * (config.camera_sprint_bob_amount_multiplier or 0.65)
	local sprint_speed = 1 + sprint_alpha * ((config.camera_sprint_bob_speed_multiplier or 1.12) - 1)
	local sprint_side_amount = 1 + sprint_alpha * ((config.camera_sprint_bob_side_multiplier or 0.3) - 1)
	local idle_amount = (config.camera_idle_bob_amount or 0.015) * ads_motion_weight * (1 - sprint_alpha * 0.2)
	local walk_amount = (config.camera_walk_bob_amount or 0.055) * state.camera_move_alpha * ads_motion_weight * sprint_amount
	local idle_speed = config.camera_idle_bob_speed or 1.1
	local walk_speed = (config.camera_walk_bob_speed or 8) * sprint_speed
	state.camera_bob_phase = (state.camera_bob_phase or 0)
		+ walk_speed * delta_time * math.clamp(state.camera_move_alpha, 0, 1.5)
	local walk_phase = state.camera_bob_phase
	local idle_x = math.cos(time * idle_speed * 0.73) * idle_amount * (config.camera_idle_side_multiplier or 0.25)
	local x = idle_x + math.sin(walk_phase) * walk_amount * 0.45 * sprint_side_amount
	local y = math.cos(walk_phase * 2) * walk_amount * 0.35 + math.sin(time * idle_speed) * idle_amount
	local pitch = math.rad((math.sin(time * idle_speed * 0.8) * (config.camera_idle_pitch or 0.08) + math.abs(math.cos(walk_phase)) * state.camera_move_alpha * (config.camera_walk_pitch or 0.12) * sprint_amount) * ads_motion_weight)
	local roll = math.rad(math.sin(walk_phase) * state.camera_move_alpha * (config.camera_walk_roll or 0.28) * ads_motion_weight * sprint_amount * sprint_side_amount)

	return CFrame.new(x, y, 0) * CFrame.Angles(pitch, 0, roll)
end

function gun_viewmodel_motion.get_procedural_motion(config, state, delta_time: number, aim_alpha: number): CFrame
	if config.procedural_enabled == false then
		return CFrame.identity
	end

	local hip_weight = 1 - aim_alpha
	local ads_weight = aim_alpha
	local ads_stability = config.ads_movement_stability or 0.05
	local ads_motion_weight = ads_stability + (1 - ads_stability) * hip_weight
	local character_speed, move_direction = get_character_motion()
	local move_speed = math.clamp(character_speed / math.max(config.procedural_walk_speed or 14, 1), 0, 1.5)
	state.procedural_move_alpha += (move_speed - state.procedural_move_alpha) * math.clamp(delta_time * (config.procedural_move_smoothing or 10), 0, 1)
	if move_speed == 0 and state.procedural_move_alpha < 0.001 then
		state.procedural_move_alpha = 0
	end

	local sprint_alpha = get_sprint_alpha(state, delta_time, aim_alpha, move_speed)
	local sprint_bob_alpha = state.sprint_bob_alpha or 0
	local sprint_tilt_multiplier = 1 + sprint_alpha * ((config.directional_tilt_sprint_multiplier or 1.35) - 1)
	local ads_tilt_multiplier = 1 + aim_alpha * ((config.directional_tilt_ads_multiplier or 0.3) - 1)
	local tilt_weight = math.clamp(state.procedural_move_alpha, 0, 1) * sprint_tilt_multiplier * ads_tilt_multiplier
	local directional_tilt_target = Vector3.new(
		math.rad(move_direction.Z * (config.directional_tilt_pitch or 1.2)),
		math.rad(move_direction.X * (config.directional_tilt_yaw or 0.7)),
		math.rad(-move_direction.X * (config.directional_tilt_roll or 2.4))
	) * tilt_weight
	local directional_tilt_alpha = math.clamp(
		1 - math.exp(-delta_time * (config.directional_tilt_smoothing or 10)),
		0,
		1
	)
	state.directional_tilt = state.directional_tilt or Vector3.zero
	state.directional_tilt = state.directional_tilt:Lerp(directional_tilt_target, directional_tilt_alpha)
	if directional_tilt_target.Magnitude == 0 and state.directional_tilt.Magnitude < math.rad(0.01) then
		state.directional_tilt = Vector3.zero
	end
	local directional_tilt = CFrame.Angles(
		state.directional_tilt.X,
		state.directional_tilt.Y,
		state.directional_tilt.Z
	)
	local time = state.procedural_time
	local idle_amount = (config.procedural_idle_amount or 0.025) * ads_motion_weight * (1 - sprint_alpha * 0.35)
	local idle_speed = config.procedural_idle_speed or 1.2
	local base_walk_amount = config.procedural_walk_amount or 0.055
	local hip_walk_amount = base_walk_amount * state.procedural_move_alpha * hip_weight
	local ads_walk_amount = base_walk_amount * (config.procedural_ads_walk_bob_multiplier or 0.85) * state.procedural_move_alpha * ads_weight
	local walk_amount = (hip_walk_amount + ads_walk_amount) * (1 + sprint_bob_alpha * 0.08)
	local walk_speed = config.procedural_walk_bob_speed or 8
	local ads_breath_amount = (config.procedural_ads_breath_amount or 0.006) * ads_weight
	local ads_breath_speed = config.procedural_ads_breath_speed or 0.85
	local idle_x = math.sin(time * idle_speed) * idle_amount * 0.45
	local idle_y = math.cos(time * idle_speed * 0.7) * idle_amount
	local walk_x = math.sin(time * walk_speed) * walk_amount
	local walk_y = math.abs(math.cos(time * walk_speed)) * walk_amount * 0.65
	local ads_y = math.sin(time * ads_breath_speed) * ads_breath_amount
	local hip_walk_weight = state.procedural_move_alpha * hip_weight
	local ads_walk_weight = state.procedural_move_alpha * ads_weight
	local base_walk_roll = config.procedural_walk_roll or 0.45
	local roll_amount = base_walk_roll * hip_walk_weight
		+ base_walk_roll * (config.procedural_ads_walk_roll_multiplier or 0.85) * ads_walk_weight
	local pitch_amount = (config.procedural_idle_pitch or 0.12) * ads_motion_weight
		+ math.abs(math.cos(time * walk_speed)) * (config.procedural_ads_walk_pitch or 0.11) * ads_walk_weight
	local yaw_amount = (config.procedural_idle_yaw or 0.1) * ads_motion_weight
	local roll = math.rad(roll_amount * math.sin(time * walk_speed))
	local pitch = math.rad(pitch_amount * math.sin(time * idle_speed * 0.8))
	local yaw = math.rad(yaw_amount * math.cos(time * idle_speed * 0.6))
	local sprint_pose = CFrame.new(
		config.sprint_pose_x or 0.22,
		config.sprint_pose_y or 0.22,
		config.sprint_pose_z or -0.28
	) * CFrame.Angles(
		math.rad(config.sprint_pose_pitch or -13),
		math.rad(config.sprint_pose_yaw or 8),
		math.rad(config.sprint_pose_roll or -9)
	)
	local sprint_bob = CFrame.new(
		math.sin(time * walk_speed) * (config.sprint_bob_x or 0.01) * sprint_bob_alpha,
		math.abs(math.cos(time * walk_speed)) * (config.sprint_bob_y or 0.014) * sprint_bob_alpha,
		0
	) * CFrame.Angles(
		math.rad(math.sin(time * walk_speed * 0.5) * (config.sprint_bob_pitch or 0.28) * sprint_bob_alpha),
		math.rad(math.sin(time * walk_speed) * (config.sprint_bob_yaw or 0.16) * sprint_bob_alpha),
		math.rad(math.sin(time * walk_speed) * (config.sprint_bob_roll or 0.38) * sprint_bob_alpha)
	)
	local base_motion = CFrame.new(idle_x + walk_x, idle_y + walk_y + ads_y, 0) * CFrame.Angles(pitch, yaw, roll)
	return base_motion * directional_tilt * CFrame.identity:Lerp(sprint_pose * sprint_bob, sprint_alpha)
end

function gun_viewmodel_motion.get_ads_locked_motion(config, state, camera_delta: Vector2, aim_alpha: number): CFrame
	if config.procedural_enabled == false or aim_alpha <= 0 then
		return CFrame.identity
	end

	local amount = aim_alpha * (config.procedural_ads_locked_amount or 1)
	local time = state.procedural_time
	local breath_speed = config.procedural_ads_breath_speed or 0.85
	local breath_pitch = math.rad(math.sin(time * breath_speed * 0.82) * (config.procedural_ads_breath_pitch or 0.06) * amount)
	local breath_yaw = math.rad(math.cos(time * breath_speed * 0.65) * (config.procedural_ads_breath_yaw or 0.035) * amount)
	local breath_roll = math.rad(math.sin(time * breath_speed * 0.48) * (config.procedural_ads_breath_roll or 0.045) * amount)
	local turn_limit = math.rad(config.procedural_ads_turn_limit or 0.42)
	local turn_pitch = math.clamp(-camera_delta.X * (config.procedural_ads_turn_pitch or 0.1), -turn_limit, turn_limit) * amount
	local turn_yaw = math.clamp(-camera_delta.Y * (config.procedural_ads_turn_yaw or 0.16), -turn_limit, turn_limit) * amount
	local turn_roll = math.clamp(camera_delta.Y * (config.procedural_ads_turn_roll or 0.24), -turn_limit, turn_limit) * amount
	local recoil_roll = math.clamp(state.viewmodel_recoil_rotation.Z * (config.procedural_ads_recoil_roll or 0.16), -turn_limit, turn_limit) * amount

	return CFrame.Angles(
		breath_pitch + turn_pitch,
		breath_yaw + turn_yaw,
		breath_roll + turn_roll + recoil_roll
	)
end

return gun_viewmodel_motion
