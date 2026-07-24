local ragdoll_service = {}

local recovery_tokens = setmetatable({}, { __mode = "k" })
local bound_humanoids = setmetatable({}, { __mode = "k" })
local ragdoll_handler
local ragdoll_state_remote

local function set_player_ragdoll_state(player, ragdolled)
	player:SetAttribute("ragdolled", ragdolled == true)
	if ragdoll_state_remote then
		ragdoll_state_remote:FireClient(player, ragdolled == true)
	end
end

local function set_ragdoll_state(ctx, character, ragdolled)
	local player = ctx.Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	set_player_ragdoll_state(player, ragdolled)
	if ragdolled then
		local pipeline = ctx.runtime:try_get("CombatPipeline")
		if pipeline then
			pipeline:cancel_actor(player, "ragdolled")
		end
	end
end

local function get_hit_data(ctx, character)
	local hit_data = ctx.npc_hit_data[character]
	if not hit_data then
		return nil, nil, nil
	end
	return hit_data.origin, hit_data.direction, hit_data.position
end

function ragdoll_service.apply(ctx, character, source_position, hit_direction, hit_position, duration, multiplier)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or not ragdoll_handler then
		return false
	end
	recovery_tokens[character] = (recovery_tokens[character] or 0) + 1
	local recovery_token = recovery_tokens[character]
	local applied
	if ragdoll_handler:IsRagdolled(character) then
		applied = ragdoll_handler:Knockback(character, source_position, hit_direction, hit_position, multiplier)
	else
		applied = ragdoll_handler:Apply(character, source_position, hit_direction, hit_position, multiplier)
		set_ragdoll_state(ctx, character, true)
	end
	if type(duration) ~= "number" or duration <= 0 or humanoid.Health <= 0 then
		return applied
	end
	task.delay(duration, function()
		if recovery_tokens[character] ~= recovery_token or not character.Parent or humanoid.Health <= 0 then
			return
		end
		local removed = ragdoll_handler:Remove(character)
		local player = ctx.Players:GetPlayerFromCharacter(character)
		if removed and player then
			ctx.runtime:get("PlayerMovementService").recover_player(player)
		end
		set_ragdoll_state(ctx, character, false)
	end)
	return applied
end

function ragdoll_service.is_ragdolled(character)
	return ragdoll_handler and ragdoll_handler:IsRagdolled(character) or false
end

local function bind_character(ctx, character)
	local player = ctx.Players:GetPlayerFromCharacter(character)
	if player then
		set_player_ragdoll_state(player, false)
	end
	recovery_tokens[character] = nil
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid or bound_humanoids[humanoid] then
		return
	end
	bound_humanoids[humanoid] = true
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Died:Connect(function()
		local source_position, hit_direction, hit_position = get_hit_data(ctx, character)
		ragdoll_service.apply(ctx, character, source_position, hit_direction, hit_position, nil, 1)
	end)
end

local function bind_player(ctx, player)
	if player.Character then
		bind_character(ctx, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		bind_character(ctx, character)
	end)
end

function ragdoll_service.setup(ctx)
	local modules = ctx.ServerStorage:WaitForChild("Modules", 5)
	local packages = modules and modules:WaitForChild("Packages", 5)
	local ragdoll_module = packages and packages:WaitForChild("RagdollHandler", 5)
	if not ragdoll_module then
		return
	end
	ragdoll_handler = require(ragdoll_module)
	ragdoll_state_remote = ctx.remote_map.RagdollState
	for _, player in ctx.Players:GetPlayers() do
		bind_player(ctx, player)
	end
	ctx.Players.PlayerAdded:Connect(function(player)
		bind_player(ctx, player)
	end)
end

return ragdoll_service

