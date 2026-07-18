local npc_values = {}

local metadata_by_instance = {}

function npc_values.get_metadata(parent)
	if not parent then
		return nil
	end

	if not metadata_by_instance[parent] then
		metadata_by_instance[parent] = {}
	end
	return metadata_by_instance[parent]
end

function npc_values.set_metadata(parent, metadata)
	if not parent then
		return nil
	end

	metadata_by_instance[parent] = metadata or {}
	return metadata_by_instance[parent]
end

function npc_values.clear_metadata(parent)
	if parent then
		metadata_by_instance[parent] = nil
	end
end

function npc_values.read_string(parent, name, fallback)
	local metadata = metadata_by_instance[parent]
	local value = metadata and metadata[name] or parent and parent:GetAttribute(name)

	if type(value) == "string" then
		return value
	end
	return fallback or ""
end

function npc_values.read_number(parent, name, fallback)
	local metadata = metadata_by_instance[parent]
	local value = metadata and metadata[name] or parent and parent:GetAttribute(name)

	if type(value) == "number" then
		return value
	end
	return fallback
end

function npc_values.read_bool(parent, name, fallback)
	local metadata = metadata_by_instance[parent]
	local value = metadata and metadata[name] or parent and parent:GetAttribute(name)

	if type(value) == "boolean" then
		return value
	end
	return fallback
end

function npc_values.write_string(parent, name, text)
	local metadata = npc_values.get_metadata(parent)

	if not metadata then
		return nil
	end

	metadata[name] = tostring(text or "")
	parent:SetAttribute(name, metadata[name])
	return metadata[name]
end

function npc_values.write_number(parent, name, number)
	local metadata = npc_values.get_metadata(parent)

	if not metadata then
		return nil
	end

	metadata[name] = number
	parent:SetAttribute(name, metadata[name])
	return metadata[name]
end

function npc_values.write_bool(parent, name, bool)
	local metadata = npc_values.get_metadata(parent)

	if not metadata then
		return nil
	end

	metadata[name] = bool == nil and true or bool
	parent:SetAttribute(name, metadata[name])
	return metadata[name]
end

function npc_values.clear(parent, name)
	local metadata = metadata_by_instance[parent]
	if metadata then
		metadata[name] = nil
	end
	if parent then
		parent:SetAttribute(name, nil)
	end
end

function npc_values.get_part(model, names)
	for _, name in names do
		local part = model:FindFirstChild(name, true)

		if part and part:IsA("BasePart") then
			return part
		end
	end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

function npc_values.get_or_create_animator(humanoid)
	local animator = humanoid:FindFirstChildWhichIsA("Animator")

	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end
return npc_values


