local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponMath = require(ReplicatedStorage.Modules.Shared.WeaponMath)

local ShotPattern = {}

export type WeaponConfig = {
	pellets_per_fire: number?,
	spread_hip: number?,
	spread_aim: number?,
	spread_max: number?,
}

local DEFAULT_PELLET_COUNT = 1
local MIN_PELLET_COUNT = 1
local DEFAULT_SPREAD_DEGREES = 0

function ShotPattern.get_pellet_count(config: WeaponConfig): number
	local pellets_per_fire = config.pellets_per_fire or DEFAULT_PELLET_COUNT
	if type(pellets_per_fire) ~= "number" then
		return DEFAULT_PELLET_COUNT
	end
	return math.max(MIN_PELLET_COUNT, math.floor(pellets_per_fire))
end

function ShotPattern.get_weapon_spread(config: WeaponConfig, aiming: boolean, spread_heat: number?): number
	local base_spread = aiming and config.spread_aim or config.spread_hip
	if type(base_spread) ~= "number" then
		base_spread = DEFAULT_SPREAD_DEGREES
	end
	return math.max(0, base_spread + (spread_heat or 0))
end

function ShotPattern.get_pellet_spread(config: WeaponConfig): number
	local spread = config.spread_hip or config.spread_max or DEFAULT_SPREAD_DEGREES
	if type(spread) ~= "number" then
		return DEFAULT_SPREAD_DEGREES
	end
	return math.max(0, spread)
end

function ShotPattern.direction_with_spread(base_direction: Vector3, spread_degrees: number, random_source: Random?): Vector3
	if typeof(base_direction) ~= "Vector3" or base_direction.Magnitude <= 0 then
		return Vector3.zAxis
	end
	return WeaponMath.random_spread_direction(base_direction.Unit, math.max(spread_degrees, 0), random_source)
end

function ShotPattern.build_directions(base_direction: Vector3, pellet_count: number, spread_degrees: number, random_source: Random?): { Vector3 }
	local directions = table.create(math.max(pellet_count, 1))
	for pellet_index = 1, math.max(pellet_count, 1) do
		directions[pellet_index] = ShotPattern.direction_with_spread(base_direction, spread_degrees, random_source)
	end
	return directions
end

function ShotPattern.build_weapon_directions(base_direction: Vector3, config: WeaponConfig, aiming: boolean, spread_heat: number?, random_source: Random?): { Vector3 }
	local pellet_count = ShotPattern.get_pellet_count(config)
	local spread = ShotPattern.get_weapon_spread(config, aiming, spread_heat)
	return ShotPattern.build_directions(base_direction, pellet_count, spread, random_source)
end

function ShotPattern.build_npc_directions(base_direction: Vector3, config: WeaponConfig, random_source: Random?): { Vector3 }
	local pellet_count = ShotPattern.get_pellet_count(config)
	if pellet_count <= 1 then
		return { ShotPattern.direction_with_spread(base_direction, 0, random_source) }
	end
	return ShotPattern.build_directions(base_direction, pellet_count, ShotPattern.get_pellet_spread(config), random_source)
end
return ShotPattern


