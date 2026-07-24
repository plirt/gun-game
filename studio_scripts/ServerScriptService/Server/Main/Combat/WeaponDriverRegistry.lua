local weapon_driver_registry = {}
weapon_driver_registry.__index = weapon_driver_registry

function weapon_driver_registry.new()
	return setmetatable({
		drivers = {},
	}, weapon_driver_registry)
end

function weapon_driver_registry:register(driver_id, driver)
	assert(type(driver_id) == "string" and driver_id ~= "", "driver_id is required")
	assert(type(driver) == "table", "driver is required")
	assert(type(driver.validate) == "function", "driver.validate is required")
	assert(type(driver.activate) == "function", "driver.activate is required")
	assert(not self.drivers[driver_id], string.format("driver %s is already registered", driver_id))
	self.drivers[driver_id] = driver
	return driver
end

function weapon_driver_registry:replace(driver_id, driver)
	assert(type(driver_id) == "string" and driver_id ~= "", "driver_id is required")
	assert(type(driver) == "table", "driver is required")
	assert(type(driver.validate) == "function", "driver.validate is required")
	assert(type(driver.activate) == "function", "driver.activate is required")
	self.drivers[driver_id] = driver
	return driver
end

function weapon_driver_registry:get(driver_id)
	return self.drivers[driver_id]
end

function weapon_driver_registry:get_ids()
	local ids = {}
	for driver_id in self.drivers do
		table.insert(ids, driver_id)
	end
	table.sort(ids)
	return ids
end

return weapon_driver_registry

