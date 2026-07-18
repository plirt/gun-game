local ContentProvider = game:GetService("ContentProvider")

local gun_animation_controller = {}

local function get_animator(viewmodel: Model): Animator?
	local animation_controller = viewmodel:FindFirstChildWhichIsA("AnimationController")
	local humanoid = viewmodel:FindFirstChildWhichIsA("Humanoid")
	local animation_parent = animation_controller or humanoid
	if not animation_parent then
		return nil
	end

	local animator = animation_parent:FindFirstChildWhichIsA("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animation_parent
	end
	return animator
end

local function get_animation_priority(animation_name: string): Enum.AnimationPriority
	if animation_name == "Idle" then
		return Enum.AnimationPriority.Idle
	elseif animation_name == "Fire" or animation_name == "ADS" then
		return Enum.AnimationPriority.Action4
	elseif animation_name == "Equip" or string.find(animation_name, "Reload", 1, true) then
		return Enum.AnimationPriority.Action3
	end
	return Enum.AnimationPriority.Action
end

function gun_animation_controller.collect(viewmodel: Model): { Animation }
	local animations = {}
	for _, descendant in viewmodel:GetDescendants() do
		if descendant:IsA("Animation") and descendant.AnimationId ~= "" then
			table.insert(animations, descendant)
		end
	end
	return animations
end

function gun_animation_controller.preload_assets(viewmodel: Model)
	local preload_list = gun_animation_controller.collect(viewmodel)
	if #preload_list == 0 then
		return
	end
	pcall(function()
		ContentProvider:PreloadAsync(preload_list)
	end)
end

function gun_animation_controller.find(viewmodel: Model, animation_name: string): Animation?
	for _, animation in gun_animation_controller.collect(viewmodel) do
		if animation.Name == animation_name then
			return animation
		end
	end
	return nil
end

function gun_animation_controller.load(viewmodel: Model, animation: Animation?): AnimationTrack?
	local animator = get_animator(viewmodel)
	if not animation or not animator then
		return nil
	end

	local track = animator:LoadAnimation(animation)
	track.Name = animation.Name
	track.Priority = get_animation_priority(animation.Name)
	return track
end

function gun_animation_controller.get_duration(track: AnimationTrack?, fallback_duration: number, speed: number?): number
	if not track or track.Length <= 0 then
		return fallback_duration
	end
	return track.Length / math.max(speed or 1, 0.01)
end

return gun_animation_controller
