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

local function try_step(cframe: CFrame, size: Vector3, displacement: Vector3, raycast_params: RaycastParams): CFrame?
	local up = Vector3.yAxis * STEP_HEIGHT
	if workspace:Blockcast(cframe, size, up, raycast_params) then
		return nil
	end
	local raised = cframe + up
	if workspace:Blockcast(raised, size, displacement, raycast_params) then
		return nil
	end
	local advanced = raised + displacement
	local down = -Vector3.yAxis * (STEP_HEIGHT + COLLISION_SKIN)
	local floor = workspace:Blockcast(advanced, size, down, raycast_params)
	if not floor then
		return nil
	end
	return advanced + down.Unit * math.max(floor.Distance - COLLISION_SKIN, 0)
end

function movement_simulation.step(
	start_cframe: CFrame,
	root_size: Vector3,
	move_direction: Vector3,
	delta_time: number,
	speed: number,
	raycast_params: RaycastParams
): CFrame
	local direction = horizontal(move_direction)
	if direction.Magnitude > 1 then
		direction = direction.Unit
	end
	if direction.Magnitude <= 1e-4 or delta_time <= 0 or speed <= 0 then
		return start_cframe
	end

	local remaining = direction * speed * delta_time
	local current = start_cframe
	local cast_size = Vector3.new(
		math.max(root_size.X * 0.82, 0.5),
		math.max(root_size.Y * 0.9, 1),
		math.max(root_size.Z * 0.82, 0.5)
	)

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
			local stepped = try_step(current, cast_size, remaining, raycast_params)
			if stepped then
				current = stepped
				break
			end
		end

		local direction_unit = remaining.Unit
		local traveled = math.max(hit.Distance - COLLISION_SKIN, 0)
		current = current + direction_unit * traveled
		local leftover = remaining - direction_unit * traveled
		remaining = horizontal(leftover - hit.Normal * leftover:Dot(hit.Normal))
	end

	return with_position(start_cframe, current.Position)
end

return movement_simulation
