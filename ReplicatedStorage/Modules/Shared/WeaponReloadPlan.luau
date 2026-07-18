local weapon_reload_plan = {}

export type ReloadPlan = {
	style: string,
	round_count: number,
	start_time: number,
	insert_time: number,
	end_time: number,
	total_time: number,
	start_animation: string?,
	insert_animation: string?,
	end_animation: string?,
	magazine_animation: string?,
	animation_speed: number,
}

function weapon_reload_plan.build(config: any, magazine: number, reserve: number): ReloadPlan
	local round_count = math.min(math.max(config.magazine_size - magazine, 0), math.max(reserve, 0))
	local animation_speed = math.max(config.reload_animation_speed or 1, 0.01)
	if config.reload_style == "per_round" then
		local start_time = math.max(config.reload_start_time or 0, 0)
		local insert_time = math.max(config.reload_insert_time or 0.65, 0.05)
		local end_time = math.max(config.reload_end_time or 0, 0)
		return {
			style = "per_round",
			round_count = round_count,
			start_time = start_time,
			insert_time = insert_time,
			end_time = end_time,
			total_time = start_time + insert_time * round_count + end_time,
			start_animation = config.reload_start_animation,
			insert_animation = config.reload_insert_animation or "TacticalReload",
			end_animation = config.reload_end_animation,
			magazine_animation = nil,
			animation_speed = animation_speed,
		}
	end
	local tactical = magazine > 0
	local total_time = tactical and config.reload_tactical_time or config.reload_empty_time
	return {
		style = "magazine",
		round_count = round_count,
		start_time = 0,
		insert_time = 0,
		end_time = 0,
		total_time = total_time or 1.5,
		start_animation = nil,
		insert_animation = nil,
		end_animation = nil,
		magazine_animation = tactical and "TacticalReload" or "Reload",
		animation_speed = tactical and (config.tactical_reload_animation_speed or animation_speed) or animation_speed,
	}
end

return weapon_reload_plan
