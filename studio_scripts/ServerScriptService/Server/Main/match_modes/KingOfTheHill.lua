local king_of_the_hill = {}

king_of_the_hill.id = "king_of_the_hill"
king_of_the_hill.name = "King of the Hill"

local teams = {
	{
		id = "white",
		name = "White",
		brick_color = BrickColor.new("Institutional white"),
	},
	{
		id = "black",
		name = "Black",
		brick_color = BrickColor.new("Really black"),
	},
}

local function get_hill()
	local objectives = workspace:FindFirstChild("Objectives")
	local hill = objectives and objectives:FindFirstChild("KingOfTheHill")
	return hill and hill:IsA("BasePart") and hill or nil
end

local function set_hill_active(active)
	local hill = get_hill()
	if not hill then
		return
	end
	hill.Transparency = active and 0.45 or 1
	hill.CanQuery = active
	local label = hill:FindFirstChild("Label")
	if label and label:IsA("BillboardGui") then
		label.Enabled = active
	end
end

local function get_root(entity)
	if entity:IsA("Player") then
		local character = entity.Character
		return character and character:FindFirstChild("HumanoidRootPart")
	end
	if entity:IsA("Model") then
		return entity:FindFirstChild("HumanoidRootPart")
	end
	return nil
end

local function is_alive(entity)
	local model = entity:IsA("Player") and entity.Character or entity
	local humanoid = model and model:FindFirstChildWhichIsA("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function is_inside(hill, root)
	if not root or not root:IsA("BasePart") then
		return false
	end
	local local_position = hill.CFrame:PointToObjectSpace(root.Position)
	local half_size = hill.Size * 0.5
	return math.abs(local_position.X) <= half_size.X
		and math.abs(local_position.Z) <= half_size.Z
		and math.abs(local_position.Y) <= math.max(half_size.Y, 8)
end

local function count_occupants(ctx, hill, assignments)
	local counts = {}
	for _, player in ctx.Players:GetPlayers() do
		local team_id = assignments[player]
		if team_id and is_alive(player) and is_inside(hill, get_root(player)) then
			counts[team_id] = (counts[team_id] or 0) + 1
		end
	end
	local npcs = workspace:FindFirstChild("Npcs")
	if npcs then
		for _, npc in npcs:GetChildren() do
			local team_id = assignments[npc]
			if team_id and npc:IsA("Model") and is_alive(npc) and is_inside(hill, get_root(npc)) then
				counts[team_id] = (counts[team_id] or 0) + 1
			end
		end
	end
	return counts
end

local function get_holder(counts)
	local holder
	local active_teams = 0
	for team_id, count in counts do
		if count > 0 then
			holder = team_id
			active_teams += 1
		end
	end
	return active_teams == 1 and holder or nil, active_teams > 1
end

local function get_team_name(team_id)
	for _, team in teams do
		if team.id == team_id then
			return team.name
		end
	end
	return ""
end

function king_of_the_hill.create(options)
	return {
		id = king_of_the_hill.id,
		name = king_of_the_hill.name,
		round_seconds = options.round_seconds,
		intermission_seconds = options.intermission_seconds,
		kill_limit = options.score_limit,
		score_limit = options.score_limit,
		teams = teams,
		objective = "hill",
	}
end

function king_of_the_hill.get_teams()
	return teams
end

function king_of_the_hill.start()
	set_hill_active(true)
end

function king_of_the_hill.stop()
	set_hill_active(false)
end

function king_of_the_hill.assign_teams(players)
	local assignments = {}
	local ordered_players = table.clone(players)
	table.sort(ordered_players, function(a, b)
		return a.UserId < b.UserId
	end)
	for index, player in ordered_players do
		assignments[player] = teams[(index - 1) % #teams + 1].id
	end
	return assignments
end

function king_of_the_hill.score_kill(scores, team_scores, assignments, killer, victim)
	if killer == victim then
		return
	end
	local score = scores[killer]
	if score then
		score.kills += 1
	end
end

function king_of_the_hill.score_death(scores, victim)
	local score = scores[victim]
	if score then
		score.deaths += 1
	end
end

function king_of_the_hill.can_damage(assignments, attacker, victim)
	local attacker_team_id = assignments[attacker]
	local victim_team_id = assignments[victim]
	return not attacker_team_id or not victim_team_id or attacker_team_id ~= victim_team_id
end

function king_of_the_hill.update(ctx, match, scores, team_scores, assignments, delta_time)
	local hill = get_hill()
	if not hill then
		return {
			type = "hill",
			status = "HILL UNAVAILABLE",
			score_limit = match.score_limit,
		}
	end
	local counts = count_occupants(ctx, hill, assignments)
	local holder, contested = get_holder(counts)
	if holder and team_scores[holder] then
		team_scores[holder].score = math.min(team_scores[holder].score + delta_time, match.score_limit)
	end
	if holder == "white" then
		hill.Color = Color3.fromRGB(245, 245, 245)
	elseif holder == "black" then
		hill.Color = Color3.fromRGB(20, 20, 20)
	else
		hill.Color = Color3.fromRGB(130, 130, 130)
	end
	local status = "HILL EMPTY"
	if contested then
		status = "HILL CONTESTED"
	elseif holder then
		status = string.upper(get_team_name(holder)) .. " CONTROLS HILL"
	end
	return {
		type = "hill",
		status = status,
		holder_team_id = holder,
		contested = contested,
		occupants = counts,
		score_limit = match.score_limit,
	}
end

function king_of_the_hill.should_end(match, scores, team_scores)
	for _, team_score in team_scores do
		if team_score.score >= match.score_limit then
			return true
		end
	end
	return os.clock() >= match.ends_at
end

function king_of_the_hill.get_winners(scores, team_scores)
	local winners = {}
	local best_score = -1
	for _, team_score in team_scores do
		if team_score.score > best_score then
			table.clear(winners)
			table.insert(winners, {
				type = "team",
				id = team_score.id,
				name = team_score.name,
				score = math.floor(team_score.score),
			})
			best_score = team_score.score
		elseif team_score.score == best_score then
			table.insert(winners, {
				type = "team",
				id = team_score.id,
				name = team_score.name,
				score = math.floor(team_score.score),
			})
		end
	end
	return winners
end

return king_of_the_hill

