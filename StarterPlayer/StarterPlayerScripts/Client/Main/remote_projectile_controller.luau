local ReplicatedStorage = game:GetService("ReplicatedStorage")

local projectile_handler = require(ReplicatedStorage.Modules.Client.ProjectileHandler)
local visualizer = require(ReplicatedStorage.Modules.Client.ProjectileHandler:WaitForChild("Visualizer"))
local WeaponConfig = require(ReplicatedStorage.Modules.Shared.WeaponConfig)

local remote_projectile_controller = {}
local config_cache = {}

type RemoteFolder = Folder & {
	WeaponFire: RemoteEvent,
}

type Context = {
	player: Player,
	remotes: RemoteFolder,
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

function remote_projectile_controller.setup(ctx: Context)
	ctx.remotes.WeaponFire.OnClientEvent:Connect(function(shooter, gun_name, origin, direction, play_sound)
		if shooter == ctx.player then
			return
		end

		if typeof(shooter) ~= "Instance" or type(gun_name) ~= "string" or typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
			return
		end

		if direction.Magnitude <= 0 then
			return
		end

		local config = get_config(gun_name)
		if not config then
			return
		end

		local character_gun = get_character_gun(shooter)
		local muzzle_cframe, muzzle_attachment = get_muzzle(character_gun)

		visualizer:ShowMuzzleFlash(muzzle_attachment, config, muzzle_cframe or CFrame.new(origin))

		if play_sound ~= false then
			play_shoot_sound(character_gun)
		end

		projectile_handler.fire(origin, direction.Unit, shooter, config)
	end)
end
return remote_projectile_controller
