local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FootstepModule = require(ReplicatedStorage.Modules.Client.Packages.FootstepModule)

local footstep_controller = {}

local MIN_MOVE_SPEED = 2.5
local WALK_INTERVAL = 0.42
local SPRINT_INTERVAL = 0.3
local CROUCH_INTERVAL = 0.58
local DEFAULT_VOLUME = 0.38
local DEFAULT_ROLLOFF_DISTANCE = 45
local PITCH_VARIANCE = 0.08

local muted_default_sounds = {
	Running = true,
	Walk = true,
	Walking = true,
}

local random = Random.new()

local state = {
	character = nil,
	humanoid = nil,
	root = nil,
	elapsed = 0,
	last_material = nil,
	default_sound_connections = {},
}

local function get_character_parts(character: Model?)
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and not root:IsA("BasePart") then
		root = nil
	end
	return humanoid, root
end

local function clear_default_sound_connections()
	for _, connection in state.default_sound_connections do
		connection:Disconnect()
	end
	table.clear(state.default_sound_connections)
end

local function mute_default_sound(instance: Instance)
	if not instance:IsA("Sound") or not muted_default_sounds[instance.Name] then
		return
	end
	instance.Volume = 0
	instance.SoundId = ""
	instance:Stop()
end

local function mute_default_character_sounds(character: Model?)
	clear_default_sound_connections()
	if not character then
		return
	end
	for _, descendant in character:GetDescendants() do
		mute_default_sound(descendant)
	end
	table.insert(state.default_sound_connections, character.DescendantAdded:Connect(mute_default_sound))
end

local function get_interval(ctx, speed: number): number
	local movement_state = ctx.movement_state
	if movement_state and movement_state.crouching then
		return CROUCH_INTERVAL
	end
	if movement_state and movement_state.sprinting then
		return SPRINT_INTERVAL
	end
	local speed_alpha = math.clamp((speed - 8) / 10, 0, 1)
	return WALK_INTERVAL + (SPRINT_INTERVAL - WALK_INTERVAL) * speed_alpha
end

local function get_horizontal_speed(root: BasePart): number
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function get_sound_id(material: Enum.Material): string?
	local sounds: {string}? = FootstepModule:GetTableFromMaterial(material)
	if not sounds or #sounds == 0 then
		sounds = FootstepModule.SoundIds.Concrete
	end
	if not sounds or #sounds == 0 then
		return nil
	end
	return FootstepModule:GetRandomSound(sounds)
end

local function play_step(root: BasePart, material: Enum.Material)
	local sound_id = get_sound_id(material)
	if not sound_id then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Footstep"
	sound.SoundId = sound_id
	sound.Volume = DEFAULT_VOLUME
	sound.RollOffMaxDistance = DEFAULT_ROLLOFF_DISTANCE
	sound.PlaybackSpeed = 1 + random:NextNumber(-PITCH_VARIANCE, PITCH_VARIANCE)
	sound.Parent = root
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

local function set_character(character: Model?)
	state.character = character
	state.humanoid, state.root = get_character_parts(character)
	state.elapsed = 0
	state.last_material = nil
	mute_default_character_sounds(character)
end

local function refresh_character(ctx)
	local character = ctx.player.Character
	if character ~= state.character then
		set_character(character)
		return
	end
	if character and (not state.humanoid or not state.root or not state.humanoid.Parent or not state.root.Parent) then
		state.humanoid, state.root = get_character_parts(character)
	end
end

function footstep_controller.setup(ctx)
	ctx.player.CharacterAdded:Connect(set_character)

	set_character(ctx.player.Character)

	ctx.RunService.RenderStepped:Connect(function(delta_time)
		refresh_character(ctx)
		local humanoid = state.humanoid
		local root = state.root
		if not humanoid or not root or humanoid.Health <= 0 then
			state.elapsed = 0
			return
		end
		local floor_material = humanoid.FloorMaterial
		if floor_material == Enum.Material.Air then
			state.elapsed = 0
			return
		end
		local speed = get_horizontal_speed(root)
		if speed < MIN_MOVE_SPEED or humanoid.MoveDirection.Magnitude <= 0.05 then
			state.elapsed = 0
			return
		end
		local interval = get_interval(ctx, speed)
		state.elapsed += delta_time
		if state.last_material ~= floor_material then
			state.elapsed = math.max(state.elapsed, interval)
			state.last_material = floor_material
		end
		if state.elapsed >= interval then
			state.elapsed -= interval
			play_step(root, floor_material)
		end
	end)
end

return footstep_controller
