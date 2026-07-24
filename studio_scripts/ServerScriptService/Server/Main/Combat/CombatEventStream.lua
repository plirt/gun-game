local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RingBuffer = require(ReplicatedStorage.Modules.Shared.Framework.RingBuffer)

local combat_event_stream = {}
combat_event_stream.__index = combat_event_stream

function combat_event_stream.new(capacity)
	return setmetatable({
		sequence = 0,
		listeners = {},
		all_listeners = {},
		history = RingBuffer.new(capacity or 1024),
	}, combat_event_stream)
end

local function make_connection(bucket, callback)
	local connected = true
	return {
		disconnect = function()
			if not connected then
				return
			end
			connected = false
			bucket[callback] = nil
		end,
	}
end

function combat_event_stream:subscribe(event_name, callback)
	assert(type(event_name) == "string" and event_name ~= "", "event_name is required")
	assert(type(callback) == "function", "callback is required")
	local bucket = self.listeners[event_name]
	if not bucket then
		bucket = {}
		self.listeners[event_name] = bucket
	end
	bucket[callback] = true
	return make_connection(bucket, callback)
end

function combat_event_stream:subscribe_all(callback)
	assert(type(callback) == "function", "callback is required")
	self.all_listeners[callback] = true
	return make_connection(self.all_listeners, callback)
end

local function dispatch(bucket, event)
	if not bucket then
		return
	end
	local callbacks = {}
	for callback in bucket do
		table.insert(callbacks, callback)
	end
	for _, callback in callbacks do
		local ok, err = pcall(callback, event)
		if not ok then
			warn(err)
		end
	end
end

function combat_event_stream:emit(event_name, payload)
	self.sequence += 1
	local event = table.clone(payload or {})
	event.type = event_name
	event.sequence = self.sequence
	event.time = event.time or workspace:GetServerTimeNow()
	table.freeze(event)
	self.history:push(event)
	dispatch(self.listeners[event_name], event)
	dispatch(self.all_listeners, event)
	return event
end

function combat_event_stream:get_since(oldest_time, predicate)
	local events = {}
	for _, event in self.history:values() do
		if event.time >= oldest_time and (not predicate or predicate(event)) then
			table.insert(events, event)
		end
	end
	return events
end

function combat_event_stream:clear()
	self.history:clear()
end

return combat_event_stream

