local SoundService = game:GetService("SoundService")

local replay_sound_player = {}
replay_sound_player.__index = replay_sound_player

local SHOT_MATCH_SECONDS = 0.3
local SHOT_MATCH_DISTANCE = 16
local LATE_SOUND_LEAD_SECONDS = 0.2
local REPLAY_SOUND_ATTRIBUTE = "DeathReplaySound"

function replay_sound_player.new()
	return setmetatable({
		events = {},
		active = {},
	}, replay_sound_player)
end

function replay_sound_player:prepare(sound_buffer, replay_shots, first_time, last_time, capture_end_time)
	table.clear(self.events)
	for _, event in sound_buffer do
		if event.time >= first_time and event.time <= capture_end_time then
			local replay_event = table.clone(event)
			local closest_shot_time = nil
			local closest_error = math.huge
			if typeof(event.position) == "Vector3" then
				for _, shot in replay_shots do
					local time_error = math.abs(event.time - shot.time)
					if time_error <= SHOT_MATCH_SECONDS
						and time_error < closest_error
						and (event.position - shot.origin).Magnitude <= SHOT_MATCH_DISTANCE
					then
						closest_shot_time = shot.time
						closest_error = time_error
					end
				end
			end
			if closest_shot_time then
				replay_event.time = closest_shot_time
			elseif replay_event.time > last_time then
				replay_event.time = math.max(first_time, last_time - LATE_SOUND_LEAD_SECONDS)
			end
			if replay_event.stopped_time and replay_event.stopped_time > last_time then
				replay_event.stopped_time = nil
			end
			replay_event.started = false
			table.insert(self.events, replay_event)
		end
	end
	table.sort(self.events, function(first, second)
		return first.time < second.time
	end)
end

function replay_sound_player:start(event, replay_world)
	if not event.template then
		return
	end
	local sound = event.template:Clone()
	sound:SetAttribute(REPLAY_SOUND_ATTRIBUTE, true)
	local container = sound
	if typeof(event.position) == "Vector3" and replay_world then
		local emitter = Instance.new("Part")
		emitter.Name = "ReplaySoundEmitter"
		emitter:SetAttribute(REPLAY_SOUND_ATTRIBUTE, true)
		emitter.Anchored = true
		emitter.CanCollide = false
		emitter.CanQuery = false
		emitter.CanTouch = false
		emitter.Transparency = 1
		emitter.Size = Vector3.new(0.05, 0.05, 0.05)
		emitter.CFrame = CFrame.new(event.position)
		emitter.Parent = replay_world
		sound.Parent = emitter
		container = emitter
	else
		sound.Parent = SoundService
	end
	pcall(function()
		sound.TimePosition = math.max(event.time_position or 0, 0)
	end)
	sound:Play()
	local active_sound = {
		sound = sound,
		container = container,
		stopped_time = event.stopped_time,
	}
	table.insert(self.active, active_sound)
	sound.Ended:Once(function()
		if container.Parent then
			container:Destroy()
		end
	end)
end

function replay_sound_player:update(replay_time, replay_world)
	for _, event in self.events do
		if not event.started and event.time <= replay_time then
			event.started = true
			self:start(event, replay_world)
		end
	end
	for index = #self.active, 1, -1 do
		local active_sound = self.active[index]
		if not active_sound.sound.Parent
			or (active_sound.stopped_time and active_sound.stopped_time <= replay_time)
		then
			if active_sound.container.Parent then
				active_sound.container:Destroy()
			end
			table.remove(self.active, index)
		end
	end
end

function replay_sound_player:clear()
	for _, active_sound in self.active do
		if active_sound.container and active_sound.container.Parent then
			active_sound.container:Destroy()
		elseif active_sound.sound and active_sound.sound.Parent then
			active_sound.sound:Destroy()
		end
	end
	table.clear(self.active)
	table.clear(self.events)
end

return replay_sound_player

