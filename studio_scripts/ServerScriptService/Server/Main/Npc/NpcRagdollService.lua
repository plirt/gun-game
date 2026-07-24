local npc_ragdoll_service = {}

local npc_agent_service = require(script.Parent.NpcAgentService)
local npc_threat_service = require(script.Parent.NpcThreatService)

local ragdoll_health = 10
local ragdoll_settle_seconds = 0.8

local bound_npcs = setmetatable({}, { __mode = "k" })

local function freeze_ragdoll(npc)
	if not npc.Parent then
		return
	end
	for _, descendant in npc:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
			descendant.Anchored = true
		end
	end
end

local function bind_npc(ctx, npc, ragdoll_handler)
	if not npc:IsA("Model") or bound_npcs[npc] then
		return
	end

	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	bound_npcs[npc] = true
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false

	local dropped_gun = false
	local freeze_scheduled = false
	local function apply()
		if not npc.Parent then
			return
		end
		local hit_data = ctx.npc_hit_data[npc]
		npc_threat_service.set_state(npc, "ragdolled")
		if not dropped_gun then
			dropped_gun = true
			npc_agent_service.drop_gun(npc, hit_data and hit_data.direction)
		end
		if not ragdoll_handler:IsRagdolled(npc) then
			ragdoll_handler:Apply(
				npc,
				hit_data and hit_data.origin,
				hit_data and hit_data.direction,
				hit_data and hit_data.position
			)
		end
		if not freeze_scheduled then
			freeze_scheduled = true
			task.delay(ragdoll_settle_seconds, freeze_ragdoll, npc)
		end
	end

	if humanoid.Health <= ragdoll_health then
		apply()
		return
	end

	local health_connection
	local died_connection
	health_connection = humanoid.HealthChanged:Connect(function(health)
		if health <= ragdoll_health then
			apply()
			if health_connection then
				health_connection:Disconnect()
			end
			if died_connection then
				died_connection:Disconnect()
			end
		end
	end)
	died_connection = humanoid.Died:Connect(function()
		apply()
		if health_connection then
			health_connection:Disconnect()
		end
		if died_connection then
			died_connection:Disconnect()
		end
	end)
end

function npc_ragdoll_service.setup(ctx)
	local packages = ctx.ServerStorage:FindFirstChild("Modules") and ctx.ServerStorage.Modules:FindFirstChild("Packages")
	local ragdoll_module = packages and packages:FindFirstChild("RagdollHandler")
	if not ragdoll_module then
		return
	end

	local ragdoll_handler = require(ragdoll_module)
	local npcs = workspace:FindFirstChild("Npcs")
	if not npcs then
		return
	end

	for _, npc in npcs:GetChildren() do
		bind_npc(ctx, npc, ragdoll_handler)
	end

	npcs.ChildAdded:Connect(function(npc)
		task.defer(bind_npc, ctx, npc, ragdoll_handler)
	end)
end
return npc_ragdoll_service


