local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)
local MovementSimulation = require(ReplicatedStorage.Modules.Shared.MovementSimulation)

local movement_controller = {}

local ACTION_CONTEXT_NAME = "MovementInputActions"
local MAX_PENDING_COMMANDS = 120
local MOVEMENT_COMMANDS_PER_BATCH = 2

local function menu_blocks_movement(ctx): boolean
	return ctx.menu_open == true or ctx.shop_open == true or ctx.attachments_open == true
end

local function is_ragdolled(ctx): boolean
	return ctx.ragdolled == true or ctx.player:GetAttribute("ragdolled") == true
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
	state.outgoing_commands = {}
	state.simulation_accumulator = 0
	state.last_reconciliation_error = 0
	state.predicted_velocity = Vector3.zero
	state.predicted_move_direction = Vector3.zero
	state.motion_velocity = Vector3.zero
	state.vertical_velocity = 0
	state.grounded = false
end

local function suspend_prediction(state)
	if state.prediction_suspended then
		return
	end
	reset_prediction(state)
	state.prediction_suspended = true
	state.sprinting = false
	state.moving = false
	state.crouching = false
	state.lean_direction = 0
end

local function resume_prediction(state)
	if not state.prediction_suspended then
		return
	end
	reset_prediction(state)
	state.prediction_suspended = false
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
	state.base_ground_clearance = character and state.root
		and MovementSimulation.get_ground_clearance(character, state.root)
		or nil
	state.base_hip_height = humanoid and math.max(0, humanoid.HipHeight) or nil
	state.base_camera_offset = humanoid and humanoid.CameraOffset or nil
	state.sprinting = false
	state.moving = false
	state.crouching = false
	state.lean_direction = 0
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
	state.lean_left_action = create_action(context, "LeanLeft", { Enum.KeyCode.Q }, function() end)
	state.lean_right_action = create_action(context, "LeanRight", { Enum.KeyCode.E }, function() end)
end

local function apply_command(state, command)
	local root = state.root
	if not root or not state.raycast_params then
		return
	end
	local speed = MovementConfig.get_speed(command.crouching, command.sprinting, command.aiming)
	local previous_position = root.Position
	local base_ground_clearance = state.base_ground_clearance or root.Size.Y * 0.5
	local ground_clearance = base_ground_clearance
		+ (command.crouching and MovementConfig.CROUCH_HIP_HEIGHT_OFFSET or 0)
	local next_cframe, vertical_velocity, grounded = MovementSimulation.step(
		root.CFrame,
		root.Size,
		command.move_direction,
		command.delta_time,
		speed,
		state.vertical_velocity,
		state.grounded,
		ground_clearance,
		base_ground_clearance,
		state.raycast_params
	)
	root.CFrame = next_cframe
	state.vertical_velocity = vertical_velocity
	state.grounded = grounded

	local displacement = next_cframe.Position - previous_position
	state.predicted_velocity = command.delta_time > 0
		and displacement / command.delta_time
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
	local generation = payload[1] or payload.generation
	local acknowledged_sequence = payload[2] or payload.acknowledged_sequence
	local authoritative_cframe = payload[3] or payload.cframe
	local vertical_velocity = payload[4] or payload.vertical_velocity
	local grounded = payload[5]
	if grounded == nil then
		grounded = payload.grounded
	end
	local base_ground_clearance = payload[6] or payload.base_ground_clearance
	if typeof(authoritative_cframe) ~= "CFrame"
		or type(acknowledged_sequence) ~= "number"
		or (type(generation) ~= "number" and type(generation) ~= "string")
		or type(vertical_velocity) ~= "number"
		or type(grounded) ~= "boolean"
		or type(base_ground_clearance) ~= "number"
	then
		return
	end
	local root = state.root
	if not root then
		return
	end
	if state.generation and generation ~= state.generation then
		reset_prediction(state)
	end
	state.generation = generation
	state.next_sequence = math.max(state.next_sequence, acknowledged_sequence)
	if acknowledged_sequence < state.acknowledged_sequence then
		return
	end
	state.acknowledged_sequence = acknowledged_sequence
	discard_acknowledged_commands(state, acknowledged_sequence)

	local predicted_before = root.Position
	root.CFrame = authoritative_cframe
	state.vertical_velocity = vertical_velocity
	state.grounded = grounded
	state.base_ground_clearance = base_ground_clearance
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
		state.lean_direction = 0
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
		lean_direction = state.lean_direction,
	}
end

local function predict_and_send(ctx, state, command_remote, delta_time)
	local command = build_command(ctx, state, delta_time)
	apply_command(state, command)
	table.insert(state.pending_commands, command)
	if #state.pending_commands > MAX_PENDING_COMMANDS then
		table.remove(state.pending_commands, 1)
	end
	table.insert(state.outgoing_commands, {
		command.sequence,
		command.delta_time,
		command.move_direction,
		command.crouching,
		command.sprinting,
		command.aiming,
		command.lean_direction,
	})
	if #state.outgoing_commands >= MOVEMENT_COMMANDS_PER_BATCH then
		command_remote:FireServer(state.outgoing_commands)
		state.outgoing_commands = {}
	end
end

function movement_controller.setup(ctx)
	local state = {
		character = nil,
		humanoid = nil,
		root = nil,
		raycast_params = nil,
		base_hip_height = nil,
		base_camera_offset = nil,
		base_ground_clearance = nil,
		sprinting = false,
		moving = false,
		crouching = false,
		body_camera_offset = Vector3.zero,
		sprint_action = nil,
		lean_left_action = nil,
		lean_right_action = nil,
		lean_direction = 0,
		generation = nil,
		next_sequence = 0,
		acknowledged_sequence = 0,
		pending_commands = {},
		outgoing_commands = {},
		simulation_accumulator = 0,
		last_reconciliation_error = 0,
		predicted_velocity = Vector3.zero,
		predicted_move_direction = Vector3.zero,
		motion_velocity = Vector3.zero,
		vertical_velocity = 0,
		grounded = false,
		prediction_suspended = false,
	}
	ctx.movement_state = state
	for _, manager in ctx.managers do
		manager.movement_state = state
	end

	local command_remote = ctx.remotes:WaitForChild("MovementCommand")
	local snapshot_remote = ctx.remotes:WaitForChild("MovementSnapshot")
	snapshot_remote.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and not is_ragdolled(ctx) and not state.prediction_suspended then
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
		if is_ragdolled(ctx) or humanoid.PlatformStand then
			suspend_prediction(state)
			return
		end
		resume_prediction(state)
		apply_jump_lock(humanoid)
		apply_crouch_height(state)
		set_sprinting(ctx, state, get_action_state(state.sprint_action))
		local leaning_blocked = menu_blocks_movement(ctx)
			or state.sprinting
			or ctx.UserInputService:GetFocusedTextBox() ~= nil
		if leaning_blocked then
			state.lean_direction = 0
		else
			local lean_left = get_action_state(state.lean_left_action)
			local lean_right = get_action_state(state.lean_right_action)
			state.lean_direction = (lean_right and 1 or 0) - (lean_left and 1 or 0)
		end
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

