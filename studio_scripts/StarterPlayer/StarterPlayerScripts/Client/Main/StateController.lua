local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GunStateMachine = require(ReplicatedStorage.Modules.Client.GunStateMachine)

local state_controller = {}

function state_controller.setup(ctx)
	function ctx.catalog()
		local by_id = {}
		if ctx.shop_state then
			for _, weapon in ctx.shop_state.catalog or {} do
				by_id[weapon.id] = weapon
			end
		end
		return by_id
	end

	function ctx.weapon_data(gun_id)
		return ctx.catalog()[gun_id] or { id = gun_id, display_name = gun_id, width = 1, height = 1, price = 0, rarity = "" }
	end

	function ctx.weapon_name(gun_id)
		return gun_id and gun_id ~= "" and ctx.weapon_data(gun_id).display_name or "Empty"
	end

	function ctx.backpack_map()
		local map = {}
		if ctx.shop_state then
			for _, item in ctx.shop_state.backpack or {} do
				map[item.gun_id] = item
			end
		end
		return map
	end

	function ctx.owns(gun_id)
		if not ctx.shop_state then
			return false
		end
		for _, owned_id in ctx.shop_state.inventory or {} do
			if owned_id == gun_id then
				return true
			end
		end
		return false
	end

	function ctx.is_packed(gun_id)
		return ctx.backpack_map()[gun_id] ~= nil
	end

	function ctx.server_now()
		return ctx.shop_state and ((ctx.shop_state.server_time or os.time()) + (os.time() - ctx.state_received_at)) or os.time()
	end

	function ctx.format_time(seconds)
		seconds = math.max(0, math.floor(seconds))
		return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
	end

	function ctx.grid_pixel_size(cells)
		return cells * ctx.CELL_SIZE + math.max(cells - 1, 0) * ctx.CELL_GAP
	end

	function ctx.request_state(action, payload)
		local ok, result = pcall(function()
			return ctx.remotes.ShopRequest:InvokeServer(action or "GetState", payload or {})
		end)
		if ok and type(result) == "table" then
			ctx.shop_state = result
			ctx.weapon_attachments = type(result.attachments) == "table" and result.attachments or ctx.weapon_attachments
			ctx.GRID_COLUMNS = result.backpack_columns or ctx.GRID_COLUMNS
			ctx.GRID_ROWS = result.backpack_rows or ctx.GRID_ROWS
			ctx.state_received_at = os.time()
			if result.message and result.message ~= "" then
				ctx.status_message = result.message
			end
		else
			ctx.status_message = "Shop unavailable."
		end
		if not ctx.auto_equipped and not ctx.menu_open and ctx.equip_slot then
			ctx.auto_equipped = true
			task.defer(function()
				ctx.equip_slot(ctx.active_slot or 1, true)
			end)
		end
		if ctx.render then
			ctx.render()
		end
	end
end

function state_controller.start(ctx)
	local weapon_state_remote = ctx.remotes:WaitForChild("WeaponState")
	weapon_state_remote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.gun_name) ~= "string" then
			return
		end
		local manager = ctx.managers[payload.gun_name]
		if not manager or manager.destroyed then
			return
		end
		local sequence = payload.sequence
		if type(sequence) ~= "number" or sequence <= (manager.last_server_weapon_sequence or 0) then
			return
		end
		manager.last_server_weapon_sequence = sequence
		if type(payload.magazine) == "number" then
			manager.magazine = math.max(0, math.floor(payload.magazine))
		end
		if type(payload.reserve) == "number" then
			manager.reserve = math.max(0, math.floor(payload.reserve))
		end
		if payload.reloading ~= true and manager.reloading then
			manager.reload_token += 1
			manager.reloading = false
			GunStateMachine.set(manager, "idle")
		end
	end)


	ctx.remotes.ShopUpdated.OnClientEvent:Connect(function(reason, value, authoritative_cash)
		if type(authoritative_cash) == "number" and ctx.shop_state then
			ctx.shop_state.cash = math.max(0, math.floor(authoritative_cash))
			if ctx.render then
				ctx.render()
			end
			return
		end
		if (reason == "KillReward" or reason == "NpcKillReward")
			and type(value) == "number"
			and ctx.shop_state
		then
			ctx.shop_state.cash = math.max(0, math.floor((ctx.shop_state.cash or 0) + value))
			if ctx.render then
				ctx.render()
			end
			return
		end
		if reason == "RotationChanged" then
			local refresh_delay = (ctx.player.UserId % 10) * 0.1
			task.delay(refresh_delay, ctx.request_state, "GetState")
			return
		end
		ctx.request_state("GetState")
	end)

	task.spawn(function()
		ctx.request_state("GetState")
		while true do
			task.wait(1)
			if ctx.shop_state then
				local remaining = (ctx.shop_state.rotation_ends_at or os.time()) - ctx.server_now()
				if remaining <= 0 then
					ctx.request_state("GetState")
				elseif ctx.render and not ctx.dragging then
					ctx.render()
				end
			end
		end
	end)
end
return state_controller

