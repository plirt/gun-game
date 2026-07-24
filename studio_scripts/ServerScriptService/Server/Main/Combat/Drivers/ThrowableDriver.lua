local throwable_driver = {}
throwable_driver.__index = throwable_driver

function throwable_driver.new(event_stream)
	return setmetatable({
		event_stream = event_stream,
	}, throwable_driver)
end

function throwable_driver:validate(actor, action)
	if type(action.execute) ~= "function" or typeof(action.direction) ~= "Vector3" then
		return false, "bad_throwable_action"
	end
	if action.direction.Magnitude <= 0 then
		return false, "bad_direction"
	end
	action.direction = action.direction.Unit
	return true, action
end

function throwable_driver:activate(actor, action)
	local entity = actor:get_entity()
	self.event_stream:emit("throwable_activated", {
		actor = entity,
		item_id = action.item_id,
		direction = action.direction,
	})
	local ok, result = action.execute(actor, action, self.event_stream)
	if not ok then
		return false, result
	end
	return true, result
end

return throwable_driver

