local weapon_runtime_store = {}

local player_character_weapon_service = require(script.Parent.player_character_weapon_service)
local player_state = require(script.Parent.player_state)

export type RuntimeBundle = {
	player_state: any,
	weapon_state: any,
	config: any,
}

function weapon_runtime_store.get_bundle(player: Player, gun_name: string): RuntimeBundle?
	local state = player_state.ensure_player_state(player)
	if not state.inventory[gun_name] then
		return nil
	end
	if not player_state.is_in_loadout(state, gun_name) then
		return nil
	end
	if not player_character_weapon_service.is_equipped(player, gun_name) then
		return nil
	end
	local config = player_state.get_config(gun_name)
	if not config then
		return nil
	end
	return {
		player_state = state,
		weapon_state = player_state.get_weapon_state(player, gun_name, config),
		config = config,
	}
end

function weapon_runtime_store.begin_reload(weapon_state: any): number
	weapon_state.reloading = true
	weapon_state.reload_started = os.clock()
	return weapon_state.reload_started
end

function weapon_runtime_store.is_reload_active(weapon_state: any, reload_started: number): boolean
	return weapon_state.reloading and weapon_state.reload_started == reload_started
end

function weapon_runtime_store.load_round(weapon_state: any, config: any, reload_started: number): boolean
	if not weapon_runtime_store.is_reload_active(weapon_state, reload_started) then
		return false
	end
	if weapon_state.magazine >= config.magazine_size or weapon_state.reserve <= 0 then
		return false
	end
	weapon_state.magazine += 1
	weapon_state.reserve -= 1
	return true
end

function weapon_runtime_store.finish_reload(weapon_state: any, config: any, reload_started: number): boolean
	if not weapon_runtime_store.is_reload_active(weapon_state, reload_started) then
		return false
	end
	local needed = config.magazine_size - weapon_state.magazine
	local loaded = math.min(needed, weapon_state.reserve)
	weapon_state.magazine += loaded
	weapon_state.reserve -= loaded
	weapon_state.reloading = false
	weapon_state.reload_started = nil
	return true
end

function weapon_runtime_store.end_reload(weapon_state: any, reload_started: number): boolean
	if not weapon_runtime_store.is_reload_active(weapon_state, reload_started) then
		return false
	end
	weapon_state.reloading = false
	weapon_state.reload_started = nil
	return true
end

function weapon_runtime_store.cancel_reload(weapon_state: any, reload_started: number)
	if weapon_runtime_store.is_reload_active(weapon_state, reload_started) then
		weapon_state.reloading = false
		weapon_state.reload_started = nil
	end
end

function weapon_runtime_store.can_consume_fire(weapon_state: any, config: any, now: number, grace_multiplier: number): (boolean, string?)
	if weapon_state.reloading then
		return false, "reloading"
	end
	if weapon_state.magazine <= 0 then
		return false, "empty"
	end
	if now - weapon_state.last_fire_time < config.seconds_per_shot * grace_multiplier then
		return false, "fire_rate_limited"
	end
	return true, nil
end

function weapon_runtime_store.consume_fire(weapon_state: any, now: number)
	weapon_state.last_fire_time = now
	weapon_state.magazine -= 1
end

function weapon_runtime_store.get_snapshot(player: Player, gun_name: any)
	if type(gun_name) ~= "string" or gun_name == "" then
		return nil
	end
	local state = player_state.ensure_player_state(player)
	if not state.inventory[gun_name] then
		return nil
	end
	local config = player_state.get_config(gun_name)
	if not config then
		return nil
	end
	local weapon_state = player_state.get_weapon_state(player, gun_name, config)
	return {
		gun_name = gun_name,
		magazine = weapon_state.magazine,
		reserve = weapon_state.reserve,
		reloading = weapon_state.reloading == true,
	}
end

return weapon_runtime_store
