local npc_interaction_controller = {}

local npc_threat_service = require(script.Parent.npc_threat_service)

local ZIPTIE_PROMPT_NAME = "ZiptiePrompt"

local function can_ziptie(agent, player, prompt)
	local state_name = npc_threat_service.get_state(agent.npc)
	if state_name ~= "kneeling" then
		return false
	end

	local character = player.Character
	local player_root = character and character:FindFirstChild("HumanoidRootPart")
	if not player_root then
		return false
	end

	local offset = player_root.Position - agent.root.Position
	if offset.Magnitude > prompt.MaxActivationDistance + 1 then
		return false
	end
	if offset.Magnitude > 0.01 and agent.root.CFrame.LookVector:Dot(offset.Unit) > -0.2 then
		return false
	end
	return true
end

function npc_interaction_controller.get_or_create_ziptie_prompt(agent)
	local prompt = agent.root:FindFirstChild(ZIPTIE_PROMPT_NAME)
	if prompt then
		return prompt
	end

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = ZIPTIE_PROMPT_NAME
	prompt.ActionText = "Ziptie"
	prompt.ObjectText = "Kneeling suspect"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 1.4
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = agent.root
	prompt.Triggered:Connect(function(player)
		if can_ziptie(agent, player, prompt) then
			npc_threat_service.set_state(agent.npc, "restrained", player)
			prompt.Enabled = false
		end
	end)
	return prompt
end

function npc_interaction_controller.update(_, agent, state_name)
	local prompt = agent.root:FindFirstChild(ZIPTIE_PROMPT_NAME)
	if prompt then
		prompt.Enabled = state_name == "kneeling"
	end
	if state_name == "kneeling" then
		npc_interaction_controller.get_or_create_ziptie_prompt(agent).Enabled = true
	end
end
return npc_interaction_controller


