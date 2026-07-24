local npc_fill_service = {}

local npc_agent_service = require(script.Parent.Npc.NpcAgentService)
local npc_ragdoll_service = require(script.Parent.Npc.NpcRagdollService)
local npc_spawn_controller = require(script.Parent.Npc.NpcSpawnController)
local npc_threat_service = require(script.Parent.Npc.NpcThreatService)

local default_map_id = "Default"
local target_combatant_count = 5
local npc_respawn_seconds = 4
local npc_respawn_interval = 0.5
local round_active = false
local pending_respawns = 0
local respawn_worker_running = false

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

function npc_fill_service.refresh_round(ctx, max_spawn_count)
	if not round_active then
		return
	end
	local npcs_folder = get_npcs_folder()
	local desired_count = get_desired_npc_count(ctx)
	npc_spawn_controller.trim(npcs_folder, desired_count)
	npc_spawn_controller.ensure(ctx, npcs_folder, desired_count, max_spawn_count)
end

function npc_fill_service.start_round(ctx, map_id)
	local npcs_folder = get_npcs_folder()
	local resolved_map_id = map_id or default_map_id
	ctx.active_map_id = resolved_map_id
	round_active = true
	pending_respawns = 0
	npc_spawn_controller.clear(npcs_folder)
	local active_map_id = npc_spawn_controller.start(ctx, npcs_folder, resolved_map_id, get_desired_npc_count(ctx))
	return active_map_id
end

local function start_respawn_worker(ctx)
	if respawn_worker_running then
		return
	end
	respawn_worker_running = true
	task.spawn(function()
		while round_active and pending_respawns > 0 do
			pending_respawns -= 1
			npc_fill_service.refresh_round(ctx, 1)
			if pending_respawns > 0 then
				task.wait(npc_respawn_interval)
			end
		end
		respawn_worker_running = false
		if round_active and pending_respawns > 0 then
			start_respawn_worker(ctx)
		end
	end)
end

function npc_fill_service.queue_respawn(ctx, npc)
	if not npc_spawn_controller.is_generated(npc) then
		return
	end
	task.delay(npc_respawn_seconds, function()
		if npc.Parent then
			npc:Destroy()
		end
		if not round_active then
			return
		end
		pending_respawns += 1
		start_respawn_worker(ctx)
	end)
end

function npc_fill_service.end_round(ctx)
	round_active = false
	pending_respawns = 0
	local npcs_folder = get_npcs_folder()
	npc_spawn_controller.clear(npcs_folder)
end

function npc_fill_service.setup(ctx)
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
