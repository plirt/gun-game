local ui_attachments = require(script.Parent.ui_attachments)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local loadout_slots = require(ReplicatedStorage.Modules.Shared.LoadoutSlots)
local ui_elements = require(script.Parent.ui_elements)
local ui_shop_inventory = require(script.Parent.ui_shop_inventory)

local h = ui_elements.h
local mount = ui_elements.mount
local label = ui_elements.label
local button = ui_elements.button
local micro_label = ui_elements.micro_label
local panel = ui_elements.panel

local ui = {}

local BASE_VIEWPORT = Vector2.new(1180, 720)
local MIN_UI_SCALE = 0.62

local function get_viewport_size()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or BASE_VIEWPORT
end

local function get_ui_scale()
	local viewport = get_viewport_size()
	return math.clamp(math.min(viewport.X / BASE_VIEWPORT.X, viewport.Y / BASE_VIEWPORT.Y), MIN_UI_SCALE, 1)
end

local function scaled_root(child)
	local scale = get_ui_scale()
	local viewport = get_viewport_size()
	return h("Frame", {
		Name = "ScaledRoot",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(viewport.X / scale, viewport.Y / scale),
	}, {
		h("UIScale", { Scale = scale }),
		child,
	})
end

local function slot_card(ctx, slot_id)
	local slot = loadout_slots.get(slot_id)
	local item_id = ctx.shop_state and ctx.shop_state.loadout and ctx.shop_state.loadout[slot_id] or ""
	local is_active = (ctx.equipped or ctx.active_utility_id ~= nil) and ctx.active_slot == slot_id
	local item_name = item_id ~= "" and ctx.weapon_name(item_id) or "Empty"
	local children = {
		h("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		label(tostring(slot_id) .. "  " .. string.upper(slot.display_name), 11, Color3.fromRGB(190, 190, 190), true),
		label(item_name, 15, Color3.fromRGB(245, 245, 245), true),
	}
	if slot.category == "firearm" then
		table.insert(children, button(is_active and "Equipped" or "Equip", function()
			ctx.equip_slot(slot_id)
		end, 108))
	elseif slot.category == "utility" and item_id ~= "" then
		table.insert(children, button(is_active and "Held" or "Hold", function()
			ctx.equip_slot(slot_id)
		end, 108))
	else
		table.insert(children, label("Reserved", 11, Color3.fromRGB(125, 125, 125), true))
	end
	return panel({
		Size = UDim2.new(0, 142, 0, 104),
		BackgroundColor3 = is_active and Color3.fromRGB(24, 24, 24) or Color3.fromRGB(0, 0, 0),
		LayoutOrder = slot_id,
	}, children)
end

function ui.setup(_) end

local function menu_action(text, subtext, selected, on_click, order)
	return h("TextButton", {
		Name = text .. "Button",
		AutoButtonColor = true,
		BackgroundColor3 = selected and Color3.fromRGB(235, 235, 235) or Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = selected and 0.03 or 0.18,
		BorderColor3 = Color3.fromRGB(235, 235, 235),
		BorderSizePixel = 1,
		LayoutOrder = order or 1,
		Size = UDim2.new(0, 332, 0, 64),
		Text = "",
		Activated = on_click,
	}, {
		h("UIPadding", { PaddingTop = UDim.new(0, 9), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 14) }),
		h("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = string.upper(text), TextColor3 = selected and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(245, 245, 245), TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -42, 0, 34) }),
		h("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = string.upper(subtext or "Loadout available"), TextColor3 = selected and Color3.fromRGB(45, 45, 45) or Color3.fromRGB(155, 155, 155), TextSize = 8, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 0, 0, 36), Size = UDim2.new(1, -42, 0, 12) }),
		h("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = selected and "<" or ">", TextColor3 = selected and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(245, 245, 245), TextSize = 28, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -36, 0, 6), Size = UDim2.new(0, 36, 0, 42) }),
	})
end

local function start_button(ctx)
	local can_start = not ctx.can_start_match or ctx.can_start_match()
	return h("TextButton", {
		Name = "StartButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Active = can_start,
		AutoButtonColor = can_start,
		BackgroundColor3 = can_start and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(18, 18, 18),
		BackgroundTransparency = can_start and 0.12 or 0.35,
		BorderColor3 = can_start and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(85, 85, 85),
		BorderSizePixel = 2,
		Font = Enum.Font.GothamBlack,
		Text = can_start and "START" or "WAIT",
		TextColor3 = can_start and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(130, 130, 130),
		TextSize = 28,
		Position = UDim2.new(0.5, 0, 1, -56),
		Size = UDim2.new(0, 320, 0, 68),
		Activated = function()
			if can_start and ctx.start_match then
				ctx.start_match()
			end
		end,
	}, {
		h("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = can_start and "[ READY ]" or "[ RESPAWNING ]", TextColor3 = can_start and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(130, 130, 130), TextSize = 12, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -8), Size = UDim2.new(1, 0, 0, 18) }),
	})
end

local function menu_stats(ctx)
	local cash = ctx.shop_state and ctx.shop_state.cash or 0
	local inventory_count = ctx.shop_state and #(ctx.shop_state.inventory or {}) or 0
	return h("Frame", { Name = "MenuStats", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -34, 0, 34), Size = UDim2.new(0, 360, 0, 120) }, {
		h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		label("GUN  ALPHA", 16, Color3.fromRGB(160, 160, 160), true),
		label("USER  " .. ctx.player.Name, 13, Color3.fromRGB(135, 135, 135), true),
		label("CASH  $" .. tostring(cash), 13, Color3.fromRGB(245, 245, 245), true),
		label("INVENTORY  " .. tostring(inventory_count), 13, Color3.fromRGB(135, 135, 135), true),
	})
end

local function loadout_strip(ctx)
	local children = {
		h("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for _, slot in loadout_slots.get_all() do
		table.insert(children, slot_card(ctx, slot.id))
	end
	return h("Frame", {
		Name = "LoadoutStrip",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 32, 1, -150),
		Size = UDim2.new(0, 446, 0, 116),
	}, children)
end

local function death_fade_overlay(ctx)
	local alpha = math.clamp(ctx.death_fade_alpha or 0, 0, 1)
	if alpha <= 0 then
		return nil
	end
	return h("Frame", {
		Name = "DeathFade",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 1 - alpha,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1000,
	})
end

local function format_match_time(seconds)
	local clamped = math.max(0, math.floor((seconds or 0) + 0.5))
	return string.format("%d:%02d", math.floor(clamped / 60), clamped % 60)
end

local function get_match_time_left(payload)
	local target_time = payload.phase == "intermission" and payload.starts_at or payload.ends_at
	return math.max(0, (target_time or 0) - (payload.server_time or 0))
end

local function get_match_leader(payload)
	local team_scores = payload.team_scores
	if type(team_scores) == "table" and team_scores[1] then
		return team_scores[1]
	end
	local scores = payload.scores
	if type(scores) ~= "table" then
		return nil
	end
	return scores[1]
end

local function get_match_winner_text(payload)
	local winners = payload.winners
	if type(winners) ~= "table" or not winners[1] then
		return nil
	end
	if #winners == 1 then
		local winner = winners[1]
		return string.upper(winner.display_name or winner.name) .. " WINS"
	end
	return "TIE ROUND"
end

local function get_team_score_text(payload)
	local team_scores = payload.team_scores
	if type(team_scores) ~= "table" or not team_scores[1] then
		return nil
	end
	local parts = {}
	for _, team_score in team_scores do
		table.insert(parts, string.upper(team_score.name) .. " " .. tostring(team_score.score or 0))
	end
	return table.concat(parts, "   ") .. " / " .. tostring(payload.score_limit or payload.kill_limit or 0)
end

local function vote_option(ctx, option, order)
	return h("TextButton", {
		Name = option.id .. "Vote",
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.08,
		BorderColor3 = Color3.fromRGB(235, 235, 235),
		BorderSizePixel = 1,
		Font = Enum.Font.GothamBlack,
		LayoutOrder = order,
		Text = string.upper(option.name) .. "  [" .. tostring(option.votes or 0) .. "]",
		TextColor3 = Color3.fromRGB(245, 245, 245),
		TextSize = 12,
		Size = UDim2.new(1, 0, 0, 28),
		Activated = function()
			if ctx.vote_match_mode then
				ctx.vote_match_mode(option.id)
			end
		end,
	})
end

local function match_vote_list(ctx, payload)
	local options = payload.vote_options
	if payload.phase ~= "intermission" or type(options) ~= "table" or not options[1] then
		return nil
	end
	local children = {
		h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for index, option in options do
		table.insert(children, vote_option(ctx, option, index))
	end
	return h("Frame", { Name = "MatchVotes", BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 78), Size = UDim2.new(1, -24, 1, -88) }, children)
end

local function match_hud(ctx)
	if ctx.menu_open or ctx.shop_open or ctx.attachments_open then
		return nil
	end
	local payload = ctx.match_payload
	if type(payload) ~= "table" then
		return nil
	end
	local leader = get_match_leader(payload)
	local winner_text = get_match_winner_text(payload)
	local phase = payload.phase == "round" and "ROUND" or "VOTE"
	local team_score_text = get_team_score_text(payload)
	local objective_state = payload.objective_state
	local objective_text = type(objective_state) == "table" and objective_state.status or nil
	local score_text = team_score_text or "FIRST TO " .. tostring(payload.kill_limit or 0)
	if winner_text and payload.phase == "intermission" then
		score_text = winner_text
	elseif leader and not team_score_text then
		score_text = string.upper(leader.display_name or leader.name) .. "  " .. tostring(leader.kills or 0) .. "/" .. tostring(payload.kill_limit or 0)
	end
	local panel_height = payload.phase == "intermission" and 184 or objective_text and 96 or 74
	return panel({ Name = "MatchHud", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.new(0, 380, 0, panel_height), BackgroundTransparency = 0.08, BorderColor3 = Color3.fromRGB(235, 235, 235), ZIndex = 40 }, {
		h("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		h("TextLabel", { Name = "Mode", BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = string.upper(payload.mode_name ~= "" and payload.mode_name or "MATCH"), TextColor3 = Color3.fromRGB(245, 245, 245), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -92, 0, 24), ZIndex = 41 }),
		h("TextLabel", { Name = "Timer", BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = phase .. "  " .. format_match_time(get_match_time_left(payload)), TextColor3 = Color3.fromRGB(235, 235, 235), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -96, 0, 2), Size = UDim2.new(0, 96, 0, 20), ZIndex = 41 }),
		h("TextLabel", { Name = "Score", BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = score_text, TextColor3 = Color3.fromRGB(170, 170, 170), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 12, 0, 40), Size = UDim2.new(1, -24, 0, 18), ZIndex = 41 }),
		objective_text and h("TextLabel", { Name = "Objective", BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = objective_text, TextColor3 = Color3.fromRGB(235, 235, 235), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 12, 0, 61), Size = UDim2.new(1, -24, 0, 18), ZIndex = 41 }) or nil,
		match_vote_list(ctx, payload),
	})
end

local function root_with_overlay(ctx, child)
	local overlay = death_fade_overlay(ctx)
	local match = match_hud(ctx)
	if not overlay and not match then
		return scaled_root(child)
	end
	local children = { child }
	if match then
		table.insert(children, match)
	end
	if overlay then
		table.insert(children, overlay)
	end
	return scaled_root(h("Frame", { Name = "RootLayer", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, children))
end

local function content_view(ctx)
	if ctx.menu_view == "attachments" then
		return panel({ Name = "AttachmentMenuView", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(4, 4, 4) }, {
			ui_attachments.panel(ctx),
		})
	elseif ctx.menu_view == "shop" then
		return ui_shop_inventory.shop_view(ctx)
	elseif ctx.menu_view == "inventory" then
		return ui_shop_inventory.inventory_view(ctx)
	end
	return nil
end

local function get_menu_content_layout(view)
	if view == "shop" then
		return UDim2.new(0.5, 0, 0, 82), UDim2.new(0, 760, 1, -257)
	elseif view == "inventory" then
		return UDim2.new(0.5, 0, 0, 82), UDim2.new(0, 880, 1, -257)
	elseif view == "attachments" then
		return UDim2.new(0.5, 0, 0, 82), UDim2.new(0, 920, 1, -257)
	end
	return UDim2.new(0.5, 0, 0, 82), UDim2.new(0, 760, 1, -257)
end

local function main_menu(ctx)
	local selected_view = ctx.menu_view
	local content = content_view(ctx)
	local content_position, content_size = get_menu_content_layout(selected_view)
	local children = {
		h("Frame", { Name = "MenuShade", BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.24, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }),
		menu_stats(ctx),
		h("Frame", { Name = "MenuActions", BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0.5, -142), Size = UDim2.new(0, 360, 0, 228) }, {
			h("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder }),
			menu_action("Shop", "Daily weapons", selected_view == "shop", function() ctx.open_menu_view("shop") end, 1),
			menu_action("Arsenal", "Attachments", selected_view == "attachments", function() ctx.open_menu_view("attachments") end, 2),
			menu_action("Inventory", "Backpack and loadout", selected_view == "inventory", function() ctx.open_menu_view("inventory") end, 3),
		}),
		loadout_strip(ctx),
		start_button(ctx),
	}

	if content then
		table.insert(children, h("Frame", { Name = "MenuContent", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = content_position, Size = content_size }, {
			content,
		}))
	end
	return h("Frame", { Name = "MainMenu", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, children)
end

function ui.render(ctx)
	ctx.gui:ClearAllChildren()
	if not ctx.shop_state then
		mount(ctx.gui, root_with_overlay(ctx, panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 300, 0, 96) }, {
			h("UIPadding", { PaddingTop = UDim.new(0, 16), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
			label("Loading shop...", 18, Color3.fromRGB(245, 245, 245), true),
		})))
		return
	end

	if ctx.menu_open then
		mount(ctx.gui, root_with_overlay(ctx, main_menu(ctx)))
		return
	end

	local overlay = death_fade_overlay(ctx)
	local match = match_hud(ctx)
	if overlay or match then
		local children = {}
		if match then
			table.insert(children, match)
		end
		if overlay then
			table.insert(children, overlay)
		end
		mount(ctx.gui, scaled_root(h("Frame", { Name = "HudLayer", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, children)))
	end
end
return ui
