local drag_controller = {}

function drag_controller.setup(ctx)
	local function get_drag_layer()
		if ctx.drag_layer and ctx.drag_layer.Parent then
			return ctx.drag_layer
		end
		local layer = Instance.new("ScreenGui")
		layer.Name = "GunDragLayer"
		layer.ResetOnSpawn = false
		layer.IgnoreGuiInset = false
		layer.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		layer.SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension
		layer.ClipToDeviceSafeArea = true
		layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		layer.DisplayOrder = 100
		layer.Parent = ctx.player:WaitForChild("PlayerGui")
		ctx.drag_layer = layer
		return layer
	end

	function ctx.clear_drag_ghost()
		if ctx.drag_ghost then
			ctx.drag_ghost:Destroy()
			ctx.drag_ghost = nil
		end
	end

	function ctx.start_drag(gun_id, from_backpack, input, item_x, item_y)
		local weapon = ctx.weapon_data(gun_id)
		local width = weapon.width or 1
		local height = weapon.height or 1
		local drag_offset = Vector2.zero

		if from_backpack and input and item_x and item_y then
			local grid = ctx.gui:FindFirstChild("BackpackGrid", true)
			if grid then
				local step = ctx.CELL_SIZE + ctx.CELL_GAP
				local item_top_left = grid.AbsolutePosition + Vector2.new((item_x - 1) * step, (item_y - 1) * step)
				local mouse = Vector2.new(input.Position.X, input.Position.Y)
				drag_offset = mouse - item_top_left
				drag_offset = Vector2.new(
					math.clamp(drag_offset.X, 0, ctx.grid_pixel_size(width)),
					math.clamp(drag_offset.Y, 0, ctx.grid_pixel_size(height))
				)
			end
		end

		ctx.dragging = {
			gun_id = gun_id,
			from_backpack = from_backpack == true,
			width = width,
			height = height,
			drag_offset = drag_offset,
		}
		ctx.clear_drag_ghost()

		local ghost = Instance.new("Frame")
		ghost.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		ghost.BackgroundTransparency = 0.18
		ghost.BorderColor3 = Color3.fromRGB(0, 0, 0)
		ghost.BorderSizePixel = 1
		ghost.Size = UDim2.fromOffset(ctx.grid_pixel_size(ctx.dragging.width), ctx.grid_pixel_size(ctx.dragging.height))
		ghost.ZIndex = 100
		ghost.Active = false

		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.Text = weapon.display_name or gun_id
		text.TextColor3 = Color3.fromRGB(0, 0, 0)
		text.TextSize = 12
		text.Size = UDim2.fromScale(1, 1)
		text.ZIndex = 101
		text.Parent = ghost

		ctx.drag_ghost = ghost
		ghost.Parent = get_drag_layer()
	end

	local function remove_local_backpack_item(gun_id)
		if not ctx.shop_state or type(ctx.shop_state.backpack) ~= "table" then
			return
		end
		for index = #ctx.shop_state.backpack, 1, -1 do
			if ctx.shop_state.backpack[index].gun_id == gun_id then
				table.remove(ctx.shop_state.backpack, index)
			end
		end
	end

	local function place_local_backpack_item(gun_id, x, y)
		if not ctx.shop_state then
			return
		end
		ctx.shop_state.backpack = ctx.shop_state.backpack or {}
		remove_local_backpack_item(gun_id)
		table.insert(ctx.shop_state.backpack, {
			gun_id = gun_id,
			x = x,
			y = y,
		})
	end

	local function finish_local_drop()
		ctx.dragging = nil
		ctx.clear_drag_ghost()
		if ctx.render then
			ctx.render()
		end
	end

	function ctx.drop_drag()
		if not ctx.dragging then
			return
		end
		local dragging = ctx.dragging
		local grid = ctx.gui:FindFirstChild("BackpackGrid", true)
		local mouse = ctx.UserInputService:GetMouseLocation()
		local action = nil
		local payload = nil
		if grid then
			local offset = dragging.drag_offset or Vector2.zero
			local mouse_inside_grid =
				mouse.X >= grid.AbsolutePosition.X
				and mouse.Y >= grid.AbsolutePosition.Y
				and mouse.X <= grid.AbsolutePosition.X + grid.AbsoluteSize.X
				and mouse.Y <= grid.AbsolutePosition.Y + grid.AbsoluteSize.Y
			if mouse_inside_grid then
				local top_left_x = mouse.X - offset.X - grid.AbsolutePosition.X
				local top_left_y = mouse.Y - offset.Y - grid.AbsolutePosition.Y
				local step = ctx.CELL_SIZE + ctx.CELL_GAP
				local x = math.floor((top_left_x + step * 0.5) / step) + 1
				local y = math.floor((top_left_y + step * 0.5) / step) + 1
				x = math.clamp(x, 1, math.max(1, ctx.GRID_COLUMNS - dragging.width + 1))
				y = math.clamp(y, 1, math.max(1, ctx.GRID_ROWS - dragging.height + 1))
				place_local_backpack_item(dragging.gun_id, x, y)
				action = "PlaceBackpack"
				payload = { gun_id = dragging.gun_id, x = x, y = y }
			elseif dragging.from_backpack then
				remove_local_backpack_item(dragging.gun_id)
				action = "RemoveBackpack"
				payload = { gun_id = dragging.gun_id }
			end
		end
		finish_local_drop()
		if action then
			task.spawn(function()
				ctx.request_state(action, payload)
				ctx.refresh_active_weapon()
			end)
		end
	end

	ctx.RunService.RenderStepped:Connect(function()
		if ctx.drag_ghost and ctx.dragging then
			local mouse = ctx.UserInputService:GetMouseLocation()
			local offset = ctx.dragging.drag_offset or Vector2.zero
			ctx.drag_ghost.Position = UDim2.fromOffset(mouse.X - offset.X, mouse.Y - offset.Y)
		end
	end)
end
return drag_controller

