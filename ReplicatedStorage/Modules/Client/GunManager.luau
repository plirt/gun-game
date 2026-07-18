local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttachmentEffects = require(ReplicatedStorage.Modules.Shared.AttachmentEffects)
local AttachmentModifier = require(ReplicatedStorage.Modules.Client.AttachmentModifier)
local GunAimController = require(ReplicatedStorage.Modules.Client.GunAimController)
local GunAnimationController = require(ReplicatedStorage.Modules.Client.GunAnimationController)
local GunEquipController = require(ReplicatedStorage.Modules.Client.GunEquipController)
local GunFireController = require(ReplicatedStorage.Modules.Client.GunFireController)
local GunFrameController = require(ReplicatedStorage.Modules.Client.gun_frame_controller)
local GunMotionState = require(ReplicatedStorage.Modules.Client.GunMotionState)
local GunRecoilController = require(ReplicatedStorage.Modules.Client.GunRecoilController)
local GunReloadController = require(ReplicatedStorage.Modules.Client.GunReloadController)
local GunStateMachine = require(ReplicatedStorage.Modules.Client.GunStateMachine)
local GunViewmodelBuilder = require(ReplicatedStorage.Modules.Client.gun_viewmodel_builder)
local WeaponConfig = require(ReplicatedStorage.Modules.Shared.WeaponConfig)
local WeaponMath = require(ReplicatedStorage.Modules.Shared.WeaponMath)


local gun_manager = {}
gun_manager.__index = gun_manager

function gun_manager.new(gun_name, attachments, options)
	options = options or {}
	local camera = workspace.CurrentCamera
	assert(camera, "GunManager needs workspace.CurrentCamera")

	local viewmodel_template = ReplicatedStorage:WaitForChild("Viewmodel")
	local gun_template = ReplicatedStorage:WaitForChild("Guns"):WaitForChild(gun_name)
	local config_module = ReplicatedStorage:WaitForChild("GunConfigs"):WaitForChild(gun_name)
	local base_config = WeaponConfig.normalize(require(config_module))

	local viewmodel = viewmodel_template:Clone()
	local gun_model = gun_template:Clone()

	local managed_marker = Instance.new("BoolValue")
	managed_marker.Name = "ManagedByGunManager"
	managed_marker.Value = true
	managed_marker.Parent = viewmodel
	GunViewmodelBuilder.write_string_value(viewmodel, "GunName", gun_name)
	gun_model.Name = gun_name
	gun_model.Parent = viewmodel

	local supported_attachments = GunViewmodelBuilder.get_supported_attachments(gun_model, attachments)
	local config = AttachmentEffects.apply(base_config, supported_attachments)

	GunViewmodelBuilder.weld(viewmodel)
	GunViewmodelBuilder.attach_gun(gun_model, viewmodel.HumanoidRootPart, config)

	local self = setmetatable({}, gun_manager)

	self.gun_name = gun_name
	self.render_step_name = "GunManager_" .. gun_name .. "_" .. HttpService:GenerateGUID(false)
	self.viewmodel = viewmodel
	self.gun_model = gun_model
	self.camera = camera
	self.camera_anchor = viewmodel:FindFirstChild("CameraBone") or viewmodel:FindFirstChild("CameraPart")
	local viewmodel_root = viewmodel.HumanoidRootPart
	local right_arm_motor = viewmodel_root:FindFirstChild("Right Arm")
	local left_arm_motor = viewmodel_root:FindFirstChild("Left Arm")
	self.right_arm_motor = right_arm_motor and right_arm_motor:IsA("Motor6D") and right_arm_motor or nil
	self.left_arm_motor = left_arm_motor and left_arm_motor:IsA("Motor6D") and left_arm_motor or nil
	self.right_arm_base_c0 = self.right_arm_motor and self.right_arm_motor.C0 or CFrame.identity
	self.left_arm_base_c0 = self.left_arm_motor and self.left_arm_motor.C0 or CFrame.identity
	self.ads_point = GunViewmodelBuilder.find_ads_point(gun_model)
	self.sight_part = GunViewmodelBuilder.find_sight_part(gun_model)
	self.base_config = base_config
	self.config = config
	self.attachments = table.clone(supported_attachments)
	self.movement_state = options.movement_state
	self.random = Random.new()
	self.animation_tracks = {}
	self.idle_track = nil
	self.ads_track = nil

	self.equipped = false
	self.equipping = false
	self.unequipping = false
	self.aiming = false
	self.reloading = false
	self.weapon_state = "idle"
	self.last_fire_time = 0
	self.magazine = config.magazine_size
	self.reserve = config.reserve_ammo
	self.spread_heat = 0
	self.aim_alpha = 0
	self.aim_velocity = 0
	self.procedural_time = 0
	self.procedural_move_alpha = 0
	self.camera_move_alpha = 0

	GunMotionState.reset(self)
	self.last_recoil_time = 0
	self.last_camera_cframe = camera.CFrame

	self.trigger_held = false
	self.equipping = false
	self.unequipping = false
	self.unequip_started_at = 0
	self.unequip_token = 0
	self.render_bound = false
	self.equip_token = 0
	self.reload_token = 0
	self.next_aim_report_time = 0
	self.last_aim_reported = false

	self:preload_animations()
	return self
end

function gun_manager:sync_attachment_effects()
	self.attachments = GunViewmodelBuilder.get_supported_attachments(self.gun_model, self.attachments)
	self.config = AttachmentEffects.apply(self.base_config, self.attachments)
end

function gun_manager:sync_attachments()
	self:sync_attachment_effects()
	AttachmentModifier.clear_all(self.gun_model)
	AttachmentModifier.apply_loadout(self.gun_model, self.attachments)
	self.ads_point = GunViewmodelBuilder.find_ads_point(self.gun_model)
	self.sight_part = GunViewmodelBuilder.find_sight_part(self.gun_model)
	self.ads_alignment_position = nil
end

function gun_manager:set_attachment(attachment_type, attachment_name)
	if not AttachmentModifier.can_attach(self.gun_model, attachment_name) then
		return false
	end
	self.attachments[attachment_type] = attachment_name
	self:sync_attachment_effects()
	if self.equipped then
		self:sync_attachments()
	end
	return true
end

function gun_manager:remove_attachment(attachment_type)
	self.attachments[attachment_type] = nil
	self:sync_attachment_effects()
	if self.equipped then
		self:sync_attachments()
	end
end

function gun_manager:get_attachments()
	return table.clone(self.attachments)
end

function gun_manager:get_status()
	return {
		equipped = self.equipped,
		aiming = self.aiming,
		reloading = self.reloading,
		magazine = self.magazine,
		reserve = self.reserve,
		gun_name = self.gun_name,
	}
end

function gun_manager:get_animation_track(animation_name)
	if self.animation_tracks[animation_name] then
		return self.animation_tracks[animation_name]
	end

	local animation = GunAnimationController.find(self.viewmodel, animation_name)
	local track = GunAnimationController.load(self.viewmodel, animation)
	if track then
		self.animation_tracks[animation_name] = track
	end
	return track
end

function gun_manager:play_animation(animation_name, fade_time, speed, looped)
	local track = self:get_animation_track(animation_name)
	if not track then
		return nil
	end

	track.Looped = looped == true
	if track.IsPlaying then
		track:Stop(0)
	end
	track.TimePosition = 0
	track:Play(fade_time or self.config.animation_fade_time or 0.12, 1, speed or 1)
	return track
end

function gun_manager:stop_animation(animation_name, fade_time)
	local track = self.animation_tracks[animation_name]
	if track and track.IsPlaying then
		track:Stop(fade_time or self.config.animation_fade_time or 0.12)
	end
end

function gun_manager:resume_idle(fade_time)
	if not self.equipped or self.unequipping then
		return nil
	end

	self.idle_track = self:get_animation_track("Idle")
	if not self.idle_track then
		return nil
	end

	self.idle_track.Looped = true
	if not self.idle_track.IsPlaying then
		self.idle_track:Play(fade_time or self.config.idle_resume_fade_time or self.config.idle_fade_time or 0.15, 1, self.config.idle_speed or 1)
	else
		self.idle_track:AdjustWeight(1, fade_time or self.config.idle_resume_fade_time or 0.15)
	end
	return self.idle_track
end

function gun_manager:preload_animations()
	local original_parent = self.viewmodel.Parent
	local temporary_parent = nil
	local hidden_parts = nil

	if not self.viewmodel:IsDescendantOf(workspace) then
		temporary_parent = self.camera or workspace.CurrentCamera or workspace
		hidden_parts = {}
		for _, descendant in self.viewmodel:GetDescendants() do
			if descendant:IsA("BasePart") then
				hidden_parts[descendant] = descendant.LocalTransparencyModifier
				descendant.LocalTransparencyModifier = 1
			end
		end
		self.viewmodel.Parent = temporary_parent
	end

	GunAnimationController.preload_assets(self.viewmodel)

	for _, animation in GunAnimationController.collect(self.viewmodel) do
		if not self.animation_tracks[animation.Name] then
			local track = GunAnimationController.load(self.viewmodel, animation)
			if track then
				self.animation_tracks[animation.Name] = track
			end
		end
	end

	local equip_track = self.animation_tracks.Equip
	if equip_track then
		equip_track.Looped = false
		equip_track:Play(0, 1, self.config.equip_speed or 1)
		equip_track:AdjustWeight(1, 0)
		RunService.Heartbeat:Wait()
		equip_track:Stop(0)
		equip_track.TimePosition = 0
	end

	if hidden_parts then
		for part, local_transparency in hidden_parts do
			if part.Parent then
				part.LocalTransparencyModifier = local_transparency
			end
		end
	end

	if temporary_parent then
		self.viewmodel.Parent = original_parent
	end
end

function gun_manager:is_action_ready()
	return self.equipped and not self.equipping and not self.unequipping and not GunStateMachine.is_busy(self)
end

function gun_manager:add_recoil()
	GunRecoilController.add_recoil(self)
end

function gun_manager:report_aim_state(force)
	GunAimController.report(self, force)
end

function gun_manager:set_aiming(value)
	GunAimController.set_aiming(self, value)
end

function gun_manager:update(delta_time)
	GunFrameController.update(self, delta_time)
end

local function get_equip_deps()
	return {
		cleanup_camera_viewmodels = GunViewmodelBuilder.cleanup_camera_viewmodels,
		set_viewmodel_hidden = GunViewmodelBuilder.set_hidden,
		restore_viewmodel_visibility = GunViewmodelBuilder.restore_visibility,
		reset_motion_state = GunMotionState.reset,
	}
end

function gun_manager.cleanup_camera_viewmodels(keep_viewmodel)
	GunViewmodelBuilder.cleanup_camera_viewmodels(workspace.CurrentCamera, keep_viewmodel)
end

function gun_manager:equip()
	return GunEquipController.equip(self, get_equip_deps())
end

function gun_manager:finish_unequip()
	GunEquipController.finish_unequip(self, get_equip_deps())
end

function gun_manager:unequip()
	return GunEquipController.unequip(self, get_equip_deps())
end

function gun_manager:destroy()
	GunEquipController.destroy(self)
end
return gun_manager
