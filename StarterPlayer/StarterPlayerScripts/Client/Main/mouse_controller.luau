local mouse_controller = {}

function mouse_controller.setup(ctx)
	local function desired_mouse_state()
		if ctx.menu_open or ctx.shop_open or ctx.attachments_open or ctx.mouse_unlocked then
			return Enum.MouseBehavior.Default, true
		elseif ctx.equipped or ctx.active_utility_id then
			return Enum.MouseBehavior.LockCenter, false
		end
		return ctx.default_mouse_behavior, ctx.default_mouse_icon_enabled
	end

	function ctx.sync_mouse()
		local behavior, icon_enabled = desired_mouse_state()
		if ctx.UserInputService.MouseBehavior ~= behavior then
			ctx.UserInputService.MouseBehavior = behavior
		end
		if ctx.UserInputService.MouseIconEnabled ~= icon_enabled then
			ctx.UserInputService.MouseIconEnabled = icon_enabled
		end
	end

	function ctx.set_mouse_unlocked(value)
		ctx.mouse_unlocked = value == true
		ctx.sync_mouse()
		if ctx.render then
			ctx.render()
		end
	end

	ctx.RunService.RenderStepped:Connect(function()
		if ctx.menu_open or ctx.shop_open or ctx.attachments_open or ctx.mouse_unlocked or ctx.equipped or ctx.active_utility_id then
			ctx.sync_mouse()
		end
	end)
end
return mouse_controller
