local loadout_death_flow = {}

local CHARACTER_GUN_NAME = "EquippedCharacterGun"
local DEATH_FADE_IN_STEPS = 8
local RESPAWN_FADE_OUT_STEPS = 14
local DEATH_FADE_STEP_TIME = 0.03
local RESPAWN_FADE_STEP_TIME = 0.035

function loadout_death_flow.setup(ctx)
	local flow = {}
	local fade_token = 0

	local function set_death_fade(alpha)
		ctx.death_fade_alpha = math.clamp(alpha, 0, 1)
		if ctx.render then
			ctx.render()
		end
	end

	local function tween_death_fade(target_alpha, steps, step_time)
		fade_token += 1
		local token = fade_token
		local start_alpha = ctx.death_fade_alpha or 0
		for step = 1, steps do
			task.delay(step * step_time, function()
				if fade_token ~= token then
					return
				end
				local progress = step / steps
				set_death_fade(start_alpha + (target_alpha - start_alpha) * progress)
			end)
		end
	end

	local function open_respawn_menu()
		if ctx.ui_state_machine then
			ctx.ui_state_machine.set(ctx, "menu")
		end
		ctx.menu_unlocked_by_death = true
		ctx.menu_open = true
		ctx.menu_view = nil
		ctx.shop_open = false
		ctx.attachments_open = false
		ctx.respawn_menu_pending = false
		if ctx.sync_mouse then
			ctx.sync_mouse()
		end
		if ctx.render then
			ctx.render()
		end
	end

	local function hide_local_character_gun_part(instance)
		if instance:IsA("BasePart") then
			instance.LocalTransparencyModifier = 1
		end
	end

	local function is_local_character_gun_descendant(instance)
		local parent = instance
		while parent do
			if parent.Name == CHARACTER_GUN_NAME then
				return true
			end
			parent = parent.Parent
		end
		return false
	end

	function flow.hide_local_character_gun(character)
		local gun = character and character:FindFirstChild(CHARACTER_GUN_NAME)
		if not gun then
			return
		end
		hide_local_character_gun_part(gun)
		for _, descendant in gun:GetDescendants() do
			hide_local_character_gun_part(descendant)
		end
	end

	function flow.is_death_fade_blocking()
		return (ctx.death_fade_alpha or 0) > 0.02 or ctx.respawn_menu_pending == true
	end

	local function reset_active_weapon_on_death()
		ctx.firing = false
		if ctx.destroy_all_gun_managers then
			ctx.destroy_all_gun_managers()
		elseif ctx.active_gun then
			ctx.active_gun:set_aiming(false)
			ctx.active_gun.trigger_held = false
			ctx.active_gun.equipping = false
			ctx.active_gun.unequipping = false
			ctx.active_gun:unequip()
		end
		ctx.remotes.WeaponEquip:FireServer(ctx.active_gun_id or "", false)
		ctx.equipped = false
		ctx.active_slot = nil
		ctx.active_gun_id = nil
		ctx.active_gun = nil
		ctx.menu_view = nil
		ctx.shop_open = false
		ctx.attachments_open = false
		ctx.preview_attachment = nil
		ctx.menu_unlocked_by_death = true
	end

	local function show_menu_after_death()
		if ctx.set_menu_open then
			ctx.set_menu_open(true)
			return
		end
		if ctx.sync_mouse then
			ctx.sync_mouse()
		end
		if ctx.render then
			ctx.render()
		end
	end

	local function bind_character(character)
		flow.hide_local_character_gun(character)
		if ctx.has_spawned_once then
			open_respawn_menu()
			tween_death_fade(0, RESPAWN_FADE_OUT_STEPS, RESPAWN_FADE_STEP_TIME)
		else
			ctx.has_spawned_once = true
			if ctx.ui_state_machine then
				ctx.ui_state_machine.set(ctx, "menu")
			end
		end
		character.ChildAdded:Connect(function(child)
			if child.Name == CHARACTER_GUN_NAME then
				flow.hide_local_character_gun(character)
				task.defer(flow.hide_local_character_gun, character)
			end
		end)
		character.DescendantAdded:Connect(function(descendant)
			if is_local_character_gun_descendant(descendant) then
				hide_local_character_gun_part(descendant)
			end
		end)
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
		if humanoid then
			humanoid.Died:Connect(function()
				if ctx.ui_state_machine then
					ctx.ui_state_machine.set(ctx, "dying")
				end
				ctx.respawn_menu_pending = true
				tween_death_fade(1, DEATH_FADE_IN_STEPS, DEATH_FADE_STEP_TIME)
				reset_active_weapon_on_death()
				show_menu_after_death()
			end)
		end
	end

	if ctx.player.Character then
		bind_character(ctx.player.Character)
	end
	ctx.player.CharacterAdded:Connect(bind_character)

	return flow
end

return loadout_death_flow
