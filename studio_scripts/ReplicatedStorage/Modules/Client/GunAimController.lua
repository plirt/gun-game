local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local gun_aim_controller = {}

function gun_aim_controller.report(manager, force: boolean?)
	if not manager.camera then
		manager.camera = workspace.CurrentCamera
	end
	local now = os.clock()
	local should_report = force or manager.aiming ~= manager.last_aim_reported or (manager.aiming and now >= manager.next_aim_report_time)
	if not should_report or not manager.camera then
		return
	end
	manager.next_aim_report_time = now + 0.12
	manager.last_aim_reported = manager.aiming
	if manager.aiming then
		remotes.WeaponAim:FireServer(manager.gun_name, true, manager.camera.CFrame.Position, manager.camera.CFrame.LookVector)
	else
		remotes.WeaponAim:FireServer(manager.gun_name, false)
	end
end

function gun_aim_controller.command_targeted_npc(manager): boolean
	if not manager:is_action_ready() or not manager.aiming then
		return false
	end
	if not manager.camera then
		manager.camera = workspace.CurrentCamera
	end
	if not manager.camera then
		return false
	end
	remotes.NpcCommand:FireServer(manager.gun_name, manager.camera.CFrame.Position, manager.camera.CFrame.LookVector)
	return true
end

function gun_aim_controller.set_aiming(manager, value: boolean)
	manager.aiming = value and manager:is_action_ready() and not manager.reloading
	gun_aim_controller.report(manager, true)
end

return gun_aim_controller

