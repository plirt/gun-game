local match_service = {}

local Teams = game:GetService("Teams")

local match_mode_registry = require(script.Parent.match_mode_registry)
local constants = require(script.Parent.server_constants)
local npc_values = require(script.Parent.Npc.npc_values)

type PlayerScore = {
	kills: number,
	deaths: number,
	team_id: string?,
}

type WinnerList = { any }

local KILL_LIMIT = 30
local DAMAGE_CREDIT_SECONDS = 8
local UPDATE_INTERVAL = 1

local mode_rotation = match_mode_registry.get_modes()

local state = {
	phase = "intermission",
	mode_index = 0,
	match_id = 0,
	current_match = nil,
	votes = {},
	scores = {},
	team_assignments = {},
	team_scores = {},
	last_damage = {},
	last_broadcast = 0,
	last_vote = {},
	vote_broadcast_queued = false,
	objective_state = nil,
	last_mode_update = 0,
}

local bound_humanoids = setmetatable({}, { __mode = "k" })
local resolved_deaths = setmetatable({}, { __mode = "k" })

local function is_player(entity)
	return typeof(entity) == "Instance" and entity:IsA("Player")
end

local function is_npc(entity)
	local npcs = workspace:FindFirstChild("Npcs")
	return typeof(entity) == "Instance"
		and entity:IsA("Model")
		and npcs ~= nil
		and entity:IsDescendantOf(npcs)
end

local function get_combat_entity(ctx, humanoid)
	local model = humanoid and humanoid.Parent
	local player = model and ctx.Players:GetPlayerFromCharacter(model)
	if player then
		return player
	end
	if is_npc(model) then
		return model
	end
	return nil
end

local function get_or_create_remote(ctx, name: string): RemoteEvent
	local remote = ctx.remotes:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ctx.remotes
	return remote
end

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

local function clear_round_teams(ctx)
	for _, player in ctx.Players:GetPlayers() do
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

local function build_team_scores(mode)
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

local function assign_round_teams(ctx, mode)
	clear_round_teams(ctx)
	build_team_scores(mode)
	local module = match_mode_registry.get_module(mode.id)
	if not module.assign_teams then
		return
	end
	state.team_assignments = module.assign_teams(ctx.Players:GetPlayers())
	local team_lookup = {}
	for _, team_info in mode.teams or {} do
		team_lookup[team_info.id] = get_team_instance(team_info)
	end
	for player, team_id in state.team_assignments do
		local team = team_lookup[team_id]
		if team then
			player.Team = team
			player.Neutral = false
		end
	end
end

local function get_smallest_team_id(mode)
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

local function assign_npc_to_round(npc)
	local match = state.current_match
	if state.phase ~= "round" or not match then
		npc_values.clear(npc, "team_id")
		return
	end
	local mode
	for _, candidate in mode_rotation do
		if candidate.id == match.id then
			mode = candidate
			break
		end
	end
	if not mode or not mode.teams then
		state.team_assignments[npc] = nil
		npc_values.clear(npc, "team_id")
		return
	end
	local team_id = get_smallest_team_id(mode)
	if not team_id then
		return
	end
	state.team_assignments[npc] = team_id
	npc_values.write_string(npc, "team_id", team_id)
end

local function assign_joining_player(ctx, player: Player)
	local match = state.current_match
	if state.phase ~= "round" or not match then
		player.Neutral = true
		player.Team = nil
		return
	end
	local mode = nil
	for _, candidate in mode_rotation do
		if candidate.id == match.id then
			mode = candidate
			break
		end
	end
	if not mode or not mode.teams then
		player.Neutral = true
		player.Team = nil
		return
	end
	local team_lookup = {}
	for _, team_info in mode.teams do
		team_lookup[team_info.id] = get_team_instance(team_info)
	end
	local team_id = get_smallest_team_id(mode)
	local team = team_id and team_lookup[team_id]
	if not team then
		return
	end
	state.team_assignments[player] = team_id
	player.Team = team
	player.Neutral = false
end

local function get_leaderstat(player: Player, name: string): IntValue
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	local value = leaderstats:FindFirstChild(name)
	if value and value:IsA("IntValue") then
		return value
	end
	value = Instance.new("IntValue")
	value.Name = name
	value.Parent = leaderstats
	return value
end

local function sync_player_leaderstats(player: Player)
	local score = state.scores[player]
	local kills = get_leaderstat(player, "Kills")
	local deaths = get_leaderstat(player, "Deaths")
	kills.Value = score and score.kills or 0
	deaths.Value = score and score.deaths or 0
end

local function sync_all_leaderstats(ctx)
	for _, player in ctx.Players:GetPlayers() do
		sync_player_leaderstats(player)
	end
end

local function ensure_score(player: Player): PlayerScore
	local score = state.scores[player]
	if score then
		return score
	end
	score = {
		kills = 0,
		deaths = 0,
		team_id = state.team_assignments[player],
	}
	state.scores[player] = score
	sync_player_leaderstats(player)
	return score
end

local function reset_scores(ctx)
	table.clear(state.scores)
	for _, player in ctx.Players:GetPlayers() do
		ensure_score(player)
	end
	sync_all_leaderstats(ctx)
end

local function serialize_scores()
	local scores = {}
	for player, score in state.scores do
		table.insert(scores, {
			user_id = player.UserId,
			name = player.Name,
			display_name = player.DisplayName,
			team_id = score.team_id,
			kills = score.kills,
			deaths = score.deaths,
		})
	end
	table.sort(scores, function(a, b)
		if a.kills == b.kills then
			if a.deaths == b.deaths then
				return a.name < b.name
			end
			return a.deaths < b.deaths
		end
		return a.kills > b.kills
	end)
	return scores
end

local function serialize_team_scores()
	local team_scores = {}
	for _, team_score in state.team_scores do
		table.insert(team_scores, {
			id = team_score.id,
			name = team_score.name,
			score = math.floor(team_score.score + 0.0001),
		})
	end
	table.sort(team_scores, function(a, b)
		if a.score == b.score then
			return a.name < b.name
		end
		return a.score > b.score
	end)
	return team_scores
end

local function serialize_vote_options()
	local options = {}
	local vote_counts = {}
	for _, mode in mode_rotation do
		vote_counts[mode.id] = 0
	end
	for _, mode_id in state.votes do
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
	local result = {}
	for _, winner in winners do
		if typeof(winner) == "Instance" and winner:IsA("Player") then
			table.insert(result, {
				type = "player",
				user_id = winner.UserId,
				name = winner.Name,
				display_name = winner.DisplayName,
			})
		elseif type(winner) == "table" then
			table.insert(result, winner)
		end
	end
	return result
end

local function get_payload(winners)
	local match = state.current_match
	local default_mode = match_mode_registry.get_default_mode()
	return {
		phase = state.phase,
		match_id = state.match_id,
		mode_id = match and match.id or "",
		mode_name = match and match.name or "",
		kill_limit = match and match.kill_limit or default_mode.kill_limit or KILL_LIMIT,
		score_limit = match and match.score_limit or match and match.kill_limit or default_mode.kill_limit or KILL_LIMIT,
		objective = match and match.objective or nil,
		objective_state = state.objective_state,
		round_seconds = match and match.round_seconds or default_mode.round_seconds or 0,
		intermission_seconds = match and match.intermission_seconds or default_mode.intermission_seconds or 0,
		ends_at = match and match.ends_at or 0,
		starts_at = match and match.starts_at or 0,
		server_time = os.clock(),
		scores = serialize_scores(),
		team_scores = serialize_team_scores(),
		winners = winners and serialize_winners(winners) or {},
		vote_options = state.phase == "intermission" and serialize_vote_options() or {},
	}
end

local function broadcast(ctx, winners: WinnerList?)
	get_or_create_remote(ctx, "MatchState"):FireAllClients(get_payload(winners))
	state.last_broadcast = os.clock()
end

local function queue_vote_broadcast(ctx)
	if state.vote_broadcast_queued then
		return
	end
	state.vote_broadcast_queued = true
	task.delay(constants.MATCH_VOTE_UPDATE_INTERVAL, function()
		state.vote_broadcast_queued = false
		if state.phase == "intermission" then
			broadcast(ctx)
		end
	end)
end

local function broadcast_to_player(ctx, player: Player, winners: WinnerList?)
	get_or_create_remote(ctx, "MatchState"):FireClient(player, get_payload(winners))
end

local function next_mode()
	state.mode_index += 1
	if state.mode_index > #mode_rotation then
		state.mode_index = 1
	end
	return mode_rotation[state.mode_index]
end

local function get_voted_mode()
	local options = mode_rotation
	if #options == 0 then
		return next_mode()
	end
	local counts = {}
	for _, mode in options do
		counts[mode.id] = 0
	end
	for _, mode_id in state.votes do
		if counts[mode_id] ~= nil then
			counts[mode_id] += 1
		end
	end
	local best_modes = {}
	local best_count = -1
	for _, mode in options do
		local count = counts[mode.id] or 0
		if count > best_count then
			table.clear(best_modes)
			table.insert(best_modes, mode)
			best_count = count
		elseif count == best_count then
			table.insert(best_modes, mode)
		end
	end
	if #best_modes == 0 then
		return next_mode()
	end
	state.mode_index += 1
	if state.mode_index > #best_modes then
		state.mode_index = 1
	end
	return best_modes[state.mode_index]
end

local function reset_vote()
	table.clear(state.votes)
	table.clear(state.last_vote)
	state.vote_broadcast_queued = false
end

local function start_intermission(ctx, winners: WinnerList?)
	local previous_match = state.current_match
	if state.phase == "round" and previous_match then
		local previous_mode = match_mode_registry.get_module(previous_match.id)
		if previous_mode.stop then
			previous_mode.stop(ctx, previous_match)
		end
	end
	if ctx.npc_fill_service then
		ctx.npc_fill_service.end_round(ctx)
	end
	
	state.phase = "intermission"
	state.match_id += 1
	state.objective_state = nil
	state.last_mode_update = 0
	reset_vote()
	local mode = mode_rotation[state.mode_index + 1] or mode_rotation[1]
	state.current_match = {
		id = mode.id,
		name = mode.name,
		kill_limit = mode.kill_limit,
		score_limit = mode.score_limit or mode.kill_limit,
		objective = mode.objective,
		round_seconds = mode.round_seconds,
		intermission_seconds = mode.intermission_seconds,
		starts_at = os.clock() + mode.intermission_seconds,
		ends_at = 0,
	}
	broadcast(ctx, winners)
end

local function start_round(ctx)
	local mode = get_voted_mode()
	state.phase = "round"
	state.match_id += 1
	state.objective_state = nil
	state.last_mode_update = os.clock()
	table.clear(state.votes)
	state.current_match = {
		id = mode.id,
		name = mode.name,
		kill_limit = mode.kill_limit,
		score_limit = mode.score_limit or mode.kill_limit,
		objective = mode.objective,
		round_seconds = mode.round_seconds,
		intermission_seconds = mode.intermission_seconds,
		starts_at = os.clock(),
		ends_at = os.clock() + mode.round_seconds,
	}
	assign_round_teams(ctx, mode)
	local npcs = workspace:FindFirstChild("Npcs")
	if npcs then
		for _, npc in npcs:GetChildren() do
			if npc:IsA("Model") then
				assign_npc_to_round(npc)
			end
		end
	end
	reset_scores(ctx)

	if ctx.npc_fill_service then
		ctx.npc_fill_service.start_round(ctx, "Default")
	else
		warn("ctx.npc_fill_service missing on round start")
	end
	local active_mode = match_mode_registry.get_module(mode.id)
	if active_mode.start then
		active_mode.start(ctx, state.current_match)
	end
	broadcast(ctx)
end

local function on_vote(ctx, player: Player, mode_id: any)
	if state.phase ~= "intermission" or type(mode_id) ~= "string" then
		return
	end
	local now = os.clock()
	local last_vote = state.last_vote[player] or 0
	if now - last_vote < constants.MATCH_VOTE_UPDATE_INTERVAL then
		return
	end
	for _, mode in mode_rotation do
		if mode.id == mode_id then
			state.last_vote[player] = now
			state.votes[player] = mode_id
			queue_vote_broadcast(ctx)
			return
		end
	end
end

local function finish_round(ctx)
	if ctx.npc_fill_service then
		ctx.npc_fill_service.end_round(ctx)
	end
	
	local match = state.current_match
	if not match then
		start_intermission(ctx)
		return
	end
	local mode = match_mode_registry.get_module(match.id)
	local winners = mode.get_winners(state.scores, state.team_scores)
	start_intermission(ctx, winners)
end

local function credit_recent_damage(humanoid: Humanoid, attacker)
	state.last_damage[humanoid] = {
		attacker = attacker,
		time = os.clock(),
	}
end

local function consume_recent_damage(humanoid: Humanoid)
	local credit = state.last_damage[humanoid]
	state.last_damage[humanoid] = nil
	if not credit or os.clock() - credit.time > DAMAGE_CREDIT_SECONDS then
		return nil
	end
	if not credit.attacker.Parent then
		return nil
	end
	return credit.attacker
end

local function on_entity_died(ctx, victim, humanoid: Humanoid)
	if state.phase ~= "round" or resolved_deaths[humanoid] then
		return
	end
	resolved_deaths[humanoid] = true
	local killer = consume_recent_damage(humanoid)
	local match = state.current_match
	local mode = match and match_mode_registry.get_module(match.id) or match_mode_registry.get_module(match_mode_registry.get_default_mode().id)
	if is_player(victim) then
		ensure_score(victim)
		mode.score_death(state.scores, victim)
	end
	if killer and killer ~= victim then
		if is_player(killer) then
			ensure_score(killer)
		end
		mode.score_kill(state.scores, state.team_scores, state.team_assignments, killer, victim)
		if is_player(killer) then
			sync_player_leaderstats(killer)
		end
	end
	if is_player(victim) then
		sync_player_leaderstats(victim)
	elseif is_npc(victim) then
		state.team_assignments[victim] = nil
		if ctx.npc_fill_service then
			ctx.npc_fill_service.queue_respawn(ctx, victim)
		end
	end
	broadcast(ctx)
	if match and mode.should_end(match, state.scores, state.team_scores) then
		finish_round(ctx)
	end
end

local function bind_character(ctx, player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") or bound_humanoids[humanoid] then
		return
	end
	bound_humanoids[humanoid] = true
	ensure_score(player)
	humanoid.Died:Connect(function()
		on_entity_died(ctx, player, humanoid)
	end)
end

local function bind_npc(ctx, npc)
	if not npc:IsA("Model") then
		return
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid") or npc:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") or bound_humanoids[humanoid] then
		return
	end
	bound_humanoids[humanoid] = true
	assign_npc_to_round(npc)
	humanoid.Died:Connect(function()
		on_entity_died(ctx, npc, humanoid)
	end)
end

function match_service.register_npc(ctx, npc)
	bind_npc(ctx, npc)
end

function match_service.get_combat_entity(ctx, humanoid: Humanoid)
	return get_combat_entity(ctx, humanoid)
end

function match_service.record_damage(ctx, attacker, humanoid: Humanoid)
	local victim = get_combat_entity(ctx, humanoid)
	if not victim or victim == attacker or not match_service.can_damage(ctx, attacker, victim) then
		return
	end
	credit_recent_damage(humanoid, attacker)
end

function match_service.record_death(ctx, humanoid: Humanoid)
	local victim = get_combat_entity(ctx, humanoid)
	if victim then
		on_entity_died(ctx, victim, humanoid)
	end
end

function match_service.can_damage(ctx, attacker, victim): boolean
	if not attacker or not victim or attacker == victim then
		return false
	end
	local match = state.current_match
	if state.phase ~= "round" or not match then
		return true
	end
	local mode = match_mode_registry.get_module(match.id)
	if not mode.can_damage then
		return true
	end
	return mode.can_damage(state.team_assignments, attacker, victim)
end

function match_service.is_round_active()
	return state.phase == "round" and state.current_match ~= nil
end

function match_service.get_objective_position()
	local match = state.current_match
	if state.phase ~= "round" or not match or match.objective ~= "hill" then
		return nil
	end
	local objectives = workspace:FindFirstChild("Objectives")
	local hill = objectives and objectives:FindFirstChild("KingOfTheHill")
	return hill and hill:IsA("BasePart") and hill.Position or nil
end

function match_service.setup(ctx)
	ctx.match_service = match_service
	get_or_create_remote(ctx, "MatchState")
	get_or_create_remote(ctx, "MatchVote").OnServerEvent:Connect(function(player, mode_id)
		on_vote(ctx, player, mode_id)
	end)
	for _, player in ctx.Players:GetPlayers() do
		ensure_score(player)
		if player.Character then
			bind_character(ctx, player, player.Character)
		end
	end
	local npcs = workspace:FindFirstChild("Npcs")
	if npcs then
		for _, npc in npcs:GetChildren() do
			bind_npc(ctx, npc)
		end
		npcs.ChildAdded:Connect(function(npc)
			task.defer(bind_npc, ctx, npc)
		end)
	end
	ctx.Players.PlayerAdded:Connect(function(player)
		assign_joining_player(ctx, player)
		ensure_score(player)
		player.CharacterAdded:Connect(function(character)
			bind_character(ctx, player, character)
		end)
		broadcast_to_player(ctx, player)
	end)
	ctx.Players.PlayerRemoving:Connect(function(player)
		state.scores[player] = nil
		state.votes[player] = nil
		state.last_vote[player] = nil
		state.team_assignments[player] = nil
		state.last_broadcast = 0
		broadcast(ctx)
	end)
	start_intermission(ctx)
	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()
			local match = state.current_match
			if state.phase == "intermission" and match and now >= match.starts_at then
				start_round(ctx)
			elseif state.phase == "intermission" and match and now - state.last_broadcast >= UPDATE_INTERVAL then
				broadcast(ctx)
			elseif state.phase == "round" and match then
				local mode = match_mode_registry.get_module(match.id)
				local delta_time = math.min(math.max(now - state.last_mode_update, 0), 0.5)
				state.last_mode_update = now
				if mode.update then
					state.objective_state = mode.update(ctx, match, state.scores, state.team_scores, state.team_assignments, delta_time)
				end
				if mode.should_end(match, state.scores, state.team_scores) then
					finish_round(ctx)
				elseif now - state.last_broadcast >= UPDATE_INTERVAL then
					broadcast(ctx)
				end
			end
		end
	end)
end

return match_service
