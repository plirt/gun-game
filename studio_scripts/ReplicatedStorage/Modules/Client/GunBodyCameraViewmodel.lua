local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunFireController = require(ReplicatedStorage.Modules.Client.GunFireController)
local GunMotionMath = require(ReplicatedStorage.Modules.Client.GunMotionMath)
local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)

local GunBodyCameraViewmodel = {}

local local_player = Players.LocalPlayer

function GunBodyCameraViewmodel.get_deadzone(self, mouse_delta: Vector2, delta_time: number, aim_alpha: number): CFrame
	if self.config.body_camera_enabled == false then
		self.body_camera_deadzone = Vector3.zero
		self.body_camera_deadzone_velocity = Vector3.zero
		self.body_camera_mouse_delta = Vector2.zero
		return CFrame.identity
	end
	local input_smoothing = self.config.body_camera_viewmodel_input_smoothing
		or self.config.body_camera_weapon_input_smoothing
		or 28
	local input_alpha = 1 - math.exp(-input_smoothing * delta_time)
	self.body_camera_mouse_delta = self.body_camera_mouse_delta:Lerp(mouse_delta, input_alpha)
	local smoothed_mouse_delta = self.body_camera_mouse_delta
	local hip_weight = 1 - math.clamp(aim_alpha, 0, 1)
	local follow_weight = hip_weight
		+ math.clamp(aim_alpha, 0, 1) * (self.config.body_camera_ads_weapon_follow or 0.85)
	local side_limit = self.config.body_camera_weapon_side_limit or 0.11
	local lift_limit = self.config.body_camera_weapon_lift_limit or 0.06
	local pitch_limit = math.rad(self.config.body_camera_weapon_pitch_limit or 7)
	local yaw_limit = math.rad(self.config.body_camera_weapon_yaw_limit or 8)
	local roll_limit = math.rad(self.config.body_camera_weapon_roll_limit or 4.5)
	local target = Vector3.new(
		math.clamp(-smoothed_mouse_delta.X * (self.config.body_camera_weapon_side_response or 0.0012), -side_limit, side_limit),
		math.clamp(smoothed_mouse_delta.Y * (self.config.body_camera_weapon_lift_response or 0.00085), -lift_limit, lift_limit),
		0
	) * follow_weight
	local rotation_target = Vector3.new(
		math.clamp(-smoothed_mouse_delta.Y * (self.config.body_camera_weapon_pitch_response or 0.006), -pitch_limit, pitch_limit),
		math.clamp(-smoothed_mouse_delta.X * (self.config.body_camera_weapon_yaw_response or 0.0065), -yaw_limit, yaw_limit),
		math.clamp(-smoothed_mouse_delta.X * (self.config.body_camera_weapon_roll_response or 0.0035), -roll_limit, roll_limit)
	) * follow_weight
	self.body_camera_deadzone, self.body_camera_deadzone_velocity = GunMotionMath.update_spring(
		self.body_camera_deadzone,
		self.body_camera_deadzone_velocity,
		target,
		self.config.body_camera_weapon_frequency or 4.2,
		self.config.body_camera_weapon_damping or 0.7,
		delta_time,
		self.config.body_camera_weapon_limit or 0.18
	)
	self.body_camera_weapon_rotation, self.body_camera_weapon_rotation_velocity = GunMotionMath.update_spring(
		self.body_camera_weapon_rotation,
		self.body_camera_weapon_rotation_velocity,
		rotation_target,
		self.config.body_camera_weapon_rotation_frequency or 18,
		self.config.body_camera_weapon_rotation_damping or 0.82,
		delta_time,
		math.rad(self.config.body_camera_weapon_rotation_limit or 12)
	)
	local target_pitch = self.body_camera_target_pitch
	local current_pitch = self.body_camera_pitch
	local target_yaw = self.body_camera_target_yaw
	local current_yaw = self.body_camera_yaw
	local look_ahead = CFrame.identity
	if target_pitch and current_pitch and target_yaw and current_yaw then
		local lead_strength = self.config.body_camera_viewmodel_look_ahead or 0.72
		local ads_multiplier = self.config.body_camera_ads_look_ahead_multiplier or 0.35
		local lead_weight = lead_strength * ((1 - aim_alpha) + aim_alpha * ads_multiplier)
		local lead_limit = math.rad(self.config.body_camera_viewmodel_look_ahead_limit or 8)
		local pitch_lead = math.clamp((target_pitch - current_pitch) * lead_weight, -lead_limit, lead_limit)
		local yaw_error = math.atan2(math.sin(target_yaw - current_yaw), math.cos(target_yaw - current_yaw))
		local yaw_lead = math.clamp(yaw_error * lead_weight, -lead_limit, lead_limit)
		look_ahead = CFrame.Angles(pitch_lead, yaw_lead, 0)
	end
	return CFrame.new(self.body_camera_deadzone.X, self.body_camera_deadzone.Y, 0)
		* look_ahead
		* CFrame.Angles(
			self.body_camera_weapon_rotation.X,
			self.body_camera_weapon_rotation.Y,
			self.body_camera_weapon_rotation.Z
		)
end

function GunBodyCameraViewmodel.apply_camera_offset(self)
	local movement_state = self.movement_state
	if not movement_state then
		return
	end
	movement_state.body_camera_offset = Vector3.zero
	if self.config.body_camera_enabled ~= false then
		return
	end
	local humanoid = movement_state.humanoid
	if not humanoid then
		return
	end
	local crouch_offset = movement_state.crouching and MovementConfig.CROUCH_CAMERA_OFFSET or Vector3.zero
	humanoid.CameraOffset = (movement_state.base_camera_offset or Vector3.zero) + crouch_offset
end

function GunBodyCameraViewmodel.get_viewmodel_offset(self, aim_alpha: number): CFrame
	if self.config.body_camera_enabled == false then
		return CFrame.identity
	end
	local hip_offset = self.config.body_camera_viewmodel_offset or Vector3.zero
	local ads_offset = self.config.body_camera_ads_viewmodel_offset or hip_offset
	local ads_rotation = self.config.body_camera_ads_rotation or Vector3.zero
	return CFrame.new(hip_offset:Lerp(ads_offset, aim_alpha))
		* CFrame.Angles(
			math.rad(ads_rotation.X * aim_alpha),
			math.rad(ads_rotation.Y * aim_alpha),
			math.rad(ads_rotation.Z * aim_alpha)
		)
end

local function get_laser_dot(self): BasePart
	if self.laser_dot and self.laser_dot.Parent then
		return self.laser_dot
	end
	local dot = Instance.new("Part")
	dot.Name = "LaserDot"
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.new(0.08, 0.08, 0.08)
	dot.Material = Enum.Material.Neon
	dot.Color = self.config.body_camera_laser_color or Color3.fromRGB(255, 35, 35)
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanTouch = false
	dot.CanQuery = false
	dot.CastShadow = false
	dot.Parent = workspace.CurrentCamera
	self.laser_dot = dot
	return dot
end

function GunBodyCameraViewmodel.update_laser_dot(self)
	if self.config.body_camera_laser_enabled == false or not self.gun_model then
		if self.laser_dot then
			self.laser_dot.Transparency = 1
		end
		return
	end
	local muzzle_cframe = GunFireController.get_muzzle_cframe(self.gun_model)
	if not muzzle_cframe then
		return
	end
	local direction = GunFireController.get_preview_direction(self, muzzle_cframe)
	local excluded = { self.viewmodel }
	if local_player.Character then
		table.insert(excluded, local_player.Character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true
	local max_distance = self.config.max_distance or 650
	local result = workspace:Raycast(muzzle_cframe.Position, direction * max_distance, params)
	local position = result and result.Position or muzzle_cframe.Position + direction * max_distance
	local viewport_point = self.camera:WorldToViewportPoint(position)
	self.laser_dot_screen_position = if viewport_point.Z > 0
		then Vector2.new(viewport_point.X, viewport_point.Y)
		else nil
	local dot = get_laser_dot(self)
	dot.Transparency = self.config.body_camera_laser_transparency or 0.1
	dot.Size = Vector3.one * (self.config.body_camera_laser_size or 0.08)
	dot.CFrame = CFrame.new(position)
end

function GunBodyCameraViewmodel.use_ads(self): boolean
	return self.config.body_camera_enabled ~= false and self.config.body_camera_ads_lock == false
end

return GunBodyCameraViewmodel

