local ReplicatedStorage = game:GetService("ReplicatedStorage")

local weapon_damage_resolver = {}

local WeaponMath = require(ReplicatedStorage.Modules.Shared.WeaponMath)
local CombatTypes = require(script.Parent.CombatTypes)
local CombatDamageService = require(script.Parent.Combat.CombatDamageService)

type WeaponConfig = CombatTypes.WeaponConfig
type HitScanResult = CombatTypes.HitScanResult
type ProjectileResult = CombatTypes.ProjectileResult
type DamagedHumanoids = CombatTypes.DamagedHumanoids

export type Dependencies = {
	npc_hit_data: { [Model]: {
		origin: Vector3,
		position: Vector3,
		direction: Vector3,
	} },
	get_combat_entity: (Humanoid) -> Instance?,
	can_damage: (Instance, Instance) -> boolean,
	record_damage: (Instance, Humanoid) -> (),
	record_death: (Humanoid) -> (),
	record_lethal_shot: (Instance, Humanoid, DamageApplication, string?) -> (),
	record_application: ((Instance, DamageApplication, string?, number, number) -> ())?,
}

export type DamageApplication = {
	humanoid: Humanoid,
	damage: number,
	hit_model: Model?,
	origin: Vector3,
	position: Vector3,
	direction: Vector3,
}

local function can_apply_damage(
	dependencies: Dependencies,
	attacker: Instance,
	humanoid: Humanoid?,
	damaged_humanoids: DamagedHumanoids
): boolean
	if not humanoid or humanoid.Health <= 0 or damaged_humanoids[humanoid] then
		return false
	end
	local hit_entity = dependencies.get_combat_entity(humanoid)
	return not hit_entity or dependencies.can_damage(attacker, hit_entity)
end

local function get_hit_direction(result: ProjectileResult, fallback_direction: Vector3): Vector3
	local velocity = result.velocity
	if typeof(velocity) == "Vector3" and velocity.Magnitude > 0 then
		return velocity.Unit
	end
	if typeof(fallback_direction) == "Vector3" and fallback_direction.Magnitude > 0 then
		return fallback_direction.Unit
	end
	return Vector3.zAxis
end

local function build_damage_application(dependencies: Dependencies, origin: Vector3, config: WeaponConfig, hit_result: HitScanResult, humanoid: Humanoid): DamageApplication
	local result = hit_result.result
	local hit_model = humanoid.Parent
	local direction = get_hit_direction(result, hit_result.direction)
	return {
		humanoid = humanoid,
		damage = WeaponMath.damage_for_hit(config, result.hit.Instance, result.distance),
		hit_model = hit_model and hit_model:IsA("Model") and hit_model or nil,
		origin = origin,
		position = result.position,
		direction = direction,
	}
end

function weapon_damage_resolver.resolve(dependencies: Dependencies, attacker: Instance, origin: Vector3, config: WeaponConfig, hit_results: { HitScanResult }, damaged_humanoids: DamagedHumanoids?): { DamageApplication }
	local applications = {}
	damaged_humanoids = damaged_humanoids or {}
	for _, hit_result in hit_results do
		local result = hit_result.result
		if not result.hit then
			continue
		end
		local humanoid = WeaponMath.find_humanoid(result.hit.Instance)
		if not can_apply_damage(dependencies, attacker, humanoid, damaged_humanoids) then
			continue
		end
		if not humanoid then
			continue
		end
		damaged_humanoids[humanoid] = true
		table.insert(applications, build_damage_application(dependencies, origin, config, hit_result, humanoid))
	end
	return applications
end

function weapon_damage_resolver.apply(
	dependencies: Dependencies,
	attacker: Instance,
	applications: { DamageApplication },
	gun_name: string?
)
	CombatDamageService.apply(dependencies, attacker, applications, gun_name)
end

return weapon_damage_resolver

