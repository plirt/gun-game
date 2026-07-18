local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)
local MovementSimulation = require(ReplicatedStorage.Modules.Shared.MovementSimulation)

local movement_controller = {}

local ACTION_CONTEXT_NAME = "MovementInputActions"
local MAX_PENDING_COMMANDS = 120

local function menu_blocks_movement(ctx): boolean
	return ctx.menu_open == true or ctx.shop_open == true or ctx.attachments_open == true
end

local function is_aiming(ctx): boolean
	return ctx.active_gun ~= nil and ctx.active_gun.aiming == true
end

local function make_raycast_params(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	return params
end

local function apply_jump_lock(humanoid: Humanoid)
	humanoid.WalkSpeed = 0
	humanoid.Jump = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
end

local function apply_crouch_height(state)
	local humanoid = state.humanoid
	if not humanoid or not state.base_hip_height or not state.base_camera_offset then
		return
	end
	humanoid.HipHeight = state.crouching
		and state.base_hip_height + MovementConfig.CROUCH_HIP_HEIGHT_OFFSET
		or state.base_hip_height
	local crouch_offset = state.crouching and MovementConfig.CROUCH_CAMERA_OFFSET or Vector3.zero
	humanoid.CameraOffset = state.base_camera_offset + crouch_offset + (state.body_camera_offset or Vector3.zero)
end

local function reset_prediction(state)
	state.generation = nil
	state.next_sequence = 0
	state.acknowledged_sequence = 0
	state.pending_commands = {}
	state.simulation_accumulator = 0
	state.last_reconciliation_error = 0
	state.predicted_velocity = Vector3.zero
	state.predicted_move_direction = Vector3.zero
	state.motion_velocity = Vector3.zero
end

local function refresh_character(ctx, state)
	local character = ctx.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == state.humanoid and root == state.root then
		return
	end
	state.character = character
	state.humanoid = humanoid
	state.root = root and root:IsA("BasePart") and root or nil
	state.raycast_params = character and make_raycast_params(character) or nil
	state.base_hip_height = humanoid and math.max(0, humanoid.HipHeight) or nil
	state.base_camera_offset = humanoid and humanoid.CameraOffset or nil
	state.sprinting = false
	state.moving = false
	state.crouching = false
	reset_prediction(state)
	if humanoid then
		apply_jump_lock(humanoid)
		apply_crouch_height(state)
	end
end

local function set_crouching(ctx, state, enabled: boolean)
	if menu_blocks_movement(ctx) then
		enabled = false
	end
	state.crouching = enabled
	if enabled then
		state.sprinting = false
	end
	apply_crouch_height(state)
end

local function set_sprinting(ctx, state, enabled: boolean)
	if state.crouching then
		state.sprinting = false
		return
	end
	state.sprinting = enabled and not is_aiming(ctx) and not menu_blocks_movement(ctx)
end

local function get_action_context()
	local existing = script:FindFirstChild(ACTION_CONTEXT_NAME)
	if existing then
		existing:Destroy()
	end
	local context = Instance.new("InputContext")
	context.Name = ACTION_CONTEXT_NAME
	context.Enabled = true
	context.Sink = true
	context.Priority = 200
	context.Parent = script
	return context
end

local function create_action(context: InputContext, name: string, key_codes, pressed, released)
	local action = Instance.new("InputAction")
	action.Name = name
	action.Type = Enum.InputActionType.Bool
	for _, key_code in key_codes do
		local binding = Instance.new("InputBinding")
		binding.KeyCode = key_code
		binding.Parent = action
	end
	action.Pressed:Connect(pressed)
	if released then
		action.Released:Connect(released)
	end
	action.Parent = context
	return action
end

local function get_action_state(action: InputAction?): boolean
	if not action then
		return false
	end
	local ok, value = pcall(function()
		return action:GetState()
	end)
	return ok and value == true
end

local function bind_movement_actions(ctx, state)
	local context = get_action_context()
	state.sprint_action = create_action(context, "Sprint", {
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
	}, function()
		set_sprinting(ctx, state, true)
	end, function()
		state.sprinting = false
	end)
	create_action(context, "Crouch", { Enum.KeyCode.C }, function()
		if not ctx.UserInputService:GetFocusedTextBox() then
			set_crouching(ctx, state, not state.crouching)
		end
	end)
end

local function apply_command(state, command)
	local root = state.root
	if not root or not state.raycast_params then
		return
	end
	local speed = MovementConfig.get_speed(command.crouching, command.sprinting, command.aiming)
	local previous_position = root.Position
	local next_cframe = MovementSimulation.step(
		root.CFrame,
		root.Size,
		command.move_direction,
		command.delta_time,
		speed,
		state.raycast_params
	)
	root.CFrame = next_cframe

	local displacement = next_cframe.Position - previous_position
	local horizontal_displacement = Vector3.new(displacement.X, 0, displacement.Z)
	state.predicted_velocity = command.delta_time > 0
		and horizontal_displacement / command.delta_time
		or Vector3.zero
	state.predicted_move_direction = command.move_direction.Magnitude > 0.05
		and command.move_direction.Unit
		or Vector3.zero
end

local function discard_acknowledged_commands(state, acknowledged_sequence)
	local remaining = {}
	for _, command in ipairs(state.pending_commands) do
		if command.sequence > acknowledged_sequence then
			table.insert(remaining, command)
		end
	end
	state.pending_commands = remaining
end

local function reconcile_snapshot(state, payload)
	if typeof(payload.cframe) ~= "CFrame"
		or type(payload.acknowledged_sequence) ~= "number"
		or type(payload.generation) ~= "string"
	then
		return
	end
	local root = state.root
	if not root then
		return
	end
	if state.generation and payload.generation ~= state.generation then
		reset_prediction(state)
	end
	state.generation = payload.generation
	state.next_sequence = math.max(state.next_sequence, payload.acknowledged_sequence)
	if payload.acknowledged_sequence < state.acknowledged_sequence then
		return
	end
	state.acknowledged_sequence = payload.acknowledged_sequence
	discard_acknowledged_commands(state, payload.acknowledged_sequence)

	local predicted_before = root.Position
	root.CFrame = payload.cframe
	for _, command in ipairs(state.pending_commands) do
		apply_command(state, command)
	end
	state.last_reconciliation_error = (predicted_before - root.Position).Magnitude
end

local function build_command(ctx, state, delta_time)
	local humanoid = state.humanoid
	local move_direction = humanoid and humanoid.MoveDirection or Vector3.zero
	if menu_blocks_movement(ctx) then
		move_direction = Vector3.zero
		state.sprinting = false
	end
	local aiming = is_aiming(ctx)
	if state.crouching or aiming then
		state.sprinting = false
	end
	state.next_sequence += 1
	return {
		sequence = state.next_sequence,
		delta_time = delta_time,
		move_direction = Vector3.new(move_direction.X, 0, move_direction.Z),
		crouching = state.crouching,
		sprinting = state.sprinting,
		aiming = aiming,
	}
end

local function predict_and_send(ctx, state, command_remote, delta_time)
	local command = build_command(ctx, state, delta_time)
	apply_command(state, command)
	table.insert(state.pending_commands, command)
	if #state.pending_commands > MAX_PENDING_COMMANDS then
		table.remove(state.pending_commands, 1)
	end
	command_remote:FireServer(
		command.sequence,
		command.delta_time,
		command.move_direction,
		command.crouching,
		command.sprinting,
		command.aiming
	)
end

function movement_controller.setup(ctx)
	local state = {
		character = nil,
		humanoid = nil,
		root = nil,
		raycast_params = nil,
		base_hip_height = nil,
		base_camera_offset = nil,
		sprinting = false,
		moving = false,
		crouching = false,
		body_camera_offset = Vector3.zero,
		sprint_action = nil,
		generation = nil,
		next_sequence = 0,
		acknowledged_sequence = 0,
		pending_commands = {},
		simulation_accumulator = 0,
		last_reconciliation_error = 0,
		predicted_velocity = Vector3.zero,
		predicted_move_direction = Vector3.zero,
		motion_velocity = Vector3.zero,
	}
	ctx.movement_state = state
	for _, manager in ctx.managers do
		manager.movement_state = state
	end

	local command_remote = ctx.remotes:WaitForChild("MovementCommand")
	local snapshot_remote = ctx.remotes:WaitForChild("MovementSnapshot")
	snapshot_remote.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			reconcile_snapshot(state, payload)
		end
	end)

	bind_movement_actions(ctx, state)
	ctx.player.CharacterAdded:Connect(function()
		task.defer(refresh_character, ctx, state)
	end)
	refresh_character(ctx, state)

	RunService:BindToRenderStep("PvPMovementController", Enum.RenderPriority.Camera.Value + 1, function(delta_time)
		refresh_character(ctx, state)
		local humanoid = state.humanoid
		if not humanoid then
			state.moving = false
			return
		end
		apply_jump_lock(humanoid)
		set_sprinting(ctx, state, get_action_state(state.sprint_action))
		state.moving = humanoid.MoveDirection.Magnitude > 0.05 and not menu_blocks_movement(ctx)
		humanoid:Move(humanoid.MoveDirection, false)

		state.simulation_accumulator += math.min(delta_time, 0.1)
		local step = MovementConfig.COMMAND_STEP
		while state.simulation_accumulator >= step do
			state.simulation_accumulator -= step
			predict_and_send(ctx, state, command_remote, step)
		end

		local motion_alpha = 1 - math.exp(-delta_time * 14)
		state.motion_velocity = state.motion_velocity:Lerp(state.predicted_velocity, motion_alpha)
		if state.predicted_velocity.Magnitude <= 0.05 and state.motion_velocity.Magnitude < 0.01 then
			state.motion_velocity = Vector3.zero
		end
	end)
end

return movement_controller
