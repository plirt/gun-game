local AttachmentEffects = require(script.Parent.AttachmentEffects)

local AttachmentCatalog = {}

local SLOT_ORDER = { "Sight", "Grip", "Barrel" }
local SLOT_INFO = {
	Sight = {
		order = 1,
		label = "Sight",
		short = "S",
		color = Color3.fromRGB(245, 245, 245),
		baseline = { ads = 0.72, control = 0.5, spread = 0.5 },
	},
	Grip = {
		order = 2,
		label = "Grip",
		short = "G",
		color = Color3.fromRGB(245, 245, 245),
		baseline = { ads = 0.5, control = 0.64, spread = 0.58 },
	},
	Barrel = {
		order = 3,
		label = "Barrel",
		short = "B",
		color = Color3.fromRGB(245, 245, 245),
		baseline = { ads = 0.48, control = 0.56, spread = 0.64 },
	},
}

local DEFAULT_SLOT = {
	order = 20,
	label = "Module",
	short = "M",
	color = Color3.fromRGB(245, 245, 245),
	baseline = { ads = 0.5, control = 0.5, spread = 0.5 },
}

local function copy_score(score)
	return {
		ads = score.ads or 0.5,
		control = score.control or 0.5,
		spread = score.spread or 0.5,
	}
end

local function slot_info(attachment_type)
	return SLOT_INFO[attachment_type] or DEFAULT_SLOT
end

local function score_from_modifiers(attachment_type, modifiers)
	local info = slot_info(attachment_type)
	local score = copy_score(info.baseline)
	if type(modifiers) ~= "table" then
		return score
	end

	local recoil_values = {
		modifiers.recoil_viewmodel_climb,
		modifiers.recoil_viewmodel_pitch,
		modifiers.recoil_viewmodel_yaw,
		modifiers.recoil_camera_yaw,
		modifiers.recoil_camera_roll,
	}
	local recoil_sum = 0
	local recoil_count = 0
	for _, value in recoil_values do
		if type(value) == "number" then
			recoil_sum += 1 - value
			recoil_count += 1
		end
	end
	if recoil_count > 0 then
		score.control = math.clamp(score.control + recoil_sum / recoil_count, 0.08, 1)
	end

	local spread_values = {
		modifiers.spread_hip,
		modifiers.spread_aim,
		modifiers.spread_per_shot,
	}
	local spread_sum = 0
	local spread_count = 0
	for _, value in spread_values do
		if type(value) == "number" then
			spread_sum += 1 - value
			spread_count += 1
		end
	end
	if spread_count > 0 then
		score.spread = math.clamp(score.spread + spread_sum / spread_count, 0.08, 1)
	end

	if type(modifiers.ads_score) == "number" then
		score.ads = math.clamp(modifiers.ads_score, 0.08, 1)
	elseif type(modifiers.ads_time) == "number" then
		score.ads = math.clamp(score.ads + (1 - modifiers.ads_time), 0.08, 1)
	end
	return score
end

function AttachmentCatalog.get_slot_info(attachment_type)
	local info = slot_info(attachment_type)
	return {
		order = info.order,
		label = info.label,
		short = info.short,
		color = info.color,
		baseline = copy_score(info.baseline),
	}
end

function AttachmentCatalog.get_slot_order(attachment_type)
	return slot_info(attachment_type).order
end

function AttachmentCatalog.get_slot_color(attachment_type)
	return slot_info(attachment_type).color
end

function AttachmentCatalog.get_slot_short(attachment_type)
	return slot_info(attachment_type).short
end

function AttachmentCatalog.sort_types(types)
	table.sort(types, function(a, b)
		local order_a = AttachmentCatalog.get_slot_order(a)
		local order_b = AttachmentCatalog.get_slot_order(b)
		if order_a == order_b then
			return a < b
		end
		return order_a < order_b
	end)
	return types
end

function AttachmentCatalog.get_known_slots()
	return table.clone(SLOT_ORDER)
end

function AttachmentCatalog.describe_attachment(attachment)
	local effect = AttachmentEffects.describe(attachment.name)
	local attachment_type = attachment.type
	local info = slot_info(attachment_type)
	local description = effect and effect.description or (info.label .. " attachment")
	return {
		name = attachment.name,
		display_name = attachment.display_name,

		type = attachment_type,
		description = description,
		color = info.color,
		short = info.short,
		score = score_from_modifiers(attachment_type, effect and effect.modifiers),
		modifiers = effect and effect.modifiers or {},
	}
end

function AttachmentCatalog.get_build_score(attachments)
	local score = { ads = 0.5, control = 0.5, spread = 0.5 }
	local count = 0
	for attachment_type, attachment_name in attachments or {} do
		if attachment_name and attachment_name ~= "" then
			local info = slot_info(attachment_type)
			local effect = AttachmentEffects.describe(attachment_name)
			local attachment_score = score_from_modifiers(attachment_type, effect and effect.modifiers)
			score.ads += attachment_score.ads - 0.5
			score.control += attachment_score.control - 0.5
			score.spread += attachment_score.spread - 0.5
			count += 1
		end
	end
	if count == 0 then
		return score
	end
	return {
		ads = math.clamp(score.ads, 0.08, 1),
		control = math.clamp(score.control, 0.08, 1),
		spread = math.clamp(score.spread, 0.08, 1),
	}
end
return AttachmentCatalog


