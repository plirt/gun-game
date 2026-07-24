local free_for_all = {}

free_for_all.id = "free_for_all"
free_for_all.name = "Free For All"

function free_for_all.create(options)
	return {
		id = free_for_all.id,
		name = free_for_all.name,
		round_seconds = options.round_seconds,
		intermission_seconds = options.intermission_seconds,
		kill_limit = options.kill_limit,
	}
end

function free_for_all.score_kill(scores, team_scores, assignments, killer: Player, victim: Player)
	if killer == victim then
		return
	end
	local score = scores[killer]
	if not score then
		return
	end
	score.kills += 1
end

function free_for_all.score_death(scores, victim: Player)
	local score = scores[victim]
	if not score then
		return
	end
	score.deaths += 1
end

function free_for_all.can_damage(assignments, attacker: Player, victim: Player): boolean
	return attacker ~= victim
end

function free_for_all.should_end(match, scores, team_scores): boolean
	for _, score in scores do
		if score.kills >= match.kill_limit then
			return true
		end
	end
	return os.clock() >= match.ends_at
end

function free_for_all.get_winners(scores, team_scores): { Player }
	local winners = {}
	local best_kills = -1
	local best_deaths = math.huge
	for player, score in scores do
		if score.kills > best_kills or score.kills == best_kills and score.deaths < best_deaths then
			table.clear(winners)
			table.insert(winners, player)
			best_kills = score.kills
			best_deaths = score.deaths
		elseif score.kills == best_kills and score.deaths == best_deaths then
			table.insert(winners, player)
		end
	end
	return winners
end

return free_for_all

