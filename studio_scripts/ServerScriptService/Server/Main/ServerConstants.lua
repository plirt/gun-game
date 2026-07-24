local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkProtocol = require(ReplicatedStorage.Modules.Shared.Framework.NetworkProtocol)

local function policy(name: string)
	return assert(NetworkProtocol.get_spec(name), string.format("missing network policy for %s", name))
end

local constants = {
	BACKPACK_COLUMNS = 7,
	BACKPACK_ROWS = 7,
	DEFAULT_MAP_ID = "Default",
	MISSION_CHECK_INTERVAL = 0.35,
	VALID_DIRECTION_MIN_MAGNITUDE = 0.95,
	VALID_DIRECTION_MAX_MAGNITUDE = 1.05,
	MAX_REMOTE_ORIGIN_DISTANCE = 14,
	WEAPON_FIRE_RATE_GRACE_MULTIPLIER = 0.82,
	LAG_COMPENSATION_HISTORY_SECONDS = 1,
	LAG_COMPENSATION_SAMPLE_INTERVAL = 1 / 20,
	LAG_COMPENSATION_PROJECTILE_STEP_TIME = 1 / 180,
	LAG_COMPENSATION_FUTURE_GRACE = 0.075,
	LAG_COMPENSATION_VIEW_INTERPOLATION_SECONDS = 0.1,
	LAG_COMPENSATION_MAX_VIEW_DELAY_SECONDS = 0.35,
	LAG_COMPENSATION_MAX_FIRE_AGE_SECONDS = 0.65,
	LAG_COMPENSATION_HITBOX_PADDING = 0.25,
	WEAPON_AIM_UPDATE_INTERVAL = 1 / policy("WeaponAim").rate,
	MOVEMENT_UPDATE_INTERVAL = 1 / 30,
	MOVEMENT_REMOTE_RATE = policy("MovementCommand").rate,
	MOVEMENT_REMOTE_BURST = policy("MovementCommand").burst,
	WEAPON_FIRE_REMOTE_RATE = policy("WeaponFire").rate,
	WEAPON_FIRE_REMOTE_BURST = policy("WeaponFire").burst,
	WEAPON_RELOAD_REMOTE_RATE = policy("WeaponReload").rate,
	WEAPON_RELOAD_REMOTE_BURST = policy("WeaponReload").burst,
	WEAPON_EQUIP_REMOTE_RATE = policy("WeaponEquip").rate,
	WEAPON_EQUIP_REMOTE_BURST = policy("WeaponEquip").burst,
	SHOP_REMOTE_RATE = policy("ShopRequest").rate,
	SHOP_REMOTE_BURST = policy("ShopRequest").burst,
	MISSION_START_REMOTE_RATE = policy("MissionStart").rate,
	MISSION_START_REMOTE_BURST = policy("MissionStart").burst,
	MATCH_VOTE_UPDATE_INTERVAL = 1 / policy("MatchVote").rate,
	GRENADE_EQUIP_REQUEST_INTERVAL = 1 / policy("GrenadeEquip").rate,
	GRENADE_THROW_REQUEST_INTERVAL = 1 / policy("GrenadeThrow").rate,
	NPC_COMMAND_INTERVAL = 1 / policy("NpcCommand").rate,
	REPLAY_CAMERA_SAMPLE_INTERVAL = 1 / policy("ReplayCameraSnapshot").rate,
	KILL_CASH_REWARD = 100,
	NPC_KILL_CASH_REWARD = 50,
	BOUNTY_STREAK_THRESHOLD = 3,
	BOUNTY_BASE_REWARD = 300,
	BOUNTY_REWARD_PER_KILL = 100,
	BOUNTY_SURVIVE_SECONDS = 45,
	BOUNTY_TIME_PER_KILL = 8,
	BOUNTY_MAX_REMAINING_SECONDS = 60,
}
return constants

