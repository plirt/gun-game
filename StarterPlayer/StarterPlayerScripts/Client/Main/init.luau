local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local gun_manager = require(ReplicatedStorage.Modules.Client.GunManager)
local AttachmentModifier = require(ReplicatedStorage.Modules.Client.AttachmentModifier)

local Main = {}

local function enable_ignore_gui_inset(instance)
	if instance:IsA("ScreenGui") then
		instance.IgnoreGuiInset = true
	end
end

function Main.start()
	local player = Players.LocalPlayer
	local player_gui = player:WaitForChild("PlayerGui")
	for _, child in player_gui:GetChildren() do
		enable_ignore_gui_inset(child)
	end
	player_gui.ChildAdded:Connect(enable_ignore_gui_inset)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	local state_controller = require(script.state_controller)
	local mouse_controller = require(script.mouse_controller)
	local loadout_controller = require(script.loadout_controller)
	local drag_controller = require(script.drag_controller)
	local grenade_controller = require(script.grenade_controller)
	local ui = require(script.ui)
	local ui_state_machine = require(script.ui_state_machine)
	local input_controller = require(script.input_controller)
	local movement_controller = require(script.movement_controller)
	local footstep_controller = require(script.footstep_controller)
	local match_controller = require(script.match_controller)
	local remote_projectile_controller = require(script.remote_projectile_controller)
	local ragdoll_controller = require(script.ragdoll_controller)
	local hit_feedback_controller = require(ReplicatedStorage.Modules.Client.HitFeedbackController)

	local gui = Instance.new("ScreenGui")
	gui.Name = "GunShopGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	gui.ClipToDeviceSafeArea = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player_gui

	local ctx = {
		CELL_SIZE = 44,
		CELL_GAP = 2,
		GRID_COLUMNS = 7,
		GRID_ROWS = 7,
		Players = Players,
		ReplicatedStorage = ReplicatedStorage,
		RunService = RunService,
		UserInputService = UserInputService,
		gun_manager = gun_manager,
		attachment_modifier = AttachmentModifier,
		remotes = remotes,
		player = player,
		gui = gui,
		default_mouse_icon_enabled = UserInputService.MouseIconEnabled,
		default_mouse_behavior = UserInputService.MouseBehavior,
		managers = {},
		weapon_attachments = {},
		shop_state = nil,
		state_received_at = os.time(),
		status_message = "",
		menu_open = true,
		menu_unlocked_by_death = true,
		ui_flow_state = "first_join",
		ui_state_machine = ui_state_machine,
		death_fade_alpha = 0,
		respawn_menu_pending = false,
		has_spawned_once = false,
		auto_equipped = false,
		menu_view = nil,
		shop_open = false,
		attachments_open = false,
		equipped = false,
		firing = false,
		fire_loop_running = false,
		active_slot = nil,
		active_gun_id = nil,
		active_gun = nil,
		pending_utility_slot = nil,
		pending_utility_use = false,
		grenade_throw_pending = false,
		ragdolled = false,
		selected_attachment_gun_id = nil,
		selected_attachment_type = nil,
		dragging = nil,
		drag_ghost = nil,
		mouse_unlocked = false,
	}

	hit_feedback_controller.setup(remotes)
	remote_projectile_controller.setup(ctx)
	grenade_controller.setup(ctx)
	ragdoll_controller.setup(ctx)
	state_controller.setup(ctx)
	mouse_controller.setup(ctx)
	loadout_controller.setup(ctx)
	drag_controller.setup(ctx)
	ui.setup(ctx)
	input_controller.setup(ctx)
	movement_controller.setup(ctx)
	footstep_controller.setup(ctx)
	match_controller.setup(ctx)

	ctx.render = function()
		ui.render(ctx)
	end

	state_controller.start(ctx)
end

return Main
