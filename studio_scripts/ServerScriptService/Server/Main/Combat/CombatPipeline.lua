local combat_pipeline = {}
combat_pipeline.__index = combat_pipeline

function combat_pipeline.new(actor_registry, driver_registry, event_stream)
	return setmetatable({
		actor_registry = actor_registry,
		driver_registry = driver_registry,
		event_stream = event_stream,
		active_operations = setmetatable({}, { __mode = "k" }),
	}, combat_pipeline)
end

local function reject(code)
	return {
		ok = false,
		code = code,
	}
end

function combat_pipeline:cancel_actor(entity, reason)
	local operation = self.active_operations[entity]
	self.active_operations[entity] = nil
	if operation and type(operation.cancel) == "function" then
		operation:cancel(reason or "cancelled")
	end
	if operation then
		self.event_stream:emit("activation_cancelled", {
			actor = entity,
			item_id = operation.item_id,
			driver_id = operation.driver_id,
			reason = reason or "cancelled",
		})
	end
end

function combat_pipeline:activate(entity, driver_id, action)
	local actor = self.actor_registry:get(entity)
	if not actor then
		return reject("actor_unavailable")
	end
	if not actor:is_alive() then
		return reject("actor_dead")
	end
	if actor:is_blocked() then
		self:cancel_actor(entity, "actor_blocked")
		return reject("actor_blocked")
	end
	if type(action) ~= "table" or type(action.item_id) ~= "string" or action.item_id == "" then
		return reject("bad_action")
	end
	if action.requires_equipped ~= false and actor:get_equipped_item() ~= action.item_id then
		return reject("item_not_equipped")
	end
	local driver = self.driver_registry:get(driver_id)
	if not driver then
		return reject("driver_unavailable")
	end
	local valid, validated_or_code = driver:validate(actor, action)
	if not valid then
		return reject(validated_or_code or "activation_rejected")
	end
	local validated = validated_or_code or action
	self.event_stream:emit("activation_started", {
		actor = entity,
		item_id = action.item_id,
		driver_id = driver_id,
	})
	local ok, result = driver:activate(actor, validated)
	if not ok then
		self.event_stream:emit("activation_rejected", {
			actor = entity,
			item_id = action.item_id,
			driver_id = driver_id,
			code = result,
		})
		return reject(result or "activation_failed")
	end
	if type(result) == "table" and type(result.cancel) == "function" then
		result.item_id = action.item_id
		result.driver_id = driver_id
		self.active_operations[entity] = result
	end
	self.event_stream:emit("activation_finished", {
		actor = entity,
		item_id = action.item_id,
		driver_id = driver_id,
	})
	return {
		ok = true,
		result = result,
	}
end

return combat_pipeline

