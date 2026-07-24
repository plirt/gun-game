-- RingBuffer provides bounded, allocation-stable history storage for high-frequency systems.
-- Why: replay and lag compensation need recent history, not unbounded logs. Removing index 1
-- from an array shifts every element and amplifies garbage collection under load.
--
-- Tradeoff: values() materializes an ordered snapshot for consumers that need random access.
-- Hot writers remain O(1); callers should avoid requesting values every frame.

local ring_buffer = {}
ring_buffer.__index = ring_buffer

export type RingBuffer<T> = typeof(setmetatable({} :: {
	capacity: number,
	storage: { T? },
	count: number,
	write_index: number,
}, ring_buffer))

function ring_buffer.new<T>(capacity: number): RingBuffer<T>
	assert(type(capacity) == "number" and capacity >= 1 and capacity % 1 == 0, "capacity must be a positive integer")
	return setmetatable({
		capacity = capacity,
		storage = table.create(capacity),
		count = 0,
		write_index = 0,
	}, ring_buffer)
end

function ring_buffer:push<T>(value: T): T?
	self.write_index = self.write_index % self.capacity + 1
	local evicted = self.count == self.capacity and self.storage[self.write_index] or nil
	self.storage[self.write_index] = value
	self.count = math.min(self.count + 1, self.capacity)
	return evicted
end

function ring_buffer:size(): number
	return self.count
end

function ring_buffer:is_empty(): boolean
	return self.count == 0
end

function ring_buffer:get(logical_index: number)
	if logical_index < 1 or logical_index > self.count then
		return nil
	end
	local oldest_index = (self.write_index - self.count) % self.capacity + 1
	local physical_index = (oldest_index + logical_index - 2) % self.capacity + 1
	return self.storage[physical_index]
end

function ring_buffer:first()
	return self:get(1)
end

function ring_buffer:last()
	return self:get(self.count)
end

function ring_buffer:values<T>(): { T }
	local ordered = table.create(self.count)
	for index = 1, self.count do
		ordered[index] = self:get(index)
	end
	return ordered
end

function ring_buffer:for_each(callback: (any, number) -> ())
	for index = 1, self.count do
		callback(self:get(index), index)
	end
end

function ring_buffer:clear()
	table.clear(self.storage)
	self.count = 0
	self.write_index = 0
end

return ring_buffer

