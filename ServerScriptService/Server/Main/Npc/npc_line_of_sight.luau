local npc_line_of_sight = {}

local TARGET_OFFSETS = {
	Vector3.new(0, 1.45, 0),
	Vector3.new(0, 0.55, 0),
	Vector3.new(0, 2.05, 0),
}

local function get_alive_humanoid(model)
	local humanoid = model and model:FindFirstChildWhichIsA("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function get_root(model)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function make_params(exclude_instances)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude_instances or {}
	params.IgnoreWater = true
	return params
end

local function get_target_points(model)
	local root = get_root(model)
	if not root then
		return {}
	end

	local points = {}
	for _, offset in TARGET_OFFSETS do
		table.insert(points, root.Position + offset)
	end

	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		table.insert(points, head.Position)
	end
	return points
end

function npc_line_of_sight.is_npc_model(model)
	if not model or not model:IsA("Model") then
		return false
	end

	local npcs_folder = workspace:FindFirstChild("Npcs")
	return npcs_folder ~= nil and get_alive_humanoid(model) ~= nil and model:IsDescendantOf(npcs_folder)
end

function npc_line_of_sight.find_npc_from_instance(ctx, instance)
	if not instance then
		return nil, nil
	end

	local humanoid = ctx.weapon_math.find_humanoid(instance)
	local model = humanoid and humanoid.Parent
	if npc_line_of_sight.is_npc_model(model) then
		return model, humanoid
	end
	return nil, nil
end

function npc_line_of_sight.first_npc_in_direction(ctx, origin, direction, range, exclude_instances)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or type(range) ~= "number" then
		return nil, nil, nil
	end
	if direction.Magnitude <= 0.01 or range <= 0 then
		return nil, nil, nil
	end

	local result = workspace:Raycast(origin, direction.Unit * range, make_params(exclude_instances))
	if not result then
		return nil, nil, nil
	end

	local npc, humanoid = npc_line_of_sight.find_npc_from_instance(ctx, result.Instance)
	return npc, humanoid, result
end

function npc_line_of_sight.can_see_model(origin, target_model, exclude_instances, max_distance)
	if typeof(origin) ~= "Vector3" or not target_model or not target_model:IsA("Model") then
		return false, nil
	end
	if not get_alive_humanoid(target_model) or not get_root(target_model) then
		return false, nil
	end

	local params = make_params(exclude_instances)
	local best_result = nil
	for _, target_position in get_target_points(target_model) do
		local offset = target_position - origin
		local distance = offset.Magnitude
		if distance > 0.01 and (not max_distance or distance <= max_distance) then
			local result = workspace:Raycast(origin, offset, params)
			if result and result.Instance:IsDescendantOf(target_model) then
				return true, result
			end
			best_result = best_result or result
		end
	end
	return false, best_result
end
return npc_line_of_sight


