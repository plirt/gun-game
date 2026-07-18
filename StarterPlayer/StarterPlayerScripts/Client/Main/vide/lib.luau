local version = { major = 0, minor = 4, patch = 0 }

local root = require(script.Parent.root)
local branch = require(script.Parent.branch)
local mount = require(script.Parent.mount)
local create = require(script.Parent.create)
local apply = require(script.Parent.apply)
local source = require(script.Parent.source)
local effect = require(script.Parent.effect)
local derive = require(script.Parent.derive)
local cleanup = require(script.Parent.cleanup)
local untrack = require(script.Parent.untrack)
local read = require(script.Parent.read)
local batch = require(script.Parent.batch)
local context = require(script.Parent.context)
local switch = require(script.Parent.switch)
local show = require(script.Parent.show)
local indexes = require(script.Parent.indexes)
local values = require(script.Parent.values)
local spring, update_springs = require(script.Parent.spring)()
local action = require(script.Parent.action)()
local changed = require(script.Parent.changed)
local timeout, update_timeouts = require(script.Parent.timeout)()
local flags = require(script.Parent.flags)

export type Source<T> = source.Source<T>
export type source<T> = Source<T>
export type Context<T> = context.Context<T>
export type context<T> = Context<T>

local function step(dt: number)
    if game then debug.profilebegin("VIDE STEP") end

    if game then debug.profilebegin("VIDE SPRING") end
    update_springs(dt)
    if game then debug.profileend() end

    if game then debug.profilebegin("VIDE SCHEDULER") end
    update_timeouts(dt)
    if game then debug.profileend() end

    if game then debug.profileend() end
end

local stepped = game and game:GetService("RunService").Heartbeat:Connect(function(dt: number)
    task.defer(step, dt)
end)

local vide = {
    version = version,

    -- core
    root = root,
    --branch = branch,
    mount = mount,
    create = create,
    source = source,
    effect = effect,
    derive = derive,
    switch = switch,
    show = show,
    indexes = indexes,
    values = values,

    -- util
    cleanup = cleanup,
    untrack = untrack,
    read = read,
    batch = batch,
    context = context,

    -- animations
    spring = spring,

    -- actions
    action = action,
    changed = changed,

    -- flags
    strict = (nil :: any) :: boolean,
    defaults = (nil :: any) :: boolean,
    defer_nested_properties = (nil :: any) :: boolean,

    -- temporary
    apply = function(instance: Instance)
        return function(props: { [any]: any })
            apply(instance, props)
            return instance
        end
    end,

    -- runtime
    step = function(dt: number)
        if stepped then
            stepped:Disconnect()
            stepped = nil
        end
        step(dt)
    end
}

setmetatable(vide :: any, {
    __index = function(_, index: unknown): ()
        if flags[index] == nil then
            error(`{tostring(index)} is not a valid member of vide`, 0)
        else
            return flags[index]
        end
    end,

    __newindex = function(_, index: unknown, value: unknown)
        if flags[index] == nil then
            error(`{tostring(index)} is not a valid member of vide, 0`)
        else
            flags[index] = value
        end
    end
})

return vide
