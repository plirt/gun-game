local Teams = game:GetService("Teams")

local npc_values = require(script.Parent.Npc.NpcValues)

local MatchTeams = {}

local function get_team_instance(team_info)
	local team = Teams:FindFirstChild(team_info.name)
	if team and team:IsA("Team") then
		return team
	end
	team = Instance.new("Team")
	team.Name = team_info.name
	team.TeamColor = team_info.brick_color
	team.AutoAssignable = false
	team.Parent = Teams
	return team
end

local function clear_round_teams(players: Players, state)
	for _, player in players:GetPlayers() do
		player.Neutral = true
		player.Team = nil
	end
	local npcs = workspace:FindFirstChild("Npcs")
	if npcs then
		for _, npc in npcs:GetChildren() do
			if npc:IsA("Model") then
				npc_values.clear(npc, "team_id")
			end
		end
	end
	table.clear(state.team_assignments)
	table.clear(state.team_scores)
end

local function build_team_scores(state, mode)
	table.clear(state.team_scores)
	if not mode.teams then
		return
	end
	for _, team_info in mode.teams do
		state.team_scores[team_info.id] = {
			id = team_info.id,
			name = team_info.name,
			score = 0,
		}
	end
end

local function get_smallest_team_id(state, mode): string?
	local best_team_id = nil
	local best_count = math.huge
	for _, team_info in mode.teams or {} do
		local count = 0
		for _, assigned_team_id in state.team_assignments do
			if assigned_team_id == team_info.id then
				count += 1
			end
		end
		if count < best_count then
			best_count = count
			best_team_id = team_info.id
		end
	end
	return best_team_id
end

local function find_mode(mode_rotation, mode_id)
	for _, mode in mode_rotation do
		if mode.id == mode_id then
			return mode
		end
	end
	return nil
end

function MatchTeams.assign_round_teams(players: Players, state, mode, match_mode_registry)
	clear_round_teams(players, state)
	build_team_scores(state, mode)
	local mode_module = match_mode_registry.get_module(mode.id)
	if not mode_module.assign_teams then
		return
	end
	state.team_assignments = mode_module.assign_teams(players:GetPlayers())
	local team_lookup = {}
	for _, team_info in mode.teams or {} do
		team_lookup[team_info.id] = get_team_instance(team_info)
	end
	for player, team_id in state.team_assignments do
		local team = team_lookup[team_id]
		if team and player:IsA("Player") then
			player.Team = team
			player.Neutral = false
		end
	end
end

function MatchTeams.assign_npc_to_round(state, mode_rotation, npc: Model)
	local match = state.current_match
	if state.phase ~= "round" or not match then
		npc_values.clear(npc, "team_id")
		return
	end
	local mode = find_mode(mode_rotation, match.id)
	if not mode or not mode.teams then
		state.team_assignments[npc] = nil
		npc_values.clear(npc, "team_id")
		return
	end
	local team_id = get_smallest_team_id(state, mode)
	if not team_id then
		return
	end
	state.team_assignments[npc] = team_id
	npc_values.write_string(npc, "team_id", team_id)
end

function MatchTeams.assign_joining_player(state, mode_rotation, player: Player)
	local match = state.current_match
	if state.phase ~= "round" or not match then
		player.Neutral = true
		player.Team = nil
		return
	end
	local mode = find_mode(mode_rotation, match.id)
	if not mode or not mode.teams then
		player.Neutral = true
		player.Team = nil
		return
	end
	local team_lookup = {}
	for _, team_info in mode.teams do
		team_lookup[team_info.id] = get_team_instance(team_info)
	end
	local team_id = get_smallest_team_id(state, mode)
	local team = team_id and team_lookup[team_id]
	if not team then
		return
	end
	state.team_assignments[player] = team_id
	player.Team = team
	player.Neutral = false
end

return MatchTeams

