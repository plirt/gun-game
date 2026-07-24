local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunStateMachine = require(ReplicatedStorage.Modules.Client.GunStateMachine)
local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)

local gun_equip_controller = {}

local function clear_character_visibility(manager)
	if manager.character_visibility_connection then
		manager.character_visibility_connection:Disconnect()
		manager.character_visibility_connection = nil
	end
	manager.hidden_character = nil
	manager.hidden_character_parts = nil
end

local function hide_local_character(manager)
	local character = Players.LocalPlayer.Character
	if not character then
		clear_character_visibility(manager)
		return
	end
	if manager.hidden_character ~= character then
		clear_character_visibility(manager)
		manager.hidden_character = character
		manager.hidden_character_parts = {}
		local function hide_part(instance)
			if instance:IsA("BasePart") then
				manager.hidden_character_parts[instance] = true
				instance.LocalTransparencyModifier = 1
			end
		end
		for _, descendant in character:GetDescendants() do
			hide_part(descendant)
		end
		manager.character_visibility_connection = character.DescendantAdded:Connect(hide_part)
	end
	for part in manager.hidden_character_parts do
		if part.Parent then
			part.LocalTransparencyModifier = 1
		else
			manager.hidden_character_parts[part] = nil
		end
	end
end

function gun_equip_controller.equip(manager, deps): boolean?
	local current_camera = workspace.CurrentCamera
	if manager.destroyed or not manager.viewmodel or manager.viewmodel:GetAttribute("destroyed") == true then
		return false
	end
	if manager.equipped then
		if manager.viewmodel.Parent ~= current_camera then
			manager.equipped = false
		else
			return true
		end
	end
	if manager.equipping then
		return false
	end
	manager.unequip_token += 1
	manager.equip_token += 1
	local equip_token = manager.equip_token
	GunStateMachine.set(manager, "equipping")
	manager.unequipping = false
	manager.equipping = true
	manager.equipped = true
	manager.camera = current_camera
	deps.reset_motion_state(manager)
	manager.previous_camera_type = manager.previous_camera_type or current_camera.CameraType
	if manager.config.body_camera_enabled ~= false then
		current_camera.CameraType = Enum.CameraType.Scriptable
		hide_local_character(manager)
	end
	manager.last_camera_cframe = manager.camera.CFrame
	manager.body_camera_cframe = manager.camera.CFrame
	manager.body_camera_yaw = nil
	manager.body_camera_pitch = nil
	manager.body_camera_target_yaw = nil
	manager.body_camera_target_pitch = nil
	manager.body_camera_position = nil
	deps.cleanup_camera_viewmodels(manager.camera, manager.viewmodel)
	for _, child in current_camera:GetChildren() do
		if child:IsA("Model") and child ~= manager.viewmodel and child:FindFirstChild("ManagedByGunManager") then
			child:SetAttribute("destroyed", true)
			child:Destroy()
		end
	end
	current_camera:SetAttribute("ActiveGunManager", manager.render_step_name)
	manager.active_camera_owner = manager.render_step_name
	local hidden_parts = deps.set_viewmodel_hidden(manager.viewmodel, true)
	manager.viewmodel.Parent = manager.camera
	manager.idle_track = manager:resume_idle(0)
	local equip_speed = manager.config.equip_speed or 1
	local equip_track = manager:play_animation("Equip", 0, equip_speed, false)
	manager:update(1 / 60)
	manager:sync_attachments()
	manager:update(1 / 60)
	task.spawn(function()
		RunService.RenderStepped:Wait()
		if equip_track then
			RunService.RenderStepped:Wait()
		end
		if manager.equipped and not manager.unequipping and manager.equip_token == equip_token then
			deps.restore_viewmodel_visibility(hidden_parts)
		end
	end)
	if equip_track then
		local equip_length = equip_track.Length
		if equip_length <= 0 then
			equip_length = manager.config.equip_time or 0.45
		end
		local equip_duration = equip_length / math.max(equip_speed, 0.01)
		local fire_ready_delay = math.clamp(manager.config.equip_fire_ready_time or equip_duration * (manager.config.equip_fire_ready_alpha or 0.82), 0, equip_duration)
		task.delay(fire_ready_delay, function()
			if manager.equipped and manager.equipping and manager.equip_token == equip_token then
				manager.equipping = false
				GunStateMachine.set(manager, "idle")
			end
		end)
		task.delay(equip_duration, function()
			if not manager.destroyed and manager.equipped and manager.equip_token == equip_token then
				manager:stop_animation("Equip", manager.config.equip_fade_time or 0.05)
				if not manager.reloading and not manager.unequipping then
					manager:resume_idle(manager.config.idle_resume_fade_time or manager.config.idle_fade_time or 0.15)
				end
			end
		end)
	else
		manager.equipping = false
		GunStateMachine.set(manager, "idle")
		manager:resume_idle(manager.config.idle_fade_time or 0.15)
	end
	if not manager.render_bound then
		manager.render_bound = true
		RunService:BindToRenderStep(manager.render_step_name, Enum.RenderPriority.Camera.Value + 1, function(delta_time)
			manager:update(delta_time)
			if manager.config.body_camera_enabled ~= false then
				hide_local_character(manager)
			end
		end)
	end
	return true
end

function gun_equip_controller.finish_unequip(manager, deps)
	local movement_state = manager.movement_state
	local humanoid = movement_state and movement_state.humanoid
	if humanoid and movement_state.base_camera_offset then
		movement_state.body_camera_offset = Vector3.zero
		local crouch_offset = movement_state.crouching and MovementConfig.CROUCH_CAMERA_OFFSET or Vector3.zero
		humanoid.CameraOffset = movement_state.base_camera_offset + crouch_offset
	end
	if manager.camera and manager.camera:GetAttribute("ActiveGunManager") == manager.active_camera_owner then
		manager.camera:SetAttribute("ActiveGunManager", nil)
	end
	manager.active_camera_owner = nil
	if manager.camera and manager.previous_camera_type then
		manager.camera.CameraType = manager.previous_camera_type
		manager.previous_camera_type = nil
	end
	if manager.laser_dot then
		manager.laser_dot:Destroy()
		manager.laser_dot = nil
	end
	if manager.render_bound then
		RunService:UnbindFromRenderStep(manager.render_step_name)
		manager.render_bound = false
	end
	clear_character_visibility(manager)
	manager.unequipping = false
	manager.equipping = false
	GunStateMachine.set(manager, "idle")
	manager.equip_token += 1
	manager.equipped = false
	manager.aiming = false
	manager:report_aim_state(true)
	manager.reloading = false
	manager.trigger_held = false
	manager:stop_all_animations(0)
	if manager.camera then
		manager.camera.FieldOfView = manager.config.default_fov
	end
	if manager.viewmodel.Parent then
		manager.viewmodel.Parent = nil
	end
	deps.reset_motion_state(manager)
end

function gun_equip_controller.unequip(manager, deps): boolean
	if not manager.equipped or manager.equipping or manager.unequipping then
		return false
	end
	GunStateMachine.set(manager, "unequipping")
	manager.equipped = false
	manager.equipping = false
	manager.unequipping = true
	manager.aiming = false
	manager.reloading = false
	manager.trigger_held = false
	manager.unequip_started_at = os.clock()
	manager.unequip_token += 1
	local token = manager.unequip_token
	local unequip_time = math.max(manager.config.unequip_time or 0.38, 0.05)
	manager:stop_animation("Equip", manager.config.equip_fade_time or 0.05)
	manager:resume_idle(0.05)
	task.delay(unequip_time, function()
		if manager.unequipping and manager.unequip_token == token then
			manager:finish_unequip()
		end
	end)
	return true
end

function gun_equip_controller.destroy(manager)
	manager.unequip_token += 1
	manager.destroyed = true
	if manager.viewmodel then
		manager.viewmodel:SetAttribute("destroyed", true)
		manager:finish_unequip()
	end
	if manager.viewmodel then
		manager.viewmodel:Destroy()
	end
end

return gun_equip_controller

