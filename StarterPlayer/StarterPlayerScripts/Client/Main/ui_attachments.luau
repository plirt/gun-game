local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttachmentCatalog = require(ReplicatedStorage.Modules.Shared.AttachmentCatalog)
local ui_elements = require(script.Parent.ui_elements)
local ui_previews = require(script.Parent.ui_previews)

local h = ui_elements.h
local label = ui_elements.label
local button = ui_elements.button
local micro_label = ui_elements.micro_label
local panel = ui_elements.panel
local stat_bar = ui_elements.stat_bar
local gun_preview = ui_previews.gun_preview

local ui_attachments = {}

local function type_accent(attachment_type)
	return AttachmentCatalog.get_slot_order(attachment_type) % 2 == 0 and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(170, 170, 170)
end

local function copy_attachments(attachments)
	local copy = {}
	for attachment_type, attachment_name in attachments or {} do
		copy[attachment_type] = attachment_name
	end
	return copy
end

local function slot_marker(attachment_type, selected, installed)
	local accent = type_accent(attachment_type)
	return h("Frame", { BackgroundColor3 = selected and accent or Color3.fromRGB(24, 24, 24), BorderColor3 = installed and accent or Color3.fromRGB(70, 70, 70), BorderSizePixel = 1, Size = UDim2.fromOffset(42, 42) }, {
		h("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = AttachmentCatalog.get_slot_short(attachment_type), TextColor3 = selected and Color3.fromRGB(0, 0, 0) or accent, TextSize = 20, Size = UDim2.fromScale(1, 1) }),
	})
end

local function attachment_option_card(ctx, gun_id, attachment, selected, order)
	local data = AttachmentCatalog.describe_attachment(attachment)
	local accent = data.color
	local text_color = selected and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(245, 245, 245)
	local muted_color = selected and Color3.fromRGB(45, 45, 45) or Color3.fromRGB(160, 160, 160)
	local hover_props = nil
	if not selected and ctx.set_attachment_preview and ctx.clear_attachment_preview then
		hover_props = {
			InputBegan = function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					ctx.set_attachment_preview(gun_id, attachment.type, attachment.name)
				end
			end,
			InputEnded = function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					ctx.clear_attachment_preview(gun_id, attachment.type, attachment.name)
				end
			end,
		}
	end
	return panel({ Size = UDim2.new(1, 0, 0, 86), LayoutOrder = order, BackgroundColor3 = selected and Color3.fromRGB(235, 235, 235) or Color3.fromRGB(13, 13, 13), BorderColor3 = selected and accent or Color3.fromRGB(72, 72, 72) }, {
		h("UIPadding", { PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		h("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
		h("Frame", { BackgroundColor3 = selected and Color3.fromRGB(8, 8, 8) or Color3.fromRGB(28, 28, 28), BorderColor3 = accent, BorderSizePixel = 1, Size = UDim2.fromOffset(54, 54), LayoutOrder = 1 }, {
			h("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = string.upper(string.sub(data.display_name, 1, 2)), TextColor3 = accent, TextSize = 18, Size = UDim2.fromScale(1, 1) }),
		}),
		h("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -176, 1, 0), LayoutOrder = 2 }, {
			h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
			label(data.display_name, 15, text_color, true),
			label(data.description, 10, muted_color, false),
			label("ADS " .. tostring(math.floor(data.score.ads * 100)) .. "   CTRL " .. tostring(math.floor(data.score.control * 100)) .. "   SPR " .. tostring(math.floor(data.score.spread * 100)), 10, muted_color, true),
		}),
		button(selected and "ON" or "EQUIP", function()
			ctx.set_weapon_attachment(gun_id, attachment.type, attachment.name)
		end, 82, selected, "AttachmentOption", hover_props),
	})
end

function ui_attachments.panel(ctx)
	local gun_id = ctx.get_selected_attachment_gun and ctx.get_selected_attachment_gun() or ctx.active_gun_id
	local attachments = gun_id and ctx.weapon_attachments[gun_id] or {}
	local manager = gun_id and ctx.managers[gun_id]
	local guns_folder = ctx.ReplicatedStorage:FindFirstChild("Guns")
	local gun_model = manager and manager.gun_model or (guns_folder and gun_id and guns_folder:FindFirstChild(gun_id))
	local available = ctx.attachment_modifier.get_available(gun_model)
	local grouped = {}
	local types = {}
	for _, attachment in available do
		if not grouped[attachment.type] then
			grouped[attachment.type] = {}
			table.insert(types, attachment.type)
		end
		table.insert(grouped[attachment.type], attachment)
	end
	AttachmentCatalog.sort_types(types)
	local selected_type = ctx.selected_attachment_type or types[1] or "Sight"
	if selected_type and not grouped[selected_type] then
		selected_type = types[1] or "Sight"
		ctx.selected_attachment_type = selected_type
	end
	local current_name = attachments and attachments[selected_type]
	local current_label = current_name or "None"
	local preview_attachments = copy_attachments(attachments)
	local preview_attachment = ctx.preview_attachment
	local previewing_attachment = preview_attachment and preview_attachment.gun_id == gun_id
	if previewing_attachment then
		preview_attachments[preview_attachment.type] = preview_attachment.name
		if preview_attachment.type == selected_type then
			current_label = preview_attachment.name
		end
	end
	local loadout = ctx.shop_state and ctx.shop_state.loadout or {}
	local weapon_title = gun_id and ctx.weapon_name(gun_id) or "No Weapon"
	local installed_count = 0
	for _, attachment_name in attachments or {} do
		if attachment_name and attachment_name ~= "" then
			installed_count += 1
		end
	end
	local weapon_children = {
		h("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
		h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		micro_label("Gunsmith", Color3.fromRGB(185, 185, 185)),
		label("LOADOUT", 25, Color3.fromRGB(245, 245, 245), true),
	}
	for slot = 1, 2 do
		local slot_gun_id = loadout[slot]
		local selected = slot_gun_id and slot_gun_id ~= "" and slot_gun_id == gun_id
		local accent = selected and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(84, 84, 84)
		table.insert(weapon_children, panel({ Size = UDim2.new(1, 0, 0, 100), BackgroundColor3 = selected and Color3.fromRGB(235, 235, 235) or Color3.fromRGB(13, 13, 13), BorderColor3 = accent, LayoutOrder = 10 + slot }, {
			h("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
			h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
			micro_label(slot == 1 and "Primary" or "Secondary", selected and Color3.fromRGB(25, 25, 25) or Color3.fromRGB(170, 170, 170)),
			label(ctx.weapon_name(slot_gun_id), 18, selected and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(245, 245, 245), true),
			button(selected and "SELECTED" or "EDIT", function()
				if slot_gun_id and slot_gun_id ~= "" then
					ctx.set_selected_attachment_gun(slot_gun_id)
				end
			end, 96, selected),
		}))
	end
	local slot_children = {
		h("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder }),
		micro_label("Slots", Color3.fromRGB(155, 155, 155)),
		label("RAIL", 24, Color3.fromRGB(245, 245, 245), true),
	}
	for index, attachment_type in types do
		local installed = attachments and attachments[attachment_type] or "None"
		local selected = attachment_type == selected_type
		local accent = type_accent(attachment_type)
		table.insert(slot_children, h("TextButton", { AutoButtonColor = true, Text = "", BackgroundColor3 = selected and Color3.fromRGB(235, 235, 235) or Color3.fromRGB(12, 12, 12), BorderColor3 = selected and accent or Color3.fromRGB(72, 72, 72), BorderSizePixel = 1, Size = UDim2.new(1, 0, 0, 74), LayoutOrder = 10 + index, Activated = function() ctx.set_selected_attachment_type(attachment_type) end }, {
			h("UIPadding", { PaddingTop = UDim.new(0, 9), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
			h("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
			slot_marker(attachment_type, selected, installed ~= "None"),
			h("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -54, 1, 0), LayoutOrder = 2 }, {
				h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
				label(string.upper(attachment_type), 14, selected and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(245, 245, 245), true),
				label(installed, 11, selected and Color3.fromRGB(45, 45, 45) or Color3.fromRGB(160, 160, 160), false),
			}),
		}))
	end
	local preview_score = AttachmentCatalog.get_build_score(preview_attachments)
	local preview_children = {
		h("UIPadding", { PaddingTop = UDim.new(0, 16), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
		h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		micro_label(previewing_attachment and "Hover Preview" or "Current Build", Color3.fromRGB(185, 185, 185)),
		label(weapon_title, 24, Color3.fromRGB(245, 245, 245), true),
		gun_preview(ctx, gun_id, preview_attachments, { size = UDim2.new(1, 0, 0, 170), layout_order = 20, camera_distance = 2.35 }),
		panel({ Size = UDim2.new(1, 0, 0, 100), BackgroundColor3 = Color3.fromRGB(13, 13, 13), BorderColor3 = Color3.fromRGB(55, 55, 55), LayoutOrder = 30 }, {
			h("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
			h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
			stat_bar("ADS", preview_score.ads, type_accent(selected_type), 1),
			stat_bar("Control", preview_score.control, type_accent(selected_type), 2),
			stat_bar("Spread", preview_score.spread, type_accent(selected_type), 3),
		}),
		label("Installed " .. tostring(installed_count) .. "/" .. tostring(#types), 12, Color3.fromRGB(170, 170, 170), false),
	}
	local option_children = {
		h("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
		h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		micro_label(selected_type, type_accent(selected_type)),
		label(current_label, 24, Color3.fromRGB(245, 245, 245), true),
		button("CLEAR SLOT", function()
			ctx.set_weapon_attachment(gun_id, selected_type, nil)
		end, 112, current_name == nil),
	}
	local option_list_children = {
		h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for index, attachment in grouped[selected_type] or {} do
		table.insert(option_list_children, attachment_option_card(ctx, gun_id, attachment, current_name == attachment.name, 20 + index))
	end
	table.insert(option_children, h("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(0, 0, 0, math.max(#option_list_children - 1, 1) * 94), ScrollBarThickness = 4, Size = UDim2.new(1, 0, 1, -100), LayoutOrder = 30 }, option_list_children))
	return panel({ Name = "AttachmentWorkbench", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(4, 4, 4), BorderColor3 = Color3.fromRGB(245, 245, 245) }, {
		h("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
		h("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		panel({ Size = UDim2.new(0, 180, 1, 0), BackgroundColor3 = Color3.fromRGB(7, 7, 7), LayoutOrder = 1 }, weapon_children),
		panel({ Size = UDim2.new(0, 150, 1, 0), BackgroundColor3 = Color3.fromRGB(7, 7, 7), LayoutOrder = 2 }, slot_children),
		panel({ Size = UDim2.new(0, 230, 1, 0), BackgroundColor3 = Color3.fromRGB(7, 7, 7), LayoutOrder = 3 }, preview_children),
		panel({ Size = UDim2.new(1, -590, 1, 0), BackgroundColor3 = Color3.fromRGB(7, 7, 7), LayoutOrder = 4 }, option_children),
	})
end

return ui_attachments
