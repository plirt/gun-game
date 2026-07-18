local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShotPattern = require(ReplicatedStorage.Modules.Shared.ShotPattern)
local constants = require(script.Parent.server_constants)
local weapon_runtime_store = require(script.Parent.weapon_runtime_store)

local weapon_fire_validator = {}

export type FireValidationResult = {
	ok: boolean,
	code: string?,
	gun_name: string?,
	origin: Vector3?,
	directions: { Vector3 }?,
	character: Model?,
	origin_part: BasePart?,
	config: any?,
	weapon_state: any?,
	fire_time: number?,
}

local function reject(code: string): FireValidationResult
	return { ok = false, code = code }
end

local function get_character_origin(player: Player): (Model?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil, nil
	end
	return character, head or root
end

local function is_origin_clear(character: Model, origin_part: BasePart, origin: Vector3): boolean
	local offset = origin - origin_part.Position
	if offset.Magnitude <= 0.05 then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	local result = workspace:Raycast(origin_part.Position, offset, params)
	return not result or result.Distance + 0.1 >= offset.Magnitude
end

local function normalize_direction(direction: any): Vector3?
	if typeof(direction) ~= "Vector3" then
		return nil
	end
	if direction.Magnitude < constants.VALID_DIRECTION_MIN_MAGNITUDE or direction.Magnitude > constants.VALID_DIRECTION_MAX_MAGNITUDE then
		return nil
	end
	return direction.Unit
end

local function normalize_directions(payload: any, config: any): { Vector3 }?
	local max_pellets = ShotPattern.get_pellet_count(config)
	local directions = {}
	if typeof(payload) == "Vector3" then
		local direction = normalize_direction(payload)
		if not direction then
			return nil
		end
		return { direction }
	end
	if type(payload) ~= "table" then
		return nil
	end
	for _, value in payload do
		local direction = normalize_direction(value)
		if not direction then
			return nil
		end
		table.insert(directions, direction)
		if #directions > max_pellets then
			return nil
		end
	end
	if #directions <= 0 then
		return nil
	end
	return directions
end

local function validate_fire_time(fire_time: any): number?
	local now = workspace:GetServerTimeNow()
	if type(fire_time) ~= "number" then
		return nil
	end
	if fire_time > now + constants.LAG_COMPENSATION_FUTURE_GRACE then
		return nil
	end
	if fire_time < now - constants.LAG_COMPENSATION_MAX_FIRE_AGE_SECONDS then
		return nil
	end
	return fire_time
end

function weapon_fire_validator.validate(ctx, player: Player, gun_name: any, origin: any, direction_payload: any, fire_time: any): FireValidationResult
	if player:GetAttribute("ragdolled") == true then
		return reject("ragdolled")
	end
	if type(gun_name) ~= "string" or typeof(origin) ~= "Vector3" then
		return reject("bad_request")
	end
	local validated_fire_time = validate_fire_time(fire_time)
	if not validated_fire_time then
		return reject("bad_fire_time")
	end
	local bundle = weapon_runtime_store.get_bundle(player, gun_name)
	if not bundle then
		return reject("weapon_unavailable")
	end
	local directions = normalize_directions(direction_payload, bundle.config)
	if not directions then
		return reject("bad_direction")
	end
	local character, origin_part = get_character_origin(player)
	if not character or not origin_part then
		return reject("character_unavailable")
	end
	if (origin - origin_part.Position).Magnitude > constants.MAX_REMOTE_ORIGIN_DISTANCE then
		origin = origin_part.Position
	end
	if not is_origin_clear(character, origin_part, origin) then
		return reject("origin_occluded")
	end
	local now = os.clock()
	local can_fire, reason = weapon_runtime_store.can_consume_fire(bundle.weapon_state, bundle.config, now, constants.WEAPON_FIRE_RATE_GRACE_MULTIPLIER)
	if not can_fire then
		return reject(reason or "fire_rejected")
	end
	return {
		ok = true,
		gun_name = gun_name,
		origin = origin,
		directions = directions,
		character = character,
		origin_part = origin_part,
		config = bundle.config,
		weapon_state = bundle.weapon_state,
		fire_time = validated_fire_time,
	}
end

return weapon_fire_validator
