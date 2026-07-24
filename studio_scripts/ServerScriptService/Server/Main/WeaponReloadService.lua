local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponReloadPlan = require(ReplicatedStorage.Modules.Shared.WeaponReloadPlan)
local weapon_runtime_store = require(script.Parent.WeaponRuntimeStore)

local weapon_reload_service = {}

local function notify(on_state_changed)
	if on_state_changed then
		on_state_changed()
	end
end

local function run_per_round_reload(player, gun_name, weapon_state, config, reload_started, reload_plan, round_index, on_state_changed)
	local delay_time = round_index == 1 and reload_plan.start_time + reload_plan.insert_time or reload_plan.insert_time
	task.delay(delay_time, function()
		if not weapon_runtime_store.is_reload_active(weapon_state, reload_started) then
			return
		end
		local current_bundle = weapon_runtime_store.get_bundle(player, gun_name)
		if not current_bundle or current_bundle.weapon_state ~= weapon_state then
			weapon_runtime_store.cancel_reload(weapon_state, reload_started)
			notify(on_state_changed)
			return
		end
		if not weapon_runtime_store.load_round(weapon_state, config, reload_started) then
			weapon_runtime_store.end_reload(weapon_state, reload_started)
			notify(on_state_changed)
			return
		end
		notify(on_state_changed)
		if round_index < reload_plan.round_count then
			run_per_round_reload(player, gun_name, weapon_state, config, reload_started, reload_plan, round_index + 1, on_state_changed)
			return
		end
		task.delay(reload_plan.end_time, function()
			if weapon_runtime_store.end_reload(weapon_state, reload_started) then
				notify(on_state_changed)
			end
		end)
	end)
end

function weapon_reload_service.reload(player: Player, gun_name: any, on_state_changed): { ok: boolean, code: string? }
	if type(gun_name) ~= "string" then
		return { ok = false, code = "bad_request" }
	end
	local bundle = weapon_runtime_store.get_bundle(player, gun_name)
	if not bundle then
		return { ok = false, code = "weapon_unavailable" }
	end
	local weapon_state = bundle.weapon_state
	local config = bundle.config
	if weapon_state.reloading then
		return { ok = false, code = "already_reloading" }
	end
	if weapon_state.magazine >= config.magazine_size then
		return { ok = false, code = "magazine_full" }
	end
	if weapon_state.reserve <= 0 then
		return { ok = false, code = "no_reserve" }
	end
	local reload_plan = WeaponReloadPlan.build(config, weapon_state.magazine, weapon_state.reserve)
	if reload_plan.round_count <= 0 then
		return { ok = false, code = "nothing_to_load" }
	end
	local reload_started = weapon_runtime_store.begin_reload(weapon_state)
	notify(on_state_changed)
	if reload_plan.style == "per_round" then
		run_per_round_reload(player, gun_name, weapon_state, config, reload_started, reload_plan, 1, on_state_changed)
	else
		task.delay(reload_plan.total_time, function()
			if weapon_runtime_store.finish_reload(weapon_state, config, reload_started) then
				notify(on_state_changed)
			end
		end)
	end
	return { ok = true }
end

return weapon_reload_service

