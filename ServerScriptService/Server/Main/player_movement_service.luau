local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)
local MovementSimulation = require(ReplicatedStorage.Modules.Shared.MovementSimulation)

local player_movement_service = {}

local movement_states = setmetatable({}, { __mode = "k" })

local function get_or_create_remote(ctx, name: string): RemoteEvent
	local remote = ctx.remotes:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ctx.remotes
	return remote
end

local function new_state(generation: string, base_hip_height: number?)
	return {
		generation = generation,
		last_sequence = 0,
		simulated_time = 0,
		started_at = os.clock(),
		last_snapshot_at = 0,
		base_hip_height = base_hip_height,
		crouch_pose_alpha = 0,
		crouch_motor_bases = {},
		crouching = false,
		sprinting = false,
		aiming = false,
	}
end

local function get_state(player: Player)
	local state = movement_states[player]
	if state then
		return state
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local base_hip_height = humanoid and math.max(0, humanoid.HipHeight) or nil
	state = new_state(HttpService:GenerateGUID(false), base_hip_height)
	movement_states[player] = state
	return state
end

local function get_character_parts(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character
		or not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
	then
		return nil
	end
	return character, humanoid, root
end

local function make_raycast_params(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	return params
end

local function lock_native_movement(humanoid: Humanoid)
	humanoid.WalkSpeed = 0
	humanoid.Jump = false
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

local function apply_crouch_height(state, character: Model, humanoid: Humanoid)
	if state.base_hip_height == nil then
		state.base_hip_height = math.max(0, humanoid.HipHeight)
	end
	humanoid.HipHeight = state.crouching
		and state.base_hip_height + MovementConfig.CROUCH_HIP_HEIGHT_OFFSET
		or state.base_hip_height
	character:SetAttribute("Crouching", state.crouching)
end

local function get_crouch_motor_offset(motor: Motor6D): CFrame
	if motor.Name == "RootJoint" or motor.Name == "Root" then
		return CFrame.new(0, 0, 0.14) * CFrame.Angles(math.rad(10), 0, 0)
	end
	if motor.Name == "Right Hip" or motor.Name == "RightHip" then
		return CFrame.Angles(math.rad(-30), 0, math.rad(6))
	end
	if motor.Name == "Left Hip" or motor.Name == "LeftHip" then
		return CFrame.Angles(math.rad(-30), 0, math.rad(-6))
	end
	if motor.Name == "CharacterGunMotor" then
		return CFrame.new(0, 0, 0.12) * CFrame.Angles(math.rad(10), 0, 0)
	end
	return CFrame.identity
end

local function apply_crouch_pose(state, character: Model, delta_time: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	local torso = character:FindFirstChild("Torso") or character:FindFirstChild("LowerTorso")
	local motors = {
		root and (root:FindFirstChild("RootJoint") or root:FindFirstChild("Root")),
		root and root:FindFirstChild("CharacterGunMotor"),
		torso and (torso:FindFirstChild("Right Hip") or torso:FindFirstChild("RightHip")),
		torso and (torso:FindFirstChild("Left Hip") or torso:FindFirstChild("LeftHip")),
	}
	local target = state.crouching and 1 or 0
	state.crouch_pose_alpha += (target - state.crouch_pose_alpha) * math.clamp(delta_time * 12, 0, 1)
	local pose_alpha = state.crouch_pose_alpha * state.crouch_pose_alpha * (3 - 2 * state.crouch_pose_alpha)
	for _, motor in motors do
		if motor and motor:IsA("Motor6D") then
			local base_c0 = state.crouch_motor_bases[motor]
			if not base_c0 then
				base_c0 = motor.C0
				state.crouch_motor_bases[motor] = base_c0
			end
			motor.C0 = base_c0:Lerp(base_c0 * get_crouch_motor_offset(motor), pose_alpha)
		end
	end
	for motor in state.crouch_motor_bases do
		if not motor.Parent then
			state.crouch_motor_bases[motor] = nil
		end
	end
end

local function claim_network_ownership(root: BasePart)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
end

local function configure_character(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	lock_native_movement(humanoid)
	claim_network_ownership(root)
	task.delay(0.25, function()
		if root.Parent then
			claim_network_ownership(root)
		end
	end)
	humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if humanoid.Jump then
			humanoid.Jump = false
		end
	end)
	character:SetAttribute("Crouching", false)
	movement_states[player] = new_state(HttpService:GenerateGUID(false), math.max(0, humanoid.HipHeight))
end

local function is_finite_number(value): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function sanitize_command(state, sequence, delta_time, move_direction, crouching, sprinting, aiming)
	if not is_finite_number(sequence)
		or sequence % 1 ~= 0
		or sequence <= state.last_sequence
		or sequence - state.last_sequence > MovementConfig.MAX_SEQUENCE_GAP
	then
		return nil
	end
	if not is_finite_number(delta_time)
		or delta_time < MovementConfig.MIN_COMMAND_DT
		or delta_time > MovementConfig.MAX_COMMAND_DT
	then
		return nil
	end
	if typeof(move_direction) ~= "Vector3"
		or not is_finite_number(move_direction.X)
		or not is_finite_number(move_direction.Y)
		or not is_finite_number(move_direction.Z)
		or move_direction.Magnitude > 1.05
	then
		return nil
	end
	if type(crouching) ~= "boolean"
		or type(sprinting) ~= "boolean"
		or type(aiming) ~= "boolean"
	then
		return nil
	end
	local next_simulated_time = state.simulated_time + delta_time
	local elapsed = os.clock() - state.started_at
	if next_simulated_time > elapsed + MovementConfig.COMMAND_TIME_GRACE then
		return nil
	end
	return {
		sequence = sequence,
		delta_time = delta_time,
		move_direction = Vector3.new(move_direction.X, 0, move_direction.Z),
		crouching = crouching,
		sprinting = sprinting and not crouching and not aiming,
		aiming = aiming,
		next_simulated_time = next_simulated_time,
	}
end

local function send_snapshot(snapshot_remote: RemoteEvent, player: Player, state, root: BasePart)
	state.last_snapshot_at = os.clock()
	snapshot_remote:FireClient(player, {
		generation = state.generation,
		acknowledged_sequence = state.last_sequence,
		cframe = root.CFrame,
		horizontal_velocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z),
		server_time = workspace:GetServerTimeNow(),
	})
end

local function process_command(snapshot_remote, player, sequence, delta_time, move_direction, crouching, sprinting, aiming)
	local state = get_state(player)
	local command = sanitize_command(state, sequence, delta_time, move_direction, crouching, sprinting, aiming)
	local character, humanoid, root = get_character_parts(player)
	if not command or not character then
		if root and os.clock() - state.last_snapshot_at >= 0.1 then
			send_snapshot(snapshot_remote, player, state, root)
		end
		return
	end

	state.last_sequence = command.sequence
	state.simulated_time = command.next_simulated_time
	state.crouching = command.crouching
	state.sprinting = command.sprinting
	state.aiming = command.aiming

	lock_native_movement(humanoid)
	apply_crouch_height(state, character, humanoid)
	apply_crouch_pose(state, character, command.delta_time)
	claim_network_ownership(root)
	humanoid:Move(command.move_direction, false)
	local speed = MovementConfig.get_speed(state.crouching, state.sprinting, state.aiming)
	local next_cframe = MovementSimulation.step(
		root.CFrame,
		root.Size,
		command.move_direction,
		command.delta_time,
		speed,
		make_raycast_params(character)
	)
	root.CFrame = next_cframe
	send_snapshot(snapshot_remote, player, state, root)
end

local function setup_player(player: Player)
	if player.Character then
		task.defer(configure_character, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		configure_character(player, character)
	end)
end

function player_movement_service.setup(ctx)
	local command_remote = get_or_create_remote(ctx, "MovementCommand")
	local snapshot_remote = get_or_create_remote(ctx, "MovementSnapshot")
	command_remote.OnServerEvent:Connect(function(player, sequence, delta_time, move_direction, crouching, sprinting, aiming)
		process_command(snapshot_remote, player, sequence, delta_time, move_direction, crouching, sprinting, aiming)
	end)

	for _, player in ctx.Players:GetPlayers() do
		setup_player(player)
	end
	ctx.Players.PlayerAdded:Connect(setup_player)
	ctx.Players.PlayerRemoving:Connect(function(player)
		movement_states[player] = nil
	end)
end

return player_movement_service
