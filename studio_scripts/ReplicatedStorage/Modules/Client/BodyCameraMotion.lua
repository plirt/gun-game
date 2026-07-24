local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)

local body_camera_motion = {}

local local_player = Players.LocalPlayer

function body_camera_motion.reset(state)
	state.body_camera_cframe = nil
	state.body_camera_yaw = nil
	state.body_camera_pitch = nil
	state.body_camera_target_yaw = nil
	state.body_camera_target_pitch = nil
	state.body_camera_position = nil
	state.body_camera_viewmodel_position = nil
	state.body_camera_lean_alpha = 0
	state.body_camera_viewmodel_lean_roll = 0
	state.body_camera_lean_character = nil
	state.body_camera_lean_raycast_params = nil
end

function body_camera_motion.update(state, config, movement_state, camera_cframe, mouse_delta, delta_time)
	if config.body_camera_enabled == false then
		body_camera_motion.reset(state)
		return camera_cframe
	end
	local character = local_player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		state.body_camera_position = nil
		state.body_camera_viewmodel_position = nil
		return camera_cframe
	end
	if not state.body_camera_yaw or not state.body_camera_pitch then
		local pitch, yaw = camera_cframe:ToOrientation()
		state.body_camera_yaw = yaw
		state.body_camera_pitch = pitch
		state.body_camera_target_yaw = yaw
		state.body_camera_target_pitch = pitch
	end
	local sensitivity = config.body_camera_sensitivity or 0.0025
	state.body_camera_target_yaw -= mouse_delta.X * sensitivity
	state.body_camera_target_pitch = math.clamp(
		state.body_camera_target_pitch - mouse_delta.Y * sensitivity,
		math.rad(config.body_camera_min_pitch or -82),
		math.rad(config.body_camera_max_pitch or 82)
	)
	local rotation_alpha = math.clamp(
		1 - math.exp(-delta_time * (config.body_camera_rotation_smoothing or 16)),
		0,
		1
	)
	state.body_camera_yaw += (state.body_camera_target_yaw - state.body_camera_yaw) * rotation_alpha
	state.body_camera_pitch += (state.body_camera_target_pitch - state.body_camera_pitch) * rotation_alpha
	local yaw_cframe = CFrame.Angles(0, state.body_camera_yaw, 0)
	local offset = config.body_camera_mount_offset or Vector3.zero
	local viewmodel_offset = config.body_camera_viewmodel_mount_offset or offset
	local crouch_drop = movement_state
		and movement_state.crouching
		and (config.body_camera_crouch_drop or MovementConfig.BODY_CAMERA_CROUCH_DROP)
		or 0
	local height = (config.body_camera_base_height or 1.45) - crouch_drop
	local base_target_position = root.Position
		+ yaw_cframe.RightVector * offset.X
		+ Vector3.yAxis * (height + offset.Y)
		+ yaw_cframe.LookVector * offset.Z
	local viewmodel_base_position = root.Position
		+ yaw_cframe.RightVector * viewmodel_offset.X
		+ Vector3.yAxis * (height + viewmodel_offset.Y)
		+ yaw_cframe.LookVector * viewmodel_offset.Z

	local lean_target = movement_state and movement_state.lean_direction or 0
	if movement_state and movement_state.sprinting then
		lean_target = 0
	end
	lean_target = math.clamp(lean_target, -1, 1)
	local lean_alpha = math.clamp(
		1 - math.exp(-delta_time * (config.lean_smoothing or MovementConfig.LEAN_SMOOTHING)),
		0,
		1
	)
	state.body_camera_lean_alpha = (state.body_camera_lean_alpha or 0)
		+ (lean_target - (state.body_camera_lean_alpha or 0)) * lean_alpha

	if state.body_camera_lean_character ~= character then
		local lean_raycast_params = RaycastParams.new()
		lean_raycast_params.FilterType = Enum.RaycastFilterType.Exclude
		lean_raycast_params.FilterDescendantsInstances = { character }
		lean_raycast_params.IgnoreWater = true
		state.body_camera_lean_character = character
		state.body_camera_lean_raycast_params = lean_raycast_params
	end

	local lean_distance = config.lean_camera_offset or MovementConfig.LEAN_CAMERA_OFFSET
	local visual_lean_alpha = state.body_camera_lean_alpha
	if visual_lean_alpha < 0 then
		visual_lean_alpha *= config.lean_left_visual_multiplier
			or MovementConfig.LEAN_LEFT_VISUAL_MULTIPLIER
	end
	local requested_lean_offset = yaw_cframe.RightVector * visual_lean_alpha * lean_distance
	local lean_offset = requested_lean_offset
	if requested_lean_offset.Magnitude > 0.001 and state.body_camera_lean_raycast_params then
		local wall_hit = workspace:Raycast(base_target_position, requested_lean_offset, state.body_camera_lean_raycast_params)
		if wall_hit then
			local allowed_distance = math.max(
				wall_hit.Distance - (config.lean_wall_padding or MovementConfig.LEAN_WALL_PADDING),
				0
			)
			lean_offset = requested_lean_offset.Unit * math.min(allowed_distance, requested_lean_offset.Magnitude)
		end
	end
	local effective_lean = lean_distance > 0
		and lean_offset:Dot(yaw_cframe.RightVector) / lean_distance
		or 0
	state.body_camera_viewmodel_lean_roll = -math.rad(config.lean_camera_roll or MovementConfig.LEAN_CAMERA_ROLL)
		* effective_lean

	local target_position = base_target_position + lean_offset
	local viewmodel_target_position = viewmodel_base_position + lean_offset
	if not state.body_camera_position or (state.body_camera_position - target_position).Magnitude > 8 then
		state.body_camera_position = target_position
	else
		local position_alpha = math.clamp(
			1 - math.exp(-delta_time * (config.body_camera_position_smoothing or 28)),
			0,
			1
		)
		state.body_camera_position = state.body_camera_position:Lerp(target_position, position_alpha)
	end
	if not state.body_camera_viewmodel_position
		or (state.body_camera_viewmodel_position - viewmodel_target_position).Magnitude > 8
	then
		state.body_camera_viewmodel_position = viewmodel_target_position
	else
		local viewmodel_position_alpha = math.clamp(
			1 - math.exp(
				-delta_time
					* (config.body_camera_viewmodel_position_smoothing or config.body_camera_position_smoothing or 28)
			),
			0,
			1
		)
		state.body_camera_viewmodel_position = state.body_camera_viewmodel_position:Lerp(
			viewmodel_target_position,
			viewmodel_position_alpha
		)
	end
	local look_direction = (yaw_cframe * CFrame.Angles(state.body_camera_pitch, 0, 0)).LookVector
	local base_cframe = CFrame.lookAt(
		state.body_camera_position,
		state.body_camera_position + look_direction,
		Vector3.yAxis
	) * CFrame.Angles(
		0,
		0,
		math.rad(config.body_camera_base_roll or 0)
	)
	state.body_camera_cframe = base_cframe
	return base_cframe
end

function body_camera_motion.get_viewmodel_cframe(state, config, camera_cframe)
	if config.body_camera_enabled == false or not state.body_camera_viewmodel_position then
		return camera_cframe
	end
	return CFrame.lookAt(
		state.body_camera_viewmodel_position,
		state.body_camera_viewmodel_position + camera_cframe.LookVector,
		Vector3.yAxis
	)
end

function body_camera_motion.get_viewmodel_lean_cframe(state)
	return CFrame.Angles(0, 0, state.body_camera_viewmodel_lean_roll or 0)
end

return body_camera_motion

