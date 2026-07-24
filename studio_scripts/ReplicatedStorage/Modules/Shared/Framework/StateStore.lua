-- StateStore owns declared mutable state behind a small observable API.
-- Why: passing one table that mixes services, callbacks, constants, and mutable gameplay
-- fields creates invisible coupling. A declared store lets controllers share state while
-- keeping service dependencies in RuntimeGraph.
--
-- Compatibility: bind_facade can expose declared keys through an existing context table.
-- This supports incremental migration; new systems should receive the store directly.

local state_store = {}
state_store.__index = state_store

function state_store.new(initial_values: { [string]: any }?, declared_keys: { string }?)
	local declared = {}
	for _, key in declared_keys or {} do
		assert(type(key) == "string" and key ~= "", "state keys must be non-empty strings")
		declared[key] = true
	end
	for key in initial_values or {} do
		declared[key] = true
	end
	return setmetatable({
		values = table.clone(initial_values or {}),
		declared = declared,
		listeners = {},
		version = 0,
	}, state_store)
end

function state_store:has(key: string): boolean
	return self.declared[key] == true
end

function state_store:get(key: string)
	assert(self:has(key), string.format("undeclared state key %s", key))
	return self.values[key]
end

function state_store:set(key: string, value: any)
	assert(self:has(key), string.format("undeclared state key %s", key))
	local previous = self.values[key]
	if previous == value then
		return false
	end
	self.values[key] = value
	self.version += 1
	local listeners = self.listeners[key]
	if listeners then
		for callback in listeners do
			callback(value, previous, self.version)
		end
	end
	return true
end

function state_store:update(key: string, transform: (any) -> any)
	return self:set(key, transform(self:get(key)))
end

function state_store:subscribe(key: string, callback: (any, any, number) -> ())
	assert(self:has(key), string.format("undeclared state key %s", key))
	assert(type(callback) == "function", "listener must be a function")
	local listeners = self.listeners[key]
	if not listeners then
		listeners = {}
		self.listeners[key] = listeners
	end
	listeners[callback] = true
	local connected = true
	return function()
		if connected then
			connected = false
			listeners[callback] = nil
		end
	end
end

function state_store:snapshot()
	return table.clone(self.values)
end

function state_store.bind_facade(store, facade: { [any]: any })
	return setmetatable(facade, {
		__index = function(_, key)
			if type(key) == "string" and store:has(key) then
				return store:get(key)
			end
			return nil
		end,
		__newindex = function(target, key, value)
			if type(key) == "string" and store:has(key) then
				store:set(key, value)
			else
				rawset(target, key, value)
			end
		end,
	})
end

return state_store

