local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)
local MovementSimulation = require(ReplicatedStorage.Modules.Shared.MovementSimulation)
local constants = require(script.Parent.ServerConstants)
local RemoteRateLimiter = require(script.Parent.RemoteRateLimiter)

local player_movement_service = {}

local movement_remote_limiter = RemoteRateLimiter.new(
	constants.MOVEMENT_REMOTE_RATE,
	constants.MOVEMENT_REMOTE_BURST
)
local movement_states = setmetatable({}, { __mode = "k" })
local movement_generations = setmetatable({}, { __mode = "k" })

local function next_generation(player: Player): number
	local generation = (movement_generations[player] or 0) + 1
	movement_generations[player] = generation
	return generation
end

local function new_state(generation: number, base_hip_height: number?, base_ground_clearance: number?, authoritative_cframe: CFrame?)
	return {
		generation = generation,
		last_sequence = 0,
		simulated_time = 0,
		started_at = os.clock(),
		last_snapshot_at = 0,
		base_hip_height = base_hip_height,
		base_ground_clearance = base_ground_clearance,
		authoritative_cframe = authoritative_cframe,
		horizontal_velocity = Vector3.zero,
		vertical_velocity = 0,
		grounded = false,
		crouch_pose_alpha = 0,
		crouch_motor_bases = {},
		crouching = false,
		sprinting = false,
		aiming = false,
		lean_direction = 0,
		lean_pose_alpha = 0,
		applied_crouching = nil,
		last_pose_crouch_alpha = nil,
		last_pose_lean_alpha = nil,
		last_humanoid_move_direction = nil,
	}
end

local function get_state(player: Player)
	local state = movement_states[player]
	if state then
		return state
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local base_hip_height = humanoid and math.max(0, humanoid.HipHeight) or nil
	local base_ground_clearance = character and root and root:IsA("BasePart")
		and MovementSimulation.get_ground_clearance(character, root)
		or nil
	state = new_state(next_generation(player), base_hip_height, base_ground_clearance, root and root:IsA("BasePart") and root.CFrame or nil)
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
	if state.applied_crouching == state.crouching then
		return
	end
	state.applied_crouching = state.crouching
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

local function get_lean_motor_offset(motor: Motor6D, lean_alpha: number): CFrame
	local visual_lean_alpha = lean_alpha < 0
		and lean_alpha * MovementConfig.LEAN_LEFT_VISUAL_MULTIPLIER
		or lean_alpha
	if motor.Name == "RootJoint" or motor.Name == "Root" then
		return CFrame.new(MovementConfig.LEAN_CHARACTER_OFFSET * visual_lean_alpha, 0, 0)
			* CFrame.Angles(0, 0, -math.rad(MovementConfig.LEAN_CHARACTER_ROLL) * visual_lean_alpha)
	end
	if motor.Name == "CharacterGunMotor" then
		return CFrame.Angles(0, 0, -math.rad(MovementConfig.LEAN_CHARACTER_ROLL) * visual_lean_alpha)
	end
	return CFrame.identity
end

local function apply_character_pose(state, character: Model, delta_time: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	local torso = character:FindFirstChild("Torso") or character:FindFirstChild("LowerTorso")
	local motors = {
		root and (root:FindFirstChild("RootJoint") or root:FindFirstChild("Root")),
		root and root:FindFirstChild("CharacterGunMotor"),
		torso and (torso:FindFirstChild("Right Hip") or torso:FindFirstChild("RightHip")),
		torso and (torso:FindFirstChild("Left Hip") or torso:FindFirstChild("LeftHip")),
	}
	local crouch_target = state.crouching and 1 or 0
	state.crouch_pose_alpha += (crouch_target - state.crouch_pose_alpha) * math.clamp(delta_time * 12, 0, 1)
	state.lean_pose_alpha += (state.lean_direction - state.lean_pose_alpha)
		* math.clamp(delta_time * MovementConfig.LEAN_SMOOTHING, 0, 1)
	if math.abs(crouch_target - state.crouch_pose_alpha) < 0.001 then
		state.crouch_pose_alpha = crouch_target
	end
	if math.abs(state.lean_direction - state.lean_pose_alpha) < 0.001 then
		state.lean_pose_alpha = state.lean_direction
	end
	local crouch_alpha = state.crouch_pose_alpha * state.crouch_pose_alpha * (3 - 2 * state.crouch_pose_alpha)
	local pose_changed = state.last_pose_crouch_alpha ~= crouch_alpha
		or state.last_pose_lean_alpha ~= state.lean_pose_alpha
	for _, motor in motors do
		if motor and motor:IsA("Motor6D") then
			local base_c0 = state.crouch_motor_bases[motor]
			local new_motor = base_c0 == nil
			if new_motor then
				base_c0 = motor.C0
				state.crouch_motor_bases[motor] = base_c0
			end
			if pose_changed or new_motor then
				local crouch_c0 = base_c0:Lerp(base_c0 * get_crouch_motor_offset(motor), crouch_alpha)
				motor.C0 = crouch_c0 * get_lean_motor_offset(motor, state.lean_pose_alpha)
			end
		end
	end
	state.last_pose_crouch_alpha = crouch_alpha
	state.last_pose_lean_alpha = state.lean_pose_alpha
	for motor in state.crouch_motor_bases do
		if not motor.Parent then
			state.crouch_motor_bases[motor] = nil
		end
	end
end

local function claim_network_ownership(root: BasePart, player: Player)
	pcall(function()
		root:SetNetworkOwner(player)
	end)
end

local function configure_character(ctx, player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	lock_native_movement(humanoid)
	claim_network_ownership(root, player)
	task.delay(0.25, function()
		if root.Parent then
			claim_network_ownership(root, player)
		end
	end)
	humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if humanoid.Jump then
			humanoid.Jump = false
		end
	end)
	character:SetAttribute("Crouching", false)
	character:SetAttribute("LeanDirection", 0)
	player_movement_service.resync_player(player)
end

function player_movement_service.resync_player(player: Player): boolean
	local character, humanoid, root = get_character_parts(player)
	if not character then
		return false
	end
	local previous_state = movement_states[player]
	local base_hip_height = previous_state and previous_state.base_hip_height
		or math.max(0, humanoid.HipHeight)
	local base_ground_clearance = previous_state and previous_state.base_ground_clearance
		or MovementSimulation.get_ground_clearance(character, root)
	humanoid.HipHeight = base_hip_height
	character:SetAttribute("Crouching", false)
	character:SetAttribute("LeanDirection", 0)
	lock_native_movement(humanoid)
	claim_network_ownership(root, player)
	movement_states[player] = new_state(
		next_generation(player),
		base_hip_height,
		base_ground_clearance,
		root.CFrame
	)
	return true
end

function player_movement_service.recover_player(player: Player): boolean
	local character, _, root = get_character_parts(player)
	if not character then
		return false
	end
	local previous_state = movement_states[player]
	local ground_clearance = previous_state and previous_state.base_ground_clearance
		or MovementSimulation.get_ground_clearance(character, root)
	local look_direction = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look_direction.Magnitude <= 0.01 then
		look_direction = Vector3.zAxis
	else
		look_direction = look_direction.Unit
	end
	local raycast_params = make_raycast_params(character)
	local probe_height = math.max(ground_clearance + 2, 5)
	local floor = workspace:Raycast(
		root.Position + Vector3.yAxis * probe_height,
		-Vector3.yAxis * (probe_height + ground_clearance + 8),
		raycast_params
	)
	local recovery_position = root.Position
	if floor and floor.Normal.Y >= 0.35 then
		recovery_position = Vector3.new(root.Position.X, floor.Position.Y + ground_clearance, root.Position.Z)
	end
	local recovery_cframe = CFrame.lookAt(recovery_position, recovery_position + look_direction)
	local root_offset = character:GetPivot():ToObjectSpace(root.CFrame)
	root.Anchored = true
	character:PivotTo(recovery_cframe * root_offset:Inverse())
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	root.Anchored = false
	return player_movement_service.resync_player(player)
end

local function is_finite_number(value): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function sanitize_command(state, sequence, delta_time, move_direction, crouching, sprinting, aiming, lean_direction)
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
		or not is_finite_number(lean_direction)
		or lean_direction % 1 ~= 0
		or math.abs(lean_direction) > 1
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
		lean_direction = sprinting and not crouching and not aiming and 0 or lean_direction,
		next_simulated_time = next_simulated_time,
	}
end

local function send_snapshot(snapshot_remote: UnreliableRemoteEvent, player: Player, state, root: BasePart)
	state.last_snapshot_at = os.clock()
	snapshot_remote:FireClient(player, {
		state.generation,
		state.last_sequence,
		state.authoritative_cframe or root.CFrame,
		state.vertical_velocity,
		state.grounded,
		state.base_ground_clearance,
	})
end

local function process_command(snapshot_remote, player, sequence, delta_time, move_direction, crouching, sprinting, aiming, lean_direction)
	if player:GetAttribute("ragdolled") == true then
		return
	end
	local state = get_state(player)
	local command = sanitize_command(state, sequence, delta_time, move_direction, crouching, sprinting, aiming, lean_direction)
	local character, humanoid, root = get_character_parts(player)
	if not command or not character then
		if root and os.clock() - state.last_snapshot_at >= MovementConfig.SERVER_ENFORCEMENT_INTERVAL then
			send_snapshot(snapshot_remote, player, state, root)
		end
		return
	end

	state.last_sequence = command.sequence
	state.simulated_time = command.next_simulated_time
	state.crouching = command.crouching
	state.sprinting = command.sprinting
	state.aiming = command.aiming
	if state.lean_direction ~= command.lean_direction then
		state.lean_direction = command.lean_direction
		character:SetAttribute("LeanDirection", state.lean_direction)
	end

	apply_crouch_height(state, character, humanoid)
	apply_character_pose(state, character, command.delta_time)
	local previous_move_direction = state.last_humanoid_move_direction
	if not previous_move_direction
		or (previous_move_direction - command.move_direction):Dot(previous_move_direction - command.move_direction) > 0.001
	then
		state.last_humanoid_move_direction = command.move_direction
		humanoid:Move(command.move_direction, false)
	end
	local speed = MovementConfig.get_speed(state.crouching, state.sprinting, state.aiming)
	state.base_ground_clearance = state.base_ground_clearance
		or MovementSimulation.get_ground_clearance(character, root)
	local ground_clearance = state.base_ground_clearance
		+ (state.crouching and MovementConfig.CROUCH_HIP_HEIGHT_OFFSET or 0)
	local authoritative_cframe = state.authoritative_cframe or root.CFrame
	local next_cframe, vertical_velocity, grounded = MovementSimulation.step(
		authoritative_cframe,
		root.Size,
		command.move_direction,
		command.delta_time,
		speed,
		state.vertical_velocity,
		state.grounded,
		ground_clearance,
		state.base_ground_clearance,
		make_raycast_params(character)
	)
	state.authoritative_cframe = next_cframe
	state.horizontal_velocity = command.move_direction * speed
	state.vertical_velocity = vertical_velocity
	if (root.Position - next_cframe.Position).Magnitude > MovementConfig.SERVER_HARD_CORRECTION_DISTANCE then
		root.CFrame = next_cframe
		root.AssemblyLinearVelocity = state.horizontal_velocity + Vector3.new(0, vertical_velocity, 0)
	end
	state.grounded = grounded
	if os.clock() - state.last_snapshot_at >= MovementConfig.SERVER_ENFORCEMENT_INTERVAL then
		send_snapshot(snapshot_remote, player, state, root)
	end
end

local function setup_player(ctx, player: Player)
	if player.Character then
		task.defer(configure_character, ctx, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		configure_character(ctx, player, character)
	end)
end

function player_movement_service.setup(ctx)
	local command_remote = ctx.remote_map.MovementCommand
	local snapshot_remote = ctx.remote_map.MovementSnapshot
	command_remote.OnServerEvent:Connect(function(player, payload_or_sequence, delta_time, move_direction, crouching, sprinting, aiming)
		if not RemoteRateLimiter.allow(movement_remote_limiter, player) then
			return
		end
		if type(payload_or_sequence) == "table" then
			if #payload_or_sequence == 0 or #payload_or_sequence > 4 then
				return
			end
			for _, packed_command in payload_or_sequence do
				if type(packed_command) ~= "table" or #packed_command ~= 7 then
					return
				end
				process_command(
					snapshot_remote,
					player,
					packed_command[1],
					packed_command[2],
					packed_command[3],
					packed_command[4],
					packed_command[5],
					packed_command[6],
					packed_command[7]
				)
			end
			return
		end
		process_command(snapshot_remote, player, payload_or_sequence, delta_time, move_direction, crouching, sprinting, aiming, 0)
	end)

	for _, player in ctx.Players:GetPlayers() do
		setup_player(ctx, player)
	end
	ctx.Players.PlayerAdded:Connect(function(player)
		setup_player(ctx, player)
	end)
	ctx.Players.PlayerRemoving:Connect(function(player)
		movement_states[player] = nil
		movement_generations[player] = nil
		RemoteRateLimiter.clear(movement_remote_limiter, player)
	end)
end

return player_movement_service

