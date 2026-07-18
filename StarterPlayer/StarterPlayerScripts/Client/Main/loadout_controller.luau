local ReplicatedStorage = game:GetService("ReplicatedStorage")

local loadout_slots = require(ReplicatedStorage.Modules.Shared.LoadoutSlots)
local GunFireController = require(ReplicatedStorage.Modules.Client.GunFireController)
local loadout_death_flow = require(script.Parent.loadout_death_flow)

local loadout_controller = {}

function loadout_controller.setup(ctx)
	local death_flow = loadout_death_flow.setup(ctx)

	local function report_weapon_equipped(gun_id, equipped)
		ctx.remotes.WeaponEquip:FireServer(gun_id or "", equipped == true)
		if equipped and ctx.player.Character then
			task.defer(death_flow.hide_local_character_gun, ctx.player.Character)
		end
	end

	local function get_manager(gun_id)
		local cached_manager = ctx.managers[gun_id]
		if cached_manager then
			if cached_manager.destroyed or not cached_manager.viewmodel or cached_manager.viewmodel:GetAttribute("destroyed") == true then
				ctx.managers[gun_id] = nil
			else
				return cached_manager
			end
		end
		local ok, manager = pcall(function()
			return ctx.gun_manager.new(gun_id, ctx.weapon_attachments[gun_id], {
				movement_state = ctx.movement_state,
			})
		end)
		if not ok then
			ctx.status_message = "Could not equip " .. tostring(gun_id) .. "."
			return nil
		end
		ctx.managers[gun_id] = manager
		return manager
	end

	function ctx.cleanup_camera_viewmodels(keep_viewmodel)
		if ctx.gun_manager.cleanup_camera_viewmodels then
			ctx.gun_manager.cleanup_camera_viewmodels(keep_viewmodel)
		end
	end

	function ctx.destroy_all_gun_managers()
		if ctx.unequip_grenade then
			ctx.unequip_grenade()
		end
		ctx.weapon_swap_token += 1
		ctx.equip_request_token += 1
		for gun_id, manager in ctx.managers do
			pcall(function()
				manager:destroy()
			end)
			ctx.managers[gun_id] = nil
		end
		ctx.cleanup_camera_viewmodels()
	end

	function ctx.set_selected_attachment_gun(gun_id)
		ctx.selected_attachment_gun_id = gun_id
		if ctx.render then
			ctx.render()
		end
	end

	function ctx.set_selected_attachment_type(attachment_type)
		ctx.selected_attachment_type = attachment_type
		if ctx.render then
			ctx.render()
		end
	end

	function ctx.set_attachment_preview(gun_id, attachment_type, attachment_name)
		ctx.preview_attachment = {
			gun_id = gun_id,
			type = attachment_type,
			name = attachment_name,
		}
		if ctx.render then
			ctx.render()
		end
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
		if ctx.render then
			ctx.render()
		end
	end

	function ctx.get_selected_attachment_gun()
		if ctx.selected_attachment_gun_id and ctx.selected_attachment_gun_id ~= "" then
			return ctx.selected_attachment_gun_id
		end
		if ctx.active_gun_id and ctx.active_gun_id ~= "" then
			return ctx.active_gun_id
		end
		return ctx.shop_state and ctx.shop_state.loadout and (ctx.shop_state.loadout[1] ~= "" and ctx.shop_state.loadout[1] or ctx.shop_state.loadout[2]) or nil
	end

	function ctx.set_weapon_attachment(gun_id, attachment_type, attachment_name)
		ctx.clear_attachment_preview(gun_id, attachment_type)
		if not gun_id or gun_id == "" then
			ctx.status_message = "Equip or select a gun first."
			if ctx.render then
				ctx.render()
			end
			return
		end

		ctx.weapon_attachments[gun_id] = ctx.weapon_attachments[gun_id] or {}
		local manager = ctx.managers[gun_id]
		local gun_model = manager and manager.gun_model or ctx.ReplicatedStorage.Guns:FindFirstChild(gun_id)

		local should_save_attachment = false

		if attachment_name and attachment_name ~= "" then
			if not ctx.attachment_modifier.can_attach(gun_model, attachment_name) then
				ctx.status_message = ctx.weapon_name(gun_id) .. " is missing the mount for " .. attachment_name .. "."
				if ctx.render then
					ctx.render()
				end
				return
			end
			if manager and not manager:set_attachment(attachment_type, attachment_name) then
				ctx.status_message = ctx.weapon_name(gun_id) .. " is missing the mount for " .. attachment_name .. "."
				if ctx.render then
					ctx.render()
				end
				return
			end
			ctx.weapon_attachments[gun_id][attachment_type] = attachment_name
			should_save_attachment = true
			ctx.status_message = attachment_name .. " mounted on " .. ctx.weapon_name(gun_id) .. "."
		else
			ctx.weapon_attachments[gun_id][attachment_type] = nil
			should_save_attachment = true
			if manager then
				manager:remove_attachment(attachment_type)
			end
			ctx.status_message = attachment_type .. " removed from " .. ctx.weapon_name(gun_id) .. "."
		end

		if should_save_attachment and ctx.request_state then
			ctx.request_state("SetAttachment", {
				gun_id = gun_id,
				attachment_type = attachment_type,
				attachment_name = attachment_name,
			})
		elseif ctx.render then
			ctx.render()
		end
	end

	function ctx.unequip_current()
		if ctx.active_utility_id and ctx.unequip_grenade then
			ctx.unequip_grenade()
			return
		end
		ctx.weapon_swap_token += 1
		ctx.equip_request_token += 1
		if ctx.active_gun and ctx.active_gun.equipping then
			return
		end
		ctx.firing = false
		if ctx.active_gun then
			ctx.active_gun:set_aiming(false)
			ctx.active_gun.trigger_held = false
			if ctx.active_gun:unequip() == false then
				return
			end
		end
		report_weapon_equipped(ctx.active_gun_id, false)
		ctx.equipped = false
		ctx.active_slot = nil
		ctx.active_gun_id = nil
		ctx.active_gun = nil
		ctx.sync_mouse()
		if ctx.render then
			ctx.render()
		end
	end

	ctx.weapon_swap_token = 0
	ctx.equip_request_token = 0

	local function get_unequip_delay(manager)
		if not manager then
			return 0
		end
		local config = manager.config or {}
		return math.max(config.weapon_swap_delay or config.unequip_time or 0.38, 0.05)
	end

	function ctx.can_start_match()
		local character = ctx.player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return not ctx.ragdolled and not death_flow.is_death_fade_blocking() and humanoid ~= nil and humanoid.Health > 0
	end

	function ctx.equip_slot(slot, force)
		if ctx.ragdolled then
			ctx.status_message = "Cannot equip while ragdolled."
			if ctx.render then
				ctx.render()
			end
			return false
		end
		ctx.equip_request_token += 1
		local equip_request_token = ctx.equip_request_token
		if not ctx.shop_state then
			return false
		end
		local slot_info = loadout_slots.get(slot)
		if not slot_info then
			return false
		end
		if slot_info.category == "utility" then
			local utility_id = ctx.shop_state.loadout and ctx.shop_state.loadout[slot]
			if not utility_id or utility_id == "" then
				ctx.status_message = "Utility slot is empty."
				if ctx.render then
					ctx.render()
				end
				return false
			end
			if not ctx.can_start_match() or ctx.menu_open and not force then
				return false
			end
			ctx.pending_utility_slot = slot
			if ctx.active_gun then
				local swapping_from_gun = ctx.active_gun
				if swapping_from_gun.equipping then
					task.spawn(function()
						while ctx.active_gun == swapping_from_gun and swapping_from_gun.equipping and ctx.pending_utility_slot == slot do
							ctx.RunService.Heartbeat:Wait()
						end
						if ctx.active_gun == swapping_from_gun and ctx.pending_utility_slot == slot then
							ctx.equip_slot(slot, true)
						end
					end)
					return false
				end
				ctx.unequip_current()
				if ctx.active_gun then
					ctx.pending_utility_slot = nil
					ctx.pending_utility_use = false
					return false
				end
				local swap_token = ctx.weapon_swap_token
				task.delay(get_unequip_delay(swapping_from_gun), function()
					if ctx.weapon_swap_token == swap_token and ctx.pending_utility_slot == slot then
						ctx.equip_slot(slot, true)
					end
				end)
				return false
			end
			if utility_id == "GRENADE" and ctx.equip_grenade then
				return ctx.equip_grenade(slot)
			end
			return false
		elseif slot_info.category ~= "firearm" then
			ctx.pending_utility_slot = nil
			ctx.pending_utility_use = false
			ctx.status_message = slot_info.display_name .. " items are not available yet."
			if ctx.render then
				ctx.render()
			end
			return false
		end
		ctx.pending_utility_slot = nil
		ctx.pending_utility_use = false
		if ctx.active_utility_id and ctx.unequip_grenade then
			ctx.unequip_grenade()
		end
		if not ctx.can_start_match() then
			ctx.status_message = ctx.ragdolled and "Cannot equip while ragdolled." or "Wait for respawn before equipping."
			if ctx.render then
				ctx.render()
			end
			return false
		end
		if ctx.menu_open and not force then
			ctx.status_message = "Press START before equipping a weapon."
			if ctx.render then
				ctx.render()
			end
			return false
		end
		if ctx.loadout_busy and not force then
			return false
		end
		if not force then
			ctx.loadout_busy = true
		end

		local function release_loadout_busy()
			if not force then
				ctx.loadout_busy = false
			end
		end
		if not force then
			for _, manager in ctx.managers do
				if manager.equipping or manager.unequipping then
					release_loadout_busy()
					return false
				end
			end
		end
		local gun_id = ctx.shop_state.loadout and ctx.shop_state.loadout[slot]
		if not gun_id or gun_id == "" then
			ctx.status_message = "Slot " .. tostring(slot) .. " is empty."
			if ctx.render then
				ctx.render()
			end
			release_loadout_busy()
			return false
		end
		if ctx.active_gun and ctx.active_gun.equipping and not force then
			release_loadout_busy()
			return false
		end
		if ctx.equipped and ctx.active_slot == slot and ctx.active_gun_id == gun_id then
			release_loadout_busy()
			return true
		end
		local swapping_from_gun = ctx.active_gun
		local swapping_from_slot = ctx.active_slot
		local swapping_to_different_slot = swapping_from_gun and swapping_from_slot ~= slot
		if swapping_to_different_slot then
			ctx.weapon_swap_token += 1
			local swap_token = ctx.weapon_swap_token
			swapping_from_gun:set_aiming(false)
			swapping_from_gun.trigger_held = false
			if swapping_from_gun:unequip() == false then
				release_loadout_busy()
				return false
			end
			ctx.firing = false
			report_weapon_equipped(ctx.active_gun_id, false)
			ctx.managers[ctx.active_gun_id] = nil
			ctx.equipped = false
			ctx.active_slot = nil
			ctx.active_gun_id = nil
			ctx.active_gun = nil
			ctx.sync_mouse()
			if ctx.render then
				ctx.render()
			end
			task.delay(get_unequip_delay(swapping_from_gun), function()
				if ctx.weapon_swap_token == swap_token then
					ctx.equip_slot(slot, true)
				end
			end)
			release_loadout_busy()
			return false
		elseif ctx.active_gun then
			ctx.active_gun:set_aiming(false)
			ctx.active_gun:unequip()
			report_weapon_equipped(ctx.active_gun_id, false)
			ctx.managers[ctx.active_gun_id] = nil
		end
		local manager = get_manager(gun_id)
		if not manager then
			release_loadout_busy()
			return false
		end
		if ctx.equip_request_token ~= equip_request_token then
			release_loadout_busy()
			return false
		end
		ctx.active_slot = slot
		ctx.active_gun_id = gun_id
		ctx.active_gun = manager
		ctx.equipped = true
		ctx.cleanup_camera_viewmodels(manager.viewmodel)
		if manager:equip() == false then
			ctx.equipped = false
			ctx.active_slot = nil
			ctx.active_gun_id = nil
			ctx.active_gun = nil
			release_loadout_busy()
			return false
		end
		report_weapon_equipped(gun_id, true)
		ctx.sync_mouse()
		if ctx.render then
			ctx.render()
		end
		release_loadout_busy()
		return true
	end

	function ctx.start_match()
		if not ctx.can_start_match() then
			ctx.status_message = ctx.ragdolled and "Cannot start while ragdolled." or "Wait for respawn before starting."
			if ctx.render then
				ctx.render()
			end
			return false
		end
		if ctx.ui_state_machine then
			ctx.ui_state_machine.set(ctx, "spawning")
		end
		if not ctx.equipped and not ctx.equip_slot(ctx.active_slot or 1, true) then
			if ctx.ui_state_machine then
				ctx.ui_state_machine.set(ctx, "menu")
			end
			return false
		end
		local ok = pcall(function()
			ctx.remotes.MissionStart:InvokeServer("Default")
		end)
		if not ok then
			if ctx.ui_state_machine then
				ctx.ui_state_machine.set(ctx, "menu")
			end
			ctx.status_message = "Spawn failed. Try again."
			if ctx.render then
				ctx.render()
			end
			return false
		end
		ctx.set_menu_open(false)
		if ctx.ui_state_machine then
			ctx.ui_state_machine.set(ctx, "alive")
		end
		return true
	end

	function ctx.refresh_active_weapon()
		if not ctx.equipped or not ctx.active_slot or not ctx.shop_state then
			return
		end
		local gun_id = ctx.shop_state.loadout and ctx.shop_state.loadout[ctx.active_slot]
		if gun_id ~= ctx.active_gun_id then
			if not gun_id or gun_id == "" then
				ctx.unequip_current()
			else
				ctx.equip_slot(ctx.active_slot, true)
			end
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
		if ctx.render then
			ctx.render()
		end
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
		if ctx.render then
			ctx.render()
		end
	end

	function ctx.set_shop_open(value)
		if value == true then
			if ctx.menu_unlocked_by_death then
				ctx.open_menu_view("inventory")
			end
		else
			ctx.menu_view = nil
			ctx.shop_open = false
			ctx.clear_drag_ghost()
			ctx.dragging = nil
			ctx.sync_mouse()
			if ctx.render then
				ctx.render()
			end
		end
	end

	function ctx.set_attachments_open(value)
		if value == true then
			if ctx.menu_unlocked_by_death then
				ctx.open_menu_view("attachments")
			end
		else
			ctx.menu_view = nil
			ctx.attachments_open = false
			ctx.preview_attachment = nil
			ctx.sync_mouse()
			if ctx.render then
				ctx.render()
			end
		end
	end

	function ctx.run_fire_loop()
		if ctx.fire_loop_running then
			return
		end
		ctx.fire_loop_running = true
		while ctx.firing and ctx.equipped and ctx.active_gun and not ctx.ragdolled do
			GunFireController.fire(ctx.active_gun)
			task.wait()
		end
		ctx.fire_loop_running = false
	end
end
return loadout_controller
