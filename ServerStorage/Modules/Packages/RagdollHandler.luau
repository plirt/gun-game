local ragdoll_handler = {}
local ragdolled_characters = setmetatable({}, { __mode = "k" })

local joint_limits = {
	Neck = { upper = 35, twist_lower = -35, twist_upper = 35 },
	Waist = { upper = 30, twist_lower = -25, twist_upper = 25 },
	Root = { upper = 25, twist_lower = -20, twist_upper = 20 },
	LeftShoulder = { upper = 80, twist_lower = -60, twist_upper = 60 },
	RightShoulder = { upper = 80, twist_lower = -60, twist_upper = 60 },
	LeftHip = { upper = 55, twist_lower = -35, twist_upper = 35 },
	RightHip = { upper = 55, twist_lower = -35, twist_upper = 35 },
}

local function cleanup_ragdoll_objects(char)
	for _, obj in char:GetDescendants() do
		if obj.Name == "ragdoll_constraint" or obj.Name == "ragdoll_attachment" then
			obj:Destroy()
		end
	end
end

local function set_network_owner(part)
	if not part:IsA("BasePart") then
		return
	end
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
end

local function setup_part(part, is_root)
	part.Anchored = false
	part.Massless = false
	part.CanTouch = true
	part.CanQuery = true
	part.CanCollide = not is_root
	set_network_owner(part)
end

local function setup_humanoid(humanoid)
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
end

local function restore_humanoid(humanoid)
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

local function create_socket(motor)
	local part_0 = motor.Part0
	local part_1 = motor.Part1
	if not part_0 or not part_1 then
		return
	end

	local attachment_0 = Instance.new("Attachment")
	attachment_0.Name = "ragdoll_attachment"
	attachment_0.CFrame = motor.C0
	attachment_0.Parent = part_0

	local attachment_1 = Instance.new("Attachment")
	attachment_1.Name = "ragdoll_attachment"
	attachment_1.CFrame = motor.C1
	attachment_1.Parent = part_1

	local limits = joint_limits[motor.Name] or { upper = 45, twist_lower = -45, twist_upper = 45 }
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = "ragdoll_constraint"
	socket.Attachment0 = attachment_0
	socket.Attachment1 = attachment_1
	socket.LimitsEnabled = true
	socket.TwistLimitsEnabled = true
	socket.UpperAngle = limits.upper
	socket.TwistLowerAngle = limits.twist_lower
	socket.TwistUpperAngle = limits.twist_upper
	socket.MaxFrictionTorque = 35
	socket.Restitution = 0
	socket.Parent = part_0

	motor.Enabled = false
end

local function get_knockback_direction(root, source_position, hit_direction)
	if typeof(hit_direction) == "Vector3" and hit_direction.Magnitude > 0.01 then
		return hit_direction.Unit
	end
	if typeof(source_position) == "Vector3" then
		local from_source = root.Position - source_position
		if from_source.Magnitude > 0.01 then
			return from_source.Unit
		end
	end
	return root.CFrame.LookVector
end

local function knock_down(char, root, source_position, hit_direction, hit_position, multiplier)
	multiplier = type(multiplier) == "number" and math.clamp(multiplier, 0.1, 2.5) or 1
	local direction = get_knockback_direction(root, source_position, hit_direction)
	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	if horizontal.Magnitude < 0.01 then
		horizontal = root.CFrame.LookVector
	else
		horizontal = horizontal.Unit
	end

	local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso") or root
	local topple_axis = horizontal:Cross(Vector3.yAxis)
	if topple_axis.Magnitude < 0.01 then
		topple_axis = root.CFrame.RightVector
	else
		topple_axis = topple_axis.Unit
	end

	local root_velocity = (horizontal * 18 + Vector3.new(0, 4, 0)) * multiplier
	root.AssemblyLinearVelocity = root_velocity
	root.AssemblyAngularVelocity = topple_axis * 7 * multiplier

	if torso and torso:IsA("BasePart") then
		torso.AssemblyLinearVelocity = (horizontal * 22 + Vector3.new(0, 5, 0)) * multiplier
		torso.AssemblyAngularVelocity = topple_axis * 9 * multiplier
	end

	pcall(function()
		root:ApplyImpulse((horizontal * 28 + Vector3.new(0, 8, 0)) * root.AssemblyMass * multiplier)
		root:ApplyAngularImpulse(topple_axis * root.AssemblyMass * 36 * multiplier)
		if torso and torso:IsA("BasePart") and torso ~= root then
			local impulse_position = typeof(hit_position) == "Vector3" and hit_position or torso.Position + Vector3.new(0, 1.4, 0)
			torso:ApplyImpulseAtPosition((horizontal * 32 + Vector3.new(0, 10, 0)) * torso.AssemblyMass * multiplier, impulse_position)
			torso:ApplyAngularImpulse(topple_axis * torso.AssemblyMass * 48 * multiplier)
		end
	end)
end

function ragdoll_handler:Apply(char: Model, source_position: Vector3?, hit_direction: Vector3?, hit_position: Vector3?, multiplier: number?)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return false
	end
	if ragdolled_characters[char] then
		return false
	end

	ragdolled_characters[char] = true
	cleanup_ragdoll_objects(char)
	setup_humanoid(humanoid)

	for _, descendant in char:GetDescendants() do
		if descendant:IsA("BasePart") then
			setup_part(descendant, descendant == root)
		elseif descendant:IsA("Motor6D") then
			create_socket(descendant)
		end
	end

	if source_position then
		local direction = root.Position - source_position
		if direction.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + direction.Unit)
		end
	end

	knock_down(char, root, source_position, hit_direction, hit_position, multiplier)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	return true
end

function ragdoll_handler:Knockback(char: Model, source_position: Vector3?, hit_direction: Vector3?, hit_position: Vector3?, multiplier: number?)
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	knock_down(char, root, source_position, hit_direction, hit_position, multiplier)
	return true
end

function ragdoll_handler:IsRagdolled(char: Model)
	return ragdolled_characters[char] == true
end

function ragdoll_handler:Remove(char: Model)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or not ragdolled_characters[char] then
		return false
	end

	ragdolled_characters[char] = nil
	cleanup_ragdoll_objects(char)

	for _, obj in char:GetDescendants() do
		if obj:IsA("Motor6D") then
			obj.Enabled = true
		elseif obj:IsA("BasePart") then
			obj.CanCollide = obj.Name ~= "HumanoidRootPart"
		end
	end

	restore_humanoid(humanoid)
	return true
end

return ragdoll_handler