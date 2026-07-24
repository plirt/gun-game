local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttachmentEffects = require(ReplicatedStorage.Modules.Shared.AttachmentEffects)
local WeaponConfig = require(ReplicatedStorage.Modules.Shared.WeaponConfig)
local player_state = require(script.Parent.Parent.PlayerState)

local weapon_config_resolver = {}

local resolved_cache = {}

local function get_attachment_names(attachments)
	local names = {}
	for attachment_type, attachment_name in attachments or {} do
		if type(attachment_type) == "string"
			and type(attachment_name) == "string"
			and attachment_name ~= ""
		then
			table.insert(names, attachment_name)
		end
	end
	table.sort(names)
	return names
end

local function make_cache_key(item_id, names)
	return item_id .. "\0" .. table.concat(names, "\0")
end

function weapon_config_resolver.resolve(item_id, base_config, attachments)
	if type(item_id) ~= "string" or type(base_config) ~= "table" then
		return nil
	end
	local names = get_attachment_names(attachments)
	local cache_key = make_cache_key(item_id, names)
	local cached = resolved_cache[cache_key]
	if cached then
		return cached
	end
	local resolved = AttachmentEffects.apply(base_config, names)
	resolved = WeaponConfig.normalize(resolved)
	resolved_cache[cache_key] = table.freeze(resolved)
	return resolved_cache[cache_key]
end

function weapon_config_resolver.get_for_player(player, item_id)
	local base_config = player_state.get_config(item_id)
	if not base_config then
		return nil
	end
	local state = player_state.ensure_player_state(player)
	return weapon_config_resolver.resolve(item_id, base_config, state.attachments[item_id])
end

function weapon_config_resolver.get_for_actor(actor, item_id)
	local base_config = player_state.get_config(item_id)
	if not base_config then
		return nil
	end
	return weapon_config_resolver.resolve(item_id, base_config, actor:get_attachments(item_id))
end

function weapon_config_resolver.clear()
	table.clear(resolved_cache)
end

return weapon_config_resolver

