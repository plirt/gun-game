local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttachmentModifier = require(ReplicatedStorage.Modules.Client.AttachmentModifier)

local gun_viewmodel_builder = {}

local function setup_part(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.LocalTransparencyModifier = 0
end

local function is_managed_viewmodel(model)
	return model:FindFirstChild("ManagedByGunManager") ~= nil
end

function gun_viewmodel_builder.set_hidden(viewmodel, hidden)
	local saved = hidden and {} or nil
	for _, descendant in viewmodel:GetDescendants() do
		if descendant:IsA("BasePart") then
			if hidden then
				saved[descendant] = descendant.LocalTransparencyModifier
				descendant.LocalTransparencyModifier = 1
			else
				descendant.LocalTransparencyModifier = 0
			end
		end
	end
	return saved
end

function gun_viewmodel_builder.restore_visibility(saved)
	if not saved then
		return
	end
	for part, local_transparency in saved do
		if part.Parent then
			part.LocalTransparencyModifier = local_transparency
		end
	end
end

function gun_viewmodel_builder.weld(viewmodel)
	local root = viewmodel:FindFirstChild("HumanoidRootPart") or viewmodel.PrimaryPart
	assert(root and root:IsA("BasePart"), "Viewmodel needs HumanoidRootPart or PrimaryPart")
	viewmodel.PrimaryPart = root
	for _, descendant in viewmodel:GetDescendants() do
		if descendant:IsA("BasePart") then
			setup_part(descendant)
		end
	end
	root.Anchored = true
end

function gun_viewmodel_builder.read_string_value(parent, name)
	local value = parent:FindFirstChild(name)
	if value and value:IsA("StringValue") then
		return value.Value
	end
	return nil
end

function gun_viewmodel_builder.write_string_value(parent, name, text)
	local value = parent:FindFirstChild(name)
	if not value then
		value = Instance.new("StringValue")
		value.Name = name
		value.Parent = parent
	end
	value.Value = text
end

function gun_viewmodel_builder.cleanup_camera_viewmodels(camera, keep_viewmodel)
	if not camera then
		return
	end
	for _, child in camera:GetChildren() do
		local is_viewmodel = child:IsA("Model")
			and child ~= keep_viewmodel
			and (child.Name == "Viewmodel" or is_managed_viewmodel(child))
		if is_viewmodel then
			child:SetAttribute("destroyed", true)
			child:Destroy()
		end
	end
end

function gun_viewmodel_builder.attach_gun(gun_model, root, config)
	local main = gun_model.PrimaryPart or gun_model:FindFirstChild("MAIN", true)
	assert(main and main:IsA("BasePart"), "Gun needs a BasePart named MAIN or PrimaryPart")
	local existing_grip = root:FindFirstChild("MAIN")
	if existing_grip then
		existing_grip:Destroy()
	end
	local grip = Instance.new("Motor6D")
	grip.Name = "MAIN"
	grip.Part0 = root
	grip.Part1 = main
	grip.C0 = config.main_c0 or CFrame.identity
	grip.C1 = config.main_c1 or CFrame.identity
	grip.Parent = root
end

function gun_viewmodel_builder.find_ads_point(gun_model)
	local mounted_ads_point = AttachmentModifier.find_mounted_ads_point(gun_model)
	if mounted_ads_point then
		return mounted_ads_point
	end
	local names = { "ADSPoint", "ADSAim", "AimPoint", "ScopeAim", "SightAim", "CameraAim" }
	for _, name in names do
		local point = gun_model:FindFirstChild(name, true)
		if point and point:IsA("Attachment") then
			return point
		end
	end
	return nil
end

function gun_viewmodel_builder.find_sight_part(gun_model)
	return gun_model:FindFirstChild("IronSight", true)
		or gun_model:FindFirstChild("Ironsight", true)
		or gun_model:FindFirstChild("AdjustableScope", true)
		or gun_model:FindFirstChild("Muzzle", true)
end

function gun_viewmodel_builder.get_supported_attachments(gun_model, attachments)
	local supported = {}
	for attachment_type, attachment_name in attachments or {} do
		if attachment_name and attachment_name ~= "" and AttachmentModifier.can_attach(gun_model, attachment_name) then
			supported[attachment_type] = attachment_name
		end
	end
	return supported
end

return gun_viewmodel_builder
