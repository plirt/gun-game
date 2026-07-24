local ReplicatedStorage = game:GetService("ReplicatedStorage")

local loadout_slots = require(ReplicatedStorage.Modules.Shared.LoadoutSlots)
local player_state = require(script.Parent.PlayerState)
local constants = require(script.Parent.ServerConstants)
local RemoteRateLimiter = require(script.Parent.RemoteRateLimiter)

local shop_service = {}
local shop_remote_limiter = RemoteRateLimiter.new(
	constants.SHOP_REMOTE_RATE,
	constants.SHOP_REMOTE_BURST
)

local function footprints_overlap(a_x, a_y, a_w, a_h, b_x, b_y, b_w, b_h)
	return a_x < b_x + b_w and b_x < a_x + a_w and a_y < b_y + b_h and b_y < a_y + a_h
end

local function serialize_catalog(ctx)
	local catalog = {}
	for _, weapon in ctx.gun_catalog.get_all() do
		table.insert(catalog, {
			id = weapon.id,
			display_name = weapon.display_name,
			price = weapon.price,
			rarity = weapon.rarity,
			tagline = weapon.tagline,
			width = weapon.width or 1,
			height = weapon.height or 1,
			category = weapon.category or "firearm",
		})
	end
	return catalog
end

local function can_place_backpack_item(ctx, state, gun_id, x, y)
	local weapon = ctx.gun_catalog.get_weapon(gun_id)
	if not weapon then
		return false, "Unknown gun."
	end

	local width = weapon.width or 1
	local height = weapon.height or 1
	if x < 1 or y < 1 or x + width - 1 > ctx.BACKPACK_COLUMNS or y + height - 1 > ctx.BACKPACK_ROWS then
		return false, "That does not fit there."
	end

	for placed_id, placement in state.backpack do
		if type(placed_id) == "string" and type(placement) == "table" and placed_id ~= gun_id then
			local placed_weapon = ctx.gun_catalog.get_weapon(placed_id)
			local placed_width = placed_weapon and placed_weapon.width or 1
			local placed_height = placed_weapon and placed_weapon.height or 1
			if footprints_overlap(x, y, width, height, placement.x, placement.y, placed_width, placed_height) then
				return false, "Something is already there."
			end
		end
	end
	return true, ""
end

local function serialize_state(ctx, player, ok, message)
	local state = player_state.ensure_player_state(player)
	local inventory = {}
	for _, weapon in ctx.gun_catalog.get_all() do
		if state.inventory[weapon.id] then
			table.insert(inventory, weapon.id)
		end
	end

	local backpack = {}
	for gun_id, placement in state.backpack do
		local weapon = type(gun_id) == "string" and ctx.gun_catalog.get_weapon(gun_id) or nil
		if weapon and state.inventory[gun_id] and type(placement) == "table" then
			table.insert(backpack, {
				gun_id = gun_id,
				x = placement.x,
				y = placement.y,
				width = weapon.width or 1,
				height = weapon.height or 1,
			})
		end
	end
	return {
		ok = ok ~= false,
		message = message or "",
		cash = state.cash,
		inventory = inventory,
		backpack = backpack,
		attachments = state.attachments,
		backpack_columns = ctx.BACKPACK_COLUMNS,
		backpack_rows = ctx.BACKPACK_ROWS,
		loadout = {
			state.loadout[1] or "",
			state.loadout[2] or "",
			state.loadout[3] or "",
		},
		shop = ctx.gun_catalog.get_shop(os.time()),
		catalog = serialize_catalog(ctx),
		rotation_ends_at = ctx.gun_catalog.get_rotation_ends_at(os.time()),
		server_time = os.time(),
	}
end

local function handle_buy_gun(ctx, player, state, payload)
	local gun_id = payload.gun_id
	local weapon = type(gun_id) == "string" and ctx.gun_catalog.get_weapon(gun_id) or nil
	if not weapon then
		return serialize_state(ctx, player, false, "That gun does not exist.")
	end
	if state.inventory[gun_id] then
		return serialize_state(ctx, player, false, "Already owned.")
	end
	if not ctx.gun_catalog.is_in_shop(gun_id, os.time()) then
		return serialize_state(ctx, player, false, "That gun is not in this rotation.")
	end
	if state.cash < weapon.price then
		return serialize_state(ctx, player, false, "Not enough cash.")
	end
	state.cash -= weapon.price
	state.inventory[gun_id] = true
	player_state.sync_cash_leaderstat(player, state)
	player_state.mark_dirty(player)
	return serialize_state(ctx, player, true, weapon.display_name .. " added to inventory.")
end

local function handle_set_loadout(ctx, player, state, payload)
	local slot = tonumber(payload.slot)
	local gun_id = payload.gun_id
	local slot_info = loadout_slots.get(slot)
	if not slot_info then
		return serialize_state(ctx, player, false, "Invalid slot.")
	end
	if gun_id == nil or gun_id == "" then
		state.loadout[slot] = ""
		player_state.mark_dirty(player)
		return serialize_state(ctx, player, true, "Slot cleared.")
	end
	if type(gun_id) ~= "string" or not state.inventory[gun_id] then
		return serialize_state(ctx, player, false, "You do not own that item.")
	end
	local weapon = ctx.gun_catalog.get_weapon(gun_id)
	local category = weapon and weapon.category or "firearm"
	if not loadout_slots.accepts(slot, category) then
		return serialize_state(ctx, player, false, "That item does not fit this slot.")
	end
	if not player_state.is_in_backpack(state, gun_id) then
		return serialize_state(ctx, player, false, "Put it in your backpack first.")
	end
	local other_slot = loadout_slots.find_other_slot(slot, category)
	local displaced_gun_id = state.loadout[slot]

	if other_slot and state.loadout[other_slot] == gun_id then
		state.loadout[other_slot] = ""
	end

	state.loadout[slot] = gun_id

	if other_slot and displaced_gun_id and displaced_gun_id ~= "" and displaced_gun_id ~= gun_id and player_state.is_in_backpack(state, displaced_gun_id) then
		state.loadout[other_slot] = displaced_gun_id
	end
	player_state.mark_dirty(player)
	return serialize_state(ctx, player, true, "Loadout updated.")
end

local function handle_place_backpack(ctx, player, state, payload)
	local gun_id = payload.gun_id
	local x = tonumber(payload.x)
	local y = tonumber(payload.y)
	local weapon = type(gun_id) == "string" and ctx.gun_catalog.get_weapon(gun_id) or nil
	if not weapon or not state.inventory[gun_id] then
		return serialize_state(ctx, player, false, "You do not own that gun.")
	end
	if not x or not y then
		return serialize_state(ctx, player, false, "Invalid placement.")
	end
	x = math.floor(x)
	y = math.floor(y)
	local can_place, reason = can_place_backpack_item(ctx, state, gun_id, x, y)
	if not can_place then
		return serialize_state(ctx, player, false, reason)
	end
	state.backpack[gun_id] = { x = x, y = y }
	player_state.mark_dirty(player)
	return serialize_state(ctx, player, true, weapon.display_name .. " packed.")
end

local function handle_set_attachment(ctx, player, state, payload)
	local gun_id = payload.gun_id
	local attachment_type = payload.attachment_type
	local attachment_name = payload.attachment_name
	if type(gun_id) ~= "string" or not state.inventory[gun_id] then
		return serialize_state(ctx, player, false, "You do not own that gun.")
	end
	if type(attachment_type) ~= "string" or attachment_type == "" then
		return serialize_state(ctx, player, false, "Invalid attachment slot.")
	end
	if attachment_name ~= nil and type(attachment_name) ~= "string" then
		return serialize_state(ctx, player, false, "Invalid attachment.")
	end
	player_state.set_attachment(player, gun_id, attachment_type, attachment_name)
	return serialize_state(ctx, player, true, "Attachments updated.")
end

local function handle_remove_backpack(ctx, player, state, payload)
	local gun_id = payload.gun_id
	if type(gun_id) ~= "string" then
		return serialize_state(ctx, player, false, "Invalid gun.")
	end
	state.backpack[gun_id] = nil
	for _, slot in loadout_slots.get_all() do
		if state.loadout[slot.id] == gun_id then
			state.loadout[slot.id] = ""
		end
	end
	player_state.mark_dirty(player)
	return serialize_state(ctx, player, true, "Removed from backpack.")
end

function shop_service.setup(ctx)
	ctx.remotes.ShopRequest.OnServerInvoke = function(player, action, payload)
		if not RemoteRateLimiter.allow(shop_remote_limiter, player) then
			return nil
		end
		local state = player_state.ensure_player_state(player)
		action = type(action) == "string" and action or "GetState"
		payload = type(payload) == "table" and payload or {}

		if action == "BuyGun" then
			return handle_buy_gun(ctx, player, state, payload)
		elseif action == "SetLoadout" then
			return handle_set_loadout(ctx, player, state, payload)
		elseif action == "PlaceBackpack" then
			return handle_place_backpack(ctx, player, state, payload)
		elseif action == "RemoveBackpack" then
			return handle_remove_backpack(ctx, player, state, payload)
		elseif action == "SetAttachment" then
			return handle_set_attachment(ctx, player, state, payload)
		end
		return serialize_state(ctx, player, true, "")
	end

	task.spawn(function()
		local last_rotation = ctx.gun_catalog.get_rotation_index(os.time())
		while true do
			task.wait(1)
			local rotation = ctx.gun_catalog.get_rotation_index(os.time())
			if rotation ~= last_rotation then
				last_rotation = rotation
				ctx.remotes.ShopUpdated:FireAllClients("RotationChanged")
			end
		end
	end)
end
return shop_service



