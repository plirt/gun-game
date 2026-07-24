local npc_spawn_controller = {}

local map_profiles = require(script.Parent.NpcMapProfiles)
local npc_values = require(script.Parent.NpcValues)

local default_map_id = "Default"
local spawn_random = Random.new()

local function resolve_map_profile(map_id)
	local profile = map_profiles[map_id]

	if profile then
		return map_id, profile
	end

	return default_map_id, map_profiles[default_map_id]
end

local function refresh_humanoid(npc)
	local humanoid = npc:FindFirstChildWhichIsA("Humanoid")

	if not humanoid then
		return nil
	end

	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Health = humanoid.MaxHealth
	humanoid.Jump = false
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Running)

	return humanoid
end

local function get_spawn_cframe_from_instance(spawn_instance)
	if spawn_instance:IsA("BasePart") then
		return spawn_instance.CFrame
	end

	if spawn_instance:IsA("Attachment") then
		return spawn_instance.WorldCFrame
	end

	if spawn_instance:IsA("Model") then
		return spawn_instance:GetPivot()
	end

	return nil
end

local function get_pseudo_spawn_locations()
	local folder = workspace:FindFirstChild("PseudoSpawnLocations")
	local locations = {}

	if not folder then
		warn("PseudoSpawnLocations folder missing")
		return locations
	end

	for _, spawn_instance in folder:GetDescendants() do
		local spawn_cframe = get_spawn_cframe_from_instance(spawn_instance)

		if spawn_cframe then
			table.insert(locations, spawn_cframe)
		end
	end

	if #locations == 0 then
		warn("PseudoSpawnLocations has no valid spawn parts")
	end

	return locations
end

local function pick_spawn_cframe(spawn_locations, used_spawn_indexes, fallback_cframe)
	if #spawn_locations == 0 then
		return fallback_cframe
	end

	local available_indexes = {}

	for index in spawn_locations do
		if not used_spawn_indexes[index] then
			table.insert(available_indexes, index)
		end
	end

	if #available_indexes == 0 then
		table.clear(used_spawn_indexes)

		for index in spawn_locations do
			table.insert(available_indexes, index)
		end
	end

	local picked_index = available_indexes[spawn_random:NextInteger(1, #available_indexes)]
	local spawn_cframe = spawn_locations[picked_index]
	local offset = Vector3.new(spawn_random:NextNumber(-2.5, 2.5), 0, spawn_random:NextNumber(-2.5, 2.5))

	used_spawn_indexes[picked_index] = true

	return spawn_cframe + offset
end

local function get_template_npc(ctx)
	local templates = ctx.ReplicatedStorage:FindFirstChild("Templates")
	local dummy = templates and templates:FindFirstChild("Dummy")

	if dummy and dummy:IsA("Model") and dummy:FindFirstChildWhichIsA("Humanoid") then
		return dummy
	end

	warn("ReplicatedStorage.Templates.Dummy missing or invalid")

	return nil
end

local function clone_template(template, map_id, definition, spawn_cframe)
	local npc = template:Clone()

	npc.Name = "AI_" .. map_id .. "_" .. definition.id

	npc_values.write_bool(npc, "managed_npc", true)
	npc_values.write_string(npc, "npc_id", definition.id)
	npc_values.write_string(npc, "npc_type", definition.npc_type or "Default")
	npc_values.write_string(npc, "map_id", map_id)

	if definition.gun_id then
		npc_values.write_string(npc, "gun_id", definition.gun_id)
	end

	if definition.fake_fright_min_time then
		npc_values.write_number(npc, "fake_fright_min_time", definition.fake_fright_min_time)
	end

	if definition.fake_fright_max_time then
		npc_values.write_number(npc, "fake_fright_max_time", definition.fake_fright_max_time)
	end

	npc:PivotTo(spawn_cframe)
	refresh_humanoid(npc)

	return npc
end

function npc_spawn_controller.clear(npcs_folder, map_id)
	for _, npc in npcs_folder:GetChildren() do
		if npc:IsA("Model") and npc_spawn_controller.is_generated(npc) then
			local npc_map_id = npc_values.read_string(npc, "map_id", "")

			if not map_id or npc_map_id == map_id then
				npc_values.clear_metadata(npc)
				npc:Destroy()
			end
		end
	end
end

function npc_spawn_controller.ensure(ctx, npcs_folder, max_agents, max_spawn_count)
	local map_id, profile = resolve_map_profile(ctx.active_map_id or default_map_id)

	if not profile then
		warn("No NPC map profile found")
		return map_id
	end

	local template = get_template_npc(ctx)

	if not template then
		return map_id
	end

	local spawn_locations = get_pseudo_spawn_locations()
	local used_spawn_indexes = {}
	local fallback_origin = profile.spawn_origin or Vector3.zero
	local existing_ids = {}
	local existing_count = 0
	for _, npc in npcs_folder:GetChildren() do
		if npc:IsA("Model") and npc_spawn_controller.is_generated(npc) then
			local humanoid = npc:FindFirstChildWhichIsA("Humanoid")
			if humanoid and humanoid.Health > 0 then
				existing_count += 1
				existing_ids[npc_values.read_string(npc, "npc_id", npc.Name)] = true
			end
		end
	end
	local target_count = max_agents or #profile.agents
	local spawn_count = math.max(target_count - existing_count, 0)
	if type(max_spawn_count) == "number" then
		spawn_count = math.min(spawn_count, math.max(math.floor(max_spawn_count), 0))
	end
	local spawned = 0
	for _, definition in profile.agents do
		if spawned >= spawn_count then
			break
		end
		if existing_ids[definition.id] then
			continue
		end
		local fallback_cframe = CFrame.new(fallback_origin + (definition.offset or Vector3.zero))
		local spawn_cframe = pick_spawn_cframe(spawn_locations, used_spawn_indexes, fallback_cframe)
		local npc = clone_template(template, map_id, definition, spawn_cframe)
		npc.Parent = npcs_folder
		refresh_humanoid(npc)
		existing_ids[definition.id] = true
		spawned += 1
	end

	return map_id
end

function npc_spawn_controller.trim(npcs_folder, max_agents)
	local generated = {}
	for _, npc in npcs_folder:GetChildren() do
		if npc:IsA("Model") and npc_spawn_controller.is_generated(npc) then
			local humanoid = npc:FindFirstChildWhichIsA("Humanoid")
			if humanoid and humanoid.Health > 0 then
				table.insert(generated, npc)
			end
		end
	end
	table.sort(generated, function(a, b)
		return a.Name < b.Name
	end)
	for index = max_agents + 1, #generated do
		npc_values.clear_metadata(generated[index])
		generated[index]:Destroy()
	end
end

function npc_spawn_controller.start(ctx, npcs_folder, map_id, max_agents)
	ctx.active_map_id = map_id or default_map_id

	npc_spawn_controller.clear(npcs_folder)

	return npc_spawn_controller.ensure(ctx, npcs_folder, max_agents)
end

function npc_spawn_controller.is_generated(npc)
	return npc_values.read_bool(npc, "managed_npc", false) == true
end

return npc_spawn_controller
