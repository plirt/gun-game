local player_save_queue = {}

local queued_players: { [Player]: boolean } = {}
local saving_players: { [Player]: boolean } = {}

function player_save_queue.is_queued(player: Player): boolean
	return queued_players[player] == true
end

function player_save_queue.enqueue(player: Player)
	queued_players[player] = true
end

function player_save_queue.clear(player: Player)
	queued_players[player] = nil
end

function player_save_queue.remove(player: Player)
	queued_players[player] = nil
	saving_players[player] = nil
end

function player_save_queue.flush(save_callback: (Player) -> boolean)
	for player in queued_players do
		if not saving_players[player] then
			saving_players[player] = true
			local saved = save_callback(player)
			saving_players[player] = nil
			if saved then
				queued_players[player] = nil
			end
		end
	end
end

return player_save_queue
