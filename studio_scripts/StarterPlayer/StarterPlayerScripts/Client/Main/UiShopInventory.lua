local ui_elements = require(script.Parent.UiElements)
local ui_previews = require(script.Parent.UiPreviews)

local h = ui_elements.h
local label = ui_elements.label
local button = ui_elements.button
local panel = ui_elements.panel
local gun_preview = ui_previews.gun_preview

local ui_shop_inventory = {}

local function shop_card(ctx, gun_id, order)
	local weapon = ctx.weapon_data(gun_id)
	local owned = ctx.owns(gun_id)
	local can_buy = not owned and (ctx.shop_state.cash or 0) >= weapon.price
	return panel({ Size = UDim2.new(1, 0, 0, 136), LayoutOrder = order }, {
		h("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		h("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
		gun_preview(ctx, gun_id),
		h("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -166, 1, 0), LayoutOrder = 2 }, {
			h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }),
			label(weapon.display_name, 18, Color3.fromRGB(245, 245, 245), true),
			label((weapon.width or 1) .. "x" .. (weapon.height or 1) .. " | " .. weapon.rarity, 12, Color3.fromRGB(190, 190, 190), false),
			button(owned and "Owned" or ("Buy $" .. tostring(weapon.price)), function()
				if not owned and can_buy then
					ctx.request_state("BuyGun", { gun_id = gun_id })
				end
			end, 116),
		}),
	})
end

local function stash_cell(ctx, gun_id, order)
	local weapon = ctx.weapon_data(gun_id)
	local packed = ctx.is_packed(gun_id)
	return panel({ Size = UDim2.new(1, 0, 0, 58), LayoutOrder = order, BackgroundColor3 = packed and Color3.fromRGB(24, 24, 24) or Color3.fromRGB(0, 0, 0) }, {
		h("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		h("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = weapon.display_name .. "  " .. (weapon.width or 1) .. "x" .. (weapon.height or 1) .. (packed and "  PACKED" or ""),
			TextColor3 = Color3.fromRGB(245, 245, 245),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 1, 0),
			InputBegan = function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					ctx.start_drag(gun_id, false)
				end
			end,
		}),
	})
end

local function backpack_item(ctx, item, order)
	local weapon = ctx.weapon_data(item.gun_id)
	local width = item.width or weapon.width or 1
	local height = item.height or weapon.height or 1
	local x = item.x or 1
	local y = item.y or 1
	local slot_buttons = {
		h("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	if weapon.category == "utility" then
		table.insert(slot_buttons, button("U", function()
			ctx.request_state("SetLoadout", { slot = 3, gun_id = item.gun_id })
			ctx.refresh_active_weapon()
		end, 34))
	elseif weapon.category == "melee" then
		table.insert(slot_buttons, button("M", function()
			ctx.request_state("SetLoadout", { slot = 4, gun_id = item.gun_id })
			ctx.refresh_active_weapon()
		end, 34))
	else
		table.insert(slot_buttons, button("P", function()
			ctx.request_state("SetLoadout", { slot = 1, gun_id = item.gun_id })
			ctx.refresh_active_weapon()
		end, 34))
		table.insert(slot_buttons, button("S", function()
			ctx.request_state("SetLoadout", { slot = 2, gun_id = item.gun_id })
			ctx.refresh_active_weapon()
		end, 34))
	end
	return h("Frame", {
		BackgroundColor3 = Color3.fromRGB(245, 245, 245),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		BorderSizePixel = 1,
		Position = UDim2.fromOffset((x - 1) * (ctx.CELL_SIZE + ctx.CELL_GAP), (y - 1) * (ctx.CELL_SIZE + ctx.CELL_GAP)),
		Size = UDim2.fromOffset(ctx.grid_pixel_size(width), ctx.grid_pixel_size(height)),
		ZIndex = 20 + order,
		InputBegan = function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				ctx.start_drag(item.gun_id, true, input, x, y)
			end
		end,
	}, {
		h("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }),
		h("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = weapon.display_name, TextColor3 = Color3.fromRGB(0, 0, 0), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Size = UDim2.new(1, 0, 1, -22), ZIndex = 21 + order }),
		h("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 4, 1, -22), Size = UDim2.new(1, -8, 0, 18), ZIndex = 22 + order }, slot_buttons),
	})
end

local function backpack_grid(ctx)
	local children = {}
	for row = 1, ctx.GRID_ROWS do
		for col = 1, ctx.GRID_COLUMNS do
			table.insert(children, h("Frame", { BackgroundColor3 = Color3.fromRGB(0, 0, 0), BorderColor3 = Color3.fromRGB(75, 75, 75), BorderSizePixel = 1, Position = UDim2.fromOffset((col - 1) * (ctx.CELL_SIZE + ctx.CELL_GAP), (row - 1) * (ctx.CELL_SIZE + ctx.CELL_GAP)), Size = UDim2.fromOffset(ctx.CELL_SIZE, ctx.CELL_SIZE) }))
		end
	end
	for index, item in ctx.shop_state.backpack or {} do
		table.insert(children, backpack_item(ctx, item, index))
	end
	return h("Frame", { Name = "BackpackGrid", BackgroundColor3 = Color3.fromRGB(0, 0, 0), BorderColor3 = Color3.fromRGB(245, 245, 245), BorderSizePixel = 1, Size = UDim2.fromOffset(ctx.grid_pixel_size(ctx.GRID_COLUMNS), ctx.grid_pixel_size(ctx.GRID_ROWS)), ClipsDescendants = true, LayoutOrder = 20 }, children)
end

function ui_shop_inventory.shop_view(ctx)
	local remaining = (ctx.shop_state.rotation_ends_at or os.time()) - ctx.server_now()
	local shop_list = { h("UIPadding", { PaddingTop = UDim.new(0, 2) }), h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }), label("Shop", 28, Color3.fromRGB(245, 245, 245), true), label("Rotation " .. ctx.format_time(remaining), 12, Color3.fromRGB(190, 190, 190), false) }
	for index, gun_id in ctx.shop_state.shop or {} do
		table.insert(shop_list, shop_card(ctx, gun_id, index + 10))
	end
	return panel({ Name = "ShopMenuView", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.08 }, {
		h("UIPadding", { PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }),
		panel({ Size = UDim2.new(0, 720, 1, 0), BackgroundTransparency = 1 }, shop_list),
	})
end

function ui_shop_inventory.inventory_view(ctx)
	local stash_list = { h("UIPadding", { PaddingTop = UDim.new(0, 2) }), h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }), label("Inventory", 28, Color3.fromRGB(245, 245, 245), true), label("Drag guns into backpack", 12, Color3.fromRGB(190, 190, 190), false) }
	for index, gun_id in ctx.shop_state.inventory or {} do
		table.insert(stash_list, stash_cell(ctx, gun_id, index + 10))
	end
	local backpack_list = { h("UIPadding", { PaddingTop = UDim.new(0, 2) }), h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }), label("Backpack 7x7", 28, Color3.fromRGB(245, 245, 245), true), label(ctx.status_message, 12, Color3.fromRGB(210, 210, 210), false), backpack_grid(ctx) }
	return h("Frame", { Name = "InventoryMenuView", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, {
		h("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }),
		panel({ Size = UDim2.new(0, 506, 1, 0), BackgroundTransparency = 0.08, LayoutOrder = 1 }, backpack_list),
		panel({ Size = UDim2.new(1, -520, 1, 0), BackgroundTransparency = 0.08, LayoutOrder = 2 }, stash_list),
	})
end

return ui_shop_inventory

