local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player_character_weapon_service = {}

local AttachmentModifier = require(ReplicatedStorage.Modules.Shared.AttachmentModifier)
local player_state = require(script.Parent.PlayerState)
local constants = require(script.Parent.ServerConstants)
local RemoteRateLimiter = require(script.Parent.RemoteRateLimiter)

local CHARACTER_GUN_NAME = "EquippedCharacterGun"
local CHARACTER_GUN_MOTOR_NAME = "CharacterGunMotor"

local equipped_guns = {}
local external_idle_tracks = {}
local external_fire_tracks = {}
local last_equip_requests = setmetatable({}, { __mode = "k" })
local equip_remote_limiter = RemoteRateLimiter.new(
	constants.WEAPON_EQUIP_REMOTE_RATE,
	constants.WEAPON_EQUIP_REMOTE_BURST
)
local EQUIP_REQUEST_INTERVAL = 0.05
local MUTANT_EXTERNAL_C0 = CFrame.Angles(0, math.rad(-180), 0)
local EXTERNAL_IDLE_PRIORITY = Enum.AnimationPriority.Action4
local EXTERNAL_FIRE_PRIORITY = Enum.AnimationPriority.Action4

local function get_external_animation(gun: Model, animation_name: string): Animation?
	local animations = gun:FindFirstChild("Animations")
	local external = animations and animations:FindFirstChild("External")
	local animation = external and external:FindFirstChild(animation_name)
	if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then
		return animation
	end

	animation = animations and animations:FindFirstChild(animation_name)
	if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then
		return animation
	end
	return nil
end

local function get_animator(character: Model?): Animator?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function stop_track_bucket(bucket, player, fade_time)
	local track = bucket[player]
	if track then
		track:Stop(fade_time or 0.12)
		track:Destroy()
		bucket[player] = nil
	end
end

local function stop_external_idle(player)
	stop_track_bucket(external_idle_tracks, player, 0.15)
end

local function stop_external_fire(player)
	stop_track_bucket(external_fire_tracks, player, 0.05)
end

local function stop_matching_tracks(animator: Animator, animation: Animation, kept_track: AnimationTrack?)
	for _, track in animator:GetPlayingAnimationTracks() do
		if track ~= kept_track and track.Animation and track.Animation.AnimationId == animation.AnimationId then
			track:Stop(0.05)
			track:Destroy()
		end
	end
end

local function play_external_idle(player, character, gun)
	stop_external_idle(player)
	local animation = get_external_animation(gun, "Idle")
	if not animation then
		return
	end
	local animator = get_animator(character)
	if not animator then
		return
	end
	local loaded, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not loaded or not track then
		return
	end
	stop_matching_tracks(animator, animation)
	track.Priority = EXTERNAL_IDLE_PRIORITY
	track.Looped = true
	track:Play(0.15, 1, 1)
	external_idle_tracks[player] = track
end

function player_character_weapon_service.play_external_fire(player: Player)
	local character = player.Character
	local gun = character and character:FindFirstChild(CHARACTER_GUN_NAME)
	if not character or not gun then
		return
	end
	local animation = get_external_animation(gun, "Fire")
	if not animation then
		return
	end
	local animator = get_animator(character)
	if not animator then
		return
	end
	stop_external_fire(player)
	local loaded, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not loaded or not track then
		return
	end
	stop_matching_tracks(animator, animation)
	track.Priority = EXTERNAL_FIRE_PRIORITY
	track.Looped = false
	track:Play(0.03, 1, 1)
	external_fire_tracks[player] = track
	track.Stopped:Once(function()
		if external_fire_tracks[player] == track then
			external_fire_tracks[player] = nil
		end
		track:Destroy()
	end)
end

local function setup_part(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function clear_character_gun(player, character)
	stop_external_fire(player)
	stop_external_idle(player)
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local motor = root:FindFirstChild(CHARACTER_GUN_MOTOR_NAME)
		if motor and motor:IsA("Motor6D") then
			motor:Destroy()
		end
	end

	local gun = character:FindFirstChild(CHARACTER_GUN_NAME)
	if gun then
		gun:Destroy()
	end
end

local function get_main_part(gun)
	local main = gun:FindFirstChild("MAIN", true)
	if main and main:IsA("BasePart") then
		return main
	end
	return nil
end

local function attach_to_character(character, gun, gun_name)
	local root = character:FindFirstChild("HumanoidRootPart")
	local main = get_main_part(gun)
	if not root or not root:IsA("BasePart") or not main then
		return false
	end

	gun.PrimaryPart = main
	gun:PivotTo(root.CFrame)
	for _, descendant in gun:GetDescendants() do
		if descendant:IsA("BasePart") then
			setup_part(descendant)
		end
	end

	local motor = Instance.new("Motor6D")
	motor.Name = CHARACTER_GUN_MOTOR_NAME
	motor.Part0 = root
	motor.Part1 = main
	if gun_name == "MUTANT" then
		motor.C0 = MUTANT_EXTERNAL_C0
		motor.C1 = CFrame.identity
	end
	motor.Parent = root
	return true
end

local function equip_character_gun(ctx, player, gun_name)
	local character = player.Character
	if not character then
		return false
	end
	local current_gun = character:FindFirstChild(CHARACTER_GUN_NAME)
	if current_gun and current_gun:GetAttribute("gun_name") == gun_name then
		return true
	end
	clear_character_gun(player, character)
	local guns = ctx.ReplicatedStorage:FindFirstChild("Guns")
	local template = guns and guns:FindFirstChild(gun_name)
	if not template or not template:IsA("Model") then
		return false
	end

	local gun = template:Clone()
	gun.Name = CHARACTER_GUN_NAME
	gun:SetAttribute("gun_name", gun_name)
	local state = player_state.ensure_player_state(player)
	AttachmentModifier.apply_loadout(gun, state.attachments[gun_name])
	gun.Parent = character
	if not attach_to_character(character, gun, gun_name) then
		gun:Destroy()
		return false
	end
	play_external_idle(player, character, gun)
	return true
end

local function can_equip(ctx, player, gun_name)
	if player:GetAttribute("ragdolled") == true then
		return false
	end
	if type(gun_name) ~= "string" or gun_name == "" then
		return false
	end

	local state = player_state.ensure_player_state(player)
	return state.inventory[gun_name] and player_state.is_in_loadout(state, gun_name)
end

local function set_equipped(ctx, player, gun_name, equipped)
	if equipped then
		if not can_equip(ctx, player, gun_name) then
			return
		end
		equipped_guns[player] = gun_name
		equip_character_gun(ctx, player, gun_name)
	else
		equipped_guns[player] = nil
		clear_character_gun(player, player.Character)
	end
end

function player_character_weapon_service.get_equipped_gun(player: Player): string?
	return equipped_guns[player]
end

function player_character_weapon_service.is_equipped(player: Player, gun_name: string): boolean
	return equipped_guns[player] == gun_name
end

function player_character_weapon_service.setup(ctx)

	ctx.remotes.WeaponEquip.OnServerEvent:Connect(function(player, gun_name, equipped)
		if type(equipped) ~= "boolean"
			or not RemoteRateLimiter.allow(equip_remote_limiter, player)
		then
			return
		end
		local now = os.clock()
		local last_request = last_equip_requests[player]
		local is_duplicate = last_request
			and last_request.gun_name == gun_name
			and last_request.equipped == equipped
		if is_duplicate and now - last_request.time < EQUIP_REQUEST_INTERVAL then
			return
		end
		last_equip_requests[player] = {
			time = now,
			gun_name = gun_name,
			equipped = equipped,
		}
		set_equipped(ctx, player, gun_name, equipped)
	end)

	ctx.Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
			if humanoid then
				humanoid.Died:Connect(function()
					equipped_guns[player] = nil
					clear_character_gun(player, character)
				end)
			end

			task.defer(function()
				local gun_name = equipped_guns[player]
				if gun_name and player.Character == character then
					equip_character_gun(ctx, player, gun_name)
				end
			end)
		end)
	end)

	ctx.Players.PlayerRemoving:Connect(function(player)
		equipped_guns[player] = nil
		last_equip_requests[player] = nil
		RemoteRateLimiter.clear(equip_remote_limiter, player)
		stop_external_fire(player)
		stop_external_idle(player)
	end)

	for _, player in ctx.Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
			if humanoid then
				humanoid.Died:Connect(function()
					equipped_guns[player] = nil
					clear_character_gun(player, character)
				end)
			end

			task.defer(function()
				local gun_name = equipped_guns[player]
				if gun_name and player.Character == character then
					equip_character_gun(ctx, player, gun_name)
				end
			end)
		end)
	end
end
return player_character_weapon_service


