-- ReplaySnapshotCodec converts mutable Roblox models into compact indexed snapshots.
-- Why: dictionary-of-table snapshots allocated one table per body part at 20 Hz. Templates
-- now own stable part ordering, so each frame stores two flat arrays and playback can lerp by
-- index. This keeps exact world reconstruction while substantially reducing GC pressure.
--
-- Limits: structural changes invalidate a template and require recloning. The codec records
-- transforms and local transparency, not arbitrary properties; new replayable properties
-- should be added as parallel sparse channels rather than per-part tables.

local replay_snapshot_codec = {}

function replay_snapshot_codec.index_model(root: Instance)
	local by_key = {}
	local keys = {}
	local parts = {}
	local function walk(parent, parent_path)
		for child_index, child in parent:GetChildren() do
			local child_path = if parent_path == ""
				then tostring(child_index)
				else parent_path .. "/" .. tostring(child_index)
			if child:IsA("BasePart") then
				by_key[child_path] = child
				table.insert(keys, child_path)
				table.insert(parts, child)
			end
			walk(child, child_path)
		end
	end
	walk(root, "")
	return by_key, keys, parts
end

function replay_snapshot_codec.tag_clone(clone: Model, source_by_key, key_attribute: string)
	local clone_by_key = replay_snapshot_codec.index_model(clone)
	for key, clone_part in clone_by_key do
		if source_by_key[key] then
			clone_part:SetAttribute(key_attribute, key)
		end
	end
end

function replay_snapshot_codec.collect_clone_parts(root: Model, keys: { string }, key_attribute: string)
	local by_key = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			local key = descendant:GetAttribute(key_attribute)
			if type(key) == "string" then
				by_key[key] = descendant
			end
		end
	end
	local ordered = table.create(#keys)
	for index, key in keys do
		ordered[index] = by_key[key]
	end
	return by_key, ordered
end

function replay_snapshot_codec.prepare_clone(model: Model, clone_attribute: string)
	model:SetAttribute(clone_attribute, true)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript")
			or descendant:IsA("Animator")
			or descendant:IsA("AnimationController")
		then
			descendant:Destroy()
		elseif descendant:IsA("Sound") then
			descendant:Stop()
		elseif descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("Highlight")
			or descendant:IsA("BillboardGui")
		then
			descendant.Enabled = false
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.CastShadow = false
		elseif descendant:IsA("Humanoid") then
			descendant.AutoRotate = false
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			descendant.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			descendant.NameDisplayDistance = 0
			descendant.PlatformStand = true
		end
	end
end

function replay_snapshot_codec.capture(template, source: Model)
	local cframes = table.create(#template.source_parts)
	local transparencies = table.create(#template.source_parts)
	local captured = 0
	for index, part in template.source_parts do
		if part.Parent and part:IsDescendantOf(source) then
			cframes[index] = part.CFrame
			transparencies[index] = part.LocalTransparencyModifier
			captured += 1
		end
	end
	if captured == 0 then
		return nil
	end
	return {
		cframes = cframes,
		transparencies = transparencies,
	}
end

function replay_snapshot_codec.set_visible(replay_model, visible: boolean)
	for _, part in replay_model.ordered_parts do
		if part then
			part.LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end

function replay_snapshot_codec.apply(replay_model, first_state, second_state, alpha: number)
	if not replay_model or not first_state then
		return
	end
	replay_snapshot_codec.set_visible(replay_model, true)
	local second_cframes = second_state and second_state.cframes
	local second_transparencies = second_state and second_state.transparencies
	for index, first_cframe in first_state.cframes do
		local replay_part = replay_model.ordered_parts[index]
		if replay_part and first_cframe then
			local second_cframe = second_cframes and second_cframes[index]
			local first_transparency = first_state.transparencies[index] or 0
			local second_transparency = second_transparencies and second_transparencies[index]
			if second_cframe then
				replay_part.CFrame = first_cframe:Lerp(second_cframe, alpha)
				replay_part.LocalTransparencyModifier = first_transparency
					+ ((second_transparency or first_transparency) - first_transparency) * alpha
			else
				replay_part.CFrame = first_cframe
				replay_part.LocalTransparencyModifier = first_transparency
			end
		end
	end
end

return replay_snapshot_codec

