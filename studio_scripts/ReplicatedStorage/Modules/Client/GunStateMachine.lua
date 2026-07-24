local gun_state_machine = {}

export type WeaponState = "idle" | "equipping" | "reloading" | "unequipping" | "blocked"

local allowed: { [WeaponState]: { [WeaponState]: boolean } } = {
	idle = { equipping = true, reloading = true, unequipping = true, blocked = true },
	equipping = { idle = true, unequipping = true, blocked = true },
	reloading = { idle = true, unequipping = true, blocked = true },
	unequipping = { idle = true, blocked = true },
	blocked = { idle = true },
}

function gun_state_machine.set(manager, next_state: WeaponState): boolean
	local current_state = manager.weapon_state or "idle"
	if current_state == next_state then
		return true
	end
	if not allowed[current_state] or not allowed[current_state][next_state] then
		return false
	end
	manager.weapon_state = next_state
	return true
end

function gun_state_machine.is_busy(manager): boolean
	return manager.weapon_state == "equipping" or manager.weapon_state == "reloading" or manager.weapon_state == "unequipping" or manager.weapon_state == "blocked"
end

function gun_state_machine.can_fire(manager): boolean
	return manager.weapon_state == "idle" and manager.equipped and not manager.reloading and not manager.equipping and not manager.unequipping
end

return gun_state_machine

