local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local projectile_handler = require(ReplicatedStorage.Modules.Client.ProjectileHandler)
local visualizer = require(ReplicatedStorage.Modules.Client.ProjectileHandler:WaitForChild("Visualizer"))
local GunReloadController = require(ReplicatedStorage.Modules.Client.GunReloadController)
local GunStateMachine = require(ReplicatedStorage.Modules.Client.GunStateMachine)
local HitFeedbackController = require(ReplicatedStorage.Modules.Client.HitFeedbackController)
local ShotPattern = require(ReplicatedStorage.Modules.Shared.ShotPattern)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local local_player = Players.LocalPlayer

local gun_fire_controller = {}

local function get_fire_point_cframe(gun_model: Model): (CFrame?, Attachment?)
	local fire_point = gun_model:FindFirstChild("FirePoint", true)
	if not fire_point or not fire_point:IsA("Attachment") then
		return nil, nil
	end
	if fire_point.Parent and fire_point.Parent:IsA("BasePart") then
		return fire_point.WorldCFrame, fire_point
	end
	return gun_model:GetPivot() * fire_point.CFrame, fire_point
end

function gun_fire_controller.get_muzzle_cframe(gun_model: Model): (CFrame, Attachment?)
	local fire_point_cframe, fire_point = get_fire_point_cframe(gun_model)
	if fire_point_cframe then
		return fire_point_cframe, fire_point
	end
	local muzzle = gun_model:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("BasePart") then
		local attachment = muzzle:FindFirstChild("MuzzleAttachment")
		if not attachment then
			attachment = Instance.new("Attachment")
			attachment.Name = "MuzzleAttachment"
			attachment.CFrame = CFrame.new(0, 0, -muzzle.Size.Z * 0.5)
			attachment.Parent = muzzle
		end
		return attachment.WorldCFrame, attachment
	end
	return gun_model:GetPivot(), nil
end

local function play_shoot_sound(gun_model: Model)
	local sounds = gun_model:FindFirstChild("Sounds")
	local sound = sounds and (sounds:FindFirstChild("Shoot") or sounds:FindFirstChild("ShootSound"))
		or gun_model:FindFirstChild("Shoot", true)
		or gun_model:FindFirstChild("ShootSound", true)
	if not sound or not sound:IsA("Sound") then
		return
	end
	local shot_sound = sound:Clone()
	shot_sound.Parent = sound.Parent
	shot_sound:Play()
	shot_sound.Ended:Once(function()
		shot_sound:Destroy()
	end)
end

function gun_fire_controller.can_fire(manager): boolean
	if not GunStateMachine.can_fire(manager) then
		return false
	end
	if manager.magazine <= 0 then
		return false
	end
	return os.clock() - manager.last_fire_time >= manager.config.seconds_per_shot
end

local function get_aim_params(manager)
	local excluded = { manager.viewmodel }
	if local_player.Character then
		table.insert(excluded, local_player.Character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true
	return params
end

local function get_camera_target_direction(manager, muzzle_cframe)
	local camera = manager.camera
	if not camera then
		return muzzle_cframe.LookVector
	end
	local camera_cframe = camera.CFrame
	local max_distance = manager.config.max_distance or 650
	local result = workspace:Raycast(camera_cframe.Position, camera_cframe.LookVector * max_distance, get_aim_params(manager))
	local target_position = result and result.Position or camera_cframe.Position + camera_cframe.LookVector * max_distance
	local direction = target_position - muzzle_cframe.Position
	if direction.Magnitude <= 0.01 then
		return camera_cframe.LookVector
	end
	return direction.Unit
end

local function get_ads_direction(manager, muzzle_cframe)
	local ads_point = manager.ads_point
	if not ads_point then
		return get_camera_target_direction(manager, muzzle_cframe)
	end
	local sight_cframe = ads_point.WorldCFrame
	local sight_direction = sight_cframe.LookVector
	local camera_direction = manager.camera and manager.camera.CFrame.LookVector or muzzle_cframe.LookVector
	if sight_direction:Dot(camera_direction) < 0 then
		sight_direction = -sight_direction
	end
	local max_distance = manager.config.max_distance or 650
	local result = workspace:Raycast(sight_cframe.Position, sight_direction * max_distance, get_aim_params(manager))
	local target_position = result and result.Position or sight_cframe.Position + sight_direction * max_distance
	local direction = target_position - muzzle_cframe.Position
	if direction.Magnitude <= 0.01 or direction.Unit:Dot(camera_direction) <= 0 then
		return camera_direction
	end
	return direction.Unit
end

function gun_fire_controller.get_preview_direction(manager, muzzle_cframe: CFrame): Vector3
	return manager.aiming and get_ads_direction(manager, muzzle_cframe) or muzzle_cframe.LookVector
end

function gun_fire_controller.get_fire_directions(manager, muzzle_cframe: CFrame): { Vector3 }
	local base_direction = gun_fire_controller.get_preview_direction(manager, muzzle_cframe)
	return ShotPattern.build_weapon_directions(base_direction, manager.config, manager.aiming, manager.spread_heat, manager.random)
end

function gun_fire_controller.fire(manager): boolean
	if not gun_fire_controller.can_fire(manager) then
		if manager.equipped and manager.magazine <= 0 then
			GunReloadController.reload(manager)
		end
		return false
	end
	manager.last_fire_time = os.clock()
	manager.magazine -= 1
	manager.spread_heat = math.min(manager.config.spread_max, manager.spread_heat + manager.config.spread_per_shot)
	local muzzle_cframe, muzzle_attachment = gun_fire_controller.get_muzzle_cframe(manager.gun_model)
	local origin = muzzle_cframe.Position
	local fire_directions = gun_fire_controller.get_fire_directions(manager, muzzle_cframe)
	manager:play_animation("Fire", manager.config.fire_fade_time or 0, manager.config.fire_animation_speed or 1, false)
	visualizer:ShowMuzzleFlash(muzzle_attachment, manager.config, muzzle_cframe)
	play_shoot_sound(manager.gun_model)
	HitFeedbackController.pulse_fire(manager)
	for _, direction in fire_directions do
		projectile_handler.fire(origin, direction, local_player, manager.config)
	end
	remotes.WeaponFire:FireServer(manager.gun_name, origin, fire_directions, workspace:GetServerTimeNow())
	manager:add_recoil()
	return true
end

return gun_fire_controller
