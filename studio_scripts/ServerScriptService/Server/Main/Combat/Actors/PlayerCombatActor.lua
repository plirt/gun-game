local player_combat_actor = {}
player_combat_actor.__index = player_combat_actor

function player_combat_actor.new(player, dependencies)
	return setmetatable({
		entity = player,
		dependencies = dependencies,
	}, player_combat_actor)
end

function player_combat_actor:get_entity()
	return self.entity
end

function player_combat_actor:get_character()
	return self.entity.Character
end

function player_combat_actor:get_humanoid()
	local character = self:get_character()
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

function player_combat_actor:is_alive()
	local humanoid = self:get_humanoid()
	return humanoid ~= nil and humanoid.Health > 0
end

function player_combat_actor:is_blocked()
	return self.entity:GetAttribute("ragdolled") == true
end

function player_combat_actor:get_equipped_item()
	return self.dependencies.player_character_weapon_service.get_equipped_gun(self.entity)
end

function player_combat_actor:get_attachments(item_id)
	local state = self.dependencies.player_state.ensure_player_state(self.entity)
	return state.attachments[item_id] or {}
end

function player_combat_actor:get_origin_part()
	local character = self:get_character()
	if not character then
		return nil
	end
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	return head and head:IsA("BasePart") and head or root
end

return player_combat_actor

