local AttachmentEffects = {}

local EFFECTS = {
	ACOG = {
		display_name = "ACOG",
		description = "Heavy optic with slower ADS handling.",
		modifiers = {
			ads_score = 0.58,
		},
	},
	HolographicA = {
		display_name = "Holographic A",
		description = "Light optic with faster ADS handling.",
		modifiers = {
			ads_score = 0.74,
		},
	},
	VerticalGrip = {
		display_name = "Vertical Grip",
		description = "Improves recoil control and steadies spread.",
		modifiers = {
			recoil_viewmodel_climb = 0.78,
			recoil_viewmodel_pitch = 0.82,
			recoil_viewmodel_yaw = 0.74,
			recoil_viewmodel_roll = 0.78,
			recoil_camera_yaw = 0.78,
			recoil_camera_roll = 0.85,
			recoil_tip_pivot_multiplier = 0.86,
			recoil_ads_tip_pivot_multiplier = 0.9,
			spread_hip = 0.9,
			spread_aim = 0.94,
			spread_per_shot = 0.88,
		},
	},
}

local function apply_modifier(config, key, value)
	local current = config[key]
	if type(current) == "number" and type(value) == "number" then
		config[key] = current * value
	else
		config[key] = value
	end
end

function AttachmentEffects.get(attachment_name)
	return EFFECTS[attachment_name]
end

function AttachmentEffects.apply(config, attachments)
	local result = table.clone(config)
	for _, attachment_name in attachments or {} do
		local effect = EFFECTS[attachment_name]
		if effect and effect.modifiers then
			for key, value in effect.modifiers do
				apply_modifier(result, key, value)
			end
		end
	end

	return result
end

function AttachmentEffects.describe(attachment_name)
	local effect = EFFECTS[attachment_name]
	if not effect then
		return nil
	end

	return {
		display_name = effect.display_name,
		description = effect.description,
		modifiers = table.clone(effect.modifiers or {}),
	}
end

return AttachmentEffects

