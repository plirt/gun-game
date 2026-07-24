-- NetworkProtocol is the single manifest for every game-facing remote.
-- Why: transport class, direction, reliability, and request budget used to be spread across
-- service implementations. A manifest makes the network surface inspectable and prevents a
-- stale RemoteEvent from silently replacing an intended UnreliableRemoteEvent.
--
-- Security boundary: this module describes and constructs transport only. Server handlers
-- must still validate payload meaning and enforce the listed policy; creating a remote never
-- makes client data trustworthy.

local network_protocol = {}

export type RemoteSpec = {
	class_name: "RemoteEvent" | "UnreliableRemoteEvent" | "RemoteFunction",
	direction: "client_to_server" | "server_to_client" | "bidirectional",
	rate: number?,
	burst: number?,
	description: string,
}

local specs: { [string]: RemoteSpec } = {
	WeaponFire = { class_name = "RemoteEvent", direction = "client_to_server", rate = 24, burst = 12, description = "Authoritative weapon fire request" },
	WeaponReload = { class_name = "RemoteEvent", direction = "client_to_server", rate = 4, burst = 2, description = "Reload request" },
	WeaponEquip = { class_name = "RemoteEvent", direction = "client_to_server", rate = 8, burst = 4, description = "Character weapon presentation request" },
	WeaponAim = { class_name = "UnreliableRemoteEvent", direction = "client_to_server", rate = 20, burst = 4, description = "Ephemeral aim state for NPC reactions" },
	WeaponState = { class_name = "RemoteEvent", direction = "server_to_client", description = "Authoritative ammunition and reload state" },
	WeaponHitConfirm = { class_name = "UnreliableRemoteEvent", direction = "server_to_client", description = "Batched hit confirmation" },
	WeaponReplicate = { class_name = "UnreliableRemoteEvent", direction = "server_to_client", description = "Culled and batched remote shot presentation" },
	MovementCommand = { class_name = "RemoteEvent", direction = "client_to_server", rate = 24, burst = 8, description = "Batched deterministic movement commands" },
	MovementSnapshot = { class_name = "UnreliableRemoteEvent", direction = "server_to_client", description = "Movement acknowledgement and reconciliation snapshot" },
	ReplayCameraSnapshot = { class_name = "UnreliableRemoteEvent", direction = "client_to_server", rate = 12, burst = 3, description = "Bounded killer POV history" },
	DeathReplayData = { class_name = "RemoteEvent", direction = "server_to_client", description = "Authoritative lethal-shot replay metadata" },
	GrenadeEquip = { class_name = "RemoteEvent", direction = "client_to_server", rate = 8, burst = 3, description = "Grenade presentation request" },
	GrenadeThrow = { class_name = "RemoteEvent", direction = "client_to_server", rate = 5, burst = 2, description = "Authoritative grenade throw request" },
	GrenadeThrowResult = { class_name = "RemoteEvent", direction = "server_to_client", description = "Grenade request acknowledgement" },
	GrenadeExplode = { class_name = "UnreliableRemoteEvent", direction = "server_to_client", description = "Explosion presentation" },
	RagdollState = { class_name = "RemoteEvent", direction = "server_to_client", description = "Authoritative ragdoll state" },
	MatchVote = { class_name = "RemoteEvent", direction = "client_to_server", rate = 4, burst = 1, description = "Intermission mode vote" },
	MatchState = { class_name = "RemoteEvent", direction = "server_to_client", description = "Versioned match snapshot" },
	ShopRequest = { class_name = "RemoteFunction", direction = "bidirectional", rate = 8, burst = 4, description = "Validated shop transaction and query" },
	ShopUpdated = { class_name = "RemoteEvent", direction = "server_to_client", description = "Economy invalidation or authoritative cash delta" },
	MissionStart = { class_name = "RemoteFunction", direction = "bidirectional", rate = 1, burst = 1, description = "Mission/spawn start request" },
	MissionUpdate = { class_name = "RemoteEvent", direction = "server_to_client", description = "Mission lifecycle snapshot" },
	NpcCommand = { class_name = "RemoteEvent", direction = "client_to_server", rate = 7, burst = 2, description = "Validated NPC interaction ray" },
}

for _, spec in specs do
	table.freeze(spec)
end
table.freeze(specs)

function network_protocol.get_spec(name: string): RemoteSpec?
	return specs[name]
end

function network_protocol.get_specs(): { [string]: RemoteSpec }
	return specs
end

function network_protocol.ensure_server(remotes: Folder): { [string]: Instance }
	local resolved = {}
	for name, spec in specs do
		local remote = remotes:FindFirstChild(name)
		if remote and remote.ClassName ~= spec.class_name then
			remote:Destroy()
			remote = nil
		end
		if not remote then
			remote = Instance.new(spec.class_name)
			remote.Name = name
			remote.Parent = remotes
		end
		resolved[name] = remote
	end
	return resolved
end

function network_protocol.wait_for_client(remotes: Folder, timeout: number?): { [string]: Instance }
	local resolved = {}
	for name, spec in specs do
		local remote = remotes:WaitForChild(name, timeout)
		assert(remote, string.format("network protocol timed out waiting for %s", name))
		assert(remote.ClassName == spec.class_name, string.format("network protocol expected %s to be %s, got %s", name, spec.class_name, remote.ClassName))
		resolved[name] = remote
	end
	return resolved
end

function network_protocol.audit(remotes: Folder): { string }
	local issues = {}
	for name, spec in specs do
		local remote = remotes:FindFirstChild(name)
		if not remote then
			table.insert(issues, string.format("missing %s", name))
		elseif remote.ClassName ~= spec.class_name then
			table.insert(issues, string.format("%s is %s, expected %s", name, remote.ClassName, spec.class_name))
		end
	end
	for _, child in remotes:GetChildren() do
		if (child:IsA("RemoteEvent") or child:IsA("RemoteFunction") or child:IsA("UnreliableRemoteEvent")) and not specs[child.Name] then
			table.insert(issues, string.format("unmanifested remote %s", child.Name))
		end
	end
	table.sort(issues)
	return issues
end

return network_protocol

