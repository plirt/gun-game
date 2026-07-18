local DataStoreService = game:GetService("DataStoreService")

local player_data_store = {}

local STORE_NAME = "PlayerInventoryV1"
local KEY_PREFIX = "player:"
local MAX_ATTEMPTS = 4
local BASE_RETRY_DELAY = 0.8

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

function player_data_store.load(player: Player): (boolean, any)
	local key = get_player_key(player)
	local ok, result = run_with_retries(function()
		return store:GetAsync(key)
	end)
	if not ok then
		warn("Data load failed for", player.UserId, result)
		return false, nil
	end
	return true, result
end

function player_data_store.save(player: Player, data: any): boolean
	local key = get_player_key(player)
	local ok, result = run_with_retries(function()
		return store:UpdateAsync(key, function(previous_data)
			if type(previous_data) == "table" and type(data) == "table" then
				data.previous_saved_at = previous_data.saved_at
			end
			return data
		end)
	end)
	if not ok then
		warn("Data save failed for", player.UserId, result)
		return false
	end
	return true
end

return player_data_store
