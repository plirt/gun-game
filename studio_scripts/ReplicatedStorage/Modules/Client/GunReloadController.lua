local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunAnimationController = require(ReplicatedStorage.Modules.Client.GunAnimationController)
local GunStateMachine = require(ReplicatedStorage.Modules.Client.GunStateMachine)
local WeaponReloadPlan = require(ReplicatedStorage.Modules.Shared.WeaponReloadPlan)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local gun_reload_controller = {}

function gun_reload_controller.get_recoil_settle_time(manager): number
	local max_delay = manager.config.reload_recoil_settle_time or 0.16
	if max_delay <= 0 then
		return 0
	end
	local recently_recoiled = os.clock() - (manager.last_recoil_time or 0) < (manager.config.reload_recoil_recent_time or 0.18)
	local recoil_pending = manager.viewmodel_recoil_position_queued.Magnitude > 0.01
		or manager.viewmodel_recoil_rotation_queued.Magnitude > 0.001
		or math.abs(manager.camera_recoil_yaw_queued or 0) > 0.0005
	local recoil_visible = manager.viewmodel_recoil_position.Magnitude > 0.015
		or manager.viewmodel_recoil_rotation.Magnitude > 0.0015
		or (manager.arms_push_out or 0) > 0.005
	if recently_recoiled or recoil_pending or recoil_visible then
		return max_delay
	end
	return 0
end

local function is_reload_active(manager, reload_token: number): boolean
	return manager.equipped and manager.reloading and manager.reload_token == reload_token
end

local function finish_reload(manager, reload_token: number, reload_plan: WeaponReloadPlan.ReloadPlan)
	if not is_reload_active(manager, reload_token) then
		return
	end
	if reload_plan.start_animation then
		manager:stop_animation(reload_plan.start_animation)
	end
	if reload_plan.insert_animation then
		manager:stop_animation(reload_plan.insert_animation)
	end
	if reload_plan.end_animation then
		manager:stop_animation(reload_plan.end_animation)
	end
	if reload_plan.magazine_animation then
		manager:stop_animation(reload_plan.magazine_animation)
	end
	manager.reloading = false
	GunStateMachine.set(manager, "idle")
	manager:resume_idle(manager.config.idle_resume_fade_time or manager.config.idle_fade_time or 0.15)
end

local function run_per_round_reload(manager, reload_token: number, reload_plan: WeaponReloadPlan.ReloadPlan, round_index: number)
	if not is_reload_active(manager, reload_token) then
		return
	end
	if round_index > reload_plan.round_count then
		if reload_plan.end_animation then
			manager:play_animation(reload_plan.end_animation, nil, reload_plan.animation_speed)
		end
		task.delay(reload_plan.end_time, function()
			finish_reload(manager, reload_token, reload_plan)
		end)
		return
	end
	if reload_plan.insert_animation then
		manager:play_animation(reload_plan.insert_animation, nil, reload_plan.animation_speed)
	end
	task.delay(reload_plan.insert_time, function()
		if not is_reload_active(manager, reload_token) then
			return
		end
		local loaded = math.min(1, manager.config.magazine_size - manager.magazine, manager.reserve)
		if loaded <= 0 then
			finish_reload(manager, reload_token, reload_plan)
			return
		end
		manager.magazine += loaded
		manager.reserve -= loaded
		run_per_round_reload(manager, reload_token, reload_plan, round_index + 1)
	end)
end

local function begin_per_round_reload(manager, reload_token: number, reload_plan: WeaponReloadPlan.ReloadPlan)
	if reload_plan.start_animation then
		manager:play_animation(reload_plan.start_animation, nil, reload_plan.animation_speed)
	end
	task.delay(reload_plan.start_time, function()
		run_per_round_reload(manager, reload_token, reload_plan, 1)
	end)
end

local function begin_magazine_reload(manager, reload_token: number, reload_plan: WeaponReloadPlan.ReloadPlan)
	local animation_name = reload_plan.magazine_animation
	local animation_track = animation_name and manager:get_animation_track(animation_name)
	if animation_name == "TacticalReload" and not animation_track then
		animation_name = "Reload"
		animation_track = manager:get_animation_track(animation_name)
	end
	reload_plan.magazine_animation = animation_name
	local animation_duration = GunAnimationController.get_duration(animation_track, 1.5, reload_plan.animation_speed)
	local reload_time = math.max(reload_plan.total_time, animation_duration)
	if animation_name then
		local active_reload_track = manager:play_animation(animation_name, nil, reload_plan.animation_speed)
		if active_reload_track then
			if animation_name == "Reload" and manager.aiming then
				local blend_lead_time = math.min(
					manager.config.empty_reload_ads_idle_blend_lead_time or 0.28,
					animation_duration
				)
				task.delay(math.max(animation_duration - blend_lead_time, 0), function()
					if is_reload_active(manager, reload_token) and manager.aiming then
						manager:stop_animation(animation_name, blend_lead_time)
						manager:resume_idle(blend_lead_time)
					end
				end)
			end
		end
	end
	task.delay(reload_time, function()
		if not is_reload_active(manager, reload_token) then
			return
		end
		local loaded = math.min(manager.config.magazine_size - manager.magazine, manager.reserve)
		manager.magazine += loaded
		manager.reserve -= loaded
		finish_reload(manager, reload_token, reload_plan)
	end)
end

function gun_reload_controller.reload(manager): boolean
	if not manager:is_action_ready() or manager.reloading then
		return false
	end
	if manager.magazine >= manager.config.magazine_size or manager.reserve <= 0 then
		return false
	end
	local reload_plan = WeaponReloadPlan.build(manager.config, manager.magazine, manager.reserve)
	if reload_plan.round_count <= 0 or not GunStateMachine.set(manager, "reloading") then
		return false
	end
	manager.reloading = true
	manager.reload_token += 1
	local reload_token = manager.reload_token
	manager.trigger_held = false
	task.delay(gun_reload_controller.get_recoil_settle_time(manager), function()
		if not is_reload_active(manager, reload_token) then
			return
		end
		manager:stop_animation("Equip", manager.config.equip_fade_time or 0.05)
		manager:resume_idle(0)
		remotes.WeaponReload:FireServer(manager.gun_name)
		if reload_plan.style == "per_round" then
			begin_per_round_reload(manager, reload_token, reload_plan)
		else
			begin_magazine_reload(manager, reload_token, reload_plan)
		end
	end)
	return true
end

return gun_reload_controller

