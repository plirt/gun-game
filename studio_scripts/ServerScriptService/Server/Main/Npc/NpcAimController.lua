local npc_weapon_controller = require(script.Parent.NpcWeaponController)

local npc_aim_controller = {}

local TARGET_HEIGHT = Vector3.new(0, 1.35, 0)
local BASE_AIM_SPREAD_DEGREES = 7.5
local MOVING_TARGET_EXTRA_SPREAD = 7
local STILL_TARGET_SPEED = 1.35
local LEAD_STRENGTH = 0.42
local MAX_LEAD_SECONDS = 0.28
local CLOSE_RANGE = 30
local CLOSE_RANGE_SPREAD_MULTIPLIER = 0.85

export type Agent = {
	root: BasePart,
	random: Random?,
}

export type WeaponConfig = {
	muzzle_velocity: number?,
}

local function get_planar_velocity(part: BasePart): Vector3
	return Vector3.new(part.AssemblyLinearVelocity.X, 0, part.AssemblyLinearVelocity.Z)
end

local function get_predicted_target_position(target_root: BasePart, origin: Vector3, config: WeaponConfig?): (Vector3, number, Vector3)
	local target_velocity = get_planar_velocity(target_root)
	local target_position = target_root.Position + TARGET_HEIGHT
	local distance = (target_position - origin).Magnitude
	local muzzle_velocity = config and config.muzzle_velocity or 0

	if muzzle_velocity > 0 and target_velocity.Magnitude > STILL_TARGET_SPEED then
		local lead_seconds = math.clamp(distance / muzzle_velocity, 0, MAX_LEAD_SECONDS)
		target_position += target_velocity * lead_seconds * LEAD_STRENGTH
	end
	return target_position, distance, target_velocity
end

local function get_spread(distance: number, target_velocity: Vector3): number
	local spread = BASE_AIM_SPREAD_DEGREES

	if target_velocity.Magnitude > STILL_TARGET_SPEED then
		spread += MOVING_TARGET_EXTRA_SPREAD
	end

	if distance <= CLOSE_RANGE then
		spread *= CLOSE_RANGE_SPREAD_MULTIPLIER
	end
	return spread
end

function npc_aim_controller.get_direction(ctx, agent: Agent, target_root: BasePart, config: WeaponConfig?): Vector3
	local origin = npc_weapon_controller.get_fire_origin(agent)
	local target_position, distance, target_velocity = get_predicted_target_position(target_root, origin, config)
	local delta = target_position - origin

	if delta.Magnitude <= 0 then
		return agent.root.CFrame.LookVector
	end

	local base_direction = delta.Unit
	local spread = get_spread(distance, target_velocity)
	return ctx.weapon_math.random_spread_direction(base_direction, spread, agent.random)
end
return npc_aim_controller


