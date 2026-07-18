local pseudo_spawn_service = {}

local SPAWN_FOLDER_NAME = "PseudoSpawnLocations"
local SPAWN_HEIGHT_OFFSET = 3.5

local random = Random.new()

local function get_spawn_parts()
	local folder = workspace:FindFirstChild(SPAWN_FOLDER_NAME)
	if not folder then
		return {}
	end

	local spawns = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(spawns, child)
		end
	end

	table.sort(spawns, function(a, b)
		return a.Name < b.Name
	end)

	return spawns
end

local function get_character_root(player: Player): BasePart?
	local character = player.Character or player.CharacterAdded:Wait()
	return character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
end

local function clear_velocity(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

function pseudo_spawn_service.get_random_spawn(): BasePart?
	local spawns = get_spawn_parts()
	if #spawns == 0 then
		return nil
	end
	return spawns[random:NextInteger(1, #spawns)]
end

function pseudo_spawn_service.teleport_player(player: Player): boolean
	local spawn_part = pseudo_spawn_service.get_random_spawn()
	if not spawn_part then
		return false
	end

	local root = get_character_root(player)
	local character = player.Character
	if not root or not character then
		return false
	end

	local target_cframe = spawn_part.CFrame + Vector3.new(0, SPAWN_HEIGHT_OFFSET, 0)
	character:PivotTo(target_cframe)
	clear_velocity(character)

	return true
end

return pseudo_spawn_service
