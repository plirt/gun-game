local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage.Modules.Shared.WeaponConfig)

local replay_projectile_player = {}
replay_projectile_player.__index = replay_projectile_player

function replay_projectile_player.new(visualizer)
	return setmetatable({
		visualizer = visualizer,
		shots = {},
		active = {},
		lethal_added = false,
	}, replay_projectile_player)
end

local function get_muzzle_velocity(gun_name)
	if type(gun_name) ~= "string" then
		return 1000
	end
	local gun_configs = ReplicatedStorage:FindFirstChild("GunConfigs")
	local config_module = gun_configs and gun_configs:FindFirstChild(gun_name)
	if not config_module or not config_module:IsA("ModuleScript") then
		return 1000
	end
	local ok, config = pcall(function()
		return WeaponConfig.normalize(require(config_module))
	end)
	if not ok or type(config.muzzle_velocity) ~= "number" then
		return 1000
	end
	return math.max(config.muzzle_velocity, 1)
end

local function is_duplicate(shots, candidate)
	for _, shot in shots do
		if math.abs(shot.time - candidate.time) <= 0.08
			and (shot.origin - candidate.origin).Magnitude <= 2
			and shot.shooter_user_id == candidate.shooter_user_id
		then
			local first = shot.hit_position - shot.origin
			local second = candidate.hit_position - candidate.origin
			if first.Magnitude > 0 and second.Magnitude > 0 and first.Unit:Dot(second.Unit) > 0.995 then
				return true
			end
		end
	end
	return false
end

local function resolve_event_shot(event, death_time)
	if event.type ~= "weapon_activated" or typeof(event.origin) ~= "Vector3" then
		return nil
	end
	local direction = event.directions and event.directions[1]
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0 then
		return nil
	end
	direction = direction.Unit
	local max_distance = type(event.max_distance) == "number" and math.clamp(event.max_distance, 1, 2000) or 650
	local result = workspace:Raycast(event.origin, direction * max_distance)
	return {
		time = death_time + event.offset,
		shooter_user_id = event.actor_user_id,
		gun_name = event.item_id,
		origin = event.origin,
		hit_position = result and result.Position or event.origin + direction * max_distance,
		hit_normal = result and result.Normal or -direction,
		muzzle_velocity = type(event.muzzle_velocity) == "number" and math.max(event.muzzle_velocity, 1) or get_muzzle_velocity(event.item_id),
		did_hit = result ~= nil,
		started = false,
	}
end

function replay_projectile_player:merge_lethal(kill_data, first_time, death_time)
	if self.lethal_added or not kill_data then
		return
	end
	local offset = kill_data.hit_position - kill_data.origin
	if offset.Magnitude <= 0.01 then
		self.lethal_added = true
		return
	end
	local direction = offset.Unit
	local muzzle_velocity = get_muzzle_velocity(kill_data.gun_name)
	local candidate = {
		time = math.max(first_time, death_time - offset.Magnitude / muzzle_velocity),
		shooter_user_id = kill_data.killer_user_id,
		gun_name = kill_data.gun_name,
		origin = kill_data.origin,
		hit_position = kill_data.hit_position,
		hit_normal = -direction,
		muzzle_velocity = muzzle_velocity,
		did_hit = true,
		lethal = true,
		started = false,
	}
	for index = #self.shots, 1, -1 do
		local shot = self.shots[index]
		if math.abs(shot.time - candidate.time) <= 0.2
			and (shot.origin - candidate.origin).Magnitude <= 10
		then
			table.remove(self.shots, index)
			break
		end
	end
	table.insert(self.shots, candidate)
	table.sort(self.shots, function(first, second)
		return first.time < second.time
	end)
	self.lethal_added = true
end

function replay_projectile_player:prepare(local_shots, kill_data, first_time, last_time, death_time)
	table.clear(self.shots)
	table.clear(self.active)
	self.lethal_added = false
	for _, shot in local_shots do
		if shot.time >= first_time and shot.time <= last_time then
			local replay_shot = table.clone(shot)
			replay_shot.started = false
			table.insert(self.shots, replay_shot)
		end
	end
	for _, event in kill_data and kill_data.combat_events or {} do
		local shot = resolve_event_shot(event, death_time)
		if shot and shot.time >= first_time and shot.time <= last_time and not is_duplicate(self.shots, shot) then
			table.insert(self.shots, shot)
		end
	end
	table.sort(self.shots, function(first, second)
		return first.time < second.time
	end)
	self:merge_lethal(kill_data, first_time, death_time)
end

function replay_projectile_player:update(replay_time)
	for _, shot in self.shots do
		if not shot.started and shot.time <= replay_time then
			shot.started = true
			table.insert(self.active, {
				shot = shot,
				previous_position = shot.origin,
			})
		end
	end
	for index = #self.active, 1, -1 do
		local projectile = self.active[index]
		local shot = projectile.shot
		local offset = shot.hit_position - shot.origin
		local travel_time = offset.Magnitude / math.max(shot.muzzle_velocity, 1)
		local elapsed = math.max(0, replay_time - shot.time)
		local alpha = math.clamp(elapsed / math.max(travel_time, 1 / 240), 0, 1)
		local position = shot.origin:Lerp(shot.hit_position, alpha)
		if (position - projectile.previous_position).Magnitude > 0.001 then
			self.visualizer:ShowTracer(projectile.previous_position, position, { tracer_lifetime = 0.045 })
			projectile.previous_position = position
		end
		if alpha >= 1 then
			if shot.did_hit then
				self.visualizer:ShowImpact(shot.hit_position, shot.hit_normal, { impact_lifetime = 0.12 })
			end
			table.remove(self.active, index)
		end
	end
end

function replay_projectile_player:clear()
	table.clear(self.shots)
	table.clear(self.active)
	self.lethal_added = false
end

return replay_projectile_player

