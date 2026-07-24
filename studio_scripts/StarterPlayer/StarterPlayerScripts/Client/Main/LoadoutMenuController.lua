local LoadoutMenuController = {}

local function render(ctx)
	if ctx.render then
		ctx.render()
	end
end

function LoadoutMenuController.setup(ctx)
	function ctx.set_selected_attachment_gun(gun_id)
		ctx.selected_attachment_gun_id = gun_id
		render(ctx)
	end

	function ctx.set_selected_attachment_type(attachment_type)
		ctx.selected_attachment_type = attachment_type
		render(ctx)
	end

	function ctx.set_attachment_preview(gun_id, attachment_type, attachment_name)
		ctx.preview_attachment = {
			gun_id = gun_id,
			type = attachment_type,
			name = attachment_name,
		}
		render(ctx)
	end

	function ctx.clear_attachment_preview(gun_id, attachment_type, attachment_name)
		local preview = ctx.preview_attachment
		if not preview then
			return
		end
		if gun_id and preview.gun_id ~= gun_id then
			return
		end
		if attachment_type and preview.type ~= attachment_type then
			return
		end
		if attachment_name and preview.name ~= attachment_name then
			return
		end
		ctx.preview_attachment = nil
		render(ctx)
	end

	function ctx.get_selected_attachment_gun()
		if ctx.selected_attachment_gun_id and ctx.selected_attachment_gun_id ~= "" then
			return ctx.selected_attachment_gun_id
		end
		if ctx.active_gun_id and ctx.active_gun_id ~= "" then
			return ctx.active_gun_id
		end
		local loadout = ctx.shop_state and ctx.shop_state.loadout
		if not loadout then
			return nil
		end
		return loadout[1] ~= "" and loadout[1] or loadout[2]
	end

	function ctx.set_weapon_attachment(gun_id, attachment_type, attachment_name)
		ctx.clear_attachment_preview(gun_id, attachment_type)
		if not gun_id or gun_id == "" then
			ctx.status_message = "Equip or select a gun first."
			render(ctx)
			return
		end

		ctx.weapon_attachments[gun_id] = ctx.weapon_attachments[gun_id] or {}
		local manager = ctx.managers[gun_id]
		local gun_model = manager and manager.gun_model or ctx.ReplicatedStorage.Guns:FindFirstChild(gun_id)
		if attachment_name and attachment_name ~= "" then
			if not ctx.attachment_modifier.can_attach(gun_model, attachment_name) then
				ctx.status_message = ctx.weapon_name(gun_id) .. " is missing the mount for " .. attachment_name .. "."
				render(ctx)
				return
			end
			if manager and not manager:set_attachment(attachment_type, attachment_name) then
				ctx.status_message = ctx.weapon_name(gun_id) .. " is missing the mount for " .. attachment_name .. "."
				render(ctx)
				return
			end
			ctx.weapon_attachments[gun_id][attachment_type] = attachment_name
			ctx.status_message = attachment_name .. " mounted on " .. ctx.weapon_name(gun_id) .. "."
		else
			ctx.weapon_attachments[gun_id][attachment_type] = nil
			if manager then
				manager:remove_attachment(attachment_type)
			end
			ctx.status_message = attachment_type .. " removed from " .. ctx.weapon_name(gun_id) .. "."
		end

		if ctx.request_state then
			ctx.request_state("SetAttachment", {
				gun_id = gun_id,
				attachment_type = attachment_type,
				attachment_name = attachment_name,
			})
		else
			render(ctx)
		end
	end

	local function stop_menu_blocked_actions()
		if ctx.unequip_grenade then
			ctx.unequip_grenade()
		end
		ctx.firing = false
		if ctx.active_gun then
			ctx.active_gun:set_aiming(false)
			ctx.active_gun.trigger_held = false
		end
	end

	function ctx.set_menu_open(value)
		local should_open = value == true
		if should_open and not ctx.menu_unlocked_by_death then
			return
		end
		if ctx.ui_state_machine then
			ctx.ui_state_machine.set(ctx, should_open and "menu" or "alive")
		end
		ctx.menu_open = should_open
		if ctx.menu_open then
			stop_menu_blocked_actions()
		else
			ctx.menu_unlocked_by_death = false
			ctx.menu_view = nil
			ctx.shop_open = false
			ctx.attachments_open = false
			ctx.clear_drag_ghost()
			ctx.dragging = nil
		end
		ctx.sync_mouse()
		render(ctx)
	end

	function ctx.open_menu_view(view)
		if not ctx.menu_unlocked_by_death then
			return
		end
		ctx.menu_open = true
		ctx.menu_view = view
		ctx.shop_open = view == "shop" or view == "inventory"
		ctx.attachments_open = view == "attachments"
		if ctx.attachments_open then
			ctx.selected_attachment_gun_id = ctx.get_selected_attachment_gun()
		end
		stop_menu_blocked_actions()
		ctx.sync_mouse()
		render(ctx)
	end

	function ctx.set_shop_open(value)
		if value == true then
			if ctx.menu_unlocked_by_death then
				ctx.open_menu_view("inventory")
			end
			return
		end
		ctx.menu_view = nil
		ctx.shop_open = false
		ctx.clear_drag_ghost()
		ctx.dragging = nil
		ctx.sync_mouse()
		render(ctx)
	end

	function ctx.set_attachments_open(value)
		if value == true then
			if ctx.menu_unlocked_by_death then
				ctx.open_menu_view("attachments")
			end
			return
		end
		ctx.menu_view = nil
		ctx.attachments_open = false
		ctx.preview_attachment = nil
		ctx.sync_mouse()
		render(ctx)
	end
end

return LoadoutMenuController

