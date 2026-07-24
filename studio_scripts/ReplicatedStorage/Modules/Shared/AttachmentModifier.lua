local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttachmentModifier = {}

local ATTACHMENTS_FOLDER = ReplicatedStorage:WaitForChild("Attachments")
local MOUNT_FOLDER_NAME = "MountedAttachments"

local function singularize(name)
	if name:sub(-3) == "ies" then
		return name:sub(1, -4) .. "y"
	end

	if name:sub(-1) == "s" then
		return name:sub(1, -2)
	end
	return name
end

local function read_string_value(parent, name)
	local value = parent:FindFirstChild(name)
	if value and value:IsA("StringValue") then
		return value.Value
	end
	return nil
end

local function write_string_value(parent, name, text)
	local value = parent:FindFirstChild(name)
	if not value then
		value = Instance.new("StringValue")
		value.Name = name
		value.Parent = parent
	end
	value.Value = text
end

local function get_attachment_type(template)
	local parent = template.Parent
	if parent and parent ~= ATTACHMENTS_FOLDER then
		return singularize(parent.Name)
	end
	return read_string_value(template, "AttachmentType") or template.Name
end

local function get_primary_part(model)
	if model:IsA("BasePart") then
		return model
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	local first_part = model:FindFirstChildWhichIsA("BasePart", true)
	if first_part then
		model.PrimaryPart = first_part
	end
	return first_part
end

local function setup_attachment_part(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.LocalTransparencyModifier = 0
end

local function for_each_template(callback)
	for _, child in ATTACHMENTS_FOLDER:GetChildren() do
		if child:IsA("Folder") then
			for _, template in child:GetChildren() do
				if template:IsA("Model") or template:IsA("BasePart") then
					callback(template)
				end
			end
		elseif child:IsA("Model") or child:IsA("BasePart") then
			callback(child)
		end
	end
end

local function find_template(attachment_name)
	local found = nil

	for_each_template(function(template)
		if not found and template.Name == attachment_name then
			found = template
		end
	end)
	return found
end

local MOUNT_NAMES_BY_TYPE = {
	Grip = { "GripAttachment", "GripPoint" },
	Sight = { "SightAttachment", "SightPoint" },
}

local function get_mount_names(attachment_name, attachment_type)
	local names = {}
	for _, name in MOUNT_NAMES_BY_TYPE[attachment_type] or {} do
		table.insert(names, name)
	end
	table.insert(names, attachment_name .. "Point")
	table.insert(names, attachment_name .. "Attachment")
	table.insert(names, attachment_type .. "Point")
	table.insert(names, attachment_type .. "Attachment")
	return names
end

local function find_mount_point(gun_model, attachment_name, attachment_type)
	local names = get_mount_names(attachment_name, attachment_type)

	for _, name in names do
		local point = gun_model:FindFirstChild(name, true)
		if point and (point:IsA("Attachment") or point:IsA("BasePart")) then
			return point
		end
	end
	return nil
end

local function get_mount_cframe(point)
	if point:IsA("Attachment") then
		return point.WorldCFrame
	end
	return point.CFrame
end

local function get_point_part(gun_model, point)
	if point:IsA("BasePart") then
		return point
	end

	if point.Parent and point.Parent:IsA("BasePart") then
		return point.Parent
	end

	local main = gun_model.PrimaryPart or gun_model:FindFirstChild("MAIN", true)
	if main and main:IsA("BasePart") then
		return main
	end
	return gun_model:FindFirstChildWhichIsA("BasePart", true)
end

local function get_local_attach_offset(attachment_model, primary_part)
	local attach_point = attachment_model:FindFirstChild("AttachPoint", true)
		or attachment_model:FindFirstChild("MountPoint", true)
		or attachment_model:FindFirstChild("AttachmentPoint", true)
	if attach_point and attach_point:IsA("Attachment") then
		return primary_part.CFrame:ToObjectSpace(attach_point.WorldCFrame)
	end
	return CFrame.identity
end

local function clear_type(gun_model, attachment_type)
	local mounted_folder = gun_model:FindFirstChild(MOUNT_FOLDER_NAME)
	if not mounted_folder then
		return
	end

	for _, child in mounted_folder:GetChildren() do
		if child.Name == attachment_type then
			child:Destroy()
		end
	end
end

function AttachmentModifier.can_attach(gun_model, attachment_name)
	local template = find_template(attachment_name)
	if not gun_model or not template then
		return false
	end

	local attachment_type = get_attachment_type(template)
	return find_mount_point(gun_model, attachment_name, attachment_type) ~= nil
end

function AttachmentModifier.get_available(gun_model)
	local available = {}

	for_each_template(function(template)
		local attachment_type = get_attachment_type(template)
		local can_attach = not gun_model or AttachmentModifier.can_attach(gun_model, template.Name)
		if can_attach then
			table.insert(available, {
				name = template.Name,
				display_name = read_string_value(template, "DisplayName") or template.Name,
				type = attachment_type,
			})
		end
	end)

	table.sort(available, function(a, b)
		if a.type == b.type then
			return a.display_name < b.display_name
		end
		return a.type < b.type
	end)
	return available
end

function AttachmentModifier.attach(gun_model, attachment_name)
	local template = find_template(attachment_name)
	if not template then
		return nil, "Attachment " .. tostring(attachment_name) .. " was not found."
	end

	local attachment_type = get_attachment_type(template)
	local mount_point = find_mount_point(gun_model, attachment_name, attachment_type)
	if not mount_point then
		return nil, "Gun is missing " .. attachment_name .. "Point or " .. attachment_type .. "Attachment."
	end

	local mount_part = get_point_part(gun_model, mount_point)
	if not mount_part then
		return nil, "Gun has no BasePart to weld the attachment to."
	end

	clear_type(gun_model, attachment_type)

	local mounted_folder = gun_model:FindFirstChild(MOUNT_FOLDER_NAME)
	if not mounted_folder then
		mounted_folder = Instance.new("Folder")
		mounted_folder.Name = MOUNT_FOLDER_NAME
		mounted_folder.Parent = gun_model
	end

	local clone = template:Clone()
	clone.Name = attachment_type
	write_string_value(clone, "AttachmentName", attachment_name)
	write_string_value(clone, "AttachmentType", attachment_type)
	clone.Parent = mounted_folder

	local primary_part = get_primary_part(clone)
	if not primary_part then
		clone:Destroy()
		return nil, "Attachment has no BasePart to mount."
	end

	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			setup_attachment_part(descendant)
		end
	end
	if clone:IsA("BasePart") then
		setup_attachment_part(clone)
	end

	local local_attach_offset = get_local_attach_offset(clone, primary_part)
	local target_cframe = get_mount_cframe(mount_point) * local_attach_offset:Inverse()

	if clone:IsA("Model") then
		clone:PivotTo(target_cframe)
	else
		clone.CFrame = target_cframe
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = attachment_type .. "MountWeld"
	weld.Part0 = mount_part
	weld.Part1 = primary_part
	weld.Parent = primary_part
	return clone
end

function AttachmentModifier.remove(gun_model, attachment_type)
	clear_type(gun_model, attachment_type)
end

function AttachmentModifier.clear_all(gun_model)
	local mounted_folder = gun_model:FindFirstChild(MOUNT_FOLDER_NAME)
	if mounted_folder then
		mounted_folder:Destroy()
	end
end

function AttachmentModifier.apply_loadout(gun_model, attachments)
	local mounted = {}

	for attachment_type, attachment_name in attachments or {} do
		if attachment_name and attachment_name ~= "" then
			local clone, err = AttachmentModifier.attach(gun_model, attachment_name)
			if clone then
				mounted[attachment_type] = clone
			else
				warn(err)
			end
		end
	end
	return mounted
end

function AttachmentModifier.find_mounted(gun_model, attachment_type)
	local mounted_folder = gun_model:FindFirstChild(MOUNT_FOLDER_NAME)
	if not mounted_folder then
		return nil
	end
	return mounted_folder:FindFirstChild(attachment_type)
end

function AttachmentModifier.find_mounted_ads_point(gun_model)
	local sight = AttachmentModifier.find_mounted(gun_model, "Sight")
	if not sight then
		return nil
	end

	local names = { "ADSPoint", "ADSAim", "AimPoint", "ScopeAim", "SightAim", "CameraAim" }
	for _, name in names do
		local point = sight:FindFirstChild(name, true)
		if point and point:IsA("Attachment") then
			return point
		end
	end
	return nil
end
return AttachmentModifier

