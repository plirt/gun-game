local weapon_replication_service = {}

function weapon_replication_service.replicate_fire(ctx, player: Player, gun_name: string, origin: Vector3, directions: { Vector3 })
	for _, direction in directions do
		ctx.remotes.WeaponFire:FireAllClients(player, gun_name, origin, direction)
	end
end

return weapon_replication_service
