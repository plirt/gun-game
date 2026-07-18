local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunAimController = require(ReplicatedStorage.Modules.Client.GunAimController)
local GunReloadController = require(ReplicatedStorage.Modules.Client.GunReloadController)

local input_actions = {}

function input_actions.gun_ready_for_actions(ctx)
	return not ctx.ragdolled and ctx.active_gun and (not ctx.active_gun.is_action_ready or ctx.active_gun:is_action_ready())
end

function input_actions.stop_firing(ctx)
	ctx.firing = false
	if ctx.active_gun then
		ctx.active_gun.trigger_held = false
	end
end

function input_actions.reload(ctx)
	if not ctx.active_gun then
		return
	end
	input_actions.stop_firing(ctx)
	if input_actions.gun_ready_for_actions(ctx) then
		GunReloadController.reload(ctx.active_gun)
	end
end

function input_actions.command_target(ctx)
	if input_actions.gun_ready_for_actions(ctx) then
		GunAimController.command_targeted_npc(ctx.active_gun)
	end
end

function input_actions.begin_fire(ctx)
	if ctx.pending_utility_slot then
		ctx.pending_utility_use = true
		return
	end
	if ctx.active_utility_id and ctx.use_active_utility then
		ctx.use_active_utility()
		return
	end
	if not input_actions.gun_ready_for_actions(ctx) then
		return
	end
	ctx.firing = true
	ctx.active_gun.trigger_held = true
	task.spawn(ctx.run_fire_loop)
end

function input_actions.end_fire(ctx)
	ctx.drop_drag()
	input_actions.stop_firing(ctx)
end

function input_actions.begin_aim(ctx)
	if input_actions.gun_ready_for_actions(ctx) then
		ctx.active_gun:set_aiming(true)
	end
end

function input_actions.end_aim(ctx)
	if ctx.active_gun then
		ctx.active_gun:set_aiming(false)
	end
end

function input_actions.weapon_input_allowed(ctx)
	if ctx.ui_state_machine and not ctx.ui_state_machine.can_accept_weapon_input(ctx) then
		return false
	end
	return not ctx.ragdolled and not ctx.menu_open and not ctx.shop_open and not ctx.attachments_open
end

return input_actions
