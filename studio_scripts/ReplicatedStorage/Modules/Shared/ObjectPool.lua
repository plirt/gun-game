export type reset_callback<T> = (object: T) -> ()

export type prepare_callback<T> = (object: T) -> ()

export type create_pool_params<T> = {
	title: string?,
	count: number,
	template: T,
	parent: Instance?,
	prewarm: boolean?,
	allow_growth: boolean?,
	growth_limit: number?,
	reset: reset_callback<T>?,
	prepare: prepare_callback<T>?,
}

export type pool_stats = {
	capacity: number,
	allocated: number,
	available: number,
	active: number,
	allow_growth: boolean,
	destroyed: boolean,
}

export type object_pool_record<T> = {
	available: { T },
	available_lookup: { [Instance]: boolean },
	active_lookup: { [Instance]: T },
	template: T,
	capacity: number,
	allocated_count: number,
	active_count: number,
	allow_growth: boolean,
	growth_limit: number,
	destroyed: boolean,
	default_parent: Instance?,
	reset_callback: reset_callback<T>?,
	prepare_callback: prepare_callback<T>?,
}

local object_pool = {}

local function assert_instance(value: any, label: string): Instance
	assert(typeof(value) == "Instance", label .. " must be an Instance")
	return value
end

local function reset_base_part(base_part: BasePart)
	base_part.CFrame = CFrame.identity
	base_part.Anchored = true
	base_part.AssemblyLinearVelocity = Vector3.zero
	base_part.AssemblyAngularVelocity = Vector3.zero
	base_part.Transparency = 1
end

local function reset_instance(instance: Instance)
	if instance:IsA("BasePart") then
		reset_base_part(instance)
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			reset_base_part(descendant)
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		elseif descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end
end

local function can_allocate<T>(pool: object_pool_record<T>): boolean
	if pool.destroyed then
		return false
	end

	if pool.allocated_count < pool.capacity then
		return true
	end
	return pool.allow_growth and pool.allocated_count < pool.growth_limit
end

local function clone_to_pool<T>(pool: object_pool_record<T>): T?
	if not can_allocate(pool) then
		return nil
	end

	local object = (pool.template :: any):Clone() :: T
	local instance = assert_instance(object, "pooled object")

	if pool.reset_callback then
		pool.reset_callback(object)
	else
		reset_instance(instance)
	end

	instance.Parent = nil
	pool.allocated_count += 1
	pool.available_lookup[instance] = true
	table.insert(pool.available, object)
	return object
end

function object_pool.create<T>(params: create_pool_params<T>): object_pool_record<T>
	assert(params ~= nil, "object_pool.Create requires params")
	assert(type(params.count) == "number" and params.count > 0, "object_pool count must be greater than 0")
	assert(params.template ~= nil, "object_pool requires a template")

	assert_instance(params.template, "object_pool template")

	local growth_limit = params.growth_limit or params.count
	local allow_growth = params.allow_growth == true and growth_limit > params.count

	local pool: object_pool_record<T> = {
		available = {},
		available_lookup = {},
		active_lookup = {},
		template = params.template,
		capacity = params.count,
		allocated_count = 0,
		active_count = 0,
		allow_growth = allow_growth,
		growth_limit = math.max(params.count, growth_limit),
		destroyed = false,
		default_parent = params.parent,
		reset_callback = params.reset,
		prepare_callback = params.prepare,
	}

	if params.prewarm then
		for _ = 1, params.count do
			clone_to_pool(pool)
		end
	end
	return pool
end

function object_pool.acquire<T>(pool: object_pool_record<T>, parent: Instance?): T?
	if pool.destroyed then
		warn("cannot acquire from a destroyed object pool")
		return nil
	end

	if #pool.available == 0 and not clone_to_pool(pool) then
		return nil
	end

	local object = table.remove(pool.available)
	if object == nil then
		return nil
	end

	local instance = assert_instance(object, "pooled object")
	pool.available_lookup[instance] = nil
	pool.active_lookup[instance] = object
	pool.active_count += 1

	if pool.prepare_callback then
		pool.prepare_callback(object)
	end

	instance.Parent = parent or pool.default_parent or workspace
	return object
end

function object_pool.release<T>(pool: object_pool_record<T>, object: T?)
	if object == nil or pool.destroyed then
		return
	end

	local instance = assert_instance(object, "pooled object")

	if pool.available_lookup[instance] then
		return
	end

	if not pool.active_lookup[instance] then
		warn("cannot release object that does not belong to this pool:", instance:GetFullName())
		return
	end

	pool.active_lookup[instance] = nil
	pool.active_count = math.max(0, pool.active_count - 1)

	if pool.reset_callback then
		pool.reset_callback(object)
	else
		reset_instance(instance)
	end

	instance.Parent = nil
	pool.available_lookup[instance] = true
	table.insert(pool.available, object)
end

function object_pool.release_all<T>(pool: object_pool_record<T>)
	local active_objects = {}

	for _, object in pool.active_lookup do
		table.insert(active_objects, object)
	end

	for _, object in active_objects do
		object_pool.release(pool, object)
	end
end

function object_pool.resize<T>(pool: object_pool_record<T>, capacity: number, growth_limit: number?)
	assert(type(capacity) == "number" and capacity > 0, "object_pool capacity must be greater than 0")

	pool.capacity = capacity
	pool.growth_limit = math.max(capacity, growth_limit or pool.growth_limit)
	pool.allow_growth = pool.growth_limit > pool.capacity

	while pool.allocated_count > pool.capacity and #pool.available > 0 do
		local object = table.remove(pool.available)
		local instance = assert_instance(object, "pooled object")
		pool.available_lookup[instance] = nil
		pool.allocated_count -= 1
		instance:Destroy()
	end
end

function object_pool.get_stats<T>(pool: object_pool_record<T>): pool_stats
	return {
		capacity = pool.capacity,
		allocated = pool.allocated_count,
		available = #pool.available,
		active = pool.active_count,
		allow_growth = pool.allow_growth,
		destroyed = pool.destroyed,
	}
end

function object_pool.delete<T>(pool: object_pool_record<T>)
	if pool.destroyed then
		return
	end

	pool.destroyed = true

	for _, object in pool.available do
		local instance = assert_instance(object, "pooled object")
		instance:Destroy()
	end

	for instance in pool.active_lookup do
		instance:Destroy()
	end

	table.clear(pool.available)
	table.clear(pool.available_lookup)
	table.clear(pool.active_lookup)
	pool.allocated_count = 0
	pool.active_count = 0
end

function object_pool.create_pool<T>(params: create_pool_params<T>): object_pool_record<T>
	return object_pool.create(params)
end

function object_pool.get_object<T>(pool: object_pool_record<T>, overwritten_parent: Instance?): T?
	return object_pool.acquire(pool, overwritten_parent)
end

function object_pool.release_object<T>(pool: object_pool_record<T>, object: T?)
	object_pool.release(pool, object)
end
return object_pool



