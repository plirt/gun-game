local version = { major = 0, minor = 4, patch = 0 }

local root = require(script.Parent.Root)
local branch = require(script.Parent.Branch)
local mount = require(script.Parent.Mount)
local create = require(script.Parent.Create)
local apply = require(script.Parent.Apply)
local source = require(script.Parent:WaitForChild("Source"))
local effect = require(script.Parent.Effect)
local derive = require(script.Parent.Derive)
local cleanup = require(script.Parent.Cleanup)
local untrack = require(script.Parent.Untrack)
local read = require(script.Parent.Read)
local batch = require(script.Parent.Batch)
local context = require(script.Parent.Context)
local switch = require(script.Parent.Switch)
local show = require(script.Parent.Show)
local indexes = require(script.Parent.Indexes)
local values = require(script.Parent.Values)
local spring, update_springs = require(script.Parent.Spring)()
local action = require(script.Parent.Action)()
local changed = require(script.Parent:WaitForChild("Changed"))
local timeout, update_timeouts = require(script.Parent.Timeout)()
local flags = require(script.Parent.Flags)

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

