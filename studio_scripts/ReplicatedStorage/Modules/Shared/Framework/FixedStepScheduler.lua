-- FixedStepScheduler gives many entities independent, staggered update budgets.
-- Why: running expensive perception or path queries for every NPC on every Heartbeat scales
-- with frame rate and creates synchronized spikes. Scheduling by deadline makes cost depend
-- on the declared simulation frequency instead.
--
-- Limits: this is cooperative scheduling, not a job system. Callers must keep each scheduled
-- unit bounded and choose an interval appropriate for gameplay responsiveness.

local fixed_step_scheduler = {}
fixed_step_scheduler.__index = fixed_step_scheduler

function fixed_step_scheduler.new(default_interval: number, phase_count: number?)
	assert(type(default_interval) == "number" and default_interval > 0, "default_interval must be positive")
	return setmetatable({
		default_interval = default_interval,
		phase_count = math.max(math.floor(phase_count or 8), 1),
		next_times = setmetatable({}, { __mode = "k" }),
		next_phase = 0,
	}, fixed_step_scheduler)
end

function fixed_step_scheduler:should_run(key: any, now: number?, interval: number?): boolean
	local current_time = now or os.clock()
	local step = interval or self.default_interval
	assert(type(step) == "number" and step > 0, "interval must be positive")
	local next_time = self.next_times[key]
	if next_time == nil then
		local phase = self.next_phase % self.phase_count
		self.next_phase += 1
		self.next_times[key] = current_time + step + step * phase / self.phase_count
		return true
	end
	if current_time < next_time then
		return false
	end
	local elapsed_steps = math.floor((current_time - next_time) / step)
	self.next_times[key] = next_time + (elapsed_steps + 1) * step
	return true
end

function fixed_step_scheduler:forget(key: any)
	self.next_times[key] = nil
end

function fixed_step_scheduler:clear()
	table.clear(self.next_times)
	self.next_phase = 0
end

return fixed_step_scheduler

