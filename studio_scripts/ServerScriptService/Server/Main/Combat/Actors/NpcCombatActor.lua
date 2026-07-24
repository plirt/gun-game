local npc_combat_actor = {}
npc_combat_actor.__index = npc_combat_actor

function npc_combat_actor.new(agent, dependencies)
	return setmetatable({
		entity = agent.npc,
		agent = agent,
		dependencies = dependencies,
	}, npc_combat_actor)
end

function npc_combat_actor:get_entity()
	return self.entity
end

function npc_combat_actor:get_character()
	return self.agent.npc
end

function npc_combat_actor:get_humanoid()
	return self.agent.humanoid
end

function npc_combat_actor:is_alive()
	return self.entity.Parent ~= nil and self.agent.humanoid.Health > 0
end

function npc_combat_actor:is_blocked()
	return self.dependencies.is_stunned(self.entity)
		or self.dependencies.get_state(self.entity) == "ragdolled"
end

function npc_combat_actor:get_equipped_item()
	return self.agent.gun_name or self.agent.gun_id
end

function npc_combat_actor:get_attachments(item_id)
	local attachments = self.agent.attachments
	if type(attachments) == "table" then
		return attachments
	end
	return {}
end

function npc_combat_actor:get_origin_part()
	local head = self.entity:FindFirstChild("Head")
	return head and head:IsA("BasePart") and head or self.agent.root
end

return npc_combat_actor

