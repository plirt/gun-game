local RunService = game:GetService("RunService")

local weapon_hit_scan_service = {}

local constants = require(script.Parent.server_constants)
local lag_compensation_service = require(script.Parent.lag_compensation_service)

export type HitScanResult = {
	direction: Vector3,
	result: any,
}

type ProjectileState = {
	elapsed: number,
	traveled: number,
	position: Vector3,
	finished: boolean,
}

local function get_static_params(ctx, character: Model?): RaycastParams
	local excluded = {}
	if character then
		table.insert(excluded, character)
	end
	for _, player in ctx.Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true
	return params
end

local function get_elapsed_since_fire(fire_time: any): number
	if type(fire_time) ~= "number" then
		return 0
	end
	return math.max(workspace:GetServerTimeNow() - fire_time, 0)
end

local function get_max_flight_time(config): number
	return config.max_distance / math.max(config.muzzle_velocity, 1) + 2
end

local function get_projectile_values(ctx, origin: Vector3, direction: Vector3, config: any, elapsed: number)
	local initial_velocity = direction.Unit * config.muzzle_velocity
	local acceleration = config.gravity
	return {
		position = ctx.Ballistics.position_at_time(origin, initial_velocity, acceleration, elapsed),
		velocity = ctx.Ballistics.velocity_at_time(initial_velocity, acceleration, elapsed),
	}
end

local function get_projectile_segment(ctx, origin: Vector3, direction: Vector3, config: any, previous_position: Vector3, elapsed: number)
	local position = get_projectile_values(ctx, origin, direction, config, elapsed).position
	local segment = position - previous_position
	return position, segment, segment.Magnitude
end

local function get_hitbox_padding(config): number
	local projectile_radius = type(config.projectile_radius) == "number" and config.projectile_radius or 0
	return math.max(projectile_radius, constants.LAG_COMPENSATION_HITBOX_PADDING)
end

local function get_step_time(config): number
	local config_step_time = type(config.step_time) == "number" and config.step_time or constants.LAG_COMPENSATION_PROJECTILE_STEP_TIME
	return math.min(config_step_time, constants.LAG_COMPENSATION_PROJECTILE_STEP_TIME)
end

local function make_hit_result(ctx, origin: Vector3, direction: Vector3, config: any, hit, traveled_before_segment: number, segment_origin: Vector3, segment_length: number, previous_elapsed: number, step_time: number, compensation)
	local hit_position = hit.position or hit.Position
	local hit_instance = hit.part or hit.Instance
	local hit_distance_in_segment = hit.distance or (hit_position - segment_origin).Magnitude
	local hit_alpha = math.clamp(hit_distance_in_segment / segment_length, 0, 1)
	local hit_elapsed = previous_elapsed + step_time * hit_alpha
	local values = get_projectile_values(ctx, origin, direction, config, hit_elapsed)
	return {
		hit = {
			Instance = hit_instance,
			Position = hit_position,
		},
		distance = traveled_before_segment + hit_distance_in_segment,
		position = hit_position,
		time = hit_elapsed,
		velocity = values.velocity,
		rewound = hit.rewound == true,
		compensation = compensation,
	}
end

local function find_compensated_hit(ctx, shooter, origin: Vector3, direction: Vector3, config: any, fire_time: any, view_delay: number, segment_origin: Vector3, segment: Vector3, traveled: number, previous_elapsed: number, step_time: number, static_result: any)
	local segment_length = segment.Magnitude
	local segment_time = previous_elapsed + step_time * 0.5
	local snapshot = lag_compensation_service.get_projectile_snapshot(fire_time, segment_time, view_delay)
	local hitbox_padding = get_hitbox_padding(config)
	local rewind_hit = lag_compensation_service.find_segment_hit(snapshot, shooter, segment_origin, segment, hitbox_padding)
	if not rewind_hit then
		return nil
	end
	local refined_alpha = math.clamp(rewind_hit.distance / segment_length, 0, 1)
	local refined_elapsed = previous_elapsed + step_time * refined_alpha
	local refined_snapshot = lag_compensation_service.get_projectile_snapshot(fire_time, refined_elapsed, view_delay)
	local refined_hit = lag_compensation_service.find_segment_hit(refined_snapshot, shooter, segment_origin, segment, hitbox_padding) or rewind_hit
	local refined_distance = traveled + refined_hit.distance
	local static_blocks_hit = static_result and static_result.hit and static_result.distance < refined_distance
	if static_blocks_hit then
		return nil
	end
	refined_hit.rewound = true
	return make_hit_result(ctx, origin, direction, config, refined_hit, traveled, segment_origin, segment_length, previous_elapsed, step_time, {
		mode = "shooter_view",
		target_time = refined_snapshot and refined_snapshot.time or nil,
		view_delay = refined_snapshot and refined_snapshot.view_delay or view_delay,
		projectile_elapsed = refined_snapshot and refined_snapshot.projectile_elapsed or refined_elapsed,
		hitbox_padding = hitbox_padding,
	})
end

local function get_static_hit(static_params, segment_origin, segment, traveled, velocity)
	local result = workspace:Raycast(segment_origin, segment, static_params)
	if not result then
		return nil
	end
	local distance = traveled + (result.Position - segment_origin).Magnitude
	return {
		hit = result,
		distance = distance,
		position = result.Position,
		velocity = velocity,
	}
end

local function update_projectile_state(state: ProjectileState, elapsed: number, traveled: number, position: Vector3)
	state.elapsed = elapsed
	state.traveled = traveled
	state.position = position
end

local function finish_projectile(state: ProjectileState)
	state.finished = true
	return state
end

local function cast_catchup(ctx, shooter, origin: Vector3, direction: Vector3, config: any, fire_time: any, view_delay: number, catchup_elapsed: number, static_params: RaycastParams): (any?, ProjectileState)
	local step_time = get_step_time(config)
	local max_flight_time = get_max_flight_time(config)
	local target_elapsed = math.min(catchup_elapsed, max_flight_time)
	local elapsed = 0
	local traveled = 0
	local previous_position = origin
	local state = {
		elapsed = 0,
		traveled = 0,
		position = origin,
		finished = false,
	}

	while elapsed < target_elapsed do
		local previous_elapsed = elapsed
		local current_step_time = math.min(step_time, target_elapsed - elapsed)
		elapsed += current_step_time
		local position, segment, segment_length = get_projectile_segment(ctx, origin, direction, config, previous_position, elapsed)
		if segment_length <= 0 then
			previous_position = position
			continue
		end
		local velocity = get_projectile_values(ctx, origin, direction, config, elapsed).velocity
		local static_result = get_static_hit(static_params, previous_position, segment, traveled, velocity)
		local compensated_hit = find_compensated_hit(ctx, shooter, origin, direction, config, fire_time, view_delay, previous_position, segment, traveled, previous_elapsed, current_step_time, static_result)
		if compensated_hit then
			return compensated_hit, state
		end
		if static_result then
			finish_projectile(state)
			return static_result, state
		end
		traveled += segment_length
		update_projectile_state(state, elapsed, traveled, position)
		if traveled >= config.max_distance then
			finish_projectile(state)
			break
		end

		previous_position = position
	end

	if elapsed >= max_flight_time then
		finish_projectile(state)
	end

	return nil, state
end

local active_live_projectiles = {}

local function emit_late_result(on_late_result, direction: Vector3, result)
	task.defer(on_late_result, {
		direction = direction,
		result = result,
	})
end

local function step_live_projectile(live, frame_time: number): boolean
	if not live.player.Parent or not live.character.Parent then
		return true
	end

	local remaining_time = frame_time
	while remaining_time > 0
		and live.elapsed < live.max_flight_time
		and live.traveled < live.config.max_distance
	do
		local current_step_time = math.min(live.step_time, remaining_time)
		local previous_elapsed = live.elapsed
		live.elapsed += current_step_time
		remaining_time -= current_step_time

		local position, segment, segment_length = get_projectile_segment(
			live.ctx,
			live.origin,
			live.direction,
			live.config,
			live.previous_position,
			live.elapsed
		)
		if segment_length <= 0 then
			live.previous_position = position
			continue
		end

		local velocity = get_projectile_values(
			live.ctx,
			live.origin,
			live.direction,
			live.config,
			live.elapsed
		).velocity
		local static_result = get_static_hit(
			live.static_params,
			live.previous_position,
			segment,
			live.traveled,
			velocity
		)
		local compensated_hit = find_compensated_hit(
			live.ctx,
			live.player,
			live.origin,
			live.direction,
			live.config,
			live.fire_time,
			live.view_delay,
			live.previous_position,
			segment,
			live.traveled,
			previous_elapsed,
			current_step_time,
			static_result
		)
		live.traveled += segment_length
		if compensated_hit then
			emit_late_result(live.on_late_result, live.direction, compensated_hit)
			return true
		end
		if static_result then
			emit_late_result(live.on_late_result, live.direction, static_result)
			return true
		end
		live.previous_position = position
	end

	return live.elapsed >= live.max_flight_time or live.traveled >= live.config.max_distance
end

RunService.Heartbeat:Connect(function(delta_time)
	for index = #active_live_projectiles, 1, -1 do
		local live = active_live_projectiles[index]
		if step_live_projectile(live, delta_time) then
			local last = #active_live_projectiles
			active_live_projectiles[index] = active_live_projectiles[last]
			active_live_projectiles[last] = nil
		end
	end
end)

local function simulate_live(ctx, player, character: Model, origin: Vector3, direction: Vector3, config: any, fire_time: any, view_delay: number, static_params: RaycastParams, state: ProjectileState, on_late_result)
	if state.finished or not on_late_result then
		return
	end
	table.insert(active_live_projectiles, {
		ctx = ctx,
		player = player,
		character = character,
		origin = origin,
		direction = direction,
		config = config,
		fire_time = fire_time,
		view_delay = view_delay,
		static_params = static_params,
		on_late_result = on_late_result,
		step_time = get_step_time(config),
		max_flight_time = get_max_flight_time(config),
		elapsed = state.elapsed,
		traveled = state.traveled,
		previous_position = state.position,
	})
end

function weapon_hit_scan_service.cast(ctx, player, character: Model, origin: Vector3, directions: { Vector3 }, config: any, fire_time: any, on_late_result): { HitScanResult }
	local static_params = get_static_params(ctx, character)
	local view_delay = lag_compensation_service.get_shooter_view_delay(player)
	local catchup_elapsed = get_elapsed_since_fire(fire_time)
	local results = table.create(#directions)

	for _, direction in directions do
		local catchup_result, state = cast_catchup(ctx, player, origin, direction, config, fire_time, view_delay, catchup_elapsed, static_params)

		if catchup_result then
			table.insert(results, {
				direction = direction,
				result = catchup_result,
			})
		elseif state.finished then
			table.insert(results, {
				direction = direction,
				result = {
					hit = nil,
					distance = state.traveled,
					position = state.position,
					time = state.elapsed,
					velocity = get_projectile_values(ctx, origin, direction, config, state.elapsed).velocity,
				},
			})
		else
			simulate_live(ctx, player, character, origin, direction, config, fire_time, view_delay, static_params, state, on_late_result)
		end
	end

	return results
end

return weapon_hit_scan_service
