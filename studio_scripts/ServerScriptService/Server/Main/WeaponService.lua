local weapon_service = {}

local weapon_damage_resolver = require(script.Parent.WeaponDamageResolver)
local weapon_fire_validator = require(script.Parent.WeaponFireValidator)
local weapon_hit_scan_service = require(script.Parent.WeaponHitScanService)
local weapon_reload_service = require(script.Parent.WeaponReloadService)
local weapon_runtime_store = require(script.Parent.WeaponRuntimeStore)
local CombatReplicationService = require(script.Parent.Combat.CombatReplicationService)
local HitscanDriver = require(script.Parent.Combat.Drivers.HitscanDriver)
local constants = require(script.Parent.ServerConstants)
local RemoteRateLimiter = require(script.Parent.RemoteRateLimiter)

local fire_remote_limiter = RemoteRateLimiter.new(
	constants.WEAPON_FIRE_REMOTE_RATE,
	constants.WEAPON_FIRE_REMOTE_BURST
)
local reload_remote_limiter = RemoteRateLimiter.new(
	constants.WEAPON_RELOAD_REMOTE_RATE,
	constants.WEAPON_RELOAD_REMOTE_BURST
)
local sync_sequences = setmetatable({}, { __mode = "k" })
local weapon_state_delivery = setmetatable({}, { __mode = "k" })
local pending_hit_counts = setmetatable({}, { __mode = "k" })
local hit_confirm_scheduled = setmetatable({}, { __mode = "k" })
local WEAPON_STATE_SEND_INTERVAL = 0.1
local HIT_CONFIRM_SEND_INTERVAL = 0.03
local hit_scan_dependencies = nil
local combat_replication = nil

local function next_sync_sequence(player, gun_name)
	local sequences = sync_sequences[player]
	if not sequences then
		sequences = {}
		sync_sequences[player] = sequences
	end
	sequences[gun_name] = (sequences[gun_name] or 0) + 1
	return sequences[gun_name]
end

local function get_weapon_state_delivery(player)
	local delivery = weapon_state_delivery[player]
	if delivery then
		return delivery
	end
	delivery = {
		last_sent = {},
		pending = {},
		scheduled = {},
	}
	weapon_state_delivery[player] = delivery
	return delivery
end

local function send_weapon_state(ctx, player, gun_name, accepted, code)
	local snapshot = weapon_runtime_store.get_snapshot(player, gun_name)
	if not snapshot or not ctx.weapon_state_remote then
		return
	end
	local delivery = get_weapon_state_delivery(player)
	delivery.pending[gun_name] = nil
	snapshot.sequence = next_sync_sequence(player, snapshot.gun_name)
	snapshot.accepted = accepted
	snapshot.code = code
	delivery.last_sent[gun_name] = os.clock()
	ctx.weapon_state_remote:FireClient(player, snapshot)
end

local function queue_weapon_state(ctx, player, gun_name, accepted, code)
	if type(gun_name) ~= "string" or gun_name == "" then
		return
	end
	local delivery = get_weapon_state_delivery(player)
	delivery.pending[gun_name] = {
		accepted = accepted,
		code = code,
	}
	if delivery.scheduled[gun_name] then
		return
	end
	delivery.scheduled[gun_name] = true
	local elapsed = os.clock() - (delivery.last_sent[gun_name] or 0)
	local delay_time = math.max(WEAPON_STATE_SEND_INTERVAL - elapsed, 0)
	task.delay(delay_time, function()
		if not player.Parent then
			return
		end
		local latest_delivery = weapon_state_delivery[player]
		local pending = latest_delivery and latest_delivery.pending[gun_name]
		if latest_delivery then
			latest_delivery.scheduled[gun_name] = nil
		end
		if pending then
			send_weapon_state(ctx, player, gun_name, pending.accepted, pending.code)
		end
	end)
end

local function report_confirmed_hits(ctx, player, applications)
	if #applications == 0 or not ctx.weapon_hit_confirm_remote then
		return
	end
	pending_hit_counts[player] = (pending_hit_counts[player] or 0) + #applications
	if hit_confirm_scheduled[player] then
		return
	end
	hit_confirm_scheduled[player] = true
	task.delay(HIT_CONFIRM_SEND_INTERVAL, function()
		hit_confirm_scheduled[player] = nil
		local hit_count = pending_hit_counts[player] or 0
		pending_hit_counts[player] = nil
		if hit_count > 0 and player.Parent then
			ctx.weapon_hit_confirm_remote:FireClient(player, hit_count)
		end
	end)
end

local function on_fire(ctx, player, gun_name, origin, direction_payload, fire_time)
	local validation = weapon_fire_validator.validate(player, gun_name, origin, direction_payload, fire_time)
	if not validation.ok then
		queue_weapon_state(ctx, player, gun_name, false, validation.code)
		return
	end
	weapon_runtime_store.consume_fire(validation.weapon_state, os.clock())
	queue_weapon_state(ctx, player, validation.gun_name, true, nil)
	local result = ctx.runtime:get("CombatPipeline"):activate(player, "Hitscan", {
		item_id = validation.gun_name,
		origin = validation.origin,
		directions = validation.directions,
		config = validation.config,
		fire_time = validation.fire_time,
		play_sound = true,
		on_applications = function(applications)
			report_confirmed_hits(ctx, player, applications)
		end,
	})
	if not result.ok then
		queue_weapon_state(ctx, player, validation.gun_name, false, result.code)
	end
end

function weapon_service.setup(ctx)
	ctx.weapon_replicate_remote = ctx.remote_map.WeaponReplicate
	ctx.weapon_hit_confirm_remote = ctx.remote_map.WeaponHitConfirm
	ctx.weapon_state_remote = ctx.remote_map.WeaponState
	hit_scan_dependencies = {
		Players = ctx.Players,
		Ballistics = ctx.Ballistics,
	}
	local event_stream = ctx.runtime:get("CombatEventStream")
	ctx.runtime:get("WeaponDriverRegistry"):replace("Hitscan", HitscanDriver.new({
		event_stream = event_stream,
		combat_authority = ctx.combat_authority,
		npc_hit_data = ctx.npc_hit_data,
		hit_scan_dependencies = hit_scan_dependencies,
		hit_scan_service = weapon_hit_scan_service,
		damage_resolver = weapon_damage_resolver,
	}))
	combat_replication = CombatReplicationService.new(event_stream, {
		Players = ctx.Players,
		weapon_replicate_remote = ctx.weapon_replicate_remote,
	})
	ctx.remotes.WeaponReload.OnServerEvent:Connect(function(player, gun_name)
		if not RemoteRateLimiter.allow(reload_remote_limiter, player) then
			return
		end
		local result = weapon_reload_service.reload(player, gun_name, function()
			send_weapon_state(ctx, player, gun_name, true, nil)
		end)
		if not result.ok then
			queue_weapon_state(ctx, player, gun_name, false, result.code)
		end
	end)
	ctx.remotes.WeaponFire.OnServerEvent:Connect(function(player, gun_name, origin, directions, fire_time)
		if not RemoteRateLimiter.allow(fire_remote_limiter, player) then
			return
		end
		on_fire(ctx, player, gun_name, origin, directions, fire_time)
	end)
	ctx.Players.PlayerRemoving:Connect(function(player)
		sync_sequences[player] = nil
		weapon_state_delivery[player] = nil
		pending_hit_counts[player] = nil
		hit_confirm_scheduled[player] = nil
		RemoteRateLimiter.clear(fire_remote_limiter, player)
		RemoteRateLimiter.clear(reload_remote_limiter, player)
	end)
end

return weapon_service

