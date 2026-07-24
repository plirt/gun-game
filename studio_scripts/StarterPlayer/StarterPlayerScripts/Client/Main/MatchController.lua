local match_controller = {}

local function score_signature(payload)
	local scores = payload.scores
	if type(scores) ~= "table" then
		return ""
	end
	local parts = {}
	for _, score in scores do
		table.insert(parts, `{score.user_id}:{score.kills}:{score.deaths}`)
	end
	return table.concat(parts, "|")
end

local function vote_signature(payload)
	local options = payload.vote_options
	if type(options) ~= "table" then
		return ""
	end
	local parts = {}
	for _, option in options do
		table.insert(parts, `{option.id}:{option.votes or 0}`)
	end
	return table.concat(parts, "|")
end

local function team_score_signature(payload)
	local team_scores = payload.team_scores
	if type(team_scores) ~= "table" then
		return ""
	end
	local parts = {}
	for _, team_score in team_scores do
		table.insert(parts, `{team_score.id}:{team_score.score or 0}`)
	end
	return table.concat(parts, "|")
end

local function objective_signature(payload)
	local objective = payload.objective_state
	if type(objective) ~= "table" then
		return ""
	end
	return table.concat({
		tostring(objective.status),
		tostring(objective.holder_team_id),
		tostring(objective.contested),
	}, ":")
end

local function bounty_signature(payload)
	local bounty = payload.bounty
	if type(bounty) ~= "table" then
		return ""
	end
	return table.concat({
		tostring(bounty.target_user_id),
		tostring(bounty.reward),
		tostring(bounty.expires_at),
	}, ":")
end

local function winner_signature(payload)
	local winners = payload.winners
	if type(winners) ~= "table" then
		return ""
	end
	local parts = {}
	for _, winner in winners do
		table.insert(parts, tostring(winner.user_id))
	end
	return table.concat(parts, "|")
end

local function payload_signature(payload)
	if type(payload) ~= "table" then
		return ""
	end
	return table.concat({
		tostring(payload.match_id),
		tostring(payload.phase),
		tostring(payload.mode_id),
		score_signature(payload),
		team_score_signature(payload),
		objective_signature(payload),
		vote_signature(payload),
		bounty_signature(payload),
		winner_signature(payload),
	}, "#")
end

function match_controller.setup(ctx)
	ctx.match_payload = nil
	local last_signature = ""
	local last_timer_second = nil

	ctx.vote_match_mode = function(mode_id: string)
		ctx.remotes.MatchVote:FireServer(mode_id)
	end

	ctx.remotes:WaitForChild("MatchState").OnClientEvent:Connect(function(payload)
		payload.received_at = os.clock()
		ctx.match_payload = payload
		if ctx.update_hvt_marker then
			ctx.update_hvt_marker(payload.bounty)
		end
		local signature = payload_signature(payload)
		if signature ~= last_signature and ctx.render then
			last_signature = signature
			ctx.render()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.1)
			local payload = ctx.match_payload
			if type(payload) ~= "table" then
				continue
			end
			local target_time = payload.phase == "intermission" and payload.starts_at or payload.ends_at
			local elapsed_since_snapshot = math.max(0, os.clock() - (payload.received_at or os.clock()))
			local estimated_server_time = (payload.server_time or 0) + elapsed_since_snapshot
			local timer_second = math.max(0, math.ceil((target_time or 0) - estimated_server_time))
			if timer_second ~= last_timer_second then
				last_timer_second = timer_second
				if ctx.render then
					ctx.render()
				end
			end
		end
	end)
end

return match_controller

