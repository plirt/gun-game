local npc_weapon_controller = {}

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local npc_values = require(script.Parent.NpcValues)
local npc_threat_service = require(script.Parent.NpcThreatService)

local ShotPattern = require(ReplicatedStorage.Modules.Shared.ShotPattern)
local AttachmentModifier = require(ReplicatedStorage.Modules.Shared.AttachmentModifier)
local WeaponConfigResolver = require(script.Parent.Parent.Combat.WeaponConfigResolver)
local weapon_config = require(ReplicatedStorage.Modules.Shared.WeaponConfig)

local HELD_GUN_NAME = "HeldGun"
local LINE_OF_SIGHT_HEIGHT = Vector3.new(0, 1.35, 0)
local dropped_gun_lifetime = 5
local dropped_gun_settle_seconds = 0.8

local random = Random.new()
local MUTANT_EXTERNAL_C0 = CFrame.Angles(0, math.rad(-180), 0)
local ATTACHMENT_TYPES = { "Sight", "Grip", "Barrel" }

local function get_npc_attachments(npc)
	local attachments = {}
	local folder = npc:FindFirstChild("Attachments")
	for _, attachment_type in ATTACHMENT_TYPES do
		local value = npc:GetAttribute(attachment_type .. "Attachment")
		if type(value) ~= "string" and folder then
			local object = folder:FindFirstChild(attachment_type)
			if object and object:IsA("StringValue") then
				value = object.Value
			end
		end
		if type(value) == "string" and value ~= "" then
			attachments[attachment_type] = value
		end
	end
	return attachments
end

local function get_external_idle_animation(gun)
	local animations = gun:FindFirstChild("Animations")
	local external = animations and animations:FindFirstChild("External")
	local idle = external and external:FindFirstChild("Idle")
	if idle and idle:IsA("Animation") then
		return idle
	end
	return nil
end

local function stop_external_idle(agent)
	if agent.external_idle_track then
		agent.external_idle_track:Stop(0.15)
		agent.external_idle_track:Destroy()
		agent.external_idle_track = nil
	end
end

local function play_external_idle(agent, gun)
	stop_external_idle(agent)
	local animation = get_external_idle_animation(gun)
	if not animation then
		return
	end
	local animator = agent.animator or npc_values.get_or_create_animator(agent.humanoid)
	if not animator then
		return
	end
	local loaded, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not loaded or not track then
		return
	end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = true
	track:Play(0.15)
	agent.animator = animator
	agent.external_idle_track = track
end

local function setup_gun_parts(gun, dropped)
	for _, descendant in gun:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = dropped == true
			descendant.CanTouch = dropped == true
			descendant.CanQuery = dropped == true
			descendant.Massless = dropped ~= true
		end
	end
end

local function freeze_dropped_gun(gun)
	if not gun.Parent then
		return
	end
	for _, descendant in gun:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
			descendant.Anchored = true
		end
	end
end

local function choose_template(ctx, preferred_gun_id)
	local guns = ctx.ReplicatedStorage:FindFirstChild("Guns")
	if not guns then
		return nil
	end

	if preferred_gun_id and preferred_gun_id ~= "" then
		local preferred = guns:FindFirstChild(preferred_gun_id)
		if preferred and preferred:IsA("Model") and ctx.gun_configs:FindFirstChild(preferred.Name) then
			return preferred
		end
	end

	local choices = {}
	for _, child in guns:GetChildren() do
		if child:IsA("Model") and ctx.gun_configs:FindFirstChild(child.Name) then
			table.insert(choices, child)
		end
	end
	if #choices == 0 then
		return nil
	end
	return choices[random:NextInteger(1, #choices)]
end

local function attach_to_root(npc, gun, gun_name)
	local root = npc:FindFirstChild("HumanoidRootPart")
	local main = gun:FindFirstChild("MAIN", true)
	if not root or not root:IsA("BasePart") or not main or not main:IsA("BasePart") then
		return false
	end

	gun.PrimaryPart = main
	gun:PivotTo(root.CFrame * CFrame.new(0, -0.25, -2.35) * CFrame.Angles(0, math.rad(180), 0))

	local motor = Instance.new("Motor6D")
	motor.Name = "NpcGunMotor"
	motor.Part0 = root
	motor.Part1 = main
	if gun_name == "MUTANT" then
		motor.C0 = MUTANT_EXTERNAL_C0
		motor.C1 = CFrame.identity
	end
	motor.Parent = root
	return true
end

function npc_weapon_controller.equip(ctx, agent)
	if agent.gun and agent.gun.Parent then
		return agent.gun
	end

	local held = agent.npc:FindFirstChild(HELD_GUN_NAME)
	if held then
		agent.gun = held
		agent.gun_name = npc_values.read_string(held, "gun_name", "")
		play_external_idle(agent, held)
		return held
	end

	local template = choose_template(ctx, agent.gun_id)
	if not template then
		return nil
	end

	local gun = template:Clone()
	gun.Name = HELD_GUN_NAME
	npc_values.write_string(gun, "gun_name", template.Name)
	agent.attachments = get_npc_attachments(agent.npc)
	AttachmentModifier.apply_loadout(gun, agent.attachments)
	setup_gun_parts(gun, false)
	gun.Parent = agent.npc
	if not attach_to_root(agent.npc, gun, template.Name) then
		gun:Destroy()
		return nil
	end

	agent.gun = gun
	agent.gun_name = template.Name
	play_external_idle(agent, gun)
	return gun
end

function npc_weapon_controller.drop(agent, impulse_direction)
	local gun = agent.gun or agent.npc:FindFirstChild(HELD_GUN_NAME)
	if not gun then
		return false
	end

	stop_external_idle(agent)

	local root = agent.root or agent.npc:FindFirstChild("HumanoidRootPart")
	if root then
		local motor = root:FindFirstChild("NpcGunMotor")
		if motor and motor:IsA("Motor6D") then
			motor:Destroy()
		end
	end

	setup_gun_parts(gun, true)
	gun.Parent = workspace
	Debris:AddItem(gun, dropped_gun_lifetime)
	local gun_root = npc_values.get_part(gun, { "MAIN", "Handle", "Root" })
	if gun_root then
		local direction = impulse_direction
		if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.01 then
			direction = agent.root.CFrame.LookVector
		end
		gun_root:ApplyImpulse((direction.Unit * 18 + Vector3.new(0, 8, 0)) * gun_root.AssemblyMass)
		gun_root:ApplyAngularImpulse(Vector3.new(0, 1, 0) * gun_root.AssemblyMass * 18)
		task.delay(dropped_gun_settle_seconds, freeze_dropped_gun, gun)
	end

	agent.gun = nil
	agent.gun_name = nil
	return true
end

function npc_weapon_controller.cleanup(agent)
	stop_external_idle(agent)
end

function npc_weapon_controller.get_fire_origin(agent)
	local gun = agent.gun
	if gun then
		local fire_point = gun:FindFirstChild("FirePoint", true)
		if fire_point and fire_point:IsA("Attachment") then
			return fire_point.WorldPosition
		end
		local muzzle = npc_values.get_part(gun, { "Muzzle", "Barrel", "MAIN", "Handle" })
		if muzzle then
			return muzzle.Position
		end
	end
	return agent.root.Position + agent.root.CFrame.LookVector * 2 + LINE_OF_SIGHT_HEIGHT
end

function npc_weapon_controller.is_fire_origin_clear(agent, origin)
	origin = origin or npc_weapon_controller.get_fire_origin(agent)
	local head = agent.npc:FindFirstChild("Head")
	local anchor = head and head:IsA("BasePart") and head or agent.root
	if not anchor or typeof(origin) ~= "Vector3" then
		return false
	end
	local offset = origin - anchor.Position
	if offset.Magnitude <= 0.05 then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { agent.npc, agent.gun }
	params.IgnoreWater = true
	local result = workspace:Raycast(anchor.Position, offset, params)
	return not result or result.Distance + 0.1 >= offset.Magnitude
end

function npc_weapon_controller.get_config(ctx, agent)
	if not agent.gun or not agent.gun.Parent then
		return nil
	end

	local gun_name = npc_values.read_string(agent.gun, "gun_name", agent.gun_name or agent.gun_id or "")
	if gun_name == "" then
		return nil
	end

	local actor = ctx.runtime:get("CombatActorRegistry"):get(agent.npc)
	local config = actor and WeaponConfigResolver.get_for_actor(actor, gun_name) or nil
	if not config then
		local module = ctx.gun_configs and ctx.gun_configs:FindFirstChild(gun_name)
		if module and module:IsA("ModuleScript") then
			config = WeaponConfigResolver.resolve(gun_name, weapon_config.normalize(require(module)), agent.attachments)
		end
	end
	if not config then
		return nil
	end
	agent.gun_name = gun_name
	return config
end

function npc_weapon_controller.get_seconds_per_shot(config)
	if not config then
		return 0.35
	end
	if type(config.seconds_per_shot) == "number" and config.seconds_per_shot > 0 then
		return config.seconds_per_shot
	end
	if type(config.fire_rate) == "number" and config.fire_rate > 0 then
		return 60 / config.fire_rate
	end
	return 0.35
end

function npc_weapon_controller.shoot(ctx, agent, target_root, direction)
	if npc_threat_service.is_stunned(agent.npc) then
		return false
	end
	local config = npc_weapon_controller.get_config(ctx, agent)
	if not config then
		return false
	end
	local gun_name = agent.gun_name or agent.gun_id or ""
	if gun_name == "" then
		return false
	end
	local origin = npc_weapon_controller.get_fire_origin(agent)
	if not npc_weapon_controller.is_fire_origin_clear(agent, origin) then
		return false
	end
	local pellet_directions = ShotPattern.build_npc_directions(direction, config, agent.random)
	local result = ctx.runtime:get("CombatPipeline"):activate(agent.npc, "Hitscan", {
		item_id = gun_name,
		origin = origin,
		directions = pellet_directions,
		config = config,
		fire_time = workspace:GetServerTimeNow(),
		play_sound = true,
	})
	return result.ok == true
end
return npc_weapon_controller


