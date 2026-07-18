local ReplicatedStorage = game:GetService("ReplicatedStorage")

local loadout_slots = require(ReplicatedStorage.Modules.Shared.LoadoutSlots)
local input_actions = require(script.Parent.input_actions)

local input_controller = {}

local ACTION_CONTEXT_NAME = "GameplayInputActions"

local function get_action_context()
	local existing = script:FindFirstChild(ACTION_CONTEXT_NAME)
	if existing then
		existing:Destroy()
	end
	local context = Instance.new("InputContext")
	context.Name = ACTION_CONTEXT_NAME
	context.Enabled = true
	context.Sink = false
	context.Priority = 100
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

local function bind_keyboard_action(ctx, context, name, key_codes, callback)
	return create_action(context, name, key_codes, function()
		if ctx.UserInputService:GetFocusedTextBox() then
			return
		end
		callback()
	end)
end

local function bind_weapon_action(ctx, context, name, key_code, pressed, released)
	return create_action(context, name, { key_code }, function()
		if input_actions.weapon_input_allowed(ctx) then
			pressed()
		end
	end, released)
end

function input_controller.setup(ctx)
	local context = get_action_context()
	bind_keyboard_action(ctx, context, "ToggleMouseLock", { Enum.KeyCode.LeftAlt, Enum.KeyCode.RightAlt }, function()
		ctx.set_mouse_unlocked(not ctx.mouse_unlocked)
	end)
	for _, slot in loadout_slots.get_all() do
		bind_keyboard_action(ctx, context, "EquipSlot" .. tostring(slot.id), { slot.key_code }, function()
			ctx.equip_slot(slot.id)
		end)
	end
	bind_keyboard_action(ctx, context, "Reload", { Enum.KeyCode.R }, function()
		input_actions.reload(ctx)
	end)
	bind_keyboard_action(ctx, context, "CommandTarget", { Enum.KeyCode.J }, function()
		input_actions.command_target(ctx)
	end)
	bind_weapon_action(ctx, context, "Fire", Enum.KeyCode.MouseLeftButton, function()
		input_actions.begin_fire(ctx)
	end, function()
		input_actions.end_fire(ctx)
	end)
	bind_weapon_action(ctx, context, "Aim", Enum.KeyCode.MouseRightButton, function()
		input_actions.begin_aim(ctx)
	end, function()
		input_actions.end_aim(ctx)
	end)
end

return input_controller
