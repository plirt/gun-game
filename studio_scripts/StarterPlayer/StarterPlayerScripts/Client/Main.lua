local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Framework = ReplicatedStorage.Modules.Shared.Framework
local NetworkProtocol = require(Framework.NetworkProtocol)
local RuntimeGraph = require(Framework.RuntimeGraph)
local StateStore = require(Framework.StateStore)

local gun_manager = require(ReplicatedStorage.Modules.Client.GunManager)
local AttachmentModifier = require(ReplicatedStorage.Modules.Shared.AttachmentModifier)

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
	local remote_map = NetworkProtocol.wait_for_client(remotes)

	local state_controller = require(script.StateController)
	local mouse_controller = require(script.MouseController)
	local loadout_controller = require(script.LoadoutController)
	local death_replay_controller = require(script.DeathReplayController)
	local drag_controller = require(script.DragController)
	local grenade_controller = require(script.GrenadeController)
	local ui = require(script.Ui)
	local ui_state_machine = require(script.UiStateMachine)
	local input_controller = require(script.InputController)
	local movement_controller = require(script.MovementController)
	local footstep_controller = require(script.FootstepController)
	local match_controller = require(script.MatchController)
	local hvt_controller = require(script.HvtController)
	local suppression_controller = require(script.SuppressionController)
	local remote_projectile_controller = require(script.RemoteProjectileController)
	local ragdoll_controller = require(script.RagdollController)
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
		remote_map = remote_map,
		network_protocol = NetworkProtocol,
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
		replay_capture_pending = false,
		replay_active = false,
		selected_attachment_gun_id = nil,
		selected_attachment_type = nil,
		dragging = nil,
		drag_ghost = nil,
		mouse_unlocked = false,
	}

	local mutable_state_keys = {
		"GRID_COLUMNS", "GRID_ROWS", "default_mouse_icon_enabled", "default_mouse_behavior",
		"managers", "weapon_attachments", "shop_state", "state_received_at", "status_message",
		"menu_open", "menu_unlocked_by_death", "ui_flow_state", "death_fade_alpha",
		"respawn_menu_pending", "has_spawned_once", "auto_equipped", "menu_view",
		"shop_open", "attachments_open", "equipped", "firing", "fire_loop_running",
		"active_slot", "active_gun_id", "active_gun", "active_utility_id",
		"pending_utility_slot", "pending_utility_use", "grenade_throw_pending", "ragdolled",
		"replay_capture_pending", "replay_active", "replay_death_time", "replay_post_death_seconds",
		"selected_attachment_gun_id", "selected_attachment_type", "dragging", "drag_ghost",
		"drag_layer", "mouse_unlocked", "movement_state", "match_payload", "loadout_busy",
		"equip_request_token", "weapon_swap_token", "grenade_animation_track",
		"grenade_held_model", "grenade_motion_state", "grenade_previous_camera_type",
		"suppression_intensity", "preview_attachment",
	}
	local initial_state = {}
	for _, key in mutable_state_keys do
		initial_state[key] = rawget(ctx, key)
		rawset(ctx, key, nil)
	end
	local store = StateStore.new(initial_state, mutable_state_keys)
	ctx = StateStore.bind_facade(store, ctx)
	ctx.state_store = store

	-- Controllers use the same lifecycle kernel as the server. Dependencies now document
	-- which capability must exist before a controller installs callbacks into the facade.
	local runtime = RuntimeGraph.new(ctx)
	ctx.runtime = runtime
	local function register(name, dependencies, controller, setup_argument)
		runtime:register(name, dependencies, function()
			controller.setup(setup_argument or ctx)
			return controller
		end)
	end

	register("HitFeedbackController", {}, hit_feedback_controller, remotes)
	register("SuppressionController", {}, suppression_controller)
	register("DeathReplayController", {}, death_replay_controller)
	register("RemoteProjectileController", { "SuppressionController", "DeathReplayController" }, remote_projectile_controller)
	register("GrenadeController", {}, grenade_controller)
	register("RagdollController", { "GrenadeController" }, ragdoll_controller)
	register("StateController", {}, state_controller)
	register("MouseController", {}, mouse_controller)
	register("LoadoutController", { "StateController", "DeathReplayController", "GrenadeController", "RagdollController" }, loadout_controller)
	register("DragController", { "StateController" }, drag_controller)
	register("Ui", { "StateController", "LoadoutController", "DragController" }, ui)
	register("InputController", { "Ui", "LoadoutController" }, input_controller)
	register("MovementController", { "InputController", "RagdollController" }, movement_controller)
	register("FootstepController", { "MovementController" }, footstep_controller)
	register("HvtController", {}, hvt_controller)
	register("MatchController", { "HvtController", "Ui" }, match_controller)
	runtime:start_all()

	ctx.render = function()
		ui.render(ctx)
	end

	state_controller.start(ctx)
end

return Main

