local replay_timeline = {}
replay_timeline.__index = replay_timeline

function replay_timeline.new(samples, requested_death_time, post_death_seconds)
	if type(samples) ~= "table" or #samples < 2 then
		return nil
	end
	local first_time = samples[1].time
	local last_time = samples[#samples].time
	local death_time = type(requested_death_time) == "number"
		and math.clamp(requested_death_time, first_time, last_time)
		or math.max(first_time, last_time - post_death_seconds)
	local duration = last_time - first_time
	if duration < 0.25 then
		return nil
	end
	return setmetatable({
		samples = samples,
		first_time = first_time,
		last_time = last_time,
		death_time = death_time,
		duration = duration,
		index = 1,
	}, replay_timeline)
end

function replay_timeline:get_frame(replay_time)
	local samples = self.samples
	while self.index < #samples - 1 and samples[self.index + 1].time < replay_time do
		self.index += 1
	end
	local first = samples[self.index]
	local second = samples[math.min(self.index + 1, #samples)]
	local span = math.max(second.time - first.time, 1 / 240)
	local alpha = math.clamp((replay_time - first.time) / span, 0, 1)
	return first, second, alpha
end

return replay_timeline

