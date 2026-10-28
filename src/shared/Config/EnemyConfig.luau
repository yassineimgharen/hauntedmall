--!strict
-- Enemy, wave, flashlight and objective tuning.

export type EnemyType = {
	DisplayName: string,
	MaxHealth: number,
	WalkSpeed: number,
	Damage: number,
	AttackRange: number,
	AttackCooldown: number,
	AggroRange: number,
	ShopDrain: number, -- stock removed per drain tick
	ShopDrainInterval: number,
	HipHeight: number,
	AttackWindup: number, -- telegraph: the enemy rears up this long before the bite lands
	-- growth per night after the first, and hard caps (WalkSpeed cap stays below the
	-- player's 16 so a player running in a straight line can always escape)
	PerNight: { WalkSpeed: number, Damage: number, MaxHealth: number, AggroRange: number },
	Caps: { WalkSpeed: number, Damage: number, MaxHealth: number, AggroRange: number },
}

local EnemyConfig = {
	Types = {
		-- Night-1 values: scary but escapable (players walk at 16).
		ShadowCrawler = {
			DisplayName = "Shadow Crawler",
			MaxHealth = 45,
			WalkSpeed = 12.5,
			Damage = 10,
			AttackRange = 5,
			AttackCooldown = 1.8,
			AttackWindup = 0.6,
			AggroRange = 45,
			ShopDrain = 1,
			ShopDrainInterval = 2,
			HipHeight = 1.4,
			PerNight = { WalkSpeed = 0.6, Damage = 1.5, MaxHealth = 6, AggroRange = 5 },
			Caps = { WalkSpeed = 15.5, Damage = 18, MaxHealth = 90, AggroRange = 70 },
		} :: EnemyType,
		-- A disguised shopper, unmasked by the flashlight (Level 3). Fragile but quick to
		-- strike: faster wind-up, short cooldown, wide sight. Still slower than players.
		PhantomShopper = {
			DisplayName = "Phantom Shopper",
			MaxHealth = 30,
			WalkSpeed = 13.5,
			Damage = 9,
			AttackRange = 5,
			AttackCooldown = 1.5,
			AttackWindup = 0.5,
			AggroRange = 60,
			ShopDrain = 1,
			ShopDrainInterval = 2,
			HipHeight = 1.4,
			PerNight = { WalkSpeed = 0.3, Damage = 1, MaxHealth = 4, AggroRange = 0 },
			Caps = { WalkSpeed = 15, Damage = 15, MaxHealth = 60, AggroRange = 60 },
		} :: EnemyType,
	},

	Combat = {
		-- After any hit, a player can't be damaged again for this long (stops swarm stacking).
		PlayerHitGrace = 1.1,
		-- Freshly (re)spawned players can't be hurt for this long.
		RespawnGrace = 3,
		-- A wind-up "misses" if the target moved further than AttackRange + this.
		DodgeMargin = 1.5,
		Knockback = 38, -- client-applied push away from the attacker, so you can break free
	},

	Waves = {
		FirstWaveDelay = 8, -- time to equip the flashlight and get bearings
		Interval = 20,
		MaxAlive = 14, -- absolute cap (performance)
		SpawnStagger = 0.6,
	},

	AIThinkInterval = 0.2,

	Flashlight = {
		Range = 42,
		ConeHalfAngle = 20, -- degrees
		DPS = 30,
		BatterySeconds = 10,
		RechargeDelay = 1,
		RechargePerSecond = 0.12, -- fraction of capacity regained per second
		MaxAimDeviation = 80, -- degrees between aim and character facing the server accepts
		MaxAimPitch = 0.85, -- |aim.Y| limit
	},

	Fuses = {
		RepairTime = 3,
		SafeRadius = 22,
		SafeDPS = 8,
		AllRepairedStun = 5,
	},
}

-- Enemies per wave, scaled by night number and players present (solo night 1 = 3).
function EnemyConfig.WaveSize(night: number, players: number): number
	return 2 + math.floor(math.max(players, 1) * 1.2) + (night - 1) * 2
end

-- How many may be alive at once: small early, growing with nights and players.
function EnemyConfig.MaxAlive(night: number, players: number): number
	return math.min(EnemyConfig.Waves.MaxAlive, 4 + night * 2 + math.max(players, 1))
end

-- A copy of an enemy type with stats grown for the given night (1 = base) and capped.
function EnemyConfig.Scaled(typeId: string, night: number): EnemyType
	local base = EnemyConfig.Types[typeId]
	local scaled = table.clone(base)
	local steps = math.max(0, night - 1)
	for stat, growth in base.PerNight do
		local value = (base :: any)[stat] + growth * steps;
		(scaled :: any)[stat] = math.min(value, (base.Caps :: any)[stat])
	end
	return scaled
end

return EnemyConfig
