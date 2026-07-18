local weapon_service = {}

local weapon_damage_resolver = require(script.Parent.weapon_damage_resolver)
local weapon_fire_validator = require(script.Parent.weapon_fire_validator)
local weapon_hit_scan_service = require(script.Parent.weapon_hit_scan_service)
local weapon_reload_service = require(script.Parent.weapon_reload_service)
local weapon_replication_service = require(script.Parent.weapon_replication_service)
local weapon_runtime_store = require(script.Parent.weapon_runtime_store)

local sync_sequences = setmetatable({}, { __mode = "k" })

local function get_or_create_remote(ctx, name)
	local remote = ctx.remotes:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ctx.remotes
	return remote
end

local function next_sync_sequence(player, gun_name)
	local sequences = sync_sequences[player]
	if not sequences then
		sequences = {}
		sync_sequences[player] = sequences
	end
	sequences[gun_name] = (sequences[gun_name] or 0) + 1
	return sequences[gun_name]
end

local function send_weapon_state(ctx, player, gun_name, accepted, code)
	local snapshot = weapon_runtime_store.get_snapshot(player, gun_name)
	if not snapshot or not ctx.weapon_state_remote then
		return
	end
	snapshot.sequence = next_sync_sequence(player, snapshot.gun_name)
	snapshot.accepted = accepted
	snapshot.code = code
	ctx.weapon_state_remote:FireClient(player, snapshot)
end

local function report_confirmed_hits(ctx, player, applications)
	if #applications > 0 and ctx.weapon_hit_confirm_remote then
		ctx.weapon_hit_confirm_remote:FireClient(player, #applications)
	end
end

local function on_fire(ctx, player, gun_name, origin, direction_payload, fire_time)
	local validation = weapon_fire_validator.validate(ctx, player, gun_name, origin, direction_payload, fire_time)
	if not validation.ok then
		send_weapon_state(ctx, player, gun_name, false, validation.code)
		return
	end
	weapon_runtime_store.consume_fire(validation.weapon_state, os.clock())
	send_weapon_state(ctx, player, validation.gun_name, true, nil)
	weapon_replication_service.replicate_fire(ctx, player, validation.gun_name, validation.origin, validation.directions)

	local damaged_humanoids = {}
	local function apply_results(hit_results)
		local applications = weapon_damage_resolver.resolve(ctx, player, validation.origin, validation.config, hit_results, damaged_humanoids)
		weapon_damage_resolver.apply(ctx, player, applications)
		report_confirmed_hits(ctx, player, applications)
	end
	local results = weapon_hit_scan_service.cast(ctx, player, validation.character, validation.origin, validation.directions, validation.config, validation.fire_time, function(late_result)
		apply_results({ late_result })
	end)
	apply_results(results)
end

function weapon_service.setup(ctx)
	ctx.weapon_hit_confirm_remote = get_or_create_remote(ctx, "WeaponHitConfirm")
	ctx.weapon_state_remote = get_or_create_remote(ctx, "WeaponState")
	ctx.remotes.WeaponReload.OnServerEvent:Connect(function(player, gun_name)
		local result = weapon_reload_service.reload(player, gun_name, function()
			send_weapon_state(ctx, player, gun_name, true, nil)
		end)
		if not result.ok then
			send_weapon_state(ctx, player, gun_name, false, result.code)
		end
	end)
	ctx.remotes.WeaponFire.OnServerEvent:Connect(function(player, gun_name, origin, directions, fire_time)
		on_fire(ctx, player, gun_name, origin, directions, fire_time)
	end)
	ctx.Players.PlayerRemoving:Connect(function(player)
		sync_sequences[player] = nil
	end)
end

return weapon_service
