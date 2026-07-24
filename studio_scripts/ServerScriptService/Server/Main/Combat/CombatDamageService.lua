local combat_damage_service = {}

function combat_damage_service.apply(dependencies, attacker, applications, item_id)
	for _, application in applications do
		if application.hit_model then
			dependencies.npc_hit_data[application.hit_model] = {
				origin = application.origin,
				position = application.position,
				direction = application.direction,
			}
		end
		local health_before = application.humanoid.Health
		dependencies.record_damage(attacker, application.humanoid)
		application.humanoid:TakeDamage(application.damage)
		local health_after = application.humanoid.Health
		if dependencies.record_application then
			dependencies.record_application(attacker, application, item_id, health_before, health_after)
		end
		if health_before > 0 and health_after <= 0 then
			dependencies.record_lethal_shot(attacker, application.humanoid, application, item_id)
			dependencies.record_death(application.humanoid)
		end
	end
end

return combat_damage_service

