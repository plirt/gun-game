local MatchReplication = {}

local match_mode_registry = require(script.Parent.MatchModeRegistry)

type TeamWinner = {
	type: string,
	id: string,
	name: string,
	score: number,
}

type Winner = Player | TeamWinner
type WinnerList = { Winner }

function MatchReplication.get_remote(remotes: Folder, name: string): RemoteEvent
	local remote = remotes:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local function serialize_scores(scores)
	local serialized = {}
	for player, score in scores do
		table.insert(serialized, {
			user_id = player.UserId,
			name = player.Name,
			display_name = player.DisplayName,
			team_id = score.team_id,
			kills = score.kills,
			deaths = score.deaths,
		})
	end
	table.sort(serialized, function(a, b)
		if a.kills == b.kills then
			if a.deaths == b.deaths then
				return a.name < b.name
			end
			return a.deaths < b.deaths
		end
		return a.kills > b.kills
	end)
	return serialized
end

local function serialize_team_scores(team_scores)
	local serialized = {}
	for _, team_score in team_scores do
		table.insert(serialized, {
			id = team_score.id,
			name = team_score.name,
			score = math.floor(team_score.score + 0.0001),
		})
	end
	table.sort(serialized, function(a, b)
		if a.score == b.score then
			return a.name < b.name
		end
		return a.score > b.score
	end)
	return serialized
end

local function serialize_vote_options(mode_rotation, votes)
	local options = {}
	local vote_counts = {}
	for _, mode in mode_rotation do
		vote_counts[mode.id] = 0
	end
	for _, mode_id in votes do
		if vote_counts[mode_id] ~= nil then
			vote_counts[mode_id] += 1
		end
	end
	for _, mode in mode_rotation do
		table.insert(options, {
			id = mode.id,
			name = mode.name,
			votes = vote_counts[mode.id] or 0,
		})
	end
	return options
end

local function serialize_winners(winners: WinnerList)
	local serialized = {}
	for _, winner in winners do
		if typeof(winner) == "Instance" and winner:IsA("Player") then
			table.insert(serialized, {
				type = "player",
				user_id = winner.UserId,
				name = winner.Name,
				display_name = winner.DisplayName,
			})
		else
			table.insert(serialized, winner)
		end
	end
	return serialized
end

local function serialize_bounty(bounty)
	local target = bounty and bounty.target
	if not target or not target:IsA("Player") or not target.Parent then
		return nil
	end
	return {
		target_user_id = target.UserId,
		target_name = target.Name,
		target_display_name = target.DisplayName,
		reward = bounty.reward,
		expires_at = bounty.expires_at,
	}
end

local function get_payload(state, mode_rotation, winners: WinnerList?)
	local match = state.current_match
	local default_mode = match_mode_registry.get_default_mode()
	return {
		phase = state.phase,
		match_id = state.match_id,
		mode_id = match and match.id or "",
		mode_name = match and match.name or "",
		kill_limit = match and match.kill_limit or default_mode.kill_limit or 30,
		score_limit = match and match.score_limit or match and match.kill_limit or default_mode.kill_limit or 30,
		objective = match and match.objective or nil,
		objective_state = state.objective_state,
		round_seconds = match and match.round_seconds or default_mode.round_seconds or 0,
		intermission_seconds = match and match.intermission_seconds or default_mode.intermission_seconds or 0,
		ends_at = match and match.ends_at or 0,
		starts_at = match and match.starts_at or 0,
		server_time = os.clock(),
		scores = serialize_scores(state.scores),
		team_scores = serialize_team_scores(state.team_scores),
		winners = winners and serialize_winners(winners) or {},
		vote_options = state.phase == "intermission" and serialize_vote_options(mode_rotation, state.votes) or {},
		bounty = serialize_bounty(state.bounty),
	}
end

function MatchReplication.broadcast(remotes: Folder, state, mode_rotation, winners: WinnerList?)
	MatchReplication.get_remote(remotes, "MatchState"):FireAllClients(get_payload(state, mode_rotation, winners))
	state.last_broadcast = os.clock()
end

function MatchReplication.broadcast_to_player(
	remotes: Folder,
	state,
	mode_rotation,
	player: Player,
	winners: WinnerList?
)
	MatchReplication.get_remote(remotes, "MatchState"):FireClient(player, get_payload(state, mode_rotation, winners))
end

return MatchReplication

