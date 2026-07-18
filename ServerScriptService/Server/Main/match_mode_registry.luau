local free_for_all = require(script.Parent.match_modes.free_for_all)
local king_of_the_hill = require(script.Parent.match_modes.king_of_the_hill)
local team_death_match = require(script.Parent.match_modes.team_death_match)

local match_mode_registry = {}

local ROUND_SECONDS = 300
local INTERMISSION_SECONDS = 15
local KILL_LIMIT = 30
local HILL_SCORE_LIMIT = 100

local modes = {
	free_for_all.create({
		round_seconds = ROUND_SECONDS,
		intermission_seconds = INTERMISSION_SECONDS,
		kill_limit = KILL_LIMIT,
	}),
	team_death_match.create({
		round_seconds = ROUND_SECONDS,
		intermission_seconds = INTERMISSION_SECONDS,
		kill_limit = KILL_LIMIT,
	}),
	king_of_the_hill.create({
		round_seconds = ROUND_SECONDS,
		intermission_seconds = INTERMISSION_SECONDS,
		score_limit = HILL_SCORE_LIMIT,
	}),
}

local modules = {
	[free_for_all.id] = free_for_all,
	[king_of_the_hill.id] = king_of_the_hill,
	[team_death_match.id] = team_death_match,
}

function match_mode_registry.get_modes()
	return modes
end

function match_mode_registry.get_module(mode_id: string)
	return modules[mode_id] or free_for_all
end

function match_mode_registry.get_default_mode()
	return modes[1]
end

function match_mode_registry.get_next_mode(mode_index: number)
	local next_index = mode_index + 1
	if next_index > #modes then
		next_index = 1
	end
	return modes[next_index], next_index
end

return match_mode_registry
