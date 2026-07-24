local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ballistics = require(ReplicatedStorage.Modules.Shared.Ballistics)
local visualizer = require(script.Visualizer)

local projectile_handler = {}
projectile_handler.ActiveProjectiles = {}
projectile_handler.MaxProjectiles = 300

local Projectile = {}
Projectile.__index = Projectile

local available_projectiles = {}
local allocated_projectiles = 0

local function get_owner_exclusions(owner)
	local exclusions = { workspace.CurrentCamera }
	if typeof(owner) ~= "Instance" then
		return exclusions
	end
	if owner:IsA("Player") then
		if owner.Character then
			table.insert(exclusions, owner.Character)
		end
	elseif owner:IsA("Model") then
		table.insert(exclusions, owner)
	else
		table.insert(exclusions, owner)
	end
	return exclusions
end

local function acquire_projectile(origin, direction, owner, config, callback)
	local projectile = table.remove(available_projectiles)
	if not projectile then
		if allocated_projectiles >= projectile_handler.MaxProjectiles then
			return nil
		end
		projectile = setmetatable({
			raycast_params = RaycastParams.new(),
		}, Projectile)
		allocated_projectiles += 1
	end
	local velocity = direction.Unit * config.muzzle_velocity
	projectile.origin = origin
	projectile.position = origin
	projectile.previous_position = origin
	projectile.initial_velocity = velocity
	projectile.velocity = velocity
	projectile.owner = owner
	projectile.config = config
	projectile.distance = 0
	projectile.age = 0
	projectile.alive = true
	projectile.callback = callback
	projectile.raycast_params.FilterType = Enum.RaycastFilterType.Exclude
	projectile.raycast_params.FilterDescendantsInstances = get_owner_exclusions(owner)
	projectile.raycast_params.IgnoreWater = true
	return projectile
end

local function release_projectile(projectile)
	projectile.alive = false
	projectile.owner = nil
	projectile.config = nil
	projectile.callback = nil
	projectile.raycast_params.FilterDescendantsInstances = {}
	table.insert(available_projectiles, projectile)
end

function Projectile:update(delta_time)
	self.previous_position = self.position
	self.age += delta_time
	self.position = Ballistics.position_at_time(self.origin, self.initial_velocity, self.config.gravity, self.age)
	self.velocity = Ballistics.velocity_at_time(self.initial_velocity, self.config.gravity, self.age)

	local segment = self.position - self.previous_position
	local segment_length = segment.Magnitude
	if segment_length <= 0 then
		return
	end

	visualizer:ShowTracer(self.previous_position, self.position, self.config)

	local result = workspace:Raycast(self.previous_position, segment, self.raycast_params)
	self.distance += segment_length

	if result then
		self.alive = false
		visualizer:ShowImpact(result.Position, result.Normal, self.config)

		if self.callback then
			self.callback(result, self.distance)
		end
	elseif self.distance >= self.config.max_distance then
		self.alive = false
	end
end

function projectile_handler.fire(origin, direction, owner, config, callback)
	if #projectile_handler.ActiveProjectiles >= projectile_handler.MaxProjectiles then
		return nil
	end

	local projectile = acquire_projectile(origin, direction, owner, config, callback)
	if not projectile then
		return nil
	end
	table.insert(projectile_handler.ActiveProjectiles, projectile)
	return projectile
end

projectile_handler.FireProjectile = projectile_handler.fire

function projectile_handler.update(delta_time)
	for index = #projectile_handler.ActiveProjectiles, 1, -1 do
		local projectile = projectile_handler.ActiveProjectiles[index]

		if projectile.alive then
			projectile:update(delta_time)
		end

		if not projectile.alive then
			local last = #projectile_handler.ActiveProjectiles
			projectile_handler.ActiveProjectiles[index] = projectile_handler.ActiveProjectiles[last]
			projectile_handler.ActiveProjectiles[last] = nil
			release_projectile(projectile)
		end
	end
end

RunService.Heartbeat:Connect(projectile_handler.update)
return projectile_handler

