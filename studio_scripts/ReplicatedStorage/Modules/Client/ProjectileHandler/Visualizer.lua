local ReplicatedStorage = game:GetService("ReplicatedStorage")

local object_pool = require(ReplicatedStorage.Modules.Shared.ObjectPool)

local vfx_folder = ReplicatedStorage:FindFirstChild("VFX")
local client_effects_folder = workspace:WaitForChild("ClientEffects")
local tracer_folder = client_effects_folder:WaitForChild("ProjectileTracers")
local impact_folder = client_effects_folder:WaitForChild("ProjectileImpacts")
local muzzle_flash_folder = client_effects_folder:WaitForChild("MuzzleFlashes")

local ProjectileVisualizer = {}

ProjectileVisualizer.ProjectileColor = Color3.fromRGB(247, 213, 130)
ProjectileVisualizer.HitColor = Color3.fromRGB(255, 92, 64)
ProjectileVisualizer.MarkerSize = Vector3.new(0.18, 0.18, 0.18)
ProjectileVisualizer.TracerThickness = 0.055
ProjectileVisualizer.TracerLifetime = 0.045
ProjectileVisualizer.MarkerLifetime = 0.18
ProjectileVisualizer.MuzzleFlashTime = 0.1
ProjectileVisualizer.MuzzleFlashParticleLifetime = 0.5
ProjectileVisualizer.MuzzleFlashCleanupPadding = 0.04

local MarkerTemplate = Instance.new("Part")
MarkerTemplate.Name = "ImpactMarker"
MarkerTemplate.Size = ProjectileVisualizer.MarkerSize
MarkerTemplate.Anchored = true
MarkerTemplate.CanCollide = false
MarkerTemplate.CanTouch = false
MarkerTemplate.CanQuery = false
MarkerTemplate.Material = Enum.Material.Neon
MarkerTemplate.Color = ProjectileVisualizer.HitColor
MarkerTemplate.Transparency = 1

local TracerTemplate = Instance.new("Part")
TracerTemplate.Name = "BulletTracer"
TracerTemplate.Size = Vector3.new(ProjectileVisualizer.TracerThickness, ProjectileVisualizer.TracerThickness, 1)
TracerTemplate.Anchored = true
TracerTemplate.CanCollide = false
TracerTemplate.CanTouch = false
TracerTemplate.CanQuery = false
TracerTemplate.Material = Enum.Material.Neon
TracerTemplate.Color = ProjectileVisualizer.ProjectileColor
TracerTemplate.Transparency = 1

local MarkerPool = object_pool.create({
	title = "ProjectileMarkers",
	count = 120,
	template = MarkerTemplate,
	parent = impact_folder,
})

local TracerPool = object_pool.create({
	title = "ProjectileTracers",
	count = 240,
	template = TracerTemplate,
	parent = tracer_folder,
})

local function release_later(pool, object, lifetime)
	task.delay(lifetime, function()
		object_pool.release(pool, object)
	end)
end

function ProjectileVisualizer:ShowImpact(position, normal, config)
	local marker = object_pool.acquire(MarkerPool)
	if not marker then
		return
	end

	marker.Size = self.MarkerSize
	marker.Color = self.HitColor
	marker.Transparency = 0
	marker.CFrame = CFrame.lookAt(position + normal * 0.015, position + normal)

	release_later(MarkerPool, marker, (config and config.impact_lifetime) or self.MarkerLifetime)
end

function ProjectileVisualizer:ShowTracer(start_position, end_position, config)
	local delta = end_position - start_position
	local distance = delta.Magnitude
	if distance <= 0 then
		return
	end

	local tracer = object_pool.acquire(TracerPool)
	if not tracer then
		return
	end

	local thickness = self.TracerThickness
	tracer.Size = Vector3.new(thickness, thickness, distance)
	tracer.CFrame = CFrame.new(start_position, end_position) * CFrame.new(0, 0, -distance / 2)
	tracer.Color = self.ProjectileColor
	tracer.Transparency = 0.05

	release_later(TracerPool, tracer, (config and config.tracer_lifetime) or self.TracerLifetime)
end

local muzzle_flash_pools = {}
local fallback_muzzle_flash = Instance.new("Attachment")
fallback_muzzle_flash.Name = "MuzzleFlash"
local fallback_muzzle_light = Instance.new("PointLight")
fallback_muzzle_light.Name = "PointLight"
fallback_muzzle_light.Color = Color3.fromRGB(255, 202, 119)
fallback_muzzle_light.Brightness = 8
fallback_muzzle_light.Range = 14
fallback_muzzle_light.Shadows = true
fallback_muzzle_light.Enabled = false
fallback_muzzle_light.Parent = fallback_muzzle_flash

local function get_muzzle_flash_template(config)
	local template_name = config and config.muzzle_flash_vfx or "MuzzleFlash"
	local template = vfx_folder and vfx_folder:FindFirstChild(template_name)
	return template and template:IsA("Attachment") and template or fallback_muzzle_flash
end

local function get_muzzle_flash_time(config)
	return (config and config.muzzle_flash_time) or ProjectileVisualizer.MuzzleFlashTime
end

local function get_muzzle_particle_lifetime(config)
	return (config and config.muzzle_flash_particle_lifetime) or ProjectileVisualizer.MuzzleFlashParticleLifetime
end

local function clamp_emitter_lifetime(emitter, max_lifetime)
	local lifetime = emitter.Lifetime
	local min_lifetime = math.min(lifetime.Min, max_lifetime)
	local max_lifetime_value = math.min(lifetime.Max, max_lifetime)
	emitter.Lifetime = NumberRange.new(min_lifetime, math.max(min_lifetime, max_lifetime_value))
end

local function read_number_value(parent, name, fallback)
	local value = parent:FindFirstChild(name)
	if value and value:IsA("NumberValue") then
		return value.Value
	end
	return fallback
end

local function emit_particle(emitter, config)
	local emit_count = read_number_value(emitter, "EmitCount", 1)
	local emit_delay = read_number_value(emitter, "EmitDelay", 0)
	local emit_duration = read_number_value(emitter, "EmitDuration", 0)
	local particle_lifetime = get_muzzle_particle_lifetime(config)

	clamp_emitter_lifetime(emitter, particle_lifetime)
	emitter.Enabled = false

	if emit_duration > 0 then
		emit_duration = math.min(emit_duration, get_muzzle_flash_time(config))
		task.delay(emit_delay, function()
			if emitter.Parent then
				emitter.Enabled = true
				task.delay(emit_duration, function()
					if emitter.Parent then
						emitter.Enabled = false
					end
				end)
			end
		end)
		return emit_delay + emit_duration + emitter.Lifetime.Max
	end

	task.delay(emit_delay, function()
		if emitter.Parent then
			emitter:Emit(emit_count)
		end
	end)
	return emit_delay + emitter.Lifetime.Max
end

local function reset_muzzle_flash(holder)
	holder.CFrame = CFrame.identity
	holder.Transparency = 1
	for _, descendant in holder:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
			descendant:Clear()
		elseif descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end
end

local function get_muzzle_flash_pool(template)
	local pool = muzzle_flash_pools[template]
	if pool then
		return pool
	end
	local holder_template = Instance.new("Part")
	holder_template.Name = "MuzzleFlashAnchor"
	holder_template.Size = Vector3.new(0.05, 0.05, 0.05)
	holder_template.Transparency = 1
	holder_template.Anchored = true
	holder_template.CanCollide = false
	holder_template.CanTouch = false
	holder_template.CanQuery = false
	holder_template.CastShadow = false
	local flash_attachment = template:Clone()
	flash_attachment.CFrame = CFrame.identity
	flash_attachment.Parent = holder_template
	pool = object_pool.create({
		title = "MuzzleFlash",
		count = 24,
		template = holder_template,
		prewarm = true,
		allow_growth = true,
		growth_limit = 64,
		reset = reset_muzzle_flash,
	})
	holder_template:Destroy()
	muzzle_flash_pools[template] = pool
	return pool
end

function ProjectileVisualizer:ShowMuzzleFlash(attachment, config, world_cframe)
	local muzzle_cframe = world_cframe or (attachment and attachment.WorldCFrame)
	if not muzzle_cframe then
		return
	end
	local template = get_muzzle_flash_template(config)
	local pool = get_muzzle_flash_pool(template)
	local holder = object_pool.acquire(pool, muzzle_flash_folder)
	if not holder then
		return
	end
	holder.CFrame = muzzle_cframe
	local cleanup_time = get_muzzle_flash_time(config)
	for _, descendant in holder:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			cleanup_time = math.max(cleanup_time, emit_particle(descendant, config) + ProjectileVisualizer.MuzzleFlashCleanupPadding)
		elseif descendant:IsA("Light") then
			descendant.Enabled = true
			task.delay(get_muzzle_flash_time(config), function()
				if descendant.Parent then
					descendant.Enabled = false
				end
			end)
		end
	end
	release_later(pool, holder, cleanup_time)
end
return ProjectileVisualizer

