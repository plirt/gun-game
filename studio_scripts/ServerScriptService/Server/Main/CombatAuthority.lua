-- CombatAuthority is the stable boundary between combat producers and match rules.
-- Weapons, grenades, and NPCs report combat through this object without requiring
-- MatchService or knowing which mode is active. MatchService binds the current policy once.
--
-- Default behavior permits non-self damage so combat can boot without a round provider.
-- Recording hooks intentionally default to no-op; they become authoritative after bind().

local combat_authority = {}
combat_authority.__index = combat_authority

function combat_authority.new()
	return setmetatable({
		provider = nil,
		version = 0,
	}, combat_authority)
end

function combat_authority:bind(provider)
	assert(type(provider) == "table", "combat provider must be a table")
	assert(type(provider.can_damage) == "function", "combat provider requires can_damage")
	self.provider = provider
	self.version += 1
	return self.version
end

function combat_authority:can_damage(attacker, victim): boolean
	if not attacker or not victim or attacker == victim then
		return false
	end
	local provider = self.provider
	return not provider or provider.can_damage(attacker, victim)
end

function combat_authority:get_combat_entity(humanoid: Humanoid)
	local provider = self.provider
	return provider and provider.get_combat_entity and provider.get_combat_entity(humanoid) or nil
end

function combat_authority:record_damage(attacker, humanoid: Humanoid)
	local provider = self.provider
	if provider and provider.record_damage then
		provider.record_damage(attacker, humanoid)
	end
end

function combat_authority:record_death(humanoid: Humanoid)
	local provider = self.provider
	if provider and provider.record_death then
		provider.record_death(humanoid)
	end
end

function combat_authority:get_objective_position(): Vector3?
	local provider = self.provider
	return provider and provider.get_objective_position and provider.get_objective_position() or nil
end

return combat_authority

