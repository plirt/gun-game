local npc_animation_controller = {}

local npc_values = require(script.Parent.npc_values)

local COMPLIANCE_ANIMATIONS = {
	hands_up = "HandsUp",
	kneeling = "Kneeling",
	restrained = "Restrained",
}

local EXTERNAL_IDLE_BLEND_FADE = 0.12

local animation_cache = {}

local function find_animation_folder(ctx)
	local animations = ctx.ReplicatedStorage:FindFirstChild("Animations")
	return animations and animations:FindFirstChild("Npc")
end

local function set_external_idle_weight(agent, weight)
	local track = agent.external_idle_track
	if not track then
		return
	end
	if not track.IsPlaying then
		track:Play(EXTERNAL_IDLE_BLEND_FADE)
	end
	track:AdjustWeight(weight, EXTERNAL_IDLE_BLEND_FADE)
end

local function get_animation(ctx, state_name)
	local cached = animation_cache[state_name]
	if cached and cached.Parent then
		return cached
	end

	local animation_name = COMPLIANCE_ANIMATIONS[state_name]
	if not animation_name then
		return nil
	end

	local npc_animations = find_animation_folder(ctx)
	local animation = npc_animations and npc_animations:FindFirstChild(animation_name)

	if animation and animation:IsA("Animation") then
		animation_cache[state_name] = animation
		return animation
	end
	return nil
end

function npc_animation_controller.preload_agent(ctx, agent)
	local animator = agent.animator or npc_values.get_or_create_animator(agent.humanoid)

	agent.animator = animator
	agent.compliance_tracks = agent.compliance_tracks or {}

	for state_name in COMPLIANCE_ANIMATIONS do
		if not agent.compliance_tracks[state_name] then
			local animation = get_animation(ctx, state_name)

			if animation then
				local loaded, track = pcall(function()
					return animator:LoadAnimation(animation)
				end)

				if loaded and track then
					track.Priority = Enum.AnimationPriority.Action
					track.Looped = true

					agent.compliance_tracks[state_name] = track
				else
					warn("Failed to preload NPC animation " .. animation.Name .. " for " .. agent.npc.Name)
				end
			end
		end
	end
end

function npc_animation_controller.stop(agent)
	if agent.compliance_track then
		agent.compliance_track:Stop(0.15)
		agent.compliance_track = nil
	end

	agent.compliance_animation_state = nil
	set_external_idle_weight(agent, 1)
end

function npc_animation_controller.update(ctx, agent, state_name)
	if not COMPLIANCE_ANIMATIONS[state_name] then
		npc_animation_controller.stop(agent)
		return
	end

	agent.compliance_tracks = agent.compliance_tracks or {}

	if not agent.compliance_tracks[state_name] then
		npc_animation_controller.preload_agent(ctx, agent)
	end

	if agent.compliance_animation_state == state_name and agent.compliance_track then
		set_external_idle_weight(agent, 0)
		return
	end

	npc_animation_controller.stop(agent)

	local track = agent.compliance_tracks[state_name]

	if not track then
		return
	end

	set_external_idle_weight(agent, 0)
	track:Play(0.15)

	agent.compliance_track = track
	agent.compliance_animation_state = state_name
end

function npc_animation_controller.destroy_agent(agent)
	npc_animation_controller.stop(agent)

	if agent.compliance_tracks then
		for _, track in agent.compliance_tracks do
			track:Destroy()
		end

		agent.compliance_tracks = nil
	end
end
return npc_animation_controller


