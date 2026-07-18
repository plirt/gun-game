local ragdoll_controller = {}

local function clear_held_items(ctx)
	ctx.firing = false
	ctx.pending_utility_slot = nil
	ctx.pending_utility_use = false
	ctx.grenade_throw_pending = false
	if ctx.unequip_grenade then
		ctx.unequip_grenade()
	end
	if ctx.active_gun then
		ctx.active_gun:set_aiming(false)
		ctx.active_gun.trigger_held = false
		ctx.active_gun:unequip()
		ctx.remotes.WeaponEquip:FireServer(ctx.active_gun_id or "", false)
	end
	ctx.equipped = false
	ctx.active_slot = nil
	ctx.active_gun_id = nil
	ctx.active_gun = nil
	ctx.active_utility_id = nil
	ctx.sync_mouse()
	if ctx.render then
		ctx.render()
	end
end

local function set_ragdolled(ctx, value)
	ctx.ragdolled = value == true
	if ctx.ragdolled then
		clear_held_items(ctx)
	elseif ctx.render then
		ctx.render()
	end
end

function ragdoll_controller.setup(ctx)
	ctx.ragdolled = ctx.player:GetAttribute("ragdolled") == true
	ctx.player:GetAttributeChangedSignal("ragdolled"):Connect(function()
		set_ragdolled(ctx, ctx.player:GetAttribute("ragdolled") == true)
	end)
	ctx.remotes:WaitForChild("RagdollState").OnClientEvent:Connect(function(ragdolled)
		set_ragdolled(ctx, ragdolled == true)
	end)
	ctx.player.CharacterAdded:Connect(function()
		set_ragdolled(ctx, false)
	end)
end

return ragdoll_controller
