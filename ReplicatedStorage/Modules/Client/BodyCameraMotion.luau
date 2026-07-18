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
	local target_position = root.Position
		+ yaw_cframe.RightVector * offset.X
		+ Vector3.yAxis * (height + offset.Y)
		+ yaw_cframe.LookVector * offset.Z
	local viewmodel_target_position = root.Position
		+ yaw_cframe.RightVector * viewmodel_offset.X
		+ Vector3.yAxis * (height + viewmodel_offset.Y)
		+ yaw_cframe.LookVector * viewmodel_offset.Z
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
	) * CFrame.Angles(0, 0, math.rad(config.body_camera_base_roll or 0))
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

return body_camera_motion
