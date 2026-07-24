local movement_config = {
	BASE_WALK_SPEED = 16,
	SPRINT_SPEED = 24,
	CROUCH_SPEED = 8,
	ADS_SPEED = 9,
	ADS_CROUCH_SPEED = 6,
	CROUCH_HIP_HEIGHT_OFFSET = -1.25,
	CROUCH_CAMERA_OFFSET = Vector3.zero,
	BODY_CAMERA_CROUCH_DROP = 0,
	LEAN_CAMERA_OFFSET = 0.85,
	LEAN_CAMERA_ROLL = 8,
	LEAN_LEFT_VISUAL_MULTIPLIER = 1.25,
	LEAN_SMOOTHING = 12,
	LEAN_WALL_PADDING = 0.15,
	LEAN_CHARACTER_OFFSET = 0.25,
	LEAN_CHARACTER_ROLL = 10,
	CROUCH_CAMERA_SHAKE_ANGLE = 0.04,
	CROUCH_CAMERA_IMPACT_ANGLE = 0.22,
	CROUCH_VIEWMODEL_DROP = 0.08,
	CROUCH_VIEWMODEL_SHAKE_AMOUNT = 0.008,
	CROUCH_VIEWMODEL_IMPACT_AMOUNT = 0.022,
	GRAVITY = 196.2,
	MAX_FALL_SPEED = 150,
	GROUND_SNAP_DISTANCE = 0.35,
	SERVER_ENFORCEMENT_INTERVAL = 0.2,
	SERVER_HARD_CORRECTION_DISTANCE = 4,
	COMMAND_STEP = 1 / 30,
	MIN_COMMAND_DT = 1 / 120,
	MAX_COMMAND_DT = 1 / 15,
	MAX_SEQUENCE_GAP = 64,
	COMMAND_TIME_GRACE = 0.2,
}

function movement_config.get_speed(crouching: boolean, sprinting: boolean, aiming: boolean): number
	if crouching then
		return aiming and movement_config.ADS_CROUCH_SPEED or movement_config.CROUCH_SPEED
	end
	if aiming then
		return movement_config.ADS_SPEED
	end
	if sprinting then
		return movement_config.SPRINT_SPEED
	end
	return movement_config.BASE_WALK_SPEED
end

return table.freeze(movement_config)

