local GunCatalog = {}

GunCatalog.ROTATION_SECONDS = 300
GunCatalog.SHOP_SIZE = 3

GunCatalog.WEAPONS = {
	{
		id = "GLOCK",
		display_name = "Glock",
		category = "firearm",
		price = 0,
		rarity = "Starter",
		tagline = "Back to basics lol",
		width = 2,
		height = 1,
	},
	{
		id = "MUTANT",
		display_name = "Mutant",
		category = "firearm",
		price = 250,
		rarity = "Starter",
		tagline = "The Glocks humble upgrade.",
		width = 4,
		height = 2,
	},
	{
		id = "REMINGTON",
		display_name = "Remington 870",
		category = "firearm",
		price = 500,
		rarity = "Starter",
		tagline = "Shotgun",
		width = 5,
		height = 1,
	},
	{
		id = "GRENADE",
		display_name = "Frag Grenade",
		category = "utility",
		price = 0,
		rarity = "Utility",
		tagline = "Three second fuse",
		width = 1,
		height = 1,
		shop_enabled = false,
	}
}

local by_id = {}
for _, weapon in GunCatalog.WEAPONS do
	by_id[weapon.id] = weapon
end

function GunCatalog.get_weapon(gun_id)
	return by_id[gun_id]
end

function GunCatalog.get_all()
	return GunCatalog.WEAPONS
end

function GunCatalog.get_rotation_index(now)
	return math.floor((now or os.time()) / GunCatalog.ROTATION_SECONDS)
end

function GunCatalog.get_rotation_ends_at(now)
	local rotation_index = GunCatalog.get_rotation_index(now)

	return (rotation_index + 1) * GunCatalog.ROTATION_SECONDS
end

function GunCatalog.get_shop(now)
	local weapons = {}
	for _, weapon in GunCatalog.WEAPONS do
		if weapon.shop_enabled ~= false then
			table.insert(weapons, weapon)
		end
	end
	local rotation_index = GunCatalog.get_rotation_index(now)
	local start_index = rotation_index % #weapons + 1
	local shop = {}
	for offset = 0, math.min(GunCatalog.SHOP_SIZE, #weapons) - 1 do
		local index = (start_index + offset - 1) % #weapons + 1
		table.insert(shop, weapons[index].id)
	end
	return shop
end

function GunCatalog.is_in_shop(gun_id, now)
	for _, shop_gun_id in GunCatalog.get_shop(now) do
		if shop_gun_id == gun_id then

			return true
		end
	end

	return false
end

return GunCatalog
