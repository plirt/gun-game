local match_service = {}

local match_mode_registry = require(script.Parent.MatchModeRegistry)
local constants = require(script.Parent.ServerConstants)
local player_state = require(script.Parent.PlayerState)
local MatchReplication = require(script.Parent.MatchReplication)
local MatchTeams = require(script.Parent.MatchTeams)
local BountyTracker = require(script.Components.BountyTracker)
local RewardPolicy = require(script.Components.RewardPolicy)

type PlayerScore = {
	kills: number,
	deaths: number,
	team_id: string?,
}

type TeamWinner = {
	type: string,
	id: string,
	name: string,
	score: number,
}

type Winner = Player | TeamWinner
type WinnerList = { Winner }

local DAMAGE_CREDIT_SECONDS = 8
local DEFAULT_UPDATE_INTERVAL = 5
local OBJECTIVE_UPDATE_INTERVAL = 1

local function get_update_interval(match)
	return match and match.objective ~= nil and OBJECTIVE_UPDATE_INTERVAL or DEFAULT_UPDATE_INTERVAL
end

local function get_npc_fill_service(ctx)
	return ctx.runtime:get("NpcFillService")
end

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
	kill_streaks = {},
	bounty = nil,
}

local bound_humanoids = setmetatable({}, { __mode = "k" })
local resolved_deaths = setmetatable({}, { __mode = "k" })
local rewards = nil
local bounty_tracker = nil

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

local function award_cash(_, player, amount: number, reason: string)
	return RewardPolicy.award_cash(rewards, player, amount, reason)
end

local function award_kill_cash(_, killer, victim)
	return RewardPolicy.award_kill(rewards, killer, victim)
end

local function reset_scores(ctx)
	table.clear(state.scores)
	for _, player in ctx.Players:GetPlayers() do
		ensure_score(player)
	end
	sync_all_leaderstats(ctx)
end

local function broadcast(ctx, winners: WinnerList?)
	MatchReplication.broadcast(ctx.remotes, state, mode_rotation, winners)
end

local function clear_bounty()
	bounty_tracker:clear()
end

local function reset_bounty_state()
	bounty_tracker:reset()
end

local function update_bounty_after_death(_, killer, victim)
	bounty_tracker:on_death(killer, victim)
end

local function resolve_expired_bounty(_, now: number)
	return bounty_tracker:resolve_expired(now)
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
	MatchReplication.broadcast_to_player(ctx.remotes, state, mode_rotation, player, winners)
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
	get_npc_fill_service(ctx).end_round(ctx)

	state.phase = "intermission"
	state.match_id += 1
	state.objective_state = nil
	state.last_mode_update = 0
	reset_vote()
	reset_bounty_state()
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
	reset_bounty_state()
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
	MatchTeams.assign_round_teams(ctx.Players, state, mode, match_mode_registry)
	local npcs = workspace:FindFirstChild("Npcs")
	if npcs then
		for _, npc in npcs:GetChildren() do
			if npc:IsA("Model") then
				MatchTeams.assign_npc_to_round(state, mode_rotation, npc)
			end
		end
	end
	reset_scores(ctx)

	get_npc_fill_service(ctx).start_round(ctx, "Default")
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
	get_npc_fill_service(ctx).end_round(ctx)

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
		award_kill_cash(ctx, killer, victim)
		if is_player(killer) then
			sync_player_leaderstats(killer)
		end
	end
	update_bounty_after_death(ctx, killer, victim)
	if is_player(victim) then
		sync_player_leaderstats(victim)
	elseif is_npc(victim) then
		state.team_assignments[victim] = nil
		get_npc_fill_service(ctx).queue_respawn(ctx, victim)
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
	MatchTeams.assign_npc_to_round(state, mode_rotation, npc)
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
	rewards = RewardPolicy.new({
		is_player = is_player,
		is_npc = is_npc,
		player_state = player_state,
		constants = constants,
		remotes = ctx.remotes,
	})
	bounty_tracker = BountyTracker.new(state, constants, is_player, function(player, amount, reason)
		RewardPolicy.award_cash(rewards, player, amount, reason)
	end)
	ctx.combat_authority:bind({
		get_combat_entity = function(humanoid)
			return match_service.get_combat_entity(ctx, humanoid)
		end,
		can_damage = function(attacker, victim)
			return match_service.can_damage(ctx, attacker, victim)
		end,
		record_damage = function(attacker, humanoid)
			match_service.record_damage(ctx, attacker, humanoid)
		end,
		record_death = function(humanoid)
			match_service.record_death(ctx, humanoid)
		end,
		get_objective_position = match_service.get_objective_position,
	})
	MatchReplication.get_remote(ctx.remotes, "MatchState")
	MatchReplication.get_remote(ctx.remotes, "MatchVote").OnServerEvent:Connect(function(player, mode_id)
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
		MatchTeams.assign_joining_player(state, mode_rotation, player)
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
		bounty_tracker:on_player_removing(player)
		state.last_broadcast = 0
		broadcast(ctx)
	end)
	start_intermission(ctx)
	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()
			local match = state.current_match
			if state.phase == "round" and resolve_expired_bounty(ctx, now) then
				broadcast(ctx)
			end
			if state.phase == "intermission" and match and now >= match.starts_at then
				start_round(ctx)
			elseif state.phase == "intermission" and match and now - state.last_broadcast >= get_update_interval(match) then
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
				elseif now - state.last_broadcast >= get_update_interval(match) then
					broadcast(ctx)
				end
			end
		end
	end)
end

return match_service

