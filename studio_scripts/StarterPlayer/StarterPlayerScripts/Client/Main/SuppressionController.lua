local RunService = game:GetService("RunService")

local suppression_controller = {}

local SUPPRESSION_DECAY_SECONDS = 2.2
local SUPPRESSION_EVENT_INTERVAL = 0.06
local CAMERA_SHAKE_MAX_ANGLE = math.rad(0.16)

local function create_indicator(player_gui: PlayerGui)
	local existing = player_gui:FindFirstChild("SuppressionGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SuppressionGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90
	gui.Parent = player_gui

	local label = Instance.new("TextLabel")
	label.Name = "Indicator"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 58)
	label.Size = UDim2.new(0, 180, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = "SUPPRESSED"
	label.TextColor3 = Color3.fromRGB(210, 210, 210)
	label.TextSize = 11
	label.TextTransparency = 1
	label.Parent = gui

	local bar = Instance.new("Frame")
	bar.Name = "Intensity"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 80)
	bar.Size = UDim2.new(0, 0, 0, 2)
	bar.BackgroundColor3 = Color3.fromRGB(205, 205, 205)
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.Parent = gui

	return gui, label, bar
end

function suppression_controller.setup(ctx)
	local _, label, bar = create_indicator(ctx.player:WaitForChild("PlayerGui"))
	local intensity = 0
	local last_event_time = 0
	local random = Random.new()

	ctx.suppression_intensity = 0
	ctx.apply_suppression = function(strength: number, incoming_direction: Vector3?)
		if ctx.menu_open or ctx.replay_active or strength <= 0 then
			return
		end
		local now = os.clock()
		if now - last_event_time < SUPPRESSION_EVENT_INTERVAL then
			intensity = math.max(intensity, strength)
			return
		end
		last_event_time = now
		intensity = math.clamp(math.max(intensity, strength * 0.85) + strength * 0.2, 0, 1)

		local manager = ctx.active_gun
		if manager and manager.equipped then
			local direction_sign = incoming_direction and math.sign(incoming_direction:Dot(manager.camera.CFrame.RightVector)) or 0
			local pitch = random:NextNumber(-CAMERA_SHAKE_MAX_ANGLE, CAMERA_SHAKE_MAX_ANGLE) * strength
			local yaw = (random:NextNumber(-0.45, 0.45) - direction_sign * 0.35) * CAMERA_SHAKE_MAX_ANGLE * strength
			local roll = random:NextNumber(-0.5, 0.5) * CAMERA_SHAKE_MAX_ANGLE * strength
			manager.screen_shake_rotation += Vector3.new(pitch, yaw, roll)
		end
	end

	RunService.RenderStepped:Connect(function(delta_time)
		if intensity > 0 then
			intensity = math.max(0, intensity - delta_time / SUPPRESSION_DECAY_SECONDS)
		end
		ctx.suppression_intensity = intensity

		local visible_alpha = intensity * intensity
		label.TextTransparency = 1 - visible_alpha * 0.82
		bar.Size = UDim2.new(0, 150 * visible_alpha, 0, 2)
		bar.BackgroundTransparency = 1 - visible_alpha * 0.7

	end)
end

return suppression_controller

