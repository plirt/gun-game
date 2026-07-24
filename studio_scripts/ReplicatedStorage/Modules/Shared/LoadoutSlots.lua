local loadout_slots = {}

local slots = {
	{ id = 1, key = "primary", display_name = "Primary", category = "firearm", key_code = Enum.KeyCode.One },
	{ id = 2, key = "secondary", display_name = "Secondary", category = "firearm", key_code = Enum.KeyCode.Two },
	{ id = 3, key = "utility", display_name = "Utility", category = "utility", key_code = Enum.KeyCode.Three },
}

local by_id = {}
for _, slot in slots do
	by_id[slot.id] = slot
end

function loadout_slots.get_all()
	return slots
end

function loadout_slots.get(slot_id)
	return by_id[slot_id]
end

function loadout_slots.get_count()
	return #slots
end

function loadout_slots.create_empty()
	local loadout = {}
	for _, slot in slots do
		loadout[slot.id] = ""
	end
	return loadout
end

function loadout_slots.accepts(slot_id, category)
	local slot = by_id[slot_id]
	return slot ~= nil and slot.category == category
end

function loadout_slots.find_other_slot(slot_id, category)
	for _, slot in slots do
		if slot.id ~= slot_id and slot.category == category then
			return slot.id
		end
	end
	return nil
end

return loadout_slots

