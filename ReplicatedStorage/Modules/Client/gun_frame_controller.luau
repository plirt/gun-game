local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BodyCameraMotion = require(ReplicatedStorage.Modules.Client.BodyCameraMotion)
local GunFireController = require(ReplicatedStorage.Modules.Client.GunFireController)
local GunMotionMath = require(ReplicatedStorage.Modules.Client.gun_motion_math)
local GunMotionState = require(ReplicatedStorage.Modules.Client.GunMotionState)
local GunReticleController = require(ReplicatedStorage.Modules.Client.GunReticleController)
local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)
local GunViewmodelMotion = require(ReplicatedStorage.Modules.Client.GunViewmodelMotion)

local gun_frame_controller = {}

local local_player = Players.LocalPlayer

local function get_anchor_pivot(viewmodel, anchor, target_cframe)
	if not anchor or not anchor:IsA("BasePart") then
		return target_cframe
	end
	return target_cframe * anchor.CFrame:ToObjectSpace(viewmodel:GetPivot())
end

local function get_tip_pivot_recoil(viewmodel, gun_model, rotation, multiplier)
	if not multiplier or multiplier <= 0 or rotation.Magnitude <= 0 then
		return CFrame.identity
	end
	local muzzle_cframe = GunFireController.get_muzzle_cframe(gun_model)
	if not muzzle_cframe then
		return CFrame.identity
	end
	local pivot = viewmodel:GetPivot()
	local local_tip_position = pivot:PointToObjectSpace(muzzle_cframe.Position)
	local pitch_multiplier = multiplier * 1.45
	local side_multiplier = multiplier * 0.18
	local tip_rotation = CFrame.Angles(
		rotation.X * pitch_multiplier,
		rotation.Y * side_multiplier,
		rotation.Z * side_multiplier
	)
	return CFrame.new(local_tip_position) * tip_rotation * CFrame.new(-local_tip_position)
end

local function apply_arm_recoil(self, rotation)
	local aim_multiplier = self.aiming and (self.config.recoil_arm_ads_multiplier or 0.6) or 1
	local pitch = rotation.X * (self.config.recoil_arm_pitch_multiplier or 0.5) * aim_multiplier
	local yaw = rotation.Y * (self.config.recoil_arm_yaw_multiplier or 0.35) * aim_multiplier
	local roll = rotation.Z * (self.config.recoil_arm_roll_multiplier or 0.45) * aim_multiplier
	if self.right_arm_motor and self.right_arm_motor.Parent then
		self.right_arm_motor.C0 = self.right_arm_base_c0 * CFrame.Angles(pitch, yaw, roll)
	end
	if self.left_arm_motor and self.left_arm_motor.Parent then
		local support_multiplier = self.config.recoil_support_arm_multiplier or 0.78
		self.left_arm_motor.C0 = self.left_arm_base_c0 * CFrame.Angles(
			pitch * support_multiplier,
			yaw * support_multiplier,
			roll * support_multiplier
		)
	end
end

local function get_body_camera_deadzone(self, mouse_delta, delta_time, aim_alpha)
	if self.config.body_camera_enabled == false then
		self.body_camera_deadzone = Vector3.zero
		self.body_camera_deadzone_velocity = Vector3.zero
		self.body_camera_mouse_delta = Vector2.zero
		return CFrame.identity
	end
	local input_smoothing = self.config.body_camera_weapon_input_smoothing or 16
	local input_alpha = 1 - math.exp(-input_smoothing * delta_time)
	self.body_camera_mouse_delta = self.body_camera_mouse_delta:Lerp(mouse_delta, input_alpha)
	local smoothed_mouse_delta = self.body_camera_mouse_delta
	local hip_weight = 1 - math.clamp(aim_alpha, 0, 1)
	local follow_weight = hip_weight + math.clamp(aim_alpha, 0, 1) * (self.config.body_camera_ads_weapon_follow or 0.85)
	local side = math.clamp(
		-smoothed_mouse_delta.X * (self.config.body_camera_weapon_side_response or 0.0012),
		-(self.config.body_camera_weapon_side_limit or 0.11),
		self.config.body_camera_weapon_side_limit or 0.11
	)
	local lift = math.clamp(
		smoothed_mouse_delta.Y * (self.config.body_camera_weapon_lift_response or 0.00085),
		-(self.config.body_camera_weapon_lift_limit or 0.06),
		self.config.body_camera_weapon_lift_limit or 0.06
	)
	local pitch = math.clamp(
		-smoothed_mouse_delta.Y * (self.config.body_camera_weapon_pitch_response or 0.006),
		-math.rad(self.config.body_camera_weapon_pitch_limit or 7),
		math.rad(self.config.body_camera_weapon_pitch_limit or 7)
	)
	local yaw = math.clamp(
		-smoothed_mouse_delta.X * (self.config.body_camera_weapon_yaw_response or 0.0065),
		-math.rad(self.config.body_camera_weapon_yaw_limit or 8),
		math.rad(self.config.body_camera_weapon_yaw_limit or 8)
	)
	local roll = math.clamp(
		-smoothed_mouse_delta.X * (self.config.body_camera_weapon_roll_response or 0.0035),
		-math.rad(self.config.body_camera_weapon_roll_limit or 4.5),
		math.rad(self.config.body_camera_weapon_roll_limit or 4.5)
	)
	local target = Vector3.new(side, lift, 0) * follow_weight
	local rotation_target = Vector3.new(pitch, yaw, roll) * follow_weight
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
	return CFrame.new(self.body_camera_deadzone.X, self.body_camera_deadzone.Y, 0) * CFrame.Angles(
		self.body_camera_weapon_rotation.X,
		self.body_camera_weapon_rotation.Y,
		self.body_camera_weapon_rotation.Z
	)
end

local function apply_body_camera_offset(self)
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

local function get_body_camera_viewmodel_offset(self, aim_alpha)
	if self.config.body_camera_enabled == false then
		return CFrame.identity
	end
	local hip_offset = self.config.body_camera_viewmodel_offset or Vector3.zero
	local ads_offset = self.config.body_camera_ads_viewmodel_offset or hip_offset
	local ads_rotation = self.config.body_camera_ads_rotation or Vector3.zero
	return CFrame.new(hip_offset:Lerp(ads_offset, aim_alpha)) * CFrame.Angles(
		math.rad(ads_rotation.X * aim_alpha),
		math.rad(ads_rotation.Y * aim_alpha),
		math.rad(ads_rotation.Z * aim_alpha)
	)
end

local function get_laser_dot(self)
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

local function update_laser_dot(self)
	if self.config.body_camera_laser_enabled == false or not self.gun_model then
		if self.laser_dot then
			self.laser_dot.Transparency = 1
		end
		return
	end
	local muzzle_cframe = GunFireController.get_muzzle_cframe(self.gun_model)
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
	if viewport_point.Z > 0 then
		self.laser_dot_screen_position = Vector2.new(viewport_point.X, viewport_point.Y)
	else
		self.laser_dot_screen_position = nil
	end
	local dot = get_laser_dot(self)
	dot.Transparency = self.config.body_camera_laser_transparency or 0.1
	dot.Size = Vector3.one * (self.config.body_camera_laser_size or 0.08)
	dot.CFrame = CFrame.new(position)
end

local function use_body_camera_ads(self)
	return self.config.body_camera_enabled ~= false and self.config.body_camera_ads_lock == false
end

local function cleanup_duplicate_camera_viewmodels(self)
	for _, child in self.camera:GetChildren() do
		if child:IsA("Model") and child ~= self.viewmodel and (child.Name == "Viewmodel" or child:FindFirstChild("ManagedByGunManager")) then
			child:SetAttribute("destroyed", true)
			child:Destroy()
		end
	end
end

function gun_frame_controller.update(self, delta_time)
	self.camera = workspace.CurrentCamera
	if not self.camera then
		return
	end
	if self.camera:GetAttribute("ActiveGunManager") ~= self.active_camera_owner then
		if self.viewmodel and self.viewmodel.Parent == self.camera then
			self.viewmodel.Parent = nil
		end
		if self.render_bound then
			RunService:UnbindFromRenderStep(self.render_step_name)
			self.render_bound = false
		end
		return
	end
	cleanup_duplicate_camera_viewmodels(self)
	self.spread_heat = math.max(0, self.spread_heat - self.config.spread_recovery * delta_time)
	GunMotionState.ensure(self)
	self.procedural_time = (self.procedural_time or 0) + delta_time
	local mouse_delta = UserInputService:GetMouseDelta()
	local camera_cframe = self.camera.CFrame * self.camera_effect_cframe:Inverse()
	camera_cframe = BodyCameraMotion.update(
		self,
		self.config,
		self.movement_state,
		camera_cframe,
		mouse_delta,
		delta_time
	)
	local camera_delta = GunMotionMath.get_camera_delta(self.last_camera_cframe, camera_cframe)
	local look_y_delta = camera_cframe.LookVector.Y - self.last_camera_cframe.LookVector.Y
	local has_manual_camera_input = mouse_delta.Magnitude > (self.config.recoil_manual_pull_deadzone or 0.35)
	if has_manual_camera_input and look_y_delta < 0 and self.camera_recoil_rotation.X > 0 then
		local pull_down_amount = math.min(
			self.camera_recoil_rotation.X,
			math.abs(look_y_delta) * (self.config.recoil_manual_pull_strength or 1.15)
		)
		self.camera_recoil_rotation = Vector3.new(
			self.camera_recoil_rotation.X - pull_down_amount,
			self.camera_recoil_rotation.Y,
			self.camera_recoil_rotation.Z
		)
	end
	self.camera_recoil_yaw_queued = 0
	self.last_camera_cframe = camera_cframe
	local recoil_rise_alpha = math.clamp(delta_time * (self.config.recoil_rise_speed or 18), 0, 1)
	local recoil_apply_alpha = 1 - math.pow(1 - recoil_rise_alpha, 2.35)
	local viewmodel_position_step = self.viewmodel_recoil_position_queued * recoil_apply_alpha
	local viewmodel_rotation_step = self.viewmodel_recoil_rotation_queued * recoil_apply_alpha
	self.viewmodel_recoil_position += viewmodel_position_step
	self.viewmodel_recoil_position_queued -= viewmodel_position_step
	self.viewmodel_recoil_rotation += viewmodel_rotation_step
	self.viewmodel_recoil_rotation_queued -= viewmodel_rotation_step
	local camera_recoil_max_angle = math.rad(self.config.recoil_camera_max_angle or 2)
	self.camera_recoil_rotation, self.camera_recoil_velocity = GunMotionMath.update_spring(
		self.camera_recoil_rotation,
		self.camera_recoil_velocity,
		Vector3.zero,
		self.config.recoil_camera_recovery_frequency or 8,
		self.config.recoil_camera_recovery_damping or 0.82,
		delta_time,
		camera_recoil_max_angle
	)
	if self.camera_recoil_rotation.X > camera_recoil_max_angle then
		self.camera_recoil_rotation = Vector3.new(
			camera_recoil_max_angle,
			self.camera_recoil_rotation.Y,
			self.camera_recoil_rotation.Z
		)
	end
	self.camera_recoil_rotation = GunMotionMath.clamp_vector(self.camera_recoil_rotation, camera_recoil_max_angle)
	self.viewmodel_recoil_position = GunMotionMath.clamp_vector(self.viewmodel_recoil_position, self.config.recoil_viewmodel_max_offset or 0.45)
	self.viewmodel_recoil_rotation = GunMotionMath.clamp_vector(self.viewmodel_recoil_rotation, math.rad(self.config.recoil_viewmodel_max_angle or 14))
	local recoil_still_applying =
		self.viewmodel_recoil_position_queued.Magnitude > 0.025
		or self.viewmodel_recoil_rotation_queued.Magnitude > 0.0025
		or math.abs(self.camera_recoil_yaw_queued or 0) > 0.001
	local recoil_settled = GunMotionState.is_recoil_settled(self)
	if recoil_settled then
		self.gun_rotation_kick, self.gun_rotation_kick_velocity = GunMotionMath.update_spring(
			self.gun_rotation_kick,
			self.gun_rotation_kick_velocity,
			Vector3.zero,
			self.config.recoil_gun_rotation_kick_recovery_frequency or 10,
			self.config.recoil_gun_rotation_kick_recovery_damping or 0.7,
			delta_time,
			math.rad(self.config.recoil_gun_rotation_kick_max_angle or 1.25)
		)
	else
		self.gun_rotation_kick_velocity = Vector3.zero
	end
	if not recoil_still_applying then
		self.viewmodel_recoil_rotation, self.viewmodel_recoil_rotation_velocity = GunMotionMath.update_spring(
			self.viewmodel_recoil_rotation,
			self.viewmodel_recoil_rotation_velocity,
			Vector3.zero,
			self.config.recoil_viewmodel_recovery_frequency or 6.5,
			self.config.recoil_viewmodel_recovery_damping or 0.58,
			delta_time,
			math.rad(self.config.recoil_viewmodel_max_angle or 14)
		)
		self.viewmodel_recoil_position, self.viewmodel_recoil_position_velocity = GunMotionMath.update_spring(
			self.viewmodel_recoil_position,
			self.viewmodel_recoil_position_velocity,
			Vector3.zero,
			self.config.recoil_viewmodel_position_recovery_frequency or 7.5,
			self.config.recoil_viewmodel_position_recovery_damping or 0.62,
			delta_time,
			self.config.recoil_viewmodel_max_offset or 0.45
		)
		self.arms_push_out, self.arms_push_out_velocity = GunMotionMath.update_number_spring(
			self.arms_push_out,
			self.arms_push_out_velocity,
			0,
			self.config.recoil_arms_recovery_frequency or 8,
			self.config.recoil_arms_recovery_damping or 0.6,
			delta_time,
			0,
			self.config.recoil_arms_push_out_max or 0.18
		)
	else
		self.viewmodel_recoil_rotation_velocity = Vector3.zero
		self.viewmodel_recoil_position_velocity = Vector3.zero
		self.arms_push_out_velocity = 0
	end
	self.viewmodel_recoil_position_velocity = Vector3.zero
	self.arms_push_out_velocity = 0
	self.screen_shake_rotation, self.screen_shake_velocity = GunMotionMath.update_spring(
		self.screen_shake_rotation,
		self.screen_shake_velocity,
		Vector3.zero,
		self.config.screen_shake_frequency or 16,
		self.config.screen_shake_damping or 0.78,
		delta_time,
		math.rad(self.config.screen_shake_max_angle or 1.2)
	)
	if self.screen_shake_rotation.Magnitude < math.rad(0.015) and self.screen_shake_velocity.Magnitude < math.rad(0.08) then
		self.screen_shake_rotation = Vector3.zero
		self.screen_shake_velocity = Vector3.zero
	end
	if self.camera_recoil_rotation.Magnitude < math.rad(0.015) and self.camera_recoil_velocity.Magnitude < math.rad(0.08) then
		self.camera_recoil_rotation = Vector3.zero
		self.camera_recoil_velocity = Vector3.zero
	end
	local visible_aim_for_effects = math.clamp(self.aim_alpha or 0, 0, 1)
	apply_body_camera_offset(self)
	local movement_camera_motion = GunViewmodelMotion.get_camera_motion(
		self.config,
		self,
		delta_time,
		visible_aim_for_effects
	)
	self.camera_effect_cframe = movement_camera_motion * CFrame.Angles(
		self.camera_recoil_rotation.X + self.screen_shake_rotation.X,
		self.camera_recoil_rotation.Y + self.screen_shake_rotation.Y,
		self.camera_recoil_rotation.Z + self.screen_shake_rotation.Z
	)
	self.camera.CFrame = camera_cframe * self.camera_effect_cframe
	camera_cframe = self.camera.CFrame
	self.arms_push_out = math.clamp(self.arms_push_out, 0, self.config.recoil_arms_push_out_max or 0.18)
	local aim_target = self.aiming and 1 or 0
	self.aim_alpha, self.aim_velocity = GunMotionMath.update_spring(
		self.aim_alpha,
		self.aim_velocity,
		aim_target,
		self.config.aim_spring_frequency or self.config.aim_speed or 2,
		self.config.aim_spring_damping or 0.96,
		delta_time
	)
	self.aim_alpha = math.clamp(self.aim_alpha, -0.18, 1.18)
	if math.abs(aim_target - self.aim_alpha) < 0.001 and math.abs(self.aim_velocity) < 0.001 then
		self.aim_alpha = aim_target
		self.aim_velocity = 0
	end
	local visible_aim_alpha = math.clamp(self.aim_alpha, 0, 1)
	local aim_curve = GunMotionMath.smoothstep(visible_aim_alpha)
	local aim_path_curve = GunMotionMath.smootherstep(visible_aim_alpha)
	local target_fov = self.config.aim_fov
	local sight_data = GunReticleController.get_sight_data(self)
	if self.aiming and sight_data then
		target_fov = self.config.default_fov / sight_data.zoom
	end
	self.recoil_fov_offset, self.recoil_fov_velocity = GunMotionMath.update_number_spring(
		self.recoil_fov_offset,
		self.recoil_fov_velocity,
		0,
		self.config.recoil_fov_recovery_frequency or 5,
		self.config.recoil_fov_recovery_damping or 0.82,
		delta_time,
		0,
		self.config.recoil_fov_max or 9
	)
	if self.recoil_fov_offset < 0.01 and math.abs(self.recoil_fov_velocity) < 0.05 then
		self.recoil_fov_offset = 0
		self.recoil_fov_velocity = 0
	end
	self.camera.FieldOfView = self.config.default_fov
		+ (target_fov - self.config.default_fov) * aim_curve
		+ self.recoil_fov_offset
	local ads_sway_stability = self.config.ads_sway_stability or 0.05
	local sway_multiplier = ads_sway_stability + (1 - ads_sway_stability) * (1 - aim_curve)
	local horizontal_sway_amount = self.config.sway_amount * (self.config.sway_horizontal_amount or 1)
	local hip_horizontal_sway = horizontal_sway_amount + (self.config.sway_amount - horizontal_sway_amount) * aim_curve
	local sway_x = math.clamp(-camera_delta.Y * self.config.sway_amount * sway_multiplier, -math.rad(self.config.sway_limit), math.rad(self.config.sway_limit))
	local sway_y = math.clamp(-camera_delta.X * hip_horizontal_sway * sway_multiplier, -math.rad(self.config.sway_limit), math.rad(self.config.sway_limit))
	self.sway_current = self.sway_current:Lerp(Vector2.new(sway_x, sway_y), math.clamp(delta_time * self.config.sway_speed, 0, 1))
	local view_offset = self.config.position_offset:Lerp(self.config.aim_position_offset, aim_curve)
	local position_offset = CFrame.new(view_offset) * get_body_camera_viewmodel_offset(self, aim_curve)
	local rotation_offset = CFrame.Angles(
		math.rad(self.config.rotation_offset.X),
		math.rad(self.config.rotation_offset.Y),
		math.rad(self.config.rotation_offset.Z)
	)
	local sway = CFrame.Angles(self.sway_current.X, self.sway_current.Y, 0)
	local procedural = GunViewmodelMotion.get_procedural_motion(self.config, self, delta_time, aim_curve)
	local body_camera_deadzone = get_body_camera_deadzone(self, mouse_delta, delta_time, visible_aim_alpha)
	local viewmodel_camera_cframe = BodyCameraMotion.get_viewmodel_cframe(
		self,
		self.config,
		camera_cframe
	)
	local arms_push_out = CFrame.new(0, 0, -(self.arms_push_out or 0))
	local gun_visual_rotation = self.viewmodel_recoil_rotation + self.gun_rotation_kick
	apply_arm_recoil(self, gun_visual_rotation)
	local recoil_rotation_cframe = CFrame.Angles(
		gun_visual_rotation.X,
		gun_visual_rotation.Y,
		gun_visual_rotation.Z
	)
	local tip_pivot_recoil = get_tip_pivot_recoil(
		self.viewmodel,
		self.gun_model,
		gun_visual_rotation,
		self.config.recoil_tip_pivot_multiplier or 0.42
	)
	local viewmodel_recoil = tip_pivot_recoil * arms_push_out * CFrame.new(self.viewmodel_recoil_position) * recoil_rotation_cframe
	local unequip_motion = CFrame.identity
	if self.unequipping then
		unequip_motion = GunMotionMath.get_unequip_motion(self.config, os.clock() - (self.unequip_started_at or os.clock()))
	end
	local base_camera_part_cframe = viewmodel_camera_cframe
		* position_offset
		* rotation_offset
		* body_camera_deadzone
		* sway
		* procedural
		* unequip_motion
	if aim_curve > 0 and self.ads_point and use_body_camera_ads(self) then
		local ads_locked_motion = GunViewmodelMotion.get_ads_locked_motion(self.config, self, camera_delta, aim_curve)
		local target_camera_part_cframe = base_camera_part_cframe * ads_locked_motion * viewmodel_recoil
		local target_pivot = get_anchor_pivot(self.viewmodel, self.camera_anchor, target_camera_part_cframe)
		self.viewmodel:PivotTo(target_pivot)
	elseif aim_curve > 0 and self.ads_point then
		self.viewmodel:PivotTo(get_anchor_pivot(self.viewmodel, self.camera_anchor, base_camera_part_cframe))
		local ads_offset = self.config.ads_point_offset or CFrame.identity
		local raise_amount = math.sin(aim_path_curve * math.pi)
		local tuck_amount = math.sin(visible_aim_alpha * math.pi * 0.5)
		local aim_frequency = self.config.aim_spring_frequency or self.config.aim_speed or 2
		local settle_amount = math.clamp(self.aim_velocity / math.max(aim_frequency * 4, 1), -1, 1)
		local ads_curve_offset = CFrame.new(
			raise_amount * (self.config.aim_transition_side or -0.12),
			raise_amount * (self.config.aim_transition_lift or 0.06),
			-raise_amount * (self.config.aim_transition_push or 0.14) + tuck_amount * (self.config.aim_transition_pullback or 0.04)
		) * CFrame.Angles(
			math.rad(settle_amount * (self.config.aim_transition_pitch or 1.15)),
			math.rad(raise_amount * (self.config.aim_transition_yaw or -0.45)),
			math.rad(-settle_amount * (self.config.aim_transition_roll or 0.7))
		)
		local current_pivot = self.viewmodel:GetPivot()
		local ads_local_cframe = current_pivot:ToObjectSpace(self.ads_point.WorldCFrame)
		local ads_recoil_multiplier = self.config.recoil_ads_visual_multiplier or 0.25
		local ads_tip_pivot_multiplier = self.config.recoil_ads_tip_pivot_multiplier
			or ((self.config.recoil_tip_pivot_multiplier or 0.42) * 0.38)
		local ads_recoil_rotation = gun_visual_rotation * ads_recoil_multiplier
		local ads_tip_pivot_recoil = get_tip_pivot_recoil(
			self.viewmodel,
			self.gun_model,
			ads_recoil_rotation,
			ads_tip_pivot_multiplier
		)
		local ads_viewmodel_recoil =
			ads_tip_pivot_recoil
			* arms_push_out
			* CFrame.new(self.viewmodel_recoil_position * ads_recoil_multiplier)
			* CFrame.Angles(
				ads_recoil_rotation.X,
				ads_recoil_rotation.Y,
				ads_recoil_rotation.Z
			)
		local recoiled_pivot = current_pivot * ads_viewmodel_recoil
		local recoiled_ads_position = (recoiled_pivot * ads_local_cframe).Position
		local target_ads_cframe = camera_cframe * ads_offset * ads_curve_offset
		local ads_position_delta = target_ads_cframe.Position - recoiled_ads_position
		local corrected_pivot = recoiled_pivot + ads_position_delta
		local ads_locked_motion = GunViewmodelMotion.get_ads_locked_motion(self.config, self, camera_delta, aim_curve)
		corrected_pivot = target_ads_cframe * ads_locked_motion * target_ads_cframe:ToObjectSpace(corrected_pivot)
		local final_pivot = current_pivot:Lerp(corrected_pivot, aim_path_curve)
		self.viewmodel:PivotTo(final_pivot)
	elseif aim_curve > 0 and self.sight_part and self.sight_part:IsA("BasePart") and not use_body_camera_ads(self) then
		self.viewmodel:PivotTo(get_anchor_pivot(self.viewmodel, self.camera_anchor, base_camera_part_cframe))
		local sight_local = camera_cframe:PointToObjectSpace(self.sight_part.Position)
		local ads_y_offset = self.config.ads_sight_y_offset or 0
		local ads_correction = CFrame.new(-sight_local.X * aim_curve, (-sight_local.Y + ads_y_offset) * aim_curve, 0)
		local corrected_pivot = camera_cframe * ads_correction * camera_cframe:ToObjectSpace(self.viewmodel:GetPivot()) * viewmodel_recoil
		self.viewmodel:PivotTo(corrected_pivot)
	else
		self.ads_alignment_position = nil
		local target_camera_part_cframe = base_camera_part_cframe * viewmodel_recoil
		local target_pivot = get_anchor_pivot(self.viewmodel, self.camera_anchor, target_camera_part_cframe)
		self.viewmodel:PivotTo(target_pivot)
	end
	update_laser_dot(self)
	self:report_aim_state(false)
end

return gun_frame_controller
