local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)
local constants = require(script.Parent.server_constants)

local player_movement_service = {}

local movement_states = setmetatable({}, { __mode = "k" })
local enforcement_accumulator = 0

local function lock_jump(humanoid: Humanoid)
	humanoid.Jump = false
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

local function get_state(player: Player)
	local state = movement_states[player]
	if state then
		return state
	end
	state = {
		crouching = false,
		sprinting = false,
		aiming = false,
		movement_token = 0,
		updated_at = 0,
	}
	movement_states[player] = state
	return state
end

local function enforce_character(player: Player, state)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	lock_jump(humanoid)
	local speed = MovementConfig.get_speed(state.crouching, state.sprinting, state.aiming)
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
	if root and root:IsA("BasePart") then
		local velocity = root.AssemblyLinearVelocity
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
		local maximum_horizontal_speed = speed * 1.5 + 4
		if horizontal.Magnitude > maximum_horizontal_speed then
			local clamped = horizontal.Unit * maximum_horizontal_speed
			root.AssemblyLinearVelocity = Vector3.new(clamped.X, velocity.Y, clamped.Z)
		end
	end
end

local function setup_character(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	lock_jump(humanoid)
	humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if humanoid.Jump then
			humanoid.Jump = false
		end
	end)
	enforce_character(player, get_state(player))
end

local function setup_player(player: Player)
	get_state(player)
	if player.Character then
		task.defer(setup_character, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		local state = get_state(player)
		state.crouching = false
		state.sprinting = false
		state.aiming = false
		state.movement_token = 0
		state.updated_at = os.clock()
		setup_character(player, character)
	end)
end

local function can_accept_movement_state(state, movement_token)
	local now = os.clock()
	if movement_token <= state.movement_token then
		return false
	end
	if now - state.updated_at < constants.MOVEMENT_UPDATE_INTERVAL then
		return false
	end
	state.movement_token = movement_token
	state.updated_at = now
	return true
end

local function is_valid_token(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value % 1 == 0
		and value >= 1
end

local function bind_movement_remote(ctx)
	local remote = ctx.remotes:WaitForChild("MovementState")
	remote.OnServerEvent:Connect(function(player, movement_token, crouching, sprinting, aiming)
		if not is_valid_token(movement_token)
			or type(crouching) ~= "boolean"
			or type(sprinting) ~= "boolean"
			or type(aiming) ~= "boolean"
		then
			return
		end
		local state = get_state(player)
		if not can_accept_movement_state(state, movement_token) then
			return
		end
		state.crouching = crouching
		state.sprinting = sprinting and not crouching and not aiming
		state.aiming = aiming
		enforce_character(player, state)
	end)
end

function player_movement_service.setup(ctx)
	bind_movement_remote(ctx)
	for _, player in ctx.Players:GetPlayers() do
		setup_player(player)
	end
	ctx.Players.PlayerAdded:Connect(setup_player)
	ctx.Players.PlayerRemoving:Connect(function(player)
		movement_states[player] = nil
	end)
	RunService.Heartbeat:Connect(function(delta_time)
		enforcement_accumulator += delta_time
		if enforcement_accumulator < MovementConfig.SERVER_ENFORCEMENT_INTERVAL then
			return
		end
		enforcement_accumulator = 0
		for _, player in ctx.Players:GetPlayers() do
			enforce_character(player, get_state(player))
		end
	end)
end

return player_movement_service
