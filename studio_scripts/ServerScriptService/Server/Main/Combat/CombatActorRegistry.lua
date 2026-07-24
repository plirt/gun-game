local PlayerCombatActor = require(script.Parent.Actors.PlayerCombatActor)

local combat_actor_registry = {}
combat_actor_registry.__index = combat_actor_registry

function combat_actor_registry.new(dependencies)
	return setmetatable({
		dependencies = dependencies,
		actors = setmetatable({}, { __mode = "k" }),
	}, combat_actor_registry)
end

function combat_actor_registry:register(entity, actor)
	assert(typeof(entity) == "Instance", "entity must be an Instance")
	assert(type(actor) == "table", "actor is required")
	self.actors[entity] = actor
	return actor
end

function combat_actor_registry:unregister(entity)
	self.actors[entity] = nil
end

function combat_actor_registry:get(entity)
	if typeof(entity) ~= "Instance" then
		return nil
	end
	local actor = self.actors[entity]
	if actor then
		return actor
	end
	if entity:IsA("Player") then
		actor = PlayerCombatActor.new(entity, self.dependencies)
		self.actors[entity] = actor
		return actor
	end
	return nil
end

function combat_actor_registry:resolve_humanoid(humanoid)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return nil
	end
	local model = humanoid.Parent
	if not model then
		return nil
	end
	local player = self.dependencies.Players:GetPlayerFromCharacter(model)
	return self:get(player or model)
end

return combat_actor_registry

