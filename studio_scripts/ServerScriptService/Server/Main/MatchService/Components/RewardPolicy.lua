-- RewardPolicy is the economy boundary for combat outcomes.
-- Match rules decide what happened; this policy decides whether that outcome is payable and
-- performs one authoritative cash mutation. Keeping economy writes out of MatchService lets
-- other modes reuse scoring without inheriting this game's reward schedule.

local reward_policy = {}

function reward_policy.new(dependencies)
	assert(type(dependencies) == "table", "RewardPolicy dependencies are required")
	assert(type(dependencies.is_player) == "function", "RewardPolicy requires is_player")
	assert(type(dependencies.is_npc) == "function", "RewardPolicy requires is_npc")
	assert(dependencies.player_state, "RewardPolicy requires player_state")
	assert(dependencies.constants, "RewardPolicy requires constants")
	return {
		dependencies = dependencies,
	}
end

function reward_policy.award_cash(policy, player, amount: number, reason: string)
	local dependencies = policy.dependencies
	if not dependencies.is_player(player) or amount <= 0 then
		return false
	end
	local cash_state = dependencies.player_state.ensure_player_state(player)
	cash_state.cash += amount
	dependencies.player_state.sync_cash_leaderstat(player, cash_state)
	dependencies.player_state.mark_dirty(player)
	local shop_updated = dependencies.remotes:FindFirstChild("ShopUpdated")
	if shop_updated and shop_updated:IsA("RemoteEvent") then
		shop_updated:FireClient(player, reason, amount, cash_state.cash)
	end
	return true
end

function reward_policy.award_kill(policy, killer, victim)
	local dependencies = policy.dependencies
	if not dependencies.is_player(killer) then
		return false
	end
	if dependencies.is_player(victim) then
		return reward_policy.award_cash(policy, killer, dependencies.constants.KILL_CASH_REWARD, "KillReward")
	elseif dependencies.is_npc(victim) then
		return reward_policy.award_cash(policy, killer, dependencies.constants.NPC_KILL_CASH_REWARD, "NpcKillReward")
	end
	return false
end

return reward_policy

