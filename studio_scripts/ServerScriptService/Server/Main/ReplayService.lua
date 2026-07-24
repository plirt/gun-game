local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RingBuffer = require(ReplicatedStorage.Modules.Shared.Framework.RingBuffer)
local constants = require(script.Parent.ServerConstants)
local ReplayEventArchive = require(script.Components.ReplayEventArchive)

local replay_service = {}

local PRE_DEATH_HISTORY_SECONDS = 4.5
local POST_DEATH_SECONDS = 3
local CAMERA_HISTORY_SECONDS = PRE_DEATH_HISTORY_SECONDS + POST_DEATH_SECONDS
local CAMERA_SAMPLE_INTERVAL = constants.REPLAY_CAMERA_SAMPLE_INTERVAL
local MAX_CAMERA_SAMPLES = math.ceil(CAMERA_HISTORY_SECONDS / CAMERA_SAMPLE_INTERVAL) + 2
local MAX_CAMERA_DISTANCE_FROM_CHARACTER = 20
local MAX_VIEWMODEL_OFFSET = 12

local camera_histories = setmetatable({}, { __mode = "k" })
local last_camera_sample_at = setmetatable({}, { __mode = "k" })
local event_archive = nil
local lethal_connection = nil

local function is_finite_number(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function is_valid_cframe(value)
	if typeof(value) ~= "CFrame" then
		return false
	end
	local position = value.Position
	return is_finite_number(position.X)
		and is_finite_number(position.Y)
		and is_finite_number(position.Z)
		and position.Magnitude < 1000000
end

local function get_character_focus(player)
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local focus = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	return focus and focus:IsA("BasePart") and focus or nil
end

local function validate_camera_sample(player, payload)
	if type(payload) ~= "table" or not is_valid_cframe(payload.camera_cframe) then
		return nil
	end
	local focus = get_character_focus(player)
	if not focus or (payload.camera_cframe.Position - focus.Position).Magnitude > MAX_CAMERA_DISTANCE_FROM_CHARACTER then
		return nil
	end

	local field_of_view = payload.field_of_view
	if not is_finite_number(field_of_view) then
		return nil
	end
	field_of_view = math.clamp(field_of_view, 30, 100)

	local viewmodel_offset = payload.viewmodel_offset
	if viewmodel_offset ~= nil then
		if not is_valid_cframe(viewmodel_offset) or viewmodel_offset.Position.Magnitude > MAX_VIEWMODEL_OFFSET then
			viewmodel_offset = nil
		end
	end

	return {
		camera_cframe = payload.camera_cframe,
		field_of_view = field_of_view,
		viewmodel_offset = viewmodel_offset,
	}
end

local function record_camera_sample(player, payload)
	local now = workspace:GetServerTimeNow()
	local last_sample = last_camera_sample_at[player] or 0
	if now - last_sample < CAMERA_SAMPLE_INTERVAL then
		return
	end

	local sample = validate_camera_sample(player, payload)
	if not sample then
		return
	end
	last_camera_sample_at[player] = now
	sample.time = now

	local history = camera_histories[player]
	if not history then
		history = RingBuffer.new(MAX_CAMERA_SAMPLES)
		camera_histories[player] = history
	end
	history:push(sample)
end

local function serialize_camera_history(player, lethal_time)
	local serialized = {}
	local history = camera_histories[player]
	if not history then
		return serialized
	end
	local oldest_time = lethal_time - CAMERA_HISTORY_SECONDS
	for _, sample in history:values() do
		if sample.time >= oldest_time then
			table.insert(serialized, {
				offset = sample.time - lethal_time,
				camera_cframe = sample.camera_cframe,
				field_of_view = sample.field_of_view,
				viewmodel_offset = sample.viewmodel_offset,
			})
		end
	end
	return serialized
end

local function get_killer_name(attacker)
	if attacker:IsA("Player") then
		return attacker.DisplayName
	end
	return attacker.Name
end

function replay_service.notify_lethal_shot(ctx, attacker, humanoid, application, gun_name)
	local victim_character = humanoid.Parent
	local victim = victim_character and ctx.Players:GetPlayerFromCharacter(victim_character)
	if not victim or not victim.Parent or not attacker or attacker == victim then
		return
	end

	local lethal_time = workspace:GetServerTimeNow()
	local killer_player = attacker:IsA("Player") and attacker or nil
	local killer_name = get_killer_name(attacker)
	local function send_replay_data()
		if not victim.Parent then
			return
		end
		ctx.death_replay_data_remote:FireClient(victim, {
			version = 3,
			lethal_time = lethal_time,
			killer_user_id = killer_player and killer_player.UserId or nil,
			killer_name = killer_name,
			gun_name = type(gun_name) == "string" and gun_name or nil,
			origin = application.origin,
			hit_position = application.position,
			direction = application.direction,
			camera_samples = killer_player and serialize_camera_history(killer_player, lethal_time) or {},
			combat_events = event_archive and event_archive:serialize(lethal_time) or {},
		})
	end
	send_replay_data()
	if killer_player then
		task.delay(POST_DEATH_SECONDS, send_replay_data)
	end
end

function replay_service.setup(ctx)
	ctx.replay_camera_snapshot_remote = ctx.remote_map.ReplayCameraSnapshot
	ctx.death_replay_data_remote = ctx.remote_map.DeathReplayData
	local event_stream = ctx.runtime:get("CombatEventStream")
	event_archive = ReplayEventArchive.new(event_stream, CAMERA_HISTORY_SECONDS, 256)
	lethal_connection = event_stream:subscribe("lethal_hit", function(event)
		replay_service.notify_lethal_shot(ctx, event.actor, event.humanoid, {
			origin = event.origin,
			position = event.position,
			direction = event.direction,
		}, event.item_id)
	end)

	ctx.replay_camera_snapshot_remote.OnServerEvent:Connect(function(player, payload)
		record_camera_sample(player, payload)
	end)
	ctx.Players.PlayerRemoving:Connect(function(player)
		camera_histories[player] = nil
		last_camera_sample_at[player] = nil
	end)
end

return replay_service
