local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local projectile_handler = require(ReplicatedStorage.Modules.Client.ProjectileHandler)
local visualizer = require(ReplicatedStorage.Modules.Client.ProjectileHandler:WaitForChild("Visualizer"))
local WeaponConfig = require(ReplicatedStorage.Modules.Shared.WeaponConfig)

local remote_projectile_controller = {}
local config_cache = {}

local MAX_NETWORK_BATCH_SIZE = 10
local MAX_DIRECTIONS_PER_SHOT = 2
local MAX_SHOTS_PER_FRAME = 6
local MAX_PENDING_SHOTS = 32
local SUPPRESSION_RADIUS = 10
local SUPPRESSION_DIRECT_HIT_RADIUS = 1.25
local SUPPRESSION_MIN_FORWARD_DISTANCE = 4

type RemoteFolder = Folder & {
	WeaponReplicate: UnreliableRemoteEvent,
}

type Context = {
	player: Player,
	remotes: RemoteFolder,
	replay_active: boolean?,
	apply_suppression: ((number, Vector3?) -> ())?,
	record_replay_shot: ((Instance, string, Vector3, Vector3, any) -> ())?,
}

local function get_config(gun_name: string)
	local cached_config = config_cache[gun_name]
	if cached_config then
		return cached_config
	end
	local configs = ReplicatedStorage:WaitForChild("GunConfigs")
	local config_module = configs:FindFirstChild(gun_name)

	if not config_module then
		return nil
	end

	local ok, config = pcall(function()
		return WeaponConfig.normalize(require(config_module))
	end)

	if not ok then
		return nil
	end
	config_cache[gun_name] = config
	return config
end

local function get_character_gun(shooter: Instance)
	if shooter:IsA("Player") then
		local character = shooter.Character
		return character and character:FindFirstChild("EquippedCharacterGun")
	end

	if shooter:IsA("Model") then
		return shooter:FindFirstChild("HeldGun", true) or shooter:FindFirstChild("EquippedCharacterGun", true)
	end
	return nil
end

local function get_muzzle(gun: Instance?)
	if not gun then
		return nil, nil
	end

	local fire_point = gun:FindFirstChild("FirePoint", true)
	if fire_point and fire_point:IsA("Attachment") then
		return fire_point.WorldCFrame, fire_point
	end

	local muzzle = gun:FindFirstChild("Muzzle", true)
	if not muzzle or not muzzle:IsA("BasePart") then
		return gun:GetPivot(), nil
	end
	local attachment = muzzle:FindFirstChild("MuzzleAttachment")
	if not attachment or not attachment:IsA("Attachment") then
		attachment = Instance.new("Attachment")
		attachment.Name = "MuzzleAttachment"
		attachment.Parent = muzzle
	end

	attachment.CFrame = CFrame.new(0, 0, -muzzle.Size.Z * 0.5)
	return attachment.WorldCFrame, attachment
end

local function get_shooter_exclusion(shooter: Instance): Instance?
	if shooter:IsA("Player") then
		return shooter.Character
	elseif shooter:IsA("Model") then
		return shooter
	end
	return nil
end

local function apply_near_miss_suppression(ctx: Context, shooter: Instance, origin: Vector3, direction: Vector3, config)
	if not ctx.apply_suppression then
		return
	end
	local character = ctx.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local focus = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not humanoid or humanoid.Health <= 0 or not focus or not focus:IsA("BasePart") then
		return
	end

	local unit_direction = direction.Unit
	local to_focus = focus.Position - origin
	local forward_distance = to_focus:Dot(unit_direction)
	if forward_distance < SUPPRESSION_MIN_FORWARD_DISTANCE then
		return
	end
	forward_distance = math.min(forward_distance, config.max_distance or 650)
	local closest_point = origin + unit_direction * forward_distance
	local miss_distance = (focus.Position - closest_point).Magnitude
	if miss_distance <= SUPPRESSION_DIRECT_HIT_RADIUS or miss_distance >= SUPPRESSION_RADIUS then
		return
	end

	local exclusions = { character, workspace.CurrentCamera }
	local shooter_exclusion = get_shooter_exclusion(shooter)
	if shooter_exclusion then
		table.insert(exclusions, shooter_exclusion)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions
	params.IgnoreWater = true
	local obstruction = workspace:Raycast(origin, unit_direction * forward_distance, params)
	if obstruction and (obstruction.Position - origin).Magnitude < forward_distance - 0.5 then
		return
	end

	local strength = 1 - math.clamp(
		(miss_distance - SUPPRESSION_DIRECT_HIT_RADIUS) / (SUPPRESSION_RADIUS - SUPPRESSION_DIRECT_HIT_RADIUS),
		0,
		1
	)
	ctx.apply_suppression(strength, unit_direction)
end

local function play_shoot_sound(gun: Instance?)
	local sounds = gun and gun:FindFirstChild("Sounds")
	local sound = sounds and (sounds:FindFirstChild("Shoot") or sounds:FindFirstChild("ShootSound"))
		or (gun and (gun:FindFirstChild("Shoot", true) or gun:FindFirstChild("ShootSound", true)))

	if not sound or not sound:IsA("Sound") then
		return
	end

	local clone = sound:Clone()
	clone.Parent = sound.Parent
	clone:Play()
	clone.Ended:Once(function()
		clone:Destroy()
	end)
end

local function process_shot(ctx: Context, shot)
	if ctx.replay_active then
		return
	end
	local shooter = shot[1]
	local gun_name = shot[2]
	if shooter == ctx.player then
		return
	end
	if typeof(shooter) ~= "Instance" or type(gun_name) ~= "string" then
		return
	end

	local origin
	local direction_payload
	local play_sound
	if typeof(shot[4]) == "Vector3" or type(shot[4]) == "table" then
		origin = shot[3]
		direction_payload = shot[4]
		play_sound = shot[5]
	else
		direction_payload = shot[3]
		play_sound = shot[4]
	end

	local directions = typeof(direction_payload) == "Vector3" and { direction_payload } or direction_payload
	if type(directions) ~= "table" or #directions == 0 or #directions > MAX_DIRECTIONS_PER_SHOT then
		return
	end
	for _, direction in directions do
		if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0 then
			return
		end
	end

	local config = get_config(gun_name)
	if not config then
		return
	end
	local character_gun = get_character_gun(shooter)
	local muzzle_cframe, muzzle_attachment = get_muzzle(character_gun)
	if typeof(origin) ~= "Vector3" then
		if muzzle_cframe then
			origin = muzzle_cframe.Position
		elseif shooter:IsA("Player") then
			local character = shooter.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			origin = root and root:IsA("BasePart") and root.Position or nil
		elseif shooter:IsA("Model") then
			origin = shooter:GetPivot().Position
		end
	end
	if typeof(origin) ~= "Vector3" then
		return
	end
	for _, direction in directions do
		if ctx.record_replay_shot then
			ctx.record_replay_shot(shooter, gun_name, origin, direction.Unit, config)
		end
		apply_near_miss_suppression(ctx, shooter, origin, direction, config)
	end
	visualizer:ShowMuzzleFlash(muzzle_attachment, config, muzzle_cframe or CFrame.new(origin))
	if play_sound ~= false then
		play_shoot_sound(character_gun)
	end
	for _, direction in directions do
		projectile_handler.fire(origin, direction.Unit, shooter, config)
	end
end

function remote_projectile_controller.setup(ctx: Context)
	local pending_shots = {}
	local next_shot_index = 1
	local function enqueue_shot(shot)
		if #pending_shots - next_shot_index + 1 >= MAX_PENDING_SHOTS then
			next_shot_index += 1
		end
		table.insert(pending_shots, shot)
	end
	ctx.remotes:WaitForChild("WeaponReplicate").OnClientEvent:Connect(function(payload_or_shooter, gun_name, origin, direction_payload, play_sound)
		if type(payload_or_shooter) == "table" then
			if #payload_or_shooter == 0 or #payload_or_shooter > MAX_NETWORK_BATCH_SIZE then
				return
			end
			for _, shot in payload_or_shooter do
				if type(shot) == "table" then
					enqueue_shot(shot)
				end
			end
			return
		end
		enqueue_shot({ payload_or_shooter, gun_name, origin, direction_payload, play_sound })
	end)

	RunService.RenderStepped:Connect(function()
		local processed = 0
		while processed < MAX_SHOTS_PER_FRAME and next_shot_index <= #pending_shots do
			process_shot(ctx, pending_shots[next_shot_index])
			next_shot_index += 1
			processed += 1
		end
		if next_shot_index > #pending_shots then
			table.clear(pending_shots)
			next_shot_index = 1
		elseif next_shot_index > 64 then
			local remaining = {}
			for index = next_shot_index, #pending_shots do
				table.insert(remaining, pending_shots[index])
			end
			pending_shots = remaining
			next_shot_index = 1
		end
	end)
end
return remote_projectile_controller

