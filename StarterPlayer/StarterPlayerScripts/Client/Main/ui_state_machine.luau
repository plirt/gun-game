local ui_state_machine = {}

export type UiFlowState = "first_join" | "menu" | "spawning" | "alive" | "dying" | "dead"

local allowed: { [UiFlowState]: { [UiFlowState]: boolean } } = {
	first_join = { menu = true, spawning = true },
	menu = { spawning = true, dying = true },
	spawning = { alive = true, menu = true, dying = true },
	alive = { dying = true, menu = true },
	dying = { dead = true, menu = true },
	dead = { menu = true, spawning = true },
}

function ui_state_machine.set(ctx, next_state: UiFlowState): boolean
	local current_state = ctx.ui_flow_state or "first_join"
	if current_state == next_state then
		return true
	end
	if not allowed[current_state] or not allowed[current_state][next_state] then
		return false
	end
	ctx.ui_flow_state = next_state
	ctx.menu_open = next_state == "first_join" or next_state == "menu" or next_state == "dead"
	ctx.menu_unlocked_by_death = next_state == "dead" or next_state == "menu"
	ctx.respawn_menu_pending = next_state == "dead"
	return true
end

function ui_state_machine.can_accept_weapon_input(ctx): boolean
	return ctx.ui_flow_state == "alive" and not ctx.menu_open and not ctx.shop_open and not ctx.attachments_open
end

return ui_state_machine
