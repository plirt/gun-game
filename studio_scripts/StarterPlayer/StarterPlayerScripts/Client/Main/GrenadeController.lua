local ReplicatedStorage = game:GetService("ReplicatedStorage")

local utility_viewmodel_motion = require(ReplicatedStorage.Modules.Client.UtilityViewmodelMotion)

local grenade_controller = {}

local local_cooldown = 0.35
local replenish_seconds = 1.5
local ready_attribute = "grenade_ready_at"
local shake_binding_name = "GrenadeCameraShake"
local last_throw_at = 0
local throw_request_id = 0
local local_ready_at = 0
local shake_strength = 0
local shake_ends_at = 0
local shake_duration = 0

local function get_camera_distance(position)
	local camera = workspace.CurrentCamera
	if not camera then
		return math.huge
	end
	return (camera.CFrame.Position - position).Magnitude
end

local function get_occlusion_multiplier(ctx, position)
	local camera = workspace.CurrentCamera
	local character = ctx.player.Character
	if not camera then
		return 0
	end
	local offset = position - camera.CFrame.Position
	if offset.Magnitude <= 0.1 then
		return 1
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = character and { character } or {}
	params.IgnoreWater = true
	local result = workspace:Raycast(camera.CFrame.Position, offset, params)
	return result and 0.45 or 1
end

local function add_shake(ctx, position, maximum_distance)
	local distance = get_camera_distance(position)
	if distance >= maximum_distance then
		return
	end
	local distance_alpha = 1 - math.clamp(distance / maximum_distance, 0, 1)
	local strength = distance_alpha * distance_alpha * get_occlusion_multiplier(ctx, position)
	shake_strength = math.clamp(shake_strength + strength, 0, 1)
	shake_duration = math.max(shake_duration, 0.55 + strength * 0.9)
	shake_ends_at = os.clock() + shake_duration
end

local function update_shake()
	if shake_strength <= 0 then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local remaining = shake_ends_at - os.clock()
	if remaining <= 0 then
		shake_strength = 0
		shake_duration = 0
		return
	end
	local alpha = math.clamp(remaining / math.max(shake_duration, 0.01), 0, 1)
	local envelope = alpha * alpha * shake_strength
	local time = os.clock()
	local pitch = math.noise(time * 23, 0, 0) * math.rad(2.8) * envelope
	local yaw = math.noise(0, time * 19, 0) * math.rad(2.2) * envelope
	local roll = math.noise(0, 0, time * 17) * math.rad(1.6) * envelope
	local x = math.noise(time * 15, 4, 0) * 0.12 * envelope
	local y = math.noise(7, time * 16, 0) * 0.1 * envelope
	camera.CFrame *= CFrame.new(x, y, 0) * CFrame.Angles(pitch, yaw, roll)
end

local function destroy_held_model(ctx)
	local animation_track = ctx.grenade_animation_track
	if animation_track then
		animation_track:Stop(0.1)
	end
	ctx.grenade_animation_track = nil
	local held_model = ctx.grenade_held_model
	if held_model and held_model.Parent then
		held_model:Destroy()
	end
	ctx.grenade_held_model = nil
	ctx.grenade_motion_state = nil
	local camera = workspace.CurrentCamera
	if camera and ctx.grenade_previous_camera_type then
		camera.CameraType = ctx.grenade_previous_camera_type
	end
	ctx.grenade_previous_camera_type = nil
end

local function get_ready_at(ctx)
	local replicated_ready_at = ctx.player:GetAttribute(ready_attribute)
	if type(replicated_ready_at) ~= "number" then
		replicated_ready_at = 0
	end
	return math.max(local_ready_at, replicated_ready_at)
end

local function create_held_model(ctx)
	local viewmodel_template = ctx.ReplicatedStorage:FindFirstChild("Viewmodel")
	local utility_items = ctx.ReplicatedStorage:FindFirstChild("UtilityItems")
	local grenade_template = utility_items and utility_items:FindFirstChild("Grenade")
	if not viewmodel_template or not viewmodel_template:IsA("Model") or not grenade_template or not grenade_template:IsA("Model") then
		return nil
	end
	local held_model = viewmodel_template:Clone()
	held_model.Name = "GrenadeViewmodel"
	held_model:SetAttribute("utility_viewmodel", true)
	local root = held_model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		held_model:Destroy()
		return nil
	end
	held_model.PrimaryPart = root
	for _, descendant in held_model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant == root
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = descendant ~= root
		end
	end
	local grenade = grenade_template:Clone()
	grenade.Name = "Grenade"
	local grenade_main = grenade:FindFirstChild("Grenade")
	if not grenade_main or not grenade_main:IsA("BasePart") then
		held_model:Destroy()
		return nil
	end
	grenade.PrimaryPart = grenade_main
	for _, descendant in grenade:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = true
		end
	end
	grenade.Parent = held_model
	grenade:PivotTo(root.CFrame)
	local grip = Instance.new("Motor6D")
	grip.Name = "Grenade"
	grip.Part0 = root
	grip.Part1 = grenade_main
	grip.C0 = CFrame.Angles(0, math.rad(90), 0)
	grip.Parent = root
	local camera = workspace.CurrentCamera
	if not camera then
		held_model:Destroy()
		return nil
	end
	ctx.grenade_previous_camera_type = camera.CameraType == Enum.CameraType.Scriptable
		and Enum.CameraType.Custom
		or camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	held_model.Parent = camera
	local animation_controller = held_model:FindFirstChildWhichIsA("AnimationController")
	local idle_animation = grenade:FindFirstChild("Idle", true)
	if animation_controller and idle_animation and idle_animation:IsA("Animation") then
		local animator = animation_controller:FindFirstChildWhichIsA("Animator") or Instance.new("Animator")
		animator.Parent = animation_controller
		local animation_track = animator:LoadAnimation(idle_animation)
		animation_track.Priority = Enum.AnimationPriority.Action4
		animation_track.Looped = true
		animation_track:Play(0.15)
		ctx.grenade_animation_track = animation_track
	end
	ctx.grenade_motion_state = utility_viewmodel_motion.new(ctx.movement_state, workspace.CurrentCamera)
	return held_model
end

local function update_held_model(ctx, delta_time)
	local held_model = ctx.grenade_held_model
	local motion_state = ctx.grenade_motion_state
	local camera = workspace.CurrentCamera
	if not held_model or not held_model.Parent or not motion_state or not camera then
		return
	end
	local viewmodel_camera_cframe, motion = utility_viewmodel_motion.update(
		motion_state,
		ctx.movement_state,
		camera,
		delta_time
	)
	held_model:PivotTo(viewmodel_camera_cframe * motion)
end

function grenade_controller.setup(ctx)
	local equip_remote = ctx.remotes:WaitForChild("GrenadeEquip")
	local throw_remote = ctx.remotes:WaitForChild("GrenadeThrow")
	local throw_result_remote = ctx.remotes:WaitForChild("GrenadeThrowResult")
	local explode_remote = ctx.remotes:WaitForChild("GrenadeExplode")

	ctx.equip_grenade = function(slot)
		if ctx.ragdolled then
			ctx.pending_utility_slot = nil
			ctx.pending_utility_use = false
			ctx.status_message = "Cannot equip while ragdolled."
			if ctx.render then
				ctx.render()
			end
			return false
		end
		local remaining = get_ready_at(ctx) - workspace:GetServerTimeNow()
		if remaining > 0 then
			ctx.pending_utility_slot = nil
			ctx.pending_utility_use = false
			ctx.status_message = string.format("Grenade replenishing: %ds", math.ceil(remaining))
			if ctx.render then
				ctx.render()
			end
			return false
		end
		if ctx.active_utility_id == "GRENADE" and ctx.grenade_held_model then
			return true
		end
		destroy_held_model(ctx)
		local held_model = create_held_model(ctx)
		if not held_model then
			return false
		end
		ctx.grenade_held_model = held_model
		ctx.active_utility_id = "GRENADE"
		ctx.active_slot = slot
		ctx.active_gun_id = nil
		ctx.active_gun = nil
		ctx.equipped = false
		if ctx.sync_mouse then
			ctx.sync_mouse()
		end
		equip_remote:FireServer(true)
		ctx.pending_utility_slot = nil
		local use_when_ready = ctx.pending_utility_use
		ctx.pending_utility_use = false
		if use_when_ready then
			task.defer(ctx.use_active_utility)
		end
		if ctx.render then
			ctx.render()
		end
		return true
	end

	ctx.unequip_grenade = function()
		throw_request_id += 1
		ctx.grenade_throw_pending = false
		if not ctx.active_utility_id and not ctx.grenade_held_model then
			return
		end
		destroy_held_model(ctx)
		ctx.active_utility_id = nil
		if ctx.active_slot == 3 then
			ctx.active_slot = nil
		end
		if ctx.sync_mouse then
			ctx.sync_mouse()
		end
		equip_remote:FireServer(false)
		if ctx.render then
			ctx.render()
		end
	end

	ctx.throw_grenade = function()
		if ctx.ragdolled then
			return false
		end
		if ctx.active_utility_id ~= "GRENADE" or not ctx.grenade_held_model then
			return false
		end
		if ctx.menu_open or ctx.shop_open or ctx.attachments_open then
			return false
		end
		if ctx.ui_state_machine and not ctx.ui_state_machine.can_accept_weapon_input(ctx) then
			return false
		end
		local camera = workspace.CurrentCamera
		local now = os.clock()
		if not camera or ctx.grenade_throw_pending or now - last_throw_at < local_cooldown then
			return false
		end
		throw_request_id += 1
		local request_id = throw_request_id
		ctx.grenade_throw_pending = true
		throw_remote:FireServer(request_id, camera.CFrame.LookVector)
		task.delay(1.5, function()
			if throw_request_id == request_id then
				ctx.grenade_throw_pending = false
			end
		end)
		return true
	end

	ctx.use_active_utility = ctx.throw_grenade

	throw_result_remote.OnClientEvent:Connect(function(request_id, success, ready_at, reason)
		if request_id ~= throw_request_id then
			return
		end
		ctx.grenade_throw_pending = false
		if success ~= true then
			ctx.status_message = reason == "replenishing" and "Grenade replenishing." or "Grenade throw rejected."
			if ctx.render then
				ctx.render()
			end
			return
		end
		last_throw_at = os.clock()
		local_ready_at = type(ready_at) == "number" and ready_at or workspace:GetServerTimeNow() + replenish_seconds
		destroy_held_model(ctx)
		ctx.active_utility_id = nil
		ctx.active_slot = nil
		if ctx.sync_mouse then
			ctx.sync_mouse()
		end
		ctx.status_message = "Grenade thrown."
		if ctx.render then
			ctx.render()
		end
		if ctx.equip_slot then
			task.defer(ctx.equip_slot, 1, true)
		end
	end)

	explode_remote.OnClientEvent:Connect(function(position, maximum_distance)
		if typeof(position) == "Vector3" and type(maximum_distance) == "number" then
			add_shake(ctx, position, maximum_distance)
		end
	end)

	ctx.RunService:BindToRenderStep(shake_binding_name, Enum.RenderPriority.Camera.Value + 2, function(delta_time)
		update_held_model(ctx, delta_time)
		update_shake()
	end)
end

return grenade_controller

