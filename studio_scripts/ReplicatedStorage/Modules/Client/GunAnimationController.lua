local ContentProvider = game:GetService("ContentProvider")

local gun_animation_controller = {}
gun_animation_controller.__index = gun_animation_controller

local function get_animator(viewmodel: Model): Animator
	local animation_controller = viewmodel:FindFirstChildWhichIsA("AnimationController")
	local humanoid = viewmodel:FindFirstChildWhichIsA("Humanoid")
	local animation_parent = animation_controller or humanoid
	assert(animation_parent, "Viewmodel needs an AnimationController or Humanoid")

	local animator = animation_parent:FindFirstChildWhichIsA("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animation_parent
	end
	return animator
end

local function get_priority(animation_name: string): Enum.AnimationPriority
	if animation_name == "Idle" then
		return Enum.AnimationPriority.Idle
	elseif animation_name == "Fire" or animation_name == "ADS" then
		return Enum.AnimationPriority.Action4
	elseif animation_name == "Equip" or string.find(animation_name, "Reload", 1, true) then
		return Enum.AnimationPriority.Action3
	end
	return Enum.AnimationPriority.Action
end

local function collect_first_person_animations(gun_model: Model): { Animation }
	local animations_folder = gun_model:FindFirstChild("Animations")
	if not animations_folder then
		return {}
	end

	local animations = {}
	for _, child in animations_folder:GetChildren() do
		if child:IsA("Animation") and child.AnimationId ~= "" then
			table.insert(animations, child)
		end
	end
	return animations
end

function gun_animation_controller.new(viewmodel: Model, gun_model: Model)
	local self = setmetatable({}, gun_animation_controller)
	self.animator = get_animator(viewmodel)
	self.tracks = {}
	self.idle_track = nil
	self.action_track = nil
	self.action_name = nil
	self.action_serial = 0

	local animations = collect_first_person_animations(gun_model)
	if #animations > 0 then
		local success, preload_error = pcall(function()
			ContentProvider:PreloadAsync(animations)
		end)
		if not success then
			warn("Unable to preload viewmodel animations:", preload_error)
		end
	end

	for _, animation in animations do
		local track = self.animator:LoadAnimation(animation)
		track.Name = animation.Name
		track.Priority = get_priority(animation.Name)
		self.tracks[animation.Name] = track
	end

	return self
end

function gun_animation_controller:get_track(animation_name: string): AnimationTrack?
	return self.tracks[animation_name]
end

function gun_animation_controller:play_idle(fade_time: number?, speed: number?): AnimationTrack?
	local track = self.tracks.Idle
	if not track then
		return nil
	end

	track.Priority = Enum.AnimationPriority.Idle
	track.Looped = true
	if not track.IsPlaying then
		track.TimePosition = 0
		track:Play(fade_time or 0.12, 1, speed or 1)
	else
		track:AdjustSpeed(speed or 1)
	end
	track:AdjustWeight(1, fade_time or 0.12)
	self.idle_track = track
	return track
end

function gun_animation_controller:play_action(
	animation_name: string,
	fade_time: number?,
	speed: number?,
	looped: boolean?
): AnimationTrack?
	local track = self.tracks[animation_name]
	if not track then
		return nil
	end

	self.action_serial += 1
	local action_serial = self.action_serial
	local previous_track = self.action_track
	if previous_track and previous_track ~= track and previous_track.IsPlaying then
		previous_track:Stop(fade_time or 0.03)
	end
	if track.IsPlaying then
		track:Stop(0)
	end

	track.Priority = get_priority(animation_name)
	track.Looped = looped == true
	track.TimePosition = 0
	track:Play(fade_time or 0.05, 1, speed or 1)
	self.action_track = track
	self.action_name = animation_name

	track.Stopped:Once(function()
		if self.action_serial == action_serial and self.action_track == track then
			self.action_track = nil
			self.action_name = nil
		end
	end)
	return track
end

function gun_animation_controller:play(
	animation_name: string,
	fade_time: number?,
	speed: number?,
	looped: boolean?
): AnimationTrack?
	if animation_name == "Idle" then
		return self:play_idle(fade_time, speed)
	end
	return self:play_action(animation_name, fade_time, speed, looped)
end

function gun_animation_controller:stop(animation_name: string, fade_time: number?)
	local track = self.tracks[animation_name]
	if not track or not track.IsPlaying then
		return
	end

	if track == self.action_track then
		self.action_serial += 1
		self.action_track = nil
		self.action_name = nil
	elseif track == self.idle_track then
		self.idle_track = nil
	end
	track:Stop(fade_time or 0.05)
end

function gun_animation_controller:stop_all(fade_time: number?)
	self.action_serial += 1
	self.action_track = nil
	self.action_name = nil
	self.idle_track = nil
	for _, track in self.tracks do
		if track.IsPlaying then
			track:Stop(fade_time or 0)
		end
	end
end

function gun_animation_controller.get_duration(
	track: AnimationTrack?,
	fallback_duration: number,
	speed: number?
): number
	if not track or track.Length <= 0 then
		return fallback_duration
	end
	return track.Length / math.max(speed or 1, 0.01)
end

return gun_animation_controller

