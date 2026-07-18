local ReplicatedStorage = game:GetService("ReplicatedStorage")

local loadout_slots = require(ReplicatedStorage.Modules.Shared.LoadoutSlots)

local player_data_schema = {}

local CURRENT_VERSION = 3

export type BackpackPlacement = { x: number, y: number }
export type AttachmentMap = { [string]: string }

export type PlayerData = {
	version: number,
	scoped_user_id: string,
	session_id: string?,
	cash: number,
	inventory: { [string]: boolean },
	loadout: { [number]: string },
	backpack: { [string]: BackpackPlacement },
	attachments: { [string]: AttachmentMap },
	saved_at: number?,
	previous_saved_at: number?,
}

function player_data_schema.current_version(): number
	return CURRENT_VERSION
end

local function sanitize_cash(value): number
	local cash = tonumber(value)
	if not cash then
		return 0
	end
	return math.max(0, math.floor(cash))
end

local function sanitize_inventory(value): { [string]: boolean }
	local inventory = {}
	if type(value) ~= "table" then
		return inventory
	end
	for key, item in value do
		if type(key) == "number" and type(item) == "string" and item ~= "" then
			inventory[item] = true
		elseif type(key) == "string" and key ~= "" and item == true then
			inventory[key] = true
		end
	end
	return inventory
end

local function sanitize_loadout(value): { [number]: string }
	local loadout = loadout_slots.create_empty()
	if type(value) ~= "table" then
		return loadout
	end
	for _, slot in loadout_slots.get_all() do
		loadout[slot.id] = type(value[slot.id]) == "string" and value[slot.id] or ""
	end
	return loadout
end

local function sanitize_backpack(value): { [string]: BackpackPlacement }
	local backpack = {}
	if type(value) ~= "table" then
		return backpack
	end
	for gun_id, placement in value do
		if type(gun_id) == "string" and type(placement) == "table" then
			local x = tonumber(placement.x)
			local y = tonumber(placement.y)
			if x and y then
				backpack[gun_id] = { x = math.floor(x), y = math.floor(y) }
			end
		end
	end
	return backpack
end

local function sanitize_attachments(value): { [string]: AttachmentMap }
	local attachments = {}
	if type(value) ~= "table" then
		return attachments
	end
	for gun_id, gun_attachments in value do
		if type(gun_id) == "string" and type(gun_attachments) == "table" then
			local clean = {}
			for attachment_type, attachment_name in gun_attachments do
				if type(attachment_type) == "string" and type(attachment_name) == "string" and attachment_name ~= "" then
					clean[attachment_type] = attachment_name
				end
			end
			if next(clean) ~= nil then
				attachments[gun_id] = clean
			end
		end
	end
	return attachments
end

function player_data_schema.migrate(raw_data: any, player: Player?): PlayerData?
	if type(raw_data) ~= "table" then
		return nil
	end
	return {
		version = CURRENT_VERSION,
		scoped_user_id = tostring(raw_data.scoped_user_id or (player and player.UserId) or ""),
		session_id = type(raw_data.session_id) == "string" and raw_data.session_id or nil,
		cash = sanitize_cash(raw_data.cash),
		inventory = sanitize_inventory(raw_data.inventory),
		loadout = sanitize_loadout(raw_data.loadout),
		backpack = sanitize_backpack(raw_data.backpack),
		attachments = sanitize_attachments(raw_data.attachments),
		saved_at = tonumber(raw_data.saved_at),
		previous_saved_at = tonumber(raw_data.previous_saved_at),
	}
end

function player_data_schema.serialize(player: Player, session_id: string?, state: any): PlayerData
	return {
		version = CURRENT_VERSION,
		scoped_user_id = tostring(player.UserId),
		session_id = session_id,
		cash = sanitize_cash(state.cash),
		inventory = sanitize_inventory(state.inventory),
		loadout = sanitize_loadout(state.loadout),
		backpack = sanitize_backpack(state.backpack),
		attachments = sanitize_attachments(state.attachments),
		saved_at = os.time(),
	}
end

return player_data_schema
