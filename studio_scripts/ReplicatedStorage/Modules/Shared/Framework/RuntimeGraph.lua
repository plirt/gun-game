-- RuntimeGraph is a small dependency-injection and lifecycle kernel for game systems.
-- Why: implicit setup order through a shared context made services appear decoupled while
-- still depending on fields installed by earlier modules. The graph makes those edges
-- executable: missing services and cycles fail at startup instead of during a match.
--
-- Limits: factories must not yield forever and runtime-only peer lookups should use
-- try_get intentionally. destroy_all provides rollback, but cannot undo unmanaged Roblox
-- connections created by a service that does not expose a destroy method.

local runtime_graph = {}
runtime_graph.__index = runtime_graph

export type Scope = {
	core: { [string]: any },
	get: (Scope, string) -> any,
	try_get: (Scope, string) -> any?,
}

export type RuntimeGraph = typeof(setmetatable({} :: {
	core: { [string]: any },
	definitions: { [string]: any },
	registration_order: { string },
	instances: { [string]: any },
	start_order: { string },
	states: { [string]: string },
	sealed: boolean,
}, runtime_graph))

local function assert_name(name: any)
	assert(type(name) == "string" and name ~= "", "service name must be a non-empty string")
end

function runtime_graph.new(core: { [string]: any }?): RuntimeGraph
	return setmetatable({
		core = core or {},
		definitions = {},
		registration_order = {},
		instances = {},
		start_order = {},
		states = {},
		sealed = false,
	}, runtime_graph)
end

function runtime_graph:register(name: string, dependencies: { string }?, factory: (Scope) -> any)
	assert(not self.sealed, "runtime is sealed")
	assert_name(name)
	assert(self.definitions[name] == nil, string.format("service %s is already registered", name))
	assert(type(factory) == "function", "service factory must be a function")
	local dependency_list = table.clone(dependencies or {})
	for _, dependency_name in dependency_list do
		assert_name(dependency_name)
		assert(dependency_name ~= name, string.format("service %s cannot depend on itself", name))
	end
	self.definitions[name] = {
		name = name,
		dependencies = dependency_list,
		factory = factory,
	}
	table.insert(self.registration_order, name)
	return self
end

function runtime_graph:try_get(name: string)
	return self.instances[name]
end

function runtime_graph:get(name: string)
	local instance = self.instances[name]
	assert(instance ~= nil, string.format("service %s has not started", name))
	return instance
end

local function make_scope(graph: RuntimeGraph): Scope
	local scope = {
		core = graph.core,
	}
	function scope:get(name: string)
		return graph:get(name)
	end
	function scope:try_get(name: string)
		return graph:try_get(name)
	end
	return scope :: Scope
end

local function start_definition(graph: RuntimeGraph, name: string, chain: { string }, scope: Scope)
	local state = graph.states[name]
	if state == "started" then
		return
	end
	if state == "starting" then
		table.insert(chain, name)
		error("runtime dependency cycle: " .. table.concat(chain, " -> "), 0)
	end
	local definition = graph.definitions[name]
	assert(definition, string.format("service %s was requested but never registered", name))
	graph.states[name] = "starting"
	table.insert(chain, name)
	for _, dependency_name in definition.dependencies do
		start_definition(graph, dependency_name, chain, scope)
	end
	table.remove(chain)
	local instance = definition.factory(scope)
	if instance == nil then
		instance = true
	end
	graph.instances[name] = instance
	graph.states[name] = "started"
	table.insert(graph.start_order, name)
end

function runtime_graph:start_all()
	assert(not self.sealed, "runtime has already started")
	local scope = make_scope(self)
	local ok, start_error = xpcall(function()
		for _, name in self.registration_order do
			start_definition(self, name, {}, scope)
		end
	end, debug.traceback)
	if not ok then
		self:destroy_all()
		error(start_error, 0)
	end
	self.sealed = true
	return self
end

function runtime_graph:destroy_all()
	for index = #self.start_order, 1, -1 do
		local name = self.start_order[index]
		local instance = self.instances[name]
		if type(instance) == "table" and type(instance.destroy) == "function" then
			local ok, destroy_error = pcall(instance.destroy, instance)
			if not ok then
				warn(string.format("Failed to destroy %s: %s", name, tostring(destroy_error)))
			end
		end
		self.instances[name] = nil
		self.states[name] = nil
	end
	table.clear(self.start_order)
	self.sealed = false
end

function runtime_graph:get_start_order(): { string }
	return table.clone(self.start_order)
end

return runtime_graph

