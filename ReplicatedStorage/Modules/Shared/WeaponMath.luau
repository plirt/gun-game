local WeaponMath = {}

local TAU = math.pi * 2

local function get_basis(direction)
	local forward = direction.Unit
	local up = math.abs(forward:Dot(Vector3.yAxis)) > 0.98 and Vector3.xAxis or Vector3.yAxis
	local right = forward:Cross(up).Unit
	local corrected_up = right:Cross(forward).Unit
	return forward, right, corrected_up
end

function WeaponMath.random_spread_direction(direction, spread_degrees, random_source)
	if spread_degrees <= 0 then
		return direction.Unit
	end

	local rng = random_source or Random.new()
	local forward, right, up = get_basis(direction)
	local radius = math.tan(math.rad(spread_degrees)) * math.sqrt(rng:NextNumber())
	local theta = rng:NextNumber() * TAU
	return (forward + right * math.cos(theta) * radius + up * math.sin(theta) * radius).Unit
end

function WeaponMath.damage_for_hit(config, hit_part, distance)
	local damage = config.damage
	local name = string.lower(hit_part.Name)

	if name == "head" then
		damage *= config.headshot_multiplier
	elseif string.find(name, "arm") or string.find(name, "leg") then
		damage *= config.limb_multiplier
	end

	local falloff_start = config.damage_falloff_start
	local falloff_end = math.max(config.damage_falloff_end, falloff_start + 1)

	if distance > falloff_start then
		local alpha = math.clamp((distance - falloff_start) / (falloff_end - falloff_start), 0, 1)
		damage *= 1 - alpha * (1 - config.minimum_damage_multiplier)
	end
	return math.max(1, math.floor(damage + 0.5))
end

function WeaponMath.find_humanoid(hit_instance)
	local current = hit_instance

	while current and current ~= workspace do
		local humanoid = current:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
			return humanoid
		end

		current = current.Parent
	end
	return nil
end
return WeaponMath


