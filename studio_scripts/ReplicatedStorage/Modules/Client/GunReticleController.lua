local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttachmentModifier = require(ReplicatedStorage.Modules.Shared.AttachmentModifier)
local ReticleData = require(ReplicatedStorage.Data.ReticleData)

local gun_reticle_controller = {}


local function read_string_value(parent: Instance, name: string): string?
	local value = parent:FindFirstChild(name)
	if value and value:IsA("StringValue") then
		return value.Value
	end
	return nil
end

local function get_reticle_data_key(name: string?): string?
	if not name or name == "" then
		return nil
	end
	if ReticleData[name] then
		return name
	end
	local underscored = name:gsub("(%l)(%u)", "%1_%2")
	if ReticleData[underscored] then
		return underscored
	end
	local compact_name = name:gsub("_", ""):lower()
	for key in ReticleData do
		if key:gsub("_", ""):lower() == compact_name then
			return key
		end
	end
	return nil
end

function gun_reticle_controller.get_sight_data(manager)
	local mounted_sight = AttachmentModifier.find_mounted(manager.gun_model, "Sight")
	if mounted_sight then
		local data_key = read_string_value(mounted_sight, "ReticleDataKey")
			or read_string_value(mounted_sight, "AttachmentName")
			or mounted_sight.Name
		local reticle_key = get_reticle_data_key(data_key)
		if reticle_key then
			return ReticleData[reticle_key]
		end
	end
	return manager.config.sight_data
end


return gun_reticle_controller

