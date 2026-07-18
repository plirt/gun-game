local npc_fill_service = {}

local npc_agent_service = require(script.Parent.Npc.npc_agent_service)
local npc_ragdoll_service = require(script.Parent.Npc.npc_ragdoll_service)
local npc_spawn_controller = require(script.Parent.Npc.npc_spawn_controller)
local npc_threat_service = require(script.Parent.Npc.npc_threat_service)

local default_map_id = "Default"
local target_combatant_count = 5
local npc_respawn_seconds = 4
local round_active = false

local function get_npcs_folder()
	local npcs = workspace:FindFirstChild("Npcs")

	if npcs and npcs:IsA("Folder") then
		return npcs
	end

	npcs = Instance.new("Folder")
	npcs.Name = "Npcs"
	npcs.Parent = workspace

	return npcs
end

local function get_desired_npc_count(ctx)
	return math.max(target_combatant_count - #ctx.Players:GetPlayers(), 0)
end

function npc_fill_service.refresh_round(ctx)
	if not round_active then
		return
	end
	local npcs_folder = get_npcs_folder()
	local desired_count = get_desired_npc_count(ctx)
	npc_spawn_controller.trim(npcs_folder, desired_count)
	npc_spawn_controller.ensure(ctx, npcs_folder, desired_count)
	if ctx.match_service then
		for _, npc in npcs_folder:GetChildren() do
			ctx.match_service.register_npc(ctx, npc)
		end
	end
end

function npc_fill_service.start_round(ctx, map_id)
	local npcs_folder = get_npcs_folder()
	local resolved_map_id = map_id or default_map_id
	ctx.active_map_id = resolved_map_id
	round_active = true
	npc_spawn_controller.clear(npcs_folder)
	local active_map_id = npc_spawn_controller.start(ctx, npcs_folder, resolved_map_id, get_desired_npc_count(ctx))
	if ctx.match_service then
		for _, npc in npcs_folder:GetChildren() do
			ctx.match_service.register_npc(ctx, npc)
		end
	end
	return active_map_id
end

function npc_fill_service.queue_respawn(ctx, npc)
	if not npc_spawn_controller.is_generated(npc) then
		return
	end
	task.delay(npc_respawn_seconds, function()
		if npc.Parent then
			npc:Destroy()
		end
		npc_fill_service.refresh_round(ctx)
	end)
end

function npc_fill_service.end_round(ctx)
	round_active = false
	local npcs_folder = get_npcs_folder()
	npc_spawn_controller.clear(npcs_folder)
end

function npc_fill_service.setup(ctx)
	ctx.npc_fill_service = npc_fill_service

	get_npcs_folder()

	npc_threat_service.setup(ctx)
	npc_agent_service.setup(ctx)
	npc_ragdoll_service.setup(ctx)
	ctx.Players.PlayerAdded:Connect(function()
		task.defer(npc_fill_service.refresh_round, ctx)
	end)
	ctx.Players.PlayerRemoving:Connect(function()
		task.delay(0.1, npc_fill_service.refresh_round, ctx)
	end)
end

return npc_fill_service