local weapon_replication_service = require(script.Parent.Parent.WeaponReplicationService)

local combat_replication_service = {}
combat_replication_service.__index = combat_replication_service

function combat_replication_service.new(event_stream, dependencies)
	local self = setmetatable({
		connections = {},
	}, combat_replication_service)
	self.connections.weapon_activated = event_stream:subscribe("weapon_activated", function(event)
		weapon_replication_service.queue_fire(
			dependencies,
			event.actor,
			event.item_id,
			event.origin,
			event.directions,
			event.play_sound
		)
	end)
	return self
end

function combat_replication_service:destroy()
	for _, connection in self.connections do
		connection.disconnect()
	end
	table.clear(self.connections)
end

return combat_replication_service

