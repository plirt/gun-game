local remote_rate_limiter = {}

function remote_rate_limiter.new(rate_per_second: number, burst_capacity: number)
	assert(rate_per_second > 0, "rate_per_second must be positive")
	assert(burst_capacity > 0, "burst_capacity must be positive")
	return {
		rate_per_second = rate_per_second,
		burst_capacity = burst_capacity,
		buckets = setmetatable({}, { __mode = "k" }),
	}
end

function remote_rate_limiter.allow(limiter, key: Instance, cost: number?): boolean
	local now = os.clock()
	local bucket = limiter.buckets[key]
	if not bucket then
		bucket = {
			tokens = limiter.burst_capacity,
			last_update = now,
		}
		limiter.buckets[key] = bucket
	else
		local elapsed = math.max(now - bucket.last_update, 0)
		bucket.tokens = math.min(
			limiter.burst_capacity,
			bucket.tokens + elapsed * limiter.rate_per_second
		)
		bucket.last_update = now
	end

	local requested_cost = math.max(cost or 1, 0)
	if bucket.tokens < requested_cost then
		return false
	end
	bucket.tokens -= requested_cost
	return true
end

function remote_rate_limiter.clear(limiter, key: Instance)
	limiter.buckets[key] = nil
end

return remote_rate_limiter

