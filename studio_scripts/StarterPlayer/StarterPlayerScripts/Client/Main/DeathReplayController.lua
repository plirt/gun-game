-- Client replay orchestrator: records a bounded local world timeline, merges the server's
-- authoritative lethal-shot/camera data, and recreates actors, projectiles, viewmodel, and sound.
-- Snapshot encoding lives in ReplaySnapshotCodec and storage in RingBuffer so the orchestration
-- layer does not allocate a nested table for every part at 20 Hz.
--
-- Replays are intentionally observational, not a second physics simulation: topology is indexed
-- when a template is created, while late structural changes require a new template snapshot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local GunViewmodelBuilder = require(ReplicatedStorage.Modules.Client.GunViewmodelBuilder)
local projectile_visualizer = require(
	ReplicatedStorage.Modules.Client.ProjectileHandler:WaitForChild("Visualizer")
)
local WeaponConfig = require(ReplicatedStorage.Modules.Shared.WeaponConfig)
local RingBuffer = require(ReplicatedStorage.Modules.Shared.Framework.RingBuffer)
local NetworkProtocol = require(ReplicatedStorage.Modules.Shared.Framework.NetworkProtocol)
local ReplaySnapshotCodec = require(script.Components.ReplaySnapshotCodec)
local ReplayLethalDataCodec = require(script.Components.ReplayLethalDataCodec)
local ReplayTimeline = require(script.Components.ReplayTimeline)
local ReplayProjectilePlayer = require(script.Components.ReplayProjectilePlayer)
local ReplaySoundPlayer = require(script.Components.ReplaySoundPlayer)

local death_replay_controller = {}

local REPLAY_SECONDS = 4
local POST_DEATH_SECONDS = 3
local REPLAY_WINDOW_SECONDS = REPLAY_SECONDS + POST_DEATH_SECONDS
local RECORD_INTERVAL = 1 / 20
local POV_NETWORK_INTERVAL = 1 / NetworkProtocol.get_spec("ReplayCameraSnapshot").rate
local LETHAL_DATA_MAX_AGE = POST_DEATH_SECONDS + 3
local MAX_POV_SAMPLES = 128
local MAX_REPLAY_SHOTS = 320
local MAX_REPLAY_SOUNDS = 384
local REPLAY_SOUND_ATTRIBUTE = "DeathReplaySound"
local MAX_SAMPLES = math.ceil(REPLAY_WINDOW_SECONDS / RECORD_INTERVAL) + 2
local REPLAY_CLONE_ATTRIBUTE = "DeathReplayClone"
local REPLAY_PART_KEY_ATTRIBUTE = "DeathReplayPartKey"

local function create_replay_gui(player_gui: PlayerGui)
	local existing = player_gui:FindFirstChild("DeathReplayGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DeathReplayGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.Enabled = false
	gui.Parent = player_gui

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.new(0.5, 0, 0, 34)
	header.Size = UDim2.new(0, 420, 0, 30)
	header.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	header.BackgroundTransparency = 0.25
	header.BorderSizePixel = 0
	header.Font = Enum.Font.RobotoMono
	header.Text = "BODYCAM REPLAY"
	header.TextColor3 = Color3.fromRGB(235, 235, 235)
	header.TextSize = 15
	header.Parent = gui

	local skip_button = Instance.new("TextButton")
	skip_button.Name = "SkipButton"
	skip_button.AnchorPoint = Vector2.new(0.5, 1)
	skip_button.Position = UDim2.new(0.5, 0, 1, -38)
	skip_button.Size = UDim2.new(0, 320, 0, 32)
	skip_button.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	skip_button.BackgroundTransparency = 0.2
	skip_button.BorderSizePixel = 0
	skip_button.AutoButtonColor = true
	skip_button.Font = Enum.Font.GothamBold
	skip_button.Text = "PRESS SPACE OR CLICK TO SKIP"
	skip_button.TextColor3 = Color3.fromRGB(235, 235, 235)
	skip_button.TextSize = 12
	skip_button.Parent = gui

	return gui, header, skip_button
end

local function collect_parts_by_path(root)
	return ReplaySnapshotCodec.index_model(root)
end


local function prepare_replay_clone(model)
	ReplaySnapshotCodec.prepare_clone(model, REPLAY_CLONE_ATTRIBUTE)
end

local function clone_model(model)
	local was_archivable = model.Archivable
	model.Archivable = true
	local success, clone = pcall(function()
		return model:Clone()
	end)
	model.Archivable = was_archivable

	if not success or not clone or not clone:IsA("Model") then
		if clone then
			clone:Destroy()
		end
		return nil
	end
	return clone
end

local function find_active_viewmodel(camera)
	for _, child in camera:GetChildren() do
		if child:IsA("Model") and not child:GetAttribute(REPLAY_CLONE_ATTRIBUTE) then
			local lower_name = string.lower(child.Name)
			if child:FindFirstChild("ManagedByGunManager")
				or child:GetAttribute("utility_viewmodel")
				or string.find(lower_name, "viewmodel", 1, true)
			then
				return child
			end
		end
	end
	return nil
end

local function create_killer_viewmodel(gun_name)
	if type(gun_name) ~= "string" or gun_name == "" then
		return nil
	end
	local viewmodel_template = ReplicatedStorage:FindFirstChild("Viewmodel")
	local guns = ReplicatedStorage:FindFirstChild("Guns")
	local gun_configs = ReplicatedStorage:FindFirstChild("GunConfigs")
	local gun_template = guns and guns:FindFirstChild(gun_name)
	local config_module = gun_configs and gun_configs:FindFirstChild(gun_name)
	if not viewmodel_template
		or not viewmodel_template:IsA("Model")
		or not gun_template
		or not gun_template:IsA("Model")
		or not config_module
		or not config_module:IsA("ModuleScript")
	then
		return nil
	end

	local success, result = pcall(function()
		local viewmodel = viewmodel_template:Clone()
		local gun_model = gun_template:Clone()
		gun_model.Name = gun_name
		gun_model.Parent = viewmodel
		local config = WeaponConfig.normalize(require(config_module))
		GunViewmodelBuilder.weld(viewmodel)
		GunViewmodelBuilder.attach_gun(gun_model, viewmodel.HumanoidRootPart, config)
		viewmodel.Name = "ReplayKillerViewmodel"
		prepare_replay_clone(viewmodel)
		for _, descendant in viewmodel:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = 0
			end
		end
		return viewmodel
	end)
	if not success then
		warn("Could not build replay viewmodel:", result)
		return nil
	end
	return result
end

local function get_pov_sample(camera_samples, relative_time)
	if type(camera_samples) ~= "table" or #camera_samples == 0 then
		return nil, nil, 0
	end
	if #camera_samples == 1 or relative_time <= camera_samples[1].offset then
		return camera_samples[1], camera_samples[1], 0
	end
	for index = 1, #camera_samples - 1 do
		local first = camera_samples[index]
		local second = camera_samples[index + 1]
		if relative_time <= second.offset then
			local span = math.max(second.offset - first.offset, 1 / 240)
			return first, second, math.clamp((relative_time - first.offset) / span, 0, 1)
		end
	end
	local last = camera_samples[#camera_samples]
	return last, last, 0
end

local function set_replay_model_visible(replay_model, visible)
	ReplaySnapshotCodec.set_visible(replay_model, visible)
end

local function select_snapshot_state(first_state, second_state, alpha)
	if first_state and second_state and first_state.template_id == second_state.template_id then
		return first_state, second_state, alpha
	end
	if alpha < 0.5 then
		return first_state or second_state, nil, 0
	end
	return second_state or first_state, nil, 0
end

local function apply_snapshot_state(replay_model, first_state, second_state, alpha)
	ReplaySnapshotCodec.apply(replay_model, first_state, second_state, alpha)
end

function death_replay_controller.setup(ctx)
	local samples = RingBuffer.new(MAX_SAMPLES)
	local templates = {}
	local source_template_ids = setmetatable({}, { __mode = "k" })
	local next_template_id = 0
	local next_npc_actor_id = 0
	local npc_actor_ids = setmetatable({}, { __mode = "k" })
	local samples_since_prune = 0
	local record_accumulator = 0
	local network_accumulator = 0
	local playback_connection = nil
	local completion_callback = nil
	local replay_token = 0
	local replay_world = nil
	local replay_models = {}
	local killer_viewmodel = nil
	local shot_buffer = {}
	local projectile_player = ReplayProjectilePlayer.new(projectile_visualizer)
	local replay_shots = projectile_player.shots
	local active_replay_projectiles = projectile_player.active
	local sound_buffer = {}
	local sound_player = ReplaySoundPlayer.new()
	local sound_connections = setmetatable({}, { __mode = "k" })
	local active_recorded_sounds = setmetatable({}, { __mode = "k" })
	local muted_live_sounds = setmetatable({}, { __mode = "k" })
	local pending_lethal_data = nil
	local active_kill_data = nil
	local hidden_parts = setmetatable({}, { __mode = "k" })
	local hidden_decals = setmetatable({}, { __mode = "k" })
	local hidden_effects = setmetatable({}, { __mode = "k" })
	local previous_camera_state = nil
	ctx.replay_post_death_seconds = POST_DEATH_SECONDS
	local gui, header, skip_button = create_replay_gui(ctx.player:WaitForChild("PlayerGui"))
	local replay_camera_remote = ctx.remotes:WaitForChild("ReplayCameraSnapshot")
	local death_replay_data_remote = ctx.remotes:WaitForChild("DeathReplayData")

	local function sanitize_lethal_data(payload)
		return ReplayLethalDataCodec.sanitize(payload, MAX_POV_SAMPLES, 256)
	end

	death_replay_data_remote.OnClientEvent:Connect(function(payload)
		local lethal_data = sanitize_lethal_data(payload)
		if not lethal_data then
			return
		end
		if ctx.replay_active then
			active_kill_data = lethal_data
		else
			pending_lethal_data = lethal_data
		end
	end)

	ctx.record_replay_shot = function(shooter, gun_name, origin, direction, config)
		if ctx.replay_active
			or ctx.menu_open
			or typeof(origin) ~= "Vector3"
			or typeof(direction) ~= "Vector3"
			or direction.Magnitude <= 0
		then
			return
		end
		local unit_direction = direction.Unit
		local resolved_config = type(config) == "table" and config or {}
		local max_distance = type(resolved_config.max_distance) == "number"
			and resolved_config.max_distance
			or 650
		local muzzle_velocity = type(resolved_config.muzzle_velocity) == "number"
			and math.max(resolved_config.muzzle_velocity, 1)
			or 1000

		local exclusions = { workspace.CurrentCamera }
		if shooter:IsA("Player") and shooter.Character then
			table.insert(exclusions, shooter.Character)
		elseif shooter:IsA("Model") then
			table.insert(exclusions, shooter)
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = exclusions
		params.IgnoreWater = true
		local result = workspace:Raycast(origin, unit_direction * max_distance, params)
		local hit_position = result and result.Position or origin + unit_direction * max_distance
		local hit_normal = result and result.Normal or -unit_direction

		table.insert(shot_buffer, {
			time = os.clock(),
			shooter_user_id = shooter:IsA("Player") and shooter.UserId or nil,
			gun_name = gun_name,
			origin = origin,
			hit_position = hit_position,
			hit_normal = hit_normal,
			muzzle_velocity = muzzle_velocity,
			did_hit = result ~= nil,
		})
		local oldest_time = os.clock() - REPLAY_SECONDS
		while #shot_buffer > 0
			and (#shot_buffer > MAX_REPLAY_SHOTS or shot_buffer[1].time < oldest_time)
		do
			table.remove(shot_buffer, 1)
		end
	end

	local function is_replay_instance(instance)
		local current = instance
		while current do
			if current:GetAttribute(REPLAY_CLONE_ATTRIBUTE)
				or current:GetAttribute(REPLAY_SOUND_ATTRIBUTE)
			then
				return true
			end
			current = current.Parent
		end
		return false
	end

	local function get_sound_position(sound)
		local current = sound.Parent
		while current and current ~= game do
			if current:IsA("Attachment") then
				return current.WorldPosition
			elseif current:IsA("BasePart") then
				return current.Position
			elseif current:IsA("Model") then
				local success, pivot = pcall(function()
					return current:GetPivot()
				end)
				if success then
					return pivot.Position
				end
			end
			current = current.Parent
		end
		return nil
	end

	local function trim_sound_buffer()
		local oldest_time = os.clock() - REPLAY_SECONDS
		while #sound_buffer > 0
			and (#sound_buffer > MAX_REPLAY_SOUNDS or sound_buffer[1].time < oldest_time)
		do
			local removed = table.remove(sound_buffer, 1)
			if removed.template then
				removed.template:Destroy()
			end
		end
	end

	local function record_sound_event(sound)
		if ctx.replay_active
			or not sound.Parent
			or is_replay_instance(sound)
		then
			return
		end
		local now = os.clock()
		local active_event = active_recorded_sounds[sound]
		if active_event and not active_event.stopped_time and now - active_event.time <= 0.05 then
			return
		end
		local success, template = pcall(function()
			return sound:Clone()
		end)
		if not success or not template or not template:IsA("Sound") then
			if template then
				template:Destroy()
			end
			return
		end
		template:SetAttribute(REPLAY_SOUND_ATTRIBUTE, true)
		template:Stop()
		template.Parent = nil
		local event = {
			time = now,
			template = template,
			position = get_sound_position(sound),
			time_position = sound.TimePosition,
			stopped_time = nil,
		}
		table.insert(sound_buffer, event)
		active_recorded_sounds[sound] = event
		trim_sound_buffer()
	end

	local function finish_recorded_sound(sound)
		if ctx.replay_active then
			return
		end
		local event = active_recorded_sounds[sound]
		if event then
			event.stopped_time = os.clock()
			active_recorded_sounds[sound] = nil
		end
	end

	local function connect_sound(sound)
		if sound_connections[sound] or is_replay_instance(sound) then
			return
		end
		local connections = {}
		sound_connections[sound] = connections
		local function handle_started()
			if ctx.replay_active then
				if muted_live_sounds[sound] == nil then
					muted_live_sounds[sound] = sound.Volume
				end
				sound.Volume = 0
				return
			end
			record_sound_event(sound)
		end
		table.insert(connections, sound.Played:Connect(handle_started))
		table.insert(connections, sound:GetPropertyChangedSignal("Playing"):Connect(function()
			if sound.Playing then
				handle_started()
			else
				finish_recorded_sound(sound)
			end
		end))
		table.insert(connections, sound.Ended:Connect(function()
			finish_recorded_sound(sound)
		end))
		table.insert(connections, sound.Stopped:Connect(function()
			finish_recorded_sound(sound)
		end))
		table.insert(connections, sound.Paused:Connect(function()
			finish_recorded_sound(sound)
		end))
		table.insert(connections, sound.Destroying:Connect(function()
			finish_recorded_sound(sound)
			for _, connection in connections do
				connection:Disconnect()
			end
			sound_connections[sound] = nil
		end))
		local function capture_if_playing()
			if sound.Parent and sound.IsPlaying then
				handle_started()
			end
		end
		task.defer(capture_if_playing)
		task.delay(0.1, capture_if_playing)
	end

	local function monitor_sound_root(root)
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("Sound") then
				connect_sound(descendant)
			end
		end
		root.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("Sound") then
				connect_sound(descendant)
				return
			end
			task.defer(function()
				if not descendant.Parent then
					return
				end
				for _, nested in descendant:GetDescendants() do
					if nested:IsA("Sound") then
						connect_sound(nested)
					end
				end
			end)
		end)
	end

	local function mute_live_sounds()
		for sound in sound_connections do
			if sound.Parent and sound.IsPlaying and not is_replay_instance(sound) then
				if muted_live_sounds[sound] == nil then
					muted_live_sounds[sound] = sound.Volume
				end
				sound.Volume = 0
			end
		end
	end

	local function restore_live_sounds()
		for sound, volume in muted_live_sounds do
			if sound.Parent then
				sound.Volume = volume
			end
		end
		table.clear(muted_live_sounds)
	end

	local function clear_sound_buffer()
		for _, event in sound_buffer do
			if event.template then
				event.template:Destroy()
			end
		end
		table.clear(sound_buffer)
		table.clear(active_recorded_sounds)
	end

	local function seed_playing_sounds()
		if ctx.replay_active then
			return
		end
		for sound in sound_connections do
			if sound.Parent and sound.IsPlaying and not is_replay_instance(sound) then
				record_sound_event(sound)
			end
		end
	end

	local function destroy_template(template)
		for _, connection in template.connections do
			connection:Disconnect()
		end
		if template.clone then
			template.clone:Destroy()
		end
	end

	local function clear_templates()
		for _, template in templates do
			destroy_template(template)
		end
		table.clear(templates)
		table.clear(source_template_ids)
	end

	local function prune_unused_templates()
		local used_template_ids = {}
		for _, sample in samples:values() do
			for _, state in sample.actors do
				used_template_ids[state.template_id] = true
			end
			if sample.viewmodel then
				used_template_ids[sample.viewmodel.template_id] = true
			end
		end

		for template_id, template in templates do
			if not used_template_ids[template_id] then
				destroy_template(template)
				templates[template_id] = nil
			end
		end
		for source, template_id in source_template_ids do
			if templates[template_id] == nil then
				source_template_ids[source] = nil
			end
		end
	end

	local function ensure_template(source, kind)
		local existing_id = source_template_ids[source]
		local existing_template = existing_id and templates[existing_id]
		if existing_template and not existing_template.dirty then
			return existing_id
		end

		local clone = clone_model(source)
		if not clone then
			return nil
		end

		local source_by_key, part_keys, source_parts = collect_parts_by_path(source)
		local focus_index = nil
		for index, source_part in source_parts do
			if source_part.Name == "Head" then
				focus_index = index
				break
			elseif source_part.Name == "HumanoidRootPart" then
				focus_index = index
			end
		end
		ReplaySnapshotCodec.tag_clone(clone, source_by_key, REPLAY_PART_KEY_ATTRIBUTE)
		prepare_replay_clone(clone)
		clone.Parent = nil

		next_template_id += 1
		local template_id = next_template_id
		local template = {
			clone = clone,
			kind = kind,
			source = source,
			source_parts = source_parts,
			part_keys = part_keys,
			focus_index = focus_index,
			dirty = false,
			connections = {},
		}
		templates[template_id] = template
		source_template_ids[source] = template_id

		local function mark_dirty(descendant)
			if descendant:IsA("BasePart") then
				template.dirty = true
			end
		end
		table.insert(template.connections, source.DescendantAdded:Connect(mark_dirty))
		table.insert(template.connections, source.DescendantRemoving:Connect(mark_dirty))
		return template_id
	end

	local function capture_model(source, kind)
		local template_id = ensure_template(source, kind)
		local template = template_id and templates[template_id]
		if not template then
			return nil
		end

		local snapshot = ReplaySnapshotCodec.capture(template, source)
		if not snapshot then
			return nil
		end
		snapshot.template_id = template_id
		return snapshot
	end

	local function capture_actors()
		local actors = {}
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then
				local state = capture_model(character, "actor")
				if state then
					actors["player:" .. tostring(player.UserId)] = state
				end
			end
		end

		local npcs = workspace:FindFirstChild("Npcs")
		if npcs then
			for _, npc in npcs:GetChildren() do
				if npc:IsA("Model") then
					local actor_id = npc_actor_ids[npc]
					if actor_id == nil then
						next_npc_actor_id += 1
						actor_id = next_npc_actor_id
						npc_actor_ids[npc] = actor_id
					end
					local state = capture_model(npc, "actor")
					if state then
						actors["npc:" .. tostring(actor_id)] = state
					end
				end
			end
		end
		return actors
	end

	local function hide_live_model(model)
		if model:GetAttribute(REPLAY_CLONE_ATTRIBUTE) then
			return
		end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				if hidden_parts[descendant] == nil then
					hidden_parts[descendant] = descendant.LocalTransparencyModifier
				end
				descendant.LocalTransparencyModifier = 1
			elseif descendant:IsA("Decal")
				and descendant.Parent
				and descendant.Parent:IsA("BasePart")
				and descendant.Parent.Name == "Head"
				and descendant:FindFirstAncestorOfClass("Model") == model
			then
				if hidden_decals[descendant] == nil then
					hidden_decals[descendant] = descendant.Transparency
				end
				descendant.Transparency = 1
			elseif descendant:IsA("ParticleEmitter")
				or descendant:IsA("Trail")
				or descendant:IsA("Beam")
				or descendant:IsA("Highlight")
				or descendant:IsA("BillboardGui")
			then
				if hidden_effects[descendant] == nil then
					hidden_effects[descendant] = descendant.Enabled
				end
				descendant.Enabled = false
			end
		end
	end

	local function hide_live_dynamic_entities(camera)
		for _, player in Players:GetPlayers() do
			if player.Character and source_template_ids[player.Character] then
				hide_live_model(player.Character)
			end
		end
		local npcs = workspace:FindFirstChild("Npcs")
		if npcs then
			for _, npc in npcs:GetChildren() do
				if npc:IsA("Model") and source_template_ids[npc] then
					hide_live_model(npc)
				end
			end
		end
		for _, child in camera:GetChildren() do
			if child:IsA("Model") and source_template_ids[child] then
				hide_live_model(child)
			end
		end
	end

	local function restore_live_entities()
		for part, local_transparency in hidden_parts do
			if part.Parent then
				part.LocalTransparencyModifier = local_transparency
			end
		end
		for decal, transparency in hidden_decals do
			if decal.Parent then
				decal.Transparency = transparency
			end
		end
		for effect, enabled in hidden_effects do
			if effect.Parent then
				effect.Enabled = enabled
			end
		end
		local npcs = workspace:FindFirstChild("Npcs")
		if npcs then
			for _, npc in npcs:GetChildren() do
				if npc:IsA("Model") and not npc:GetAttribute(REPLAY_CLONE_ATTRIBUTE) then
					for _, descendant in npc:GetDescendants() do
						if descendant:IsA("BasePart") then
							descendant.LocalTransparencyModifier = 0
						end
					end
				end
			end
		end
		table.clear(hidden_parts)
		table.clear(hidden_decals)
		table.clear(hidden_effects)
	end

	local function destroy_replay_models()
		for _, replay_model in replay_models do
			if replay_model.model then
				replay_model.model:Destroy()
			end
		end
		table.clear(replay_models)
		if killer_viewmodel then
			killer_viewmodel:Destroy()
			killer_viewmodel = nil
		end
		projectile_player:clear()
		sound_player:clear()
		if replay_world then
			replay_world:Destroy()
			replay_world = nil
		end
	end

	local function create_replay_model(template_id, camera)
		if replay_models[template_id] then
			return replay_models[template_id]
		end
		local template = templates[template_id]
		if not template or not template.clone then
			return nil
		end
		local model = template.clone:Clone()
		model.Name = "Replay_" .. template.clone.Name
		model:SetAttribute(REPLAY_CLONE_ATTRIBUTE, true)
		local parts, ordered_parts = ReplaySnapshotCodec.collect_clone_parts(
			model,
			template.part_keys,
			REPLAY_PART_KEY_ATTRIBUTE
		)
		local replay_model = {
			model = model,
			parts = parts,
			ordered_parts = ordered_parts,
		}
		replay_models[template_id] = replay_model
		set_replay_model_visible(replay_model, false)
		model.Parent = if template.kind == "viewmodel" then camera else replay_world
		return replay_model
	end

	local function restore_camera()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		camera.CameraType = Enum.CameraType.Custom
		local character = ctx.player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		elseif previous_camera_state and previous_camera_state.subject then
			camera.CameraSubject = previous_camera_state.subject
		end
		if previous_camera_state then
			camera.FieldOfView = previous_camera_state.fov
		end
		previous_camera_state = nil
	end

	local function finish_replay()
		if not ctx.replay_active then
			return
		end
		replay_token += 1
		ctx.replay_active = false
		gui.Enabled = false
		if playback_connection then
			playback_connection:Disconnect()
			playback_connection = nil
		end

		destroy_replay_models()
		restore_live_entities()
		restore_live_sounds()
		restore_camera()
		samples:clear()
		table.clear(shot_buffer)
		clear_sound_buffer()
		clear_templates()
		task.defer(seed_playing_sounds)
		active_kill_data = nil

		local callback = completion_callback
		completion_callback = nil
		if callback then
			task.defer(callback)
		end
	end

	local function get_replay_model(template_id, camera)
		return replay_models[template_id] or create_replay_model(template_id, camera)
	end

	local function set_special_model_visible(model, visible)
		if not model then
			return
		end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = if visible then 0 else 1
			end
		end
	end

	local function ensure_killer_viewmodel(camera)
		if killer_viewmodel or not active_kill_data then
			return
		end
		killer_viewmodel = create_killer_viewmodel(active_kill_data.gun_name)
		if killer_viewmodel then
			killer_viewmodel.Parent = camera
		end
	end

	local function render_killer_camera(camera, relative_time)
		if not active_kill_data then
			return false
		end
		local first_pov, second_pov, pov_alpha = get_pov_sample(active_kill_data.camera_samples, relative_time)
		if not first_pov then
			return false
		end

		camera.CFrame = first_pov.camera_cframe:Lerp(second_pov.camera_cframe, pov_alpha)
		camera.FieldOfView = first_pov.field_of_view
			+ (second_pov.field_of_view - first_pov.field_of_view) * pov_alpha
		ensure_killer_viewmodel(camera)
		if killer_viewmodel then
			local first_offset = first_pov.viewmodel_offset or second_pov.viewmodel_offset
			local second_offset = second_pov.viewmodel_offset or first_offset
			local viewmodel_offset = if first_offset and second_offset
				then first_offset:Lerp(second_offset, pov_alpha)
				else CFrame.new(0, -1.25, -1.5)
			killer_viewmodel:PivotTo(camera.CFrame * viewmodel_offset)
			set_special_model_visible(killer_viewmodel, true)
		end
		return true
	end

	local function render_actor_killer_camera(camera, first, second, alpha)
		if not active_kill_data or not active_kill_data.killer_user_id then
			return false
		end
		local actor_id = "player:" .. tostring(active_kill_data.killer_user_id)
		local first_state, second_state, state_alpha = select_snapshot_state(
			first.actors[actor_id],
			second.actors[actor_id],
			alpha
		)
		if not first_state then
			return false
		end
		local template = templates[first_state.template_id]
		local focus_index = template and template.focus_index
		local first_focus = focus_index and first_state.cframes[focus_index]
		if not first_focus then
			return false
		end
		local second_focus = second_state and second_state.cframes[focus_index]
		local focus_cframe = second_focus
			and first_focus:Lerp(second_focus, state_alpha)
			or first_focus
		local camera_position = focus_cframe.Position + Vector3.new(0, 0.15, 0)
		camera.CFrame = CFrame.lookAt(
			camera_position,
			camera_position + active_kill_data.direction
		)
		camera.FieldOfView = 70
		ensure_killer_viewmodel(camera)
		if killer_viewmodel then
			killer_viewmodel:PivotTo(camera.CFrame * CFrame.new(0, -1.25, -1.5))
			set_special_model_visible(killer_viewmodel, true)
		end
		return true
	end

	local function render_replay_frame(camera, first, second, alpha, relative_time, show_killer_actor)
		local using_killer_camera = render_killer_camera(camera, relative_time)
		if not using_killer_camera then
			using_killer_camera = render_actor_killer_camera(camera, first, second, alpha)
		end
		if not using_killer_camera then
			camera.CFrame = first.cframe:Lerp(second.cframe, alpha)
			camera.FieldOfView = first.fov + (second.fov - first.fov) * alpha
		end

		for _, replay_model in replay_models do
			set_replay_model_visible(replay_model, false)
		end

		local visited_actors = {}
		local killer_actor_id = active_kill_data
			and active_kill_data.killer_user_id
			and ("player:" .. tostring(active_kill_data.killer_user_id))
			or nil
		local function apply_actor(actor_id)
			if visited_actors[actor_id] then
				return
			end
			visited_actors[actor_id] = true
			local first_state, second_state, state_alpha = select_snapshot_state(
				first.actors[actor_id],
				second.actors[actor_id],
				alpha
			)
			if not first_state then
				return
			end
			local replay_model = get_replay_model(first_state.template_id, camera)
			apply_snapshot_state(replay_model, first_state, second_state, state_alpha)
			if actor_id == killer_actor_id and using_killer_camera and not show_killer_actor then
				set_replay_model_visible(replay_model, false)
			end
		end

		for actor_id in first.actors do
			apply_actor(actor_id)
		end
		for actor_id in second.actors do
			apply_actor(actor_id)
		end

		if not using_killer_camera then
			local first_viewmodel, second_viewmodel, viewmodel_alpha = select_snapshot_state(
				first.viewmodel,
				second.viewmodel,
				alpha
			)
			if first_viewmodel then
				local replay_viewmodel = get_replay_model(first_viewmodel.template_id, camera)
				apply_snapshot_state(replay_viewmodel, first_viewmodel, second_viewmodel, viewmodel_alpha)
			end
		end
	end

	ctx.skip_death_replay = finish_replay
	ctx.start_death_replay = function(on_complete)
		if ctx.replay_active then
			finish_replay()
		end
		if samples:size() < 2 then
			if on_complete then
				task.defer(on_complete)
			end
			return false
		end

		local timeline = ReplayTimeline.new(samples:values(), ctx.replay_death_time, POST_DEATH_SECONDS)
		if not timeline then
			if on_complete then
				task.defer(on_complete)
			end
			return false
		end
		local replay_samples = timeline.samples
		local first_time = timeline.first_time
		local last_time = timeline.last_time
		local death_time = timeline.death_time
		local duration = timeline.duration

		local camera = workspace.CurrentCamera
		if not camera then
			if on_complete then
				task.defer(on_complete)
			end
			return false
		end

		if pending_lethal_data
			and os.clock() - pending_lethal_data.received_at <= LETHAL_DATA_MAX_AGE
		then
			active_kill_data = pending_lethal_data
		else
			active_kill_data = nil
		end
		pending_lethal_data = nil
		projectile_player:prepare(shot_buffer, active_kill_data, first_time, last_time, death_time)
		seed_playing_sounds()
		sound_player:prepare(sound_buffer, replay_shots, first_time, last_time, os.clock())

		replay_token += 1
		local token = replay_token
		ctx.replay_active = true
		ctx.replay_capture_pending = false
		completion_callback = on_complete
		gui.Enabled = true
		if ctx.render then
			ctx.render()
		end
		previous_camera_state = {
			subject = camera.CameraSubject,
			fov = camera.FieldOfView,
		}

		replay_world = Instance.new("Folder")
		replay_world.Name = "DeathReplayWorld"
		replay_world:SetAttribute(REPLAY_CLONE_ATTRIBUTE, true)
		replay_world.Parent = workspace
		mute_live_sounds()
		hide_live_dynamic_entities(camera)

		local used_template_ids = {}
		for _, sample in replay_samples do
			for _, state in sample.actors do
				used_template_ids[state.template_id] = true
			end
			if sample.viewmodel then
				used_template_ids[sample.viewmodel.template_id] = true
			end
		end
		for template_id in used_template_ids do
			create_replay_model(template_id, camera)
		end

		camera.CameraType = Enum.CameraType.Scriptable
		render_replay_frame(camera, replay_samples[1], replay_samples[1], 0, first_time - death_time, false)
		projectile_player:update(first_time)
		sound_player:update(first_time, replay_world)

		local started_at = os.clock()
		playback_connection = RunService.Heartbeat:Connect(function()
			if replay_token ~= token or not ctx.replay_active then
				return
			end
			local elapsed = os.clock() - started_at
			projectile_player:merge_lethal(active_kill_data, first_time, death_time)
			if elapsed >= duration then
				projectile_player:update(last_time)
				sound_player:update(last_time, replay_world)
				finish_replay()
				return
			end

			hide_live_dynamic_entities(camera)
			local replay_time = first_time + elapsed
			local first, second, alpha = timeline:get_frame(replay_time)
			render_replay_frame(camera, first, second, alpha, replay_time - death_time, false)
			projectile_player:update(replay_time)
			sound_player:update(replay_time, replay_world)
			if active_kill_data then
				header.Text = string.format(
					"BODY_CAM.mp4  //  %s   %04.1f",
					string.upper(active_kill_data.killer_name),
					math.max(duration - elapsed, 0)
				)
			else
				header.Text = string.format("BODYCAM REPLAY   %04.1f", math.max(duration - elapsed, 0))
			end
		end)
		return true
	end

	monitor_sound_root(workspace)
	monitor_sound_root(SoundService)
	monitor_sound_root(ctx.player:WaitForChild("PlayerGui"))
	seed_playing_sounds()

	skip_button.Activated:Connect(function()
		if ctx.replay_active then
			finish_replay()
		end
	end)

	UserInputService.InputBegan:Connect(function(input)
		if ctx.replay_active and input.KeyCode == Enum.KeyCode.Space then
			finish_replay()
		end
	end)

	RunService.Heartbeat:Connect(function(delta_time)
		local capture_pending = ctx.replay_capture_pending == true
		if ctx.replay_active or (ctx.menu_open and not capture_pending) then
			return
		end
		local character = ctx.player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local camera = workspace.CurrentCamera
		if not camera or (not capture_pending and (not humanoid or humanoid.Health <= 0)) then
			return
		end

		local viewmodel = not capture_pending and find_active_viewmodel(camera) or nil
		if not capture_pending then
			network_accumulator += delta_time
			if network_accumulator >= POV_NETWORK_INTERVAL then
				network_accumulator %= POV_NETWORK_INTERVAL
				local viewmodel_offset = nil
				if viewmodel then
					local success, pivot = pcall(function()
						return viewmodel:GetPivot()
					end)
					if success then
						viewmodel_offset = camera.CFrame:ToObjectSpace(pivot)
					end
				end
				replay_camera_remote:FireServer({
					camera_cframe = camera.CFrame,
					field_of_view = camera.FieldOfView,
					viewmodel_offset = viewmodel_offset,
				})
			end
		end

		if not capture_pending and not ctx.equipped then
			return
		end
		record_accumulator += delta_time
		if record_accumulator < RECORD_INTERVAL then
			return
		end
		record_accumulator %= RECORD_INTERVAL

		local evicted_sample = samples:push({
			time = os.clock(),
			cframe = camera.CFrame,
			fov = camera.FieldOfView,
			actors = capture_actors(),
			viewmodel = viewmodel and capture_model(viewmodel, "viewmodel") or nil,
		})
		if evicted_sample then
			samples_since_prune += 1
			if samples_since_prune >= 20 then
				samples_since_prune = 0
				prune_unused_templates()
			end
		end
	end)
end

return death_replay_controller
