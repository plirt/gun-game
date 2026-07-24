-- Shared deterministic movement kernel used by prediction, server authority, and replay.
-- Callers provide the same command/state pair, so reconciliation can roll back and replay
-- without duplicating movement rules on each side of the network boundary.
--
-- World collision queries are intentionally sampled from the caller's current DataModel;
-- moving platforms are therefore reconciled by authoritative snapshots, not predicted history.

local MovementConfig = require(script.Parent.MovementConfig)

local movement_simulation = {}

local COLLISION_SKIN = 0.04
local MAX_SLIDE_ITERATIONS = 2
local STEP_HEIGHT = 1.25

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function with_position(cframe: CFrame, position: Vector3): CFrame
	return CFrame.new(position) * cframe.Rotation
end

local function try_step(
	cframe: CFrame,
	size: Vector3,
	displacement: Vector3,
	ground_clearance: number,
	raycast_params: RaycastParams
): CFrame?
	local up = Vector3.yAxis * STEP_HEIGHT
	if workspace:Blockcast(cframe, size, up, raycast_params) then
		return nil
	end
	local raised = cframe + up
	if workspace:Blockcast(raised, size, displacement, raycast_params) then
		return nil
	end
	local advanced = raised + displacement
	local floor = workspace:Raycast(
		advanced.Position + Vector3.yAxis * COLLISION_SKIN,
		-Vector3.yAxis * (ground_clearance + STEP_HEIGHT + COLLISION_SKIN),
		raycast_params
	)
	if not floor or floor.Normal.Y < 0.35 then
		return nil
	end
	local position = Vector3.new(
		advanced.Position.X,
		floor.Position.Y + ground_clearance,
		advanced.Position.Z
	)
	return with_position(advanced, position)
end

function movement_simulation.get_ground_clearance(character: Model, root: BasePart): number
	local lowest_local_y = -root.Size.Y * 0.5
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and child ~= root then
			local local_position = root.CFrame:PointToObjectSpace(child.Position)
			lowest_local_y = math.min(lowest_local_y, local_position.Y - child.Size.Y * 0.5)
		end
	end
	return math.max(-lowest_local_y, root.Size.Y * 0.5 + COLLISION_SKIN)
end

function movement_simulation.step(
	start_cframe: CFrame,
	root_size: Vector3,
	move_direction: Vector3,
	delta_time: number,
	speed: number,
	vertical_velocity: number,
	grounded: boolean,
	ground_clearance: number,
	max_ground_clearance: number,
	raycast_params: RaycastParams
): (CFrame, number, boolean)
	if delta_time <= 0 then
		return start_cframe, vertical_velocity, grounded
	end

	local direction = horizontal(move_direction)
	if direction.Magnitude > 1 then
		direction = direction.Unit
	end
	local current = start_cframe
	local cast_size = Vector3.new(
		math.max(root_size.X * 0.82, 0.5),
		math.max(root_size.Y * 0.9, 1),
		math.max(root_size.Z * 0.82, 0.5)
	)

	if direction.Magnitude > 1e-4 and speed > 0 then
		local remaining = direction * speed * delta_time
		for _ = 1, MAX_SLIDE_ITERATIONS do
			if remaining.Magnitude <= 1e-4 then
				break
			end
			local hit = workspace:Blockcast(current, cast_size, remaining, raycast_params)
			if not hit then
				current = current + remaining
				break
			end

			if math.abs(hit.Normal.Y) < 0.35 then
				local stepped = try_step(current, cast_size, remaining, ground_clearance, raycast_params)
				if stepped then
					current = stepped
					grounded = true
					vertical_velocity = 0
					break
				end
			end

			local direction_unit = remaining.Unit
			local traveled = math.max(hit.Distance - COLLISION_SKIN, 0)
			current = current + direction_unit * traveled
			local leftover = remaining - direction_unit * traveled
			remaining = horizontal(leftover - hit.Normal * leftover:Dot(hit.Normal))
		end
	end

	vertical_velocity = math.max(
		vertical_velocity - MovementConfig.GRAVITY * delta_time,
		-MovementConfig.MAX_FALL_SPEED
	)
	local vertical_displacement = vertical_velocity * delta_time
	if vertical_displacement > 0 then
		local upward = Vector3.yAxis * vertical_displacement
		local ceiling = workspace:Blockcast(current, cast_size, upward, raycast_params)
		if ceiling then
			local traveled = math.max(ceiling.Distance - COLLISION_SKIN, 0)
			current += Vector3.yAxis * traveled
			vertical_velocity = 0
		else
			current += upward
		end
		grounded = false
	else
		local target_y = current.Position.Y + vertical_displacement
		local probe_distance = math.max(ground_clearance, max_ground_clearance)
			+ STEP_HEIGHT
			+ math.abs(vertical_displacement)
			+ MovementConfig.GROUND_SNAP_DISTANCE
		local floor = workspace:Raycast(
			current.Position + Vector3.yAxis * COLLISION_SKIN,
			-Vector3.yAxis * probe_distance,
			raycast_params
		)
		if floor and floor.Normal.Y >= 0.35 then
			local floor_y = floor.Position.Y + ground_clearance
			local can_snap = grounded
				and target_y - floor_y <= MovementConfig.GROUND_SNAP_DISTANCE
			if target_y <= floor_y or can_snap then
				target_y = floor_y
				vertical_velocity = 0
				grounded = true
			else
				grounded = false
			end
		else
			grounded = false
		end
		current = with_position(current, Vector3.new(current.Position.X, target_y, current.Position.Z))
	end

	return with_position(start_cframe, current.Position), vertical_velocity, grounded
end

return movement_simulation

