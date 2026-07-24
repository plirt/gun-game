local hvt_controller = {}

local UPDATE_INTERVAL = 0.2

local function find_player_by_user_id(players, user_id)
	for _, player in players:GetPlayers() do
		if player.UserId == user_id then
			return player
		end
	end
	return nil
end

local function get_estimated_server_time(payload)
	if type(payload) ~= "table" then
		return 0
	end
	local elapsed = math.max(0, os.clock() - (payload.received_at or os.clock()))
	return (payload.server_time or 0) + elapsed
end

function hvt_controller.setup(ctx)
	local active_bounty = nil
	local target_player = nil
	local character_connection = nil
	local highlight = nil
	local billboard = nil
	local label = nil

	local function destroy_visuals()
		if highlight then
			highlight:Destroy()
			highlight = nil
		end
		if billboard then
			billboard:Destroy()
			billboard = nil
		end
		label = nil
	end

	local function clear_target()
		destroy_visuals()
		if character_connection then
			character_connection:Disconnect()
			character_connection = nil
		end
		target_player = nil
		active_bounty = nil
	end

	local function update_text()
		if not label or not active_bounty then
			return
		end
		local remaining = math.max(
			0,
			(active_bounty.expires_at or 0) - get_estimated_server_time(ctx.match_payload)
		)
		local reward = math.max(0, math.floor(active_bounty.reward or 0))
		local prefix = target_player == ctx.player and "YOU ARE HVT" or "HVT TARGET"
		label.Text = string.format("%s  //  $%d  //  %ds", prefix, reward, math.ceil(remaining))
	end

	local function build_visuals(character)
		destroy_visuals()
		if not active_bounty or not target_player or target_player.Character ~= character then
			return
		end
		local focus = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
		if not focus or not focus:IsA("BasePart") then
			task.delay(0.2, function()
				if target_player and target_player.Character == character then
					build_visuals(character)
				end
			end)
			return
		end

		local is_local_target = target_player == ctx.player
		local accent = is_local_target
			and Color3.fromRGB(255, 75, 45)
			or Color3.fromRGB(255, 190, 45)

		highlight = Instance.new("Highlight")
		highlight.Name = "HvtHighlight"
		highlight.Adornee = character
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillColor = accent
		highlight.FillTransparency = 0.82
		highlight.OutlineColor = accent
		highlight.OutlineTransparency = 0.05
		highlight.Parent = character

		billboard = Instance.new("BillboardGui")
		billboard.Name = "HvtBillboard"
		billboard.Adornee = focus
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.MaxDistance = 500
		billboard.Size = UDim2.fromOffset(240, 42)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
		billboard.Parent = focus

		label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		label.BackgroundTransparency = 0.18
		label.BorderColor3 = accent
		label.BorderSizePixel = 2
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = accent
		label.TextSize = 14
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = 0.15
		label.Size = UDim2.fromScale(1, 1)
		label.Parent = billboard
		update_text()
	end

	local function bind_target(player)
		if target_player == player then
			if player.Character and (not billboard or not billboard.Parent) then
				build_visuals(player.Character)
			end
			return
		end
		if character_connection then
			character_connection:Disconnect()
			character_connection = nil
		end
		destroy_visuals()
		target_player = player
		character_connection = player.CharacterAdded:Connect(function(character)
			task.defer(build_visuals, character)
		end)
		if player.Character then
			build_visuals(player.Character)
		end
	end

	ctx.update_hvt_marker = function(bounty)
		if type(bounty) ~= "table" or type(bounty.target_user_id) ~= "number" then
			clear_target()
			return
		end
		local player = find_player_by_user_id(ctx.Players, bounty.target_user_id)
		if not player then
			clear_target()
			return
		end
		active_bounty = bounty
		bind_target(player)
		update_text()
	end

	task.spawn(function()
		while true do
			task.wait(UPDATE_INTERVAL)
			if active_bounty then
				update_text()
			end
		end
	end)
end

return hvt_controller
