local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local loadout_slots = require(ReplicatedStorage.Modules.Shared.LoadoutSlots)

local player_state = {}

local player_data_schema = require(script.Parent.player_data_schema)
local player_data_store = require(script.Parent.player_data_store)
local player_save_queue = require(script.Parent.player_save_queue)

export type WeaponRuntimeState = {
	magazine: number,
	reserve: number,
	last_fire_time: number,
	reloading: boolean,
	reload_started: number?,
}

export type PlayerState = {
	cash: number,
	inventory: { [string]: boolean },
	loadout: { [number]: string },
	backpack: { [string]: { x: number, y: number } },
	attachments: { [string]: { [string]: string } },
	weapon_states: { [string]: WeaponRuntimeState },
}

type ServerContext = {
	Players: Players,
	gun_configs: Folder,
	weapon_config: any,
}

local context: ServerContext? = nil
local states: { [Player]: PlayerState } = {}
local dirty_players: { [Player]: boolean } = {}
local save_session_ids: { [Player]: string } = {}
local config_cache: { [string]: any } = {}
local SAVE_FLUSH_INTERVAL = 20

local function get_context(): ServerContext
	assert(context, "player_state.setup must be called before using player_state")
	return context :: ServerContext
end

local function create_default_state(): PlayerState
	return {
		cash = 1000,
		inventory = { GLOCK = true, GRENADE = true },
		loadout = { [1] = "GLOCK", [2] = "", [3] = "GRENADE" },
		backpack = { GLOCK = { x = 1, y = 1 } },
		attachments = {},
		weapon_states = {},
	}
end

local function clone_string_map(map)
	local result = {}
	if type(map) ~= "table" then
		return result
	end
	for key, value in map do
		if type(key) == "string" and value == true then
			result[key] = true
		end
	end
	return result
end

local function clone_backpack(map)
	local result = {}
	if type(map) ~= "table" then
		return result
	end
	for gun_id, placement in map do
		if type(gun_id) == "string" and type(placement) == "table" then
			local x = tonumber(placement.x)
			local y = tonumber(placement.y)
			if x and y then
				result[gun_id] = { x = math.floor(x), y = math.floor(y) }
			end
		end
	end
	return result
end

local function clone_attachments(map)
	local result = {}
	if type(map) ~= "table" then
		return result
	end
	for gun_id, attachments in map do
		if type(gun_id) == "string" and type(attachments) == "table" then
			local gun_attachments = {}
			for attachment_type, attachment_name in attachments do
				if type(attachment_type) == "string" and type(attachment_name) == "string" and attachment_name ~= "" then
					gun_attachments[attachment_type] = attachment_name
				end
			end
			if next(gun_attachments) ~= nil then
				result[gun_id] = gun_attachments
			end
		end
	end
	return result
end

local function apply_saved_data(default_state: PlayerState, data): PlayerState
	if type(data) ~= "table" then
		return default_state
	end
	local cash = tonumber(data.cash)
	if cash then
		default_state.cash = math.max(0, math.floor(cash))
	end
	local inventory = clone_string_map(data.inventory)
	if next(inventory) ~= nil then
		default_state.inventory = inventory
		default_state.inventory.GLOCK = true
	end
	default_state.inventory.GRENADE = true
	if type(data.loadout) == "table" then
		for _, slot in loadout_slots.get_all() do
			if type(data.loadout[slot.id]) == "string" then
				default_state.loadout[slot.id] = data.loadout[slot.id]
			end
		end
	end
	if default_state.loadout[3] == "" then
		default_state.loadout[3] = "GRENADE"
	end
	local backpack = clone_backpack(data.backpack)
	if next(backpack) ~= nil then
		default_state.backpack = backpack
	end
	default_state.attachments = clone_attachments(data.attachments)
	return default_state
end

local function inventory_array_to_map(data)
	if type(data) ~= "table" then
		return data
	end
	if type(data.inventory) ~= "table" then
		return data
	end
	local inventory = {}
	for key, value in data.inventory do
		if type(key) == "number" and type(value) == "string" then
			inventory[value] = true
		elseif type(key) == "string" and value == true then
			inventory[key] = true
		end
	end
	data.inventory = inventory
	return data
end

function player_state.sync_cash_leaderstat(player: Player, state: PlayerState)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local cash = leaderstats:FindFirstChild("Cash")
	if not cash then
		cash = Instance.new("IntValue")
		cash.Name = "Cash"
		cash.Parent = leaderstats
	end
	cash.Value = state.cash
end

function player_state.ensure_player_state(player: Player): PlayerState
	local state = states[player]
	if state then
		return state
	end

	local ok, saved_data = player_data_store.load(player)
	local migrated_data = ok and player_data_schema.migrate(saved_data, player) or nil
	state = apply_saved_data(create_default_state(), migrated_data or inventory_array_to_map(saved_data))
	save_session_ids[player] = HttpService:GenerateGUID(false)
	states[player] = state
	player_state.sync_cash_leaderstat(player, state)
	return state
end

function player_state.mark_dirty(player: Player)
	dirty_players[player] = true
	player_save_queue.enqueue(player)
end

function player_state.save_player(player: Player): boolean
	local state = states[player]
	if not state then
		return false
	end
	local saved = player_data_store.save(player, player_data_schema.serialize(player, save_session_ids[player], state))
	if saved then
		dirty_players[player] = nil
		player_save_queue.clear(player)
	end
	return saved
end

function player_state.save_if_dirty(player: Player): boolean
	if not dirty_players[player] then
		return true
	end
	return player_state.save_player(player)
end

function player_state.set_attachment(player: Player, gun_id: string, attachment_type: string, attachment_name: string?)
	local state = player_state.ensure_player_state(player)
	state.attachments[gun_id] = state.attachments[gun_id] or {}
	if attachment_name and attachment_name ~= "" then
		state.attachments[gun_id][attachment_type] = attachment_name
	else
		state.attachments[gun_id][attachment_type] = nil
		if next(state.attachments[gun_id]) == nil then
			state.attachments[gun_id] = nil
		end
	end
	player_state.mark_dirty(player)
end

function player_state.get_config(gun_name: string): any?
	local cached_config = config_cache[gun_name]
	if cached_config then
		return cached_config
	end
	local ctx = get_context()
	local config_module = ctx.gun_configs:FindFirstChild(gun_name)
	if not config_module or not config_module:IsA("ModuleScript") then
		return nil
	end
	local config = ctx.weapon_config.normalize(require(config_module))
	config_cache[gun_name] = table.freeze(config)
	return config_cache[gun_name]
end

function player_state.get_weapon_state(player: Player, gun_name: string, config: any): WeaponRuntimeState
	local state = player_state.ensure_player_state(player)
	local weapons = state.weapon_states
	if not weapons[gun_name] then
		weapons[gun_name] = {
			magazine = config.magazine_size,
			reserve = config.reserve_ammo,
			last_fire_time = 0,
			reloading = false,
		}
	end
	return weapons[gun_name]
end

function player_state.is_in_loadout(state: PlayerState, gun_name: string): boolean
	for _, slot in loadout_slots.get_all() do
		if state.loadout[slot.id] == gun_name then
			return true
		end
	end
	return false
end

function player_state.is_in_backpack(state: PlayerState, gun_name: string): boolean
	return state.backpack[gun_name] ~= nil
end

function player_state.setup(ctx: ServerContext)
	context = ctx

	ctx.Players.PlayerAdded:Connect(function(player)
		player_state.ensure_player_state(player)
	end)

	ctx.Players.PlayerRemoving:Connect(function(player)
		player_state.save_player(player)
		states[player] = nil
		dirty_players[player] = nil
		player_save_queue.remove(player)
		save_session_ids[player] = nil
	end)

	game:BindToClose(function()
		for player in states do
			player_state.save_player(player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(SAVE_FLUSH_INTERVAL)
			player_save_queue.flush(function(player)
				return player_state.save_if_dirty(player)
			end)
		end
	end)

	for _, player in ctx.Players:GetPlayers() do
		player_state.ensure_player_state(player)
	end
end
return player_state
