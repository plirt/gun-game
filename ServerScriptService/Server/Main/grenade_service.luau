local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player_state = require(script.Parent.player_state)

local grenade_service = {}

local utility_item_id = "GRENADE"
local utility_slot = 3
local replenish_seconds = 1.5
local ready_attribute = "grenade_ready_at"
local fuse_seconds = 3
local throw_speed = 78
local throw_lift = 12
local spawn_distance = 2.4
local explosion_radius = 20
local maximum_damage = 90
local minimum_damage = 18
local self_damage_multiplier = 0.65
local explosion_origin_lift = 0.45
local target_sample_lift = 0.65
local ragdoll_duration = 1.8
local minimum_knockback = 0.55
local maximum_knockback = 1.65
local shake_radius = 90
local explosion_light_duration = 0.14

local held_grenades = setmetatable({}, { __mode = "k" })
local last_equip_requests = setmetatable({}, { __mode = "k" })
local last_throw_requests = setmetatable({}, { __mode = "k" })
local EQUIP_REQUEST_INTERVAL = 0.1
local THROW_REQUEST_INTERVAL = 0.08

local function consume_request_budget(bucket, player, interval)
	local now = os.clock()
	if now - (bucket[player] or 0) < interval then
		return false
	end
	bucket[player] = now
	return true
end

local function get_or_create_remote(ctx, name)
	local remote = ctx.remotes:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ctx.remotes
	return remote
end

local function get_or_create_active_folder()
	local folder = workspace:FindFirstChild("ActiveGrenades")
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = "ActiveGrenades"
	folder.Parent = workspace
	return folder
end

local function get_template()
	local utility_items = ReplicatedStorage:FindFirstChild("UtilityItems")
	local template = utility_items and utility_items:FindFirstChild("Grenade")
	return template and template:IsA("Model") and template or nil
end

local function remove_held_grenade(player)
	local held = held_grenades[player]
	if held and held.Parent then
		held:Destroy()
	end
	held_grenades[player] = nil
end

local function equip_held_grenade(player)
	remove_held_grenade(player)
	local template = get_template()
	local character = player.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not template or not character or not hand or not hand:IsA("BasePart") then
		return false
	end
	local held = template:Clone()
	held.Name = "HeldGrenade"
	local main = held:FindFirstChild("Grenade")
	if not main or not main:IsA("BasePart") then
		held:Destroy()
		return false
	end
	held.PrimaryPart = main
	for _, descendant in held:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
	held.Parent = character
	held:PivotTo(hand.CFrame * CFrame.new(0, -0.8, -0.15) * CFrame.Angles(0, 0, math.rad(90)))
	local motor = Instance.new("Motor6D")
	motor.Name = "GrenadeGrip"
	motor.Part0 = hand
	motor.Part1 = main
	motor.C0 = CFrame.new(0, -0.8, -0.15) * CFrame.Angles(0, 0, math.rad(90))
	motor.Parent = hand
	held_grenades[player] = held
	return true
end

local function get_character_parts(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return character, humanoid, head and head:IsA("BasePart") and head or root, root
end

local function validate_direction(direction)
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.95 or direction.Magnitude > 1.05 then
		return nil
	end
	return direction.Unit
end

local function get_spawn_position(character, origin_part, direction)
	local offset = direction * spawn_distance
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	local result = workspace:Raycast(origin_part.Position, offset, params)
	if result then
		return origin_part.Position + direction * math.max(result.Distance - 0.35, 0)
	end
	return origin_part.Position + offset
end

local function prepare_grenade(template, position, direction)
	local grenade = template:Clone()
	local main = grenade:FindFirstChild("Grenade")
	if not main or not main:IsA("BasePart") then
		grenade:Destroy()
		return nil
	end
	grenade.PrimaryPart = main
	for _, descendant in grenade:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanTouch = false
			descendant.CanQuery = true
			descendant.CanCollide = descendant == main
			descendant.Massless = descendant ~= main
		end
	end
	grenade:PivotTo(CFrame.lookAt(position, position + direction))
	grenade.Parent = get_or_create_active_folder()
	main:SetNetworkOwner(nil)
	main.AssemblyLinearVelocity = direction * throw_speed + Vector3.new(0, throw_lift, 0)
	main.AssemblyAngularVelocity = Vector3.new(8, 11, 6)
	return grenade
end

local function get_target_models(ctx)
	local targets = {}
	for _, player in ctx.Players:GetPlayers() do
		if player.Character then
			table.insert(targets, {
				entity = player,
				model = player.Character,
			})
		end
	end
	local npcs = workspace:FindFirstChild("Npcs")
	if npcs then
		for _, npc in npcs:GetChildren() do
			if npc:IsA("Model") then
				table.insert(targets, {
					entity = npc,
					model = npc,
				})
			end
		end
	end
	return targets
end

local function has_explosion_line_of_sight(position, target_model, target_part, grenade, attacker_character)
	local origin = position + Vector3.new(0, explosion_origin_lift, 0)
	local target_position = target_part.Position + Vector3.new(0, target_sample_lift, 0)
	local offset = target_position - origin
	if offset.Magnitude <= 0.1 then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { grenade, attacker_character }
	params.IgnoreWater = true
	local result = workspace:Raycast(origin, offset, params)
	return not result or result.Instance:IsDescendantOf(target_model)
end

local function apply_explosion_damage(ctx, attacker, grenade, position)
	local attacker_character = attacker.Character
	for _, target in get_target_models(ctx) do
		local humanoid = target.model:FindFirstChildWhichIsA("Humanoid")
		local root = target.model:FindFirstChild("HumanoidRootPart") or target.model:FindFirstChild("Head")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
			continue
		end
		local distance = (root.Position - position).Magnitude
		if distance > explosion_radius then
			continue
		end
		local is_self_damage = target.entity == attacker
		if not is_self_damage and ctx.match_service and not ctx.match_service.can_damage(ctx, attacker, target.entity) then
			continue
		end
		if not has_explosion_line_of_sight(position, target.model, root, grenade, attacker_character) then
			continue
		end
		local alpha = 1 - math.clamp(distance / explosion_radius, 0, 1)
		local damage = minimum_damage + (maximum_damage - minimum_damage) * alpha
		if is_self_damage then
			damage *= self_damage_multiplier
		end
		local hit_direction = root.Position - position
		hit_direction = hit_direction.Magnitude > 0.01 and hit_direction.Unit or Vector3.yAxis
		ctx.npc_hit_data[target.model] = {
			origin = position,
			position = root.Position,
			direction = hit_direction,
		}
		local lethal = humanoid.Health <= damage
		if ctx.ragdoll_service then
			local duration = lethal and nil or ragdoll_duration
			local knockback = minimum_knockback + (maximum_knockback - minimum_knockback) * alpha
			ctx.ragdoll_service.apply(ctx, target.model, position, hit_direction, root.Position, duration, knockback)
		end
		if ctx.match_service then
			ctx.match_service.record_damage(ctx, attacker, humanoid)
		end
		humanoid:TakeDamage(damage)
		if ctx.match_service and humanoid.Health <= 0 then
			ctx.match_service.record_death(ctx, humanoid)
		end
	end
end

local function emit_explosion_effects(position, grenade)
	local holder = Instance.new("Part")
	holder.Name = "GrenadeExplosion"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Position = position
	holder.Parent = workspace
	local source_sound = grenade:FindFirstChild("Explosion", true)
	if source_sound and source_sound:IsA("Sound") then
		local sound = source_sound:Clone()
		sound.Parent = holder
		sound:Play()
	end
	local vfx_folder = ReplicatedStorage:FindFirstChild("VFX")
	local template = vfx_folder and vfx_folder:FindFirstChild("Explosion")
	if template and template:IsA("Attachment") then
		local attachment = template:Clone()
		attachment.Parent = holder
		for _, descendant in attachment:GetDescendants() do
			if descendant:IsA("ParticleEmitter") then
				local emit_count = descendant:GetAttribute("EmitCount")
				local emit_delay = descendant:GetAttribute("EmitDelay")
				task.delay(type(emit_delay) == "number" and emit_delay or 0, function()
					if descendant.Parent then
						descendant:Emit(type(emit_count) == "number" and math.max(1, math.floor(emit_count)) or 5)
					end
				end)
			elseif descendant:IsA("Light") then
				descendant.Enabled = true
				task.delay(explosion_light_duration, function()
					if descendant.Parent then
						descendant.Enabled = false
					end
				end)
			end
		end
	end
	Debris:AddItem(holder, 8)
end

local function detonate(ctx, remote, attacker, grenade)
	if not grenade.Parent then
		return
	end
	local main = grenade.PrimaryPart
	local position = main and main.Position or grenade:GetPivot().Position
	apply_explosion_damage(ctx, attacker, grenade, position)
	emit_explosion_effects(position, grenade)
	remote:FireAllClients(position, explosion_radius, shake_radius)
	grenade:Destroy()
end

local function is_available(player)
	local ready_at = player:GetAttribute(ready_attribute)
	return type(ready_at) ~= "number" or workspace:GetServerTimeNow() >= ready_at
end

local function can_throw(ctx, player)
	if player:GetAttribute("ragdolled") == true then
		return false, "ragdolled"
	end
	if not is_available(player) then
		return false, "replenishing"
	end
	local state = player_state.ensure_player_state(player)
	if not state.inventory[utility_item_id] or state.loadout[utility_slot] ~= utility_item_id then
		return false, "invalid_loadout"
	end
	return true
end

local function send_throw_result(remote, player, request_id, success, reason)
	remote:FireClient(player, request_id, success, player:GetAttribute(ready_attribute) or 0, reason)
end

function grenade_service.setup(ctx)
	local equip_remote = get_or_create_remote(ctx, "GrenadeEquip")
	local throw_remote = get_or_create_remote(ctx, "GrenadeThrow")
	local throw_result_remote = get_or_create_remote(ctx, "GrenadeThrowResult")
	local explode_remote = get_or_create_remote(ctx, "GrenadeExplode")
	get_or_create_active_folder()
	equip_remote.OnServerEvent:Connect(function(player, equipped)
		if player:GetAttribute("ragdolled") == true then
			remove_held_grenade(player)
			return
		end
		if equipped ~= true then
			remove_held_grenade(player)
			return
		end
		if not consume_request_budget(last_equip_requests, player, EQUIP_REQUEST_INTERVAL) then
			return
		end
		local state = player_state.ensure_player_state(player)
		if is_available(player) and state.inventory[utility_item_id] and state.loadout[utility_slot] == utility_item_id then
			equip_held_grenade(player)
		end
	end)
	throw_remote.OnServerEvent:Connect(function(player, request_id, direction)
		if type(request_id) ~= "number"
			or request_id ~= request_id
			or request_id == math.huge
			or request_id == -math.huge
			or request_id % 1 ~= 0
			or request_id < 1
		then
			return
		end
		if not consume_request_budget(last_throw_requests, player, THROW_REQUEST_INTERVAL) then
			return
		end
		direction = validate_direction(direction)
		if not direction then
			send_throw_result(throw_result_remote, player, request_id, false, "invalid_direction")
			return
		end
		local allowed, reason = can_throw(ctx, player)
		if not allowed then
			send_throw_result(throw_result_remote, player, request_id, false, reason)
			return
		end
		local character, _, origin_part = get_character_parts(player)
		local template = get_template()
		if not character or not origin_part or not template then
			send_throw_result(throw_result_remote, player, request_id, false, "character_unavailable")
			return
		end
		local position = get_spawn_position(character, origin_part, direction)
		local grenade = prepare_grenade(template, position, direction)
		if not grenade then
			send_throw_result(throw_result_remote, player, request_id, false, "spawn_failed")
			return
		end
		remove_held_grenade(player)
		local ready_at = workspace:GetServerTimeNow() + replenish_seconds
		player:SetAttribute(ready_attribute, ready_at)
		send_throw_result(throw_result_remote, player, request_id, true)
		task.delay(fuse_seconds, detonate, ctx, explode_remote, player, grenade)
	end)
	ctx.Players.PlayerRemoving:Connect(function(player)
		remove_held_grenade(player)
		last_equip_requests[player] = nil
		last_throw_requests[player] = nil
	end)
end

return grenade_service
