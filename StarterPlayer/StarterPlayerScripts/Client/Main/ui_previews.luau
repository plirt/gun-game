local ui_elements = require(script.Parent.ui_elements)
local h = ui_elements.h

local ui_previews = {}

local function anchor_preview_model(model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

function ui_previews.gun_preview(ctx, gun_id, preview_attachments, options)
	options = options or {}
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "GunPreview"
	viewport.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
	viewport.BackgroundTransparency = 0.08
	viewport.BorderColor3 = Color3.fromRGB(72, 72, 72)
	viewport.BorderSizePixel = 1
	viewport.Size = options.size or UDim2.new(0, 154, 1, 0)
	viewport.LayoutOrder = options.layout_order or 1
	viewport.Ambient = Color3.fromRGB(150, 150, 150)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-0.6, -0.8, -0.4)
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local guns_folder = ctx.ReplicatedStorage:FindFirstChild("Guns")
	local template = guns_folder and guns_folder:FindFirstChild(gun_id)
	local model = template and template:Clone()
	if model then
		anchor_preview_model(model)
		model.Parent = world
		if preview_attachments and ctx.attachment_modifier then
			ctx.attachment_modifier.apply_loadout(model, preview_attachments)
			anchor_preview_model(model)
		end
		local _, size = model:GetBoundingBox()
		local max_size = math.max(size.X, size.Y, size.Z, 1)
		local yaw = math.rad(28)
		local dragging = false
		local last_x = 0
		local function update_preview()
			model:PivotTo(CFrame.Angles(0, yaw, 0))
			camera.CFrame = CFrame.new(Vector3.new(0, max_size * 0.18, max_size * (options.camera_distance or 2.15)), Vector3.new(0, 0, 0))
		end
		update_preview()
		viewport.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				last_x = input.Position.X
			end
		end)
		viewport.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false
			end
		end)
		viewport.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				local delta_x = input.Position.X - last_x
				last_x = input.Position.X
				yaw += delta_x * 0.018
				update_preview()
			end
		end)
	end
	return viewport
end

return ui_previews
