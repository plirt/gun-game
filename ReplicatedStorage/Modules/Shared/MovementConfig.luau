local movement_config = {
	BASE_WALK_SPEED = 16,
	SPRINT_SPEED = 24,
	CROUCH_SPEED = 8,
	ADS_SPEED = 9,
	ADS_CROUCH_SPEED = 6,
	SERVER_ENFORCEMENT_INTERVAL = 0.1,
	REMOTE_UPDATE_INTERVAL = 0.08,
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
