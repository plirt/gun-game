local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)

local movement_controller = {}

local CROUCH_HIP_HEIGHT_OFFSET = -1.35
local CROUCH_CAMERA_OFFSET = Vector3.new(0, -1.15, 0)
local ACTION_CONTEXT_NAME = "MovementInputActions"

type MovementState = {
	humanoid: Humanoid?,
	base_hip_height: number?,
	base_camera_offset: Vector3?,
	sprinting: boolean,
	moving: boolean,
	crouching: boolean,
	last_sent_crouching: boolean,
	last_sent_sprinting: boolean,
	last_sent_aiming: boolean,
	last_movement_sent_at: number,
	movement_token: number,
	body_camera_offset: Vector3,
	sprint_action: InputAction?,
}

local function menu_blocks_movement(ctx): boolean
	return ctx.menu_open == true or ctx.shop_open == true or ctx.attachments_open == true
end

local function get_character_humanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function is_aiming(ctx): boolean
	return ctx.active_gun ~= nil and ctx.active_gun.aiming == true
end

local function get_target_speed(ctx, state: MovementState): number
	if menu_blocks_movement(ctx) then
		return MovementConfig.BASE_WALK_SPEED
	end
	if state.crouching then
		return is_aiming(ctx) and MovementConfig.ADS_CROUCH_SPEED or MovementConfig.CROUCH_SPEED
	end
	if is_aiming(ctx) then
		return MovementConfig.ADS_SPEED
	end
	if state.sprinting then
		return MovementConfig.SPRINT_SPEED
	end
	return MovementConfig.BASE_WALK_SPEED
end

local function apply_jump_lock(humanoid: Humanoid)
	humanoid.Jump = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
end

local function apply_crouch_height(state: MovementState)
	local humanoid = state.humanoid
	if not humanoid or not state.base_hip_height or not state.base_camera_offset then
		return
	end
	humanoid.HipHeight = state.crouching and math.max(-1.25, state.base_hip_height + CROUCH_HIP_HEIGHT_OFFSET) or state.base_hip_height
	local crouch_offset = state.crouching and CROUCH_CAMERA_OFFSET or Vector3.zero
	humanoid.CameraOffset = state.base_camera_offset + crouch_offset + (state.body_camera_offset or Vector3.zero)
end

local function refresh_character(ctx, state: MovementState)
	local humanoid = get_character_humanoid(ctx.player)
	if humanoid == state.humanoid then
		return
	end
	state.humanoid = humanoid
	state.base_hip_height = humanoid and math.max(0, humanoid.HipHeight) or nil
	state.base_camera_offset = humanoid and humanoid.CameraOffset or nil
	state.sprinting = false
	state.moving = false
	state.crouching = false
	if humanoid then
		apply_jump_lock(humanoid)
		apply_crouch_height(state)
	end
end

local function set_crouching(ctx, state: MovementState, enabled: boolean)
	if menu_blocks_movement(ctx) then
		enabled = false
	end
	state.crouching = enabled
	if enabled then
		state.sprinting = false
	end
	apply_crouch_height(state)
end

local function set_sprinting(ctx, state: MovementState, enabled: boolean)
	if state.crouching then
		state.sprinting = false
		return
	end
	state.sprinting = enabled and not is_aiming(ctx) and not menu_blocks_movement(ctx)
end

local function send_movement_state(ctx, state: MovementState, force: boolean)
	local remote = ctx.remotes:FindFirstChild("MovementState")
	if not remote then
		return
	end
	local now = os.clock()
	local aiming = is_aiming(ctx)
	local changed = state.crouching ~= state.last_sent_crouching
		or state.sprinting ~= state.last_sent_sprinting
		or aiming ~= state.last_sent_aiming
	if not force and (not changed or now - state.last_movement_sent_at < 0.08) then
		return
	end
	state.last_sent_crouching = state.crouching
	state.last_sent_sprinting = state.sprinting
	state.last_sent_aiming = aiming
	state.last_movement_sent_at = now
	state.movement_token += 1
	remote:FireServer(state.movement_token, state.crouching, state.sprinting, aiming)
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
	action.Pressed:Connect(function()
		pressed()
	end)
	if released then
		action.Released:Connect(function()
			released()
		end)
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


local function bind_movement_actions(ctx, state: MovementState)
	local context = get_action_context()
	state.sprint_action = create_action(context, "Sprint", { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift }, function()
		set_sprinting(ctx, state, true)
		send_movement_state(ctx, state, true)
	end, function()
		state.sprinting = false
		send_movement_state(ctx, state, true)
	end)
	create_action(context, "Crouch", { Enum.KeyCode.C }, function()
		if ctx.UserInputService:GetFocusedTextBox() then
			return
		end
		set_crouching(ctx, state, not state.crouching)
		send_movement_state(ctx, state, true)
	end)
end

function movement_controller.setup(ctx)
	local state: MovementState = {
		humanoid = nil,
		base_hip_height = nil,
		base_camera_offset = nil,
		sprinting = false,
		moving = false,
		crouching = false,
		last_sent_crouching = false,
		last_sent_sprinting = false,
		last_sent_aiming = false,
		last_movement_sent_at = 0,
		movement_token = 0,
		body_camera_offset = Vector3.zero,
		sprint_action = nil,
	}

	ctx.movement_state = state
	for _, manager in ctx.managers do
		manager.movement_state = state
	end

	bind_movement_actions(ctx, state)

	ctx.player.CharacterAdded:Connect(function()
		task.defer(function()
			refresh_character(ctx, state)
			send_movement_state(ctx, state, true)
		end)
	end)

	refresh_character(ctx, state)
	send_movement_state(ctx, state, true)

	RunService:BindToRenderStep("PvPMovementController", Enum.RenderPriority.Camera.Value + 1, function(delta_time)
		refresh_character(ctx, state)

		local humanoid = state.humanoid
		if humanoid then
			apply_jump_lock(humanoid)
			state.moving = humanoid.MoveDirection.Magnitude > 0.05
			set_sprinting(ctx, state, get_action_state(state.sprint_action))
			if state.crouching then
				state.sprinting = false
			end
			if is_aiming(ctx) then
				state.sprinting = false
			end
			if menu_blocks_movement(ctx) then
				state.sprinting = false
			end
			humanoid.WalkSpeed = get_target_speed(ctx, state)
		else
			state.moving = false
		end

		send_movement_state(ctx, state, false)

	end)
end

return movement_controller
