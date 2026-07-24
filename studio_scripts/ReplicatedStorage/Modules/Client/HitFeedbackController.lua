local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local hit_feedback_controller = {}

local local_player = Players.LocalPlayer
local gui = nil
local marker = nil
local marker_strokes = {}
local active_manager = nil
local fire_pulse = 0
local hit_pulse = 0
local last_hit_time = 0

local marker_size = 28
local marker_thickness = 2
local fire_decay = 10
local hit_decay = 7

local function create_stroke(parent, rotation)
	local stroke = Instance.new("Frame")
	stroke.AnchorPoint = Vector2.new(0.5, 0.5)
	stroke.Position = UDim2.fromScale(0.5, 0.5)
	stroke.Size = UDim2.fromOffset(marker_size, marker_thickness)
	stroke.Rotation = rotation
	stroke.BackgroundColor3 = Color3.new(1, 1, 1)
	stroke.BorderSizePixel = 0
	stroke.BackgroundTransparency = 1
	stroke.Parent = parent
	table.insert(marker_strokes, stroke)
	return stroke
end

local function build_gui()
	if gui then
		return
	end
	local player_gui = local_player:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "HitFeedbackGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player_gui
	marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.fromOffset(marker_size, marker_size)
	marker.BackgroundTransparency = 1
	marker.Parent = gui
	create_stroke(marker, 45)
	create_stroke(marker, -45)
end

local function get_marker_position()
	if active_manager and active_manager.laser_dot_screen_position then
		return UDim2.fromOffset(active_manager.laser_dot_screen_position.X, active_manager.laser_dot_screen_position.Y)
	end
	return UDim2.fromScale(0.5, 0.5)
end

local function set_marker(alpha, scale)
	if not marker then
		return
	end
	marker.Position = get_marker_position()
	marker.Size = UDim2.fromOffset(marker_size * scale, marker_size * scale)
	for _, stroke in marker_strokes do
		stroke.BackgroundTransparency = 1 - alpha
		stroke.Size = UDim2.fromOffset(marker_size * scale, marker_thickness)
	end
end

function hit_feedback_controller.set_manager(manager)
	active_manager = manager
end

function hit_feedback_controller.pulse_fire(manager)
	active_manager = manager or active_manager
	fire_pulse = 1
end

function hit_feedback_controller.pulse_hit()
	hit_pulse = 1
	last_hit_time = os.clock()
end

function hit_feedback_controller.setup(remotes)
	build_gui()
	local hit_remote = remotes:WaitForChild("WeaponHitConfirm")
	hit_remote.OnClientEvent:Connect(function()
		hit_feedback_controller.pulse_hit()
	end)
	RunService.RenderStepped:Connect(function(delta_time)
		fire_pulse = math.max(fire_pulse - delta_time * fire_decay, 0)
		hit_pulse = math.max(hit_pulse - delta_time * hit_decay, 0)
		local alpha = math.max(hit_pulse, fire_pulse * 0.3)
		local scale = 1 + fire_pulse * 0.35 + hit_pulse * 0.7
		set_marker(alpha, scale)
	end)
end

return hit_feedback_controller

