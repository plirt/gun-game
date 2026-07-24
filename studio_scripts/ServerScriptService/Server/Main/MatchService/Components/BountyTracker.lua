-- BountyTracker is a reusable state machine layered over match scoring.
-- Inputs are player deaths and time; outputs are a serializable bounty record plus reward
-- callbacks. It does not know about UI, remotes, teams, or a particular match mode.
--
-- Invariant: at most one target owns HVT attributes. clear() is the only transition that
-- removes them, so round resets, disconnects, claims, and survival share the same cleanup.

local bounty_tracker = {}
bounty_tracker.__index = bounty_tracker

function bounty_tracker.new(state, constants, is_player, award_cash)
	assert(type(state) == "table", "BountyTracker requires match state")
	assert(type(is_player) == "function", "BountyTracker requires is_player")
	assert(type(award_cash) == "function", "BountyTracker requires award_cash")
	return setmetatable({
		state = state,
		constants = constants,
		is_player = is_player,
		award_cash = award_cash,
	}, bounty_tracker)
end

function bounty_tracker:clear()
	local bounty = self.state.bounty
	if bounty and bounty.target and bounty.target.Parent then
		bounty.target:SetAttribute("IsHighValueTarget", nil)
		bounty.target:SetAttribute("BountyReward", nil)
	end
	self.state.bounty = nil
end

function bounty_tracker:reset()
	self:clear()
	table.clear(self.state.kill_streaks)
end

function bounty_tracker:mark(player: Player)
	local reward = self.constants.BOUNTY_BASE_REWARD
	self.state.bounty = {
		target = player,
		reward = reward,
		expires_at = os.clock() + self.constants.BOUNTY_SURVIVE_SECONDS,
	}
	player:SetAttribute("IsHighValueTarget", true)
	player:SetAttribute("BountyReward", reward)
end

function bounty_tracker:on_death(killer, victim)
	if not self.is_player(victim) then
		return
	end
	self.state.kill_streaks[victim] = 0
	local active_bounty = self.state.bounty
	if active_bounty and active_bounty.target == victim then
		if self.is_player(killer) and killer ~= victim then
			self.award_cash(killer, active_bounty.reward, "BountyClaim")
		end
		self:clear()
	end
	if not self.is_player(killer) or killer == victim then
		return
	end
	local streak = (self.state.kill_streaks[killer] or 0) + 1
	self.state.kill_streaks[killer] = streak
	if self.state.bounty and self.state.bounty.target == killer then
		local bounty = self.state.bounty
		bounty.reward += self.constants.BOUNTY_REWARD_PER_KILL
		local remaining = math.max(bounty.expires_at - os.clock(), 0)
		bounty.expires_at = os.clock()
			+ math.min(
				remaining + self.constants.BOUNTY_TIME_PER_KILL,
				self.constants.BOUNTY_MAX_REMAINING_SECONDS
			)
		killer:SetAttribute("BountyReward", bounty.reward)
	elseif not self.state.bounty and streak >= self.constants.BOUNTY_STREAK_THRESHOLD then
		self:mark(killer)
	end
end

function bounty_tracker:resolve_expired(now: number): boolean
	local bounty = self.state.bounty
	if not bounty or now < bounty.expires_at then
		return false
	end
	local target = bounty.target
	local character = target and target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if target and target.Parent and humanoid and humanoid.Health > 0 then
		self.award_cash(target, bounty.reward, "BountySurvived")
		self.state.kill_streaks[target] = 0
	end
	self:clear()
	return true
end

function bounty_tracker:on_player_removing(player: Player)
	self.state.kill_streaks[player] = nil
	if self.state.bounty and self.state.bounty.target == player then
		self:clear()
	end
end

return bounty_tracker

