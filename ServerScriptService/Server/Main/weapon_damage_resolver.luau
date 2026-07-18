local weapon_damage_resolver = {}

export type DamageApplication = {
	humanoid: Humanoid,
	damage: number,
	hit_model: Model?,
	origin: Vector3,
	position: Vector3,
	direction: Vector3,
}

local function can_apply_damage(ctx, attacker, humanoid: Humanoid?, damaged_humanoids): boolean
	if not humanoid or humanoid.Health <= 0 or damaged_humanoids[humanoid] then
		return false
	end
	if not ctx.match_service then
		return true
	end
	local hit_entity = ctx.match_service.get_combat_entity(ctx, humanoid)
	if not hit_entity then
		return true
	end
	return ctx.match_service.can_damage(ctx, attacker, hit_entity)
end

local function get_hit_direction(result, fallback_direction)
	local velocity = result.velocity
	if typeof(velocity) == "Vector3" and velocity.Magnitude > 0 then
		return velocity.Unit
	end
	if typeof(fallback_direction) == "Vector3" and fallback_direction.Magnitude > 0 then
		return fallback_direction.Unit
	end
	return Vector3.zAxis
end

local function build_damage_application(ctx, origin: Vector3, config: any, hit_result, humanoid: Humanoid): DamageApplication
	local result = hit_result.result
	local hit_model = humanoid.Parent
	local direction = get_hit_direction(result, hit_result.direction)
	return {
		humanoid = humanoid,
		damage = ctx.weapon_math.damage_for_hit(config, result.hit.Instance, result.distance),
		hit_model = hit_model and hit_model:IsA("Model") and hit_model or nil,
		origin = origin,
		position = result.position,
		direction = direction,
	}
end

function weapon_damage_resolver.resolve(ctx, attacker, origin: Vector3, config: any, hit_results: { any }, damaged_humanoids): { DamageApplication }
	local applications = {}
	damaged_humanoids = damaged_humanoids or {}
	for _, hit_result in hit_results do
		local result = hit_result.result
		if not result.hit then
			continue
		end
		local humanoid = ctx.weapon_math.find_humanoid(result.hit.Instance)
		if not can_apply_damage(ctx, attacker, humanoid, damaged_humanoids) then
			continue
		end
		if not humanoid then
			continue
		end
		damaged_humanoids[humanoid] = true
		table.insert(applications, build_damage_application(ctx, origin, config, hit_result, humanoid))
	end
	return applications
end

function weapon_damage_resolver.apply(ctx, attacker, applications: { DamageApplication })
	for _, application in applications do
		if application.hit_model then
			ctx.npc_hit_data[application.hit_model] = {
				origin = application.origin,
				position = application.position,
				direction = application.direction,
			}
		end
		if ctx.match_service then
			ctx.match_service.record_damage(ctx, attacker, application.humanoid)
		end
		application.humanoid:TakeDamage(application.damage)
		if ctx.match_service and application.humanoid.Health <= 0 then
			ctx.match_service.record_death(ctx, application.humanoid)
		end
	end
end

return weapon_damage_resolver
