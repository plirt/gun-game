local hitscan_driver = {}
hitscan_driver.__index = hitscan_driver

function hitscan_driver.new(dependencies)
	return setmetatable({
		dependencies = dependencies,
	}, hitscan_driver)
end

function hitscan_driver:validate(actor, action)
	if typeof(action.origin) ~= "Vector3"
		or type(action.directions) ~= "table"
		or #action.directions == 0
		or type(action.config) ~= "table"
	then
		return false, "bad_hitscan_action"
	end
	local character = actor:get_character()
	if not character or not character.Parent then
		return false, "character_unavailable"
	end
	for _, direction in action.directions do
		if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0 then
			return false, "bad_direction"
		end
	end
	action.character = character
	return true, action
end

function hitscan_driver:activate(actor, action)
	local dependencies = self.dependencies
	local attacker = actor:get_entity()
	local damaged_humanoids = {}
	dependencies.event_stream:emit("weapon_activated", {
		actor = attacker,
		item_id = action.item_id,
		origin = action.origin,
		directions = action.directions,
		play_sound = action.play_sound ~= false,
		muzzle_velocity = action.config.muzzle_velocity,
		max_distance = action.config.max_distance,
	})

	local damage_dependencies = {
		npc_hit_data = dependencies.npc_hit_data,
		get_combat_entity = function(humanoid)
			return dependencies.combat_authority:get_combat_entity(humanoid)
		end,
		can_damage = function(source, victim)
			return dependencies.combat_authority:can_damage(source, victim)
		end,
		record_damage = function(source, humanoid)
			dependencies.combat_authority:record_damage(source, humanoid)
		end,
		record_death = function(humanoid)
			dependencies.combat_authority:record_death(humanoid)
		end,
		record_lethal_shot = function(source, humanoid, application, item_id)
			dependencies.event_stream:emit("lethal_hit", {
				actor = source,
				humanoid = humanoid,
				item_id = item_id,
				origin = application.origin,
				position = application.position,
				direction = application.direction,
				damage = application.damage,
			})
		end,
		record_application = function(source, application, item_id, health_before, health_after)
			dependencies.event_stream:emit("damage_applied", {
				actor = source,
				humanoid = application.humanoid,
				item_id = item_id,
				origin = application.origin,
				position = application.position,
				direction = application.direction,
				damage = application.damage,
				health_before = health_before,
				health_after = health_after,
			})
		end,
	}

	local function apply_results(hit_results)
		local applications = dependencies.damage_resolver.resolve(
			damage_dependencies,
			attacker,
			action.origin,
			action.config,
			hit_results,
			damaged_humanoids
		)
		dependencies.damage_resolver.apply(
			damage_dependencies,
			attacker,
			applications,
			action.item_id
		)
		if action.on_applications then
			action.on_applications(applications)
		end
	end

	local hit_results = dependencies.hit_scan_service.cast(
		dependencies.hit_scan_dependencies,
		attacker,
		action.character,
		action.origin,
		action.directions,
		action.config,
		action.fire_time or workspace:GetServerTimeNow(),
		function(late_result)
			apply_results({ late_result })
		end
	)
	apply_results(hit_results)
	return true, {
		hit_count = #hit_results,
	}
end

return hitscan_driver

