local npc_agent_service = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FixedStepScheduler = require(ReplicatedStorage.Modules.Shared.Framework.FixedStepScheduler)
local NpcCombatActor = require(script.Parent.Parent.Combat.Actors.NpcCombatActor)
local npc_threat_service = require(script.Parent.NpcThreatService)
local npc_aim_controller = require(script.Parent.NpcAimController)
local npc_animation_controller = require(script.Parent.NpcAnimationController)
local npc_interaction_controller = require(script.Parent.NpcInteractionController)
local npc_line_of_sight = require(script.Parent.NpcLineOfSight)
local npc_values = require(script.Parent.NpcValues)
local npc_weapon_controller = require(script.Parent.NpcWeaponController)

local npc_type_name = "npc_type"

local wander_radius = 28
local wander_repath_min = 1.8
local wander_repath_max = 3.6

local target_scan_interval = 0.16
local perception_scheduler = FixedStepScheduler.new(target_scan_interval, 8)
local shoot_range = 125

local chase_distance = 48
local hold_distance = 24
local retreat_distance = 13
local strafe_distance = 11

local strafe_repath_min = 0.45
local strafe_repath_max = 0.95

local default_walk_speed = 16
local default_sprint_speed = 20
local terrorist_walk_speed = 13
local terrorist_sprint_speed = 17
local civilian_walk_speed = 8


local stopped_states = {
	frightened = true,
	fake_fright = true,
	hands_up = true,
	kneeling = true,
	restrained = true,
	ragdolled = true,
}

local random = Random.new()
local agents = {}
local roam_points = {}

local function refresh_roam_points()
	table.clear(roam_points)
	local folder = workspace:FindFirstChild("PseudoSpawnLocations")
	if not folder then
		return
	end
	for _, instance in folder:GetDescendants() do
		if instance:IsA("BasePart") then
			table.insert(roam_points, instance.Position)
		elseif instance:IsA("Attachment") then
			table.insert(roam_points, instance.WorldPosition)
		end
	end
end

local function normalize_npc_type(npc_type)
	npc_type = string.lower(npc_type or "")

	if npc_type == "" then
		return "default"
	end

	return npc_type
end

local function is_combat_type(npc_type)
	npc_type = normalize_npc_type(npc_type)

	return npc_type == "terrorist" or npc_type == "default"
end

local function is_always_aggressive(agent)
	return normalize_npc_type(agent.npc_type) == "default"
end

local function get_walk_speed(npc_type)
	npc_type = normalize_npc_type(npc_type)

	if npc_type == "default" then
		return default_walk_speed
	elseif npc_type == "terrorist" then
		return terrorist_walk_speed
	end

	return civilian_walk_speed
end

local function get_sprint_speed(npc_type)
	npc_type = normalize_npc_type(npc_type)

	if npc_type == "default" then
		return default_sprint_speed
	elseif npc_type == "terrorist" then
		return terrorist_sprint_speed
	end

	return civilian_walk_speed
end

local function random_wander_point(agent)
	local best_point
	local best_distance = -1
	local attempts = math.min(math.max(#roam_points, 1), 5)
	for _ = 1, attempts do
		local origin = #roam_points > 0 and roam_points[random:NextInteger(1, #roam_points)] or agent.spawn_position
		local radius = random:NextNumber(wander_radius * 0.35, wander_radius)
		local theta = random:NextNumber(0, math.pi * 2)
		local point = origin + Vector3.new(math.cos(theta) * radius, 0, math.sin(theta) * radius)
		local distance = (point - agent.root.Position).Magnitude
		if distance > best_distance then
			best_point = point
			best_distance = distance
		end
	end
	return best_point or agent.spawn_position
end

local function set_next_wander(agent, now)
	agent.next_wander_at = now + random:NextNumber(wander_repath_min, wander_repath_max)
	agent.humanoid:MoveTo(random_wander_point(agent))
end

local function get_alive_target(ctx, agent)
	local best_root
	local best_score = math.huge
	local best_distance = shoot_range

	local function consider(model, entity)
		if model == agent.npc or not entity then
			return
		end
		if not ctx.combat_authority:can_damage(agent.npc, entity) then
			return
		end
		local humanoid = model:FindFirstChildWhichIsA("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
			return
		end
		local distance = (root.Position - agent.root.Position).Magnitude
		if distance > shoot_range then
			return
		end
		local fire_origin = npc_weapon_controller.get_fire_origin(agent)
		local visible = npc_weapon_controller.is_fire_origin_clear(agent, fire_origin)
			and npc_line_of_sight.can_see_model(
				fire_origin,
				model,
				{ agent.npc, agent.gun },
				shoot_range
			)
		local score = distance + (visible and 0 or 80)
		if score < best_score then
			best_root = root
			best_score = score
			best_distance = distance
		end
	end

	for _, player in ctx.Players:GetPlayers() do
		if player.Character then
			consider(player.Character, player)
		end
	end
	if best_root then
		return best_root, best_distance
	end
	local npcs = workspace:FindFirstChild("Npcs")
	if npcs then
		for _, npc in npcs:GetChildren() do
			if npc:IsA("Model") then
				consider(npc, npc)
			end
		end
	end
	return best_root, best_distance
end

local function has_line_of_sight(agent, target_root)
	local target_model = target_root and target_root.Parent
	local fire_origin = npc_weapon_controller.get_fire_origin(agent)
	if not npc_weapon_controller.is_fire_origin_clear(agent, fire_origin) then
		return false
	end
	return npc_line_of_sight.can_see_model(
		fire_origin,
		target_model,
		{ agent.npc, agent.gun },
		shoot_range
	)
end

local function face_target(agent, target_root)
	local target = Vector3.new(target_root.Position.X, agent.root.Position.Y, target_root.Position.Z)
	local delta = target - agent.root.Position

	if delta.Magnitude > 0.1 then
		agent.root.CFrame = CFrame.lookAt(agent.root.Position, agent.root.Position + delta.Unit)
	end
end

local function get_strafe_direction(agent, now)
	if not agent.next_strafe_at or now >= agent.next_strafe_at then
		agent.strafe_side = agent.random:NextInteger(0, 1) == 0 and -1 or 1
		agent.next_strafe_at = now + agent.random:NextNumber(strafe_repath_min, strafe_repath_max)
	end

	return agent.strafe_side or 1
end

local function move_like_player(agent, target_root, distance, now)
	local target_delta = target_root.Position - agent.root.Position
	local flat_delta = Vector3.new(target_delta.X, 0, target_delta.Z)

	if flat_delta.Magnitude <= 0.1 then
		return
	end

	local forward = flat_delta.Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local strafe_side = get_strafe_direction(agent, now)

	if distance > chase_distance then
		agent.humanoid.WalkSpeed = get_sprint_speed(agent.npc_type)
		agent.humanoid:MoveTo(target_root.Position)
		return
	end

	agent.humanoid.WalkSpeed = get_walk_speed(agent.npc_type)

	local move_position

	if distance < retreat_distance then
		move_position = agent.root.Position - forward * 10 + right * strafe_distance * strafe_side
	elseif distance < hold_distance then
		move_position = agent.root.Position - forward * 4 + right * strafe_distance * strafe_side
	else
		move_position = target_root.Position + right * strafe_distance * strafe_side
	end

	agent.humanoid:MoveTo(move_position)
end

local function update_visual_state(ctx, agent, state_name)
	if is_always_aggressive(agent) and state_name ~= "ragdolled" then
		state_name = "hostile"
	end

	if state_name == agent.last_visual_state then
		return
	end

	agent.last_visual_state = state_name

	npc_interaction_controller.update(ctx, agent, state_name)
	npc_animation_controller.update(ctx, agent, state_name)

	agent.humanoid.Sit = false
end

local function update_movement(ctx, agent, now)
	local state_name = npc_threat_service.get_state(agent.npc)
	local stunned = npc_threat_service.is_stunned(agent.npc)

	if is_always_aggressive(agent) and state_name ~= "ragdolled" and not stunned then
		state_name = "hostile"
		npc_threat_service.set_state(agent.npc, "hostile")
	end

	update_visual_state(ctx, agent, state_name)

	if stunned or (stopped_states[state_name] and not is_always_aggressive(agent)) then
		if not agent.was_stopped then
			agent.was_stopped = true
			agent.humanoid.WalkSpeed = 0
		end

		agent.humanoid:MoveTo(agent.root.Position)
		return
	end

	if agent.was_stopped then
		agent.was_stopped = false
		agent.humanoid.WalkSpeed = agent.base_walk_speed
	end

	if state_name == "hostile" and is_combat_type(agent.npc_type) then
		-- Perception is deliberately fixed-step and staggered. Movement can still follow the
		-- cached target every frame without multiplying LOS queries by the render rate.
		if perception_scheduler:should_run(agent, now)
			or not agent.target_root
			or not agent.target_root.Parent
		then
			agent.target_root = get_alive_target(ctx, agent)
		end
		local target_root = agent.target_root
		if target_root and target_root.Parent then
			local distance = (target_root.Position - agent.root.Position).Magnitude
			face_target(agent, target_root)
			move_like_player(agent, target_root, distance, now)
			return
		end
	end

	local objective_position = ctx.combat_authority:get_objective_position()
	if objective_position then
		local objective_distance = (objective_position - agent.root.Position).Magnitude
		if objective_distance > 6 then
			agent.humanoid.WalkSpeed = get_sprint_speed(agent.npc_type)
			agent.humanoid:MoveTo(objective_position)
		else
			agent.humanoid.WalkSpeed = get_walk_speed(agent.npc_type)
			agent.humanoid:MoveTo(agent.root.Position)
		end
		return
	end
	if now >= agent.next_wander_at then
		set_next_wander(agent, now)
	end
end

local function update_combat(ctx, agent, now)
	if not is_combat_type(agent.npc_type) or npc_threat_service.is_stunned(agent.npc) then
		return
	end

	local state_name = npc_threat_service.get_state(agent.npc)

	if is_always_aggressive(agent) and state_name ~= "ragdolled" then
		state_name = "hostile"
		npc_threat_service.set_state(agent.npc, "hostile")
	end

	if state_name ~= "hostile" then
		return
	end

	npc_weapon_controller.equip(ctx, agent)

	if not agent.gun then
		return
	end

	local target_root = agent.target_root

	if not target_root or not has_line_of_sight(agent, target_root) then
		return
	end

	face_target(agent, target_root)

	if now >= agent.next_shot_at then
		local config = npc_weapon_controller.get_config(ctx, agent)
		local seconds_per_shot = npc_weapon_controller.get_seconds_per_shot(config)
		local reaction_noise = agent.random:NextNumber(0.015, 0.08)

		agent.next_shot_at = now + seconds_per_shot + reaction_noise

		npc_weapon_controller.shoot(
			ctx,
			agent,
			target_root,
			npc_aim_controller.get_direction(ctx, agent, target_root, config)
		)
	end
end

local function setup_agent(ctx, npc)
	if agents[npc] or not npc:IsA("Model") then
		return
	end

	local humanoid = npc:FindFirstChildWhichIsA("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end

	local npc_type = normalize_npc_type(npc_values.read_string(npc, npc_type_name, "Default"))
	local gun_id = npc_values.read_string(npc, "gun_id", "")

	local agent = {
		npc = npc,
		humanoid = humanoid,
		animator = npc_values.get_or_create_animator(humanoid),
		root = root,
		npc_type = npc_type,
		gun_id = gun_id,
		spawn_position = root.Position,
		next_wander_at = 0,
		next_scan_at = 0,
		next_shot_at = 0,
		base_walk_speed = get_walk_speed(npc_type),
		strafe_side = 1,
		next_strafe_at = 0,
		random = Random.new(math.floor(os.clock() * 1000) + #npc:GetFullName()),
	}

	agents[npc] = agent
	ctx.runtime:get("CombatActorRegistry"):register(npc, NpcCombatActor.new(agent, {
		is_stunned = npc_threat_service.is_stunned,
		get_state = npc_threat_service.get_state,
	}))

	humanoid.WalkSpeed = agent.base_walk_speed
	humanoid.AutoRotate = false
	humanoid.Jump = false
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	if is_combat_type(npc_type) then
		npc_threat_service.set_state(npc, "hostile")
	end

	set_next_wander(agent, os.clock())
end

function npc_agent_service.setup(ctx)
	refresh_roam_points()
	local npcs = workspace:FindFirstChild("Npcs")

	if not npcs then
		return
	end

	for _, npc in npcs:GetChildren() do
		setup_agent(ctx, npc)
	end

	npcs.ChildAdded:Connect(function(npc)
		task.defer(setup_agent, ctx, npc)
	end)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()

		for npc, agent in agents do
			if not npc.Parent or agent.humanoid.Health <= 0 then
				npc_animation_controller.stop(agent)
				npc_weapon_controller.cleanup(agent)
				perception_scheduler:forget(agent)
				ctx.runtime:get("CombatPipeline"):cancel_actor(npc, "actor_removed")
				ctx.runtime:get("CombatActorRegistry"):unregister(npc)
				agents[npc] = nil
			else
				update_movement(ctx, agent, now)
				update_combat(ctx, agent, now)
			end
		end
	end)
end

function npc_agent_service.drop_gun(npc, impulse_direction)
	local agent = agents[npc]

	if not agent then
		return false
	end

	return npc_weapon_controller.drop(agent, impulse_direction)
end

function npc_agent_service.get_agent(npc)
	return agents[npc]
end

return npc_agent_service
