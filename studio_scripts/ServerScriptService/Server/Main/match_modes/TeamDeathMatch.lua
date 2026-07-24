local team_death_match = {}

team_death_match.id = "team_death_match"
team_death_match.name = "Team Deathmatch"

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

function team_death_match.create(options)
	return {
		id = team_death_match.id,
		name = team_death_match.name,
		round_seconds = options.round_seconds,
		intermission_seconds = options.intermission_seconds,
		kill_limit = options.kill_limit,
		teams = teams,
	}
end

function team_death_match.get_teams()
	return teams
end

function team_death_match.assign_teams(players: { Player }): { [Player]: string }
	local assignments = {}
	local ordered_players = table.clone(players)
	table.sort(ordered_players, function(a, b)
		return a.UserId < b.UserId
	end)
	for index, player in ordered_players do
		local team = teams[(index - 1) % #teams + 1]
		assignments[player] = team.id
	end
	return assignments
end

function team_death_match.score_kill(scores, team_scores, assignments, killer: Player, victim: Player)
	if killer == victim then
		return
	end
	local killer_team_id = assignments[killer]
	local victim_team_id = assignments[victim]
	if killer_team_id and victim_team_id and killer_team_id == victim_team_id then
		return
	end
	local score = scores[killer]
	if score then
		score.kills += 1
	end
	local team_score = killer_team_id and team_scores[killer_team_id]
	if team_score then
		team_score.score += 1
	end
end

function team_death_match.score_death(scores, victim: Player)
	local score = scores[victim]
	if score then
		score.deaths += 1
	end
end

function team_death_match.can_damage(assignments, attacker: Player, victim: Player): boolean
	local attacker_team_id = assignments[attacker]
	local victim_team_id = assignments[victim]
	return not attacker_team_id or not victim_team_id or attacker_team_id ~= victim_team_id
end

function team_death_match.should_end(match, scores, team_scores): boolean
	for _, team_score in team_scores do
		if team_score.score >= match.kill_limit then
			return true
		end
	end
	return os.clock() >= match.ends_at
end

function team_death_match.get_winners(scores, team_scores)
	local winners = {}
	local best_score = -1
	for _, team_score in team_scores do
		if team_score.score > best_score then
			table.clear(winners)
			table.insert(winners, {
				type = "team",
				id = team_score.id,
				name = team_score.name,
				score = team_score.score,
			})
			best_score = team_score.score
		elseif team_score.score == best_score then
			table.insert(winners, {
				type = "team",
				id = team_score.id,
				name = team_score.name,
				score = team_score.score,
			})
		end
	end
	return winners
end

return team_death_match

