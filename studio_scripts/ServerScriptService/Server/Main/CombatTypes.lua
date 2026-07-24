local CombatTypes = {}

export type WeaponConfig = {
	name: string,
	automatic: boolean,
	fire_rate: number,
	seconds_per_shot: number,
	magazine_size: number,
	reserve_ammo: number,
	reload_style: string,
	reload_time: number,
	tactical_reload_time: number,
	reload_empty_time: number,
	reload_tactical_time: number,
	reload_start_time: number,
	reload_insert_time: number,
	reload_end_time: number,
	damage: number,
	headshot_multiplier: number,
	limb_multiplier: number,
	damage_falloff_start: number,
	damage_falloff_end: number,
	minimum_damage_multiplier: number,
	muzzle_velocity: number,
	gravity: Vector3,
	max_distance: number,
	step_time: number?,
	projectile_radius: number?,
}

export type WeaponRuntimeState = {
	magazine: number,
	reserve: number,
	last_fire_time: number,
	reloading: boolean,
	reload_started: number?,
}

export type PlayerState = {
	cash: number,
	inventory: { [string]: boolean },
	loadout: { [number]: string },
	backpack: { [string]: { x: number, y: number } },
	attachments: { [string]: { [string]: string } },
	weapon_states: { [string]: WeaponRuntimeState },
}

export type HitInstance = RaycastResult | {
	Instance: BasePart,
	Position: Vector3,
}

export type CompensationData = {
	mode: string,
	target_time: number?,
	view_delay: number,
	projectile_elapsed: number,
	hitbox_padding: number,
}

export type ProjectileResult = {
	hit: HitInstance?,
	distance: number,
	position: Vector3,
	time: number?,
	velocity: Vector3,
	rewound: boolean?,
	compensation: CompensationData?,
}

export type HitScanResult = {
	direction: Vector3,
	result: ProjectileResult,
}

export type DamagedHumanoids = { [Humanoid]: boolean }

return CombatTypes

