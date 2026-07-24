local DataStoreService = game:GetService("DataStoreService")

local player_data_store = {}

local player_data_schema = require(script.Parent.PlayerDataSchema)
type PlayerData = player_data_schema.PlayerData

local STORE_NAME = "PlayerInventoryV1"
local KEY_PREFIX = "player:"
local MAX_ATTEMPTS = 4
local BASE_RETRY_DELAY = 0.8
local SESSION_LEASE_SECONDS = 120

local store = DataStoreService:GetDataStore(STORE_NAME)

local function get_player_key(player: Player): string
	return KEY_PREFIX .. tostring(player.UserId)
end

local function get_retry_delay(attempt: number): number
	return BASE_RETRY_DELAY * attempt + math.random() * 0.2
end

local function run_with_retries(callback): (boolean, any)
	local last_error = nil
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		last_error = result
		if attempt < MAX_ATTEMPTS then
			task.wait(get_retry_delay(attempt))
		end
	end
	return false, last_error
end

-- open claims a renewable datastore lease before returning profile data.
-- Why: UpdateAsync alone prevents write races inside one call, but an older server can still
-- overwrite a newer session minutes later. The lease turns that cross-server race into a
-- rejected write. A crashed server releases ownership automatically when the lease expires.
function player_data_store.open(player: Player, session_id: string): (boolean, any)
	local key = get_player_key(player)
	local acquired = false
	local now = os.time()
	local ok, result = run_with_retries(function()
		return store:UpdateAsync(key, function(previous_data)
			acquired = false
			local previous = type(previous_data) == "table" and previous_data or {}
			local active_session = previous.active_session
			local lease_expires_at = tonumber(previous.session_lease_expires_at) or 0
			if type(active_session) == "string"
				and active_session ~= session_id
				and lease_expires_at > now
			then
				return nil
			end
			local claimed = table.clone(previous)
			claimed.active_session = session_id
			claimed.session_lease_expires_at = now + SESSION_LEASE_SECONDS
			acquired = true
			return claimed
		end)
	end)
	if not ok then
		warn("Data session open failed for", player.UserId, result)
		return false, nil
	end
	if not acquired then
		warn("Data session already active for", player.UserId)
		return false, nil
	end
	return true, result
end

function player_data_store.save(player: Player, session_id: string, data: PlayerData): boolean
	local key = get_player_key(player)
	local accepted = false
	local now = os.time()
	local ok, result = run_with_retries(function()
		return store:UpdateAsync(key, function(previous_data)
			accepted = false
			local previous = type(previous_data) == "table" and previous_data or {}
			local active_session = previous.active_session
			local lease_expires_at = tonumber(previous.session_lease_expires_at) or 0
			if type(active_session) == "string"
				and active_session ~= session_id
				and lease_expires_at > now
			then
				return nil
			end
			local next_data = table.clone(data)
			next_data.previous_saved_at = previous.saved_at
			next_data.active_session = session_id
			next_data.session_lease_expires_at = now + SESSION_LEASE_SECONDS
			accepted = true
			return next_data
		end)
	end)
	if not ok or not accepted then
		warn("Data save rejected for", player.UserId, result)
		return false
	end
	return true
end

function player_data_store.release(player: Player, session_id: string): boolean
	local key = get_player_key(player)
	local released = false
	local ok, result = run_with_retries(function()
		return store:UpdateAsync(key, function(previous_data)
			released = false
			if type(previous_data) ~= "table" or previous_data.active_session ~= session_id then
				return nil
			end
			local next_data = table.clone(previous_data)
			next_data.active_session = nil
			next_data.session_lease_expires_at = nil
			released = true
			return next_data
		end)
	end)
	if not ok then
		warn("Data session release failed for", player.UserId, result)
	end
	return ok and released
end

return player_data_store

