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
	LightScale: number?, -- flashlight damage multiplier (default 1; 0 = light only slows it)
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

		-- ── Chapter 2 (the food court) ──────────────────────────────────────────
		-- A haunted steel trolley (Level 8). Rolls slowly, then aims (a red lane on the
		-- floor) and charges along it: sidestep the lane. Dizzy for a moment afterwards.
		PossessedCart = {
			DisplayName = "Possessed Cart",
			MaxHealth = 60,
			WalkSpeed = 10,
			Damage = 15,
			AttackRange = 4.5,
			AttackCooldown = 2,
			AttackWindup = 0.7,
			AggroRange = 60,
			ShopDrain = 0,
			ShopDrainInterval = 2,
			HipHeight = 1.6,
			PerNight = { WalkSpeed = 0.2, Damage = 1, MaxHealth = 5, AggroRange = 0 },
			Caps = { WalkSpeed = 12, Damage = 20, MaxHealth = 90, AggroRange = 60 },
		} :: EnemyType,
		-- An infected parcel (Level 10): sits disguised until you come close or light it,
		-- then pounces (a landing circle shows where). Bursts into two Parcel Mites.
		ParcelMimic = {
			DisplayName = "Parcel Mimic",
			MaxHealth = 50,
			WalkSpeed = 10,
			Damage = 14,
			AttackRange = 5,
			AttackCooldown = 1.8,
			AttackWindup = 0.7,
			AggroRange = 45,
			ShopDrain = 0,
			ShopDrainInterval = 2,
			HipHeight = 1.4,
			PerNight = { WalkSpeed = 0.2, Damage = 1, MaxHealth = 4, AggroRange = 0 },
			Caps = { WalkSpeed = 12, Damage = 18, MaxHealth = 80, AggroRange = 45 },
		} :: EnemyType,
		ParcelMite = {
			DisplayName = "Parcel Mite",
			MaxHealth = 16,
			WalkSpeed = 14,
			Damage = 6,
			AttackRange = 4,
			AttackCooldown = 1.3,
			AttackWindup = 0.45,
			AggroRange = 60,
			ShopDrain = 0,
			ShopDrainInterval = 2,
			HipHeight = 0.6,
			PerNight = { WalkSpeed = 0.1, Damage = 0.5, MaxHealth = 2, AggroRange = 0 },
			Caps = { WalkSpeed = 14.5, Damage = 9, MaxHealth = 26, AggroRange = 60 },
		} :: EnemyType,
		-- The thing in the hidden freezer (Level 11). Light can't hurt it, only slow it;
		-- it chills everyone near it and breathes frost. You escape it, you don't kill it.
		FrostWraith = {
			DisplayName = "Frost Wraith",
			MaxHealth = 100000,
			WalkSpeed = 12.5,
			Damage = 18,
			AttackRange = 6,
			AttackCooldown = 2.4,
			AttackWindup = 0.9,
			AggroRange = 70,
			ShopDrain = 0,
			ShopDrainInterval = 2,
			HipHeight = 3,
			LightScale = 0,
			PerNight = { WalkSpeed = 0, Damage = 0, MaxHealth = 0, AggroRange = 0 },
			Caps = { WalkSpeed = 12.5, Damage = 18, MaxHealth = 100000, AggroRange = 70 },
		} :: EnemyType,
		-- A floating spore sac (Level 13). Slow; exhales poison gas around itself and
		-- bursts into a gas cloud when burned, so burn it from a distance.
		SporeBloater = {
			DisplayName = "Spore Bloater",
			MaxHealth = 35,
			WalkSpeed = 7,
			Damage = 0,
			AttackRange = 7,
			AttackCooldown = 4,
			AttackWindup = 1.2,
			AggroRange = 55,
			ShopDrain = 0,
			ShopDrainInterval = 2,
			HipHeight = 5,
			PerNight = { WalkSpeed = 0.1, Damage = 0, MaxHealth = 3, AggroRange = 0 },
			Caps = { WalkSpeed = 8, Damage = 0, MaxHealth = 55, AggroRange = 55 },
		} :: EnemyType,
		-- The Gorging Chef's rolling minions (Level 14 boss).
		Meatball = {
			DisplayName = "Meatball",
			MaxHealth = 24,
			WalkSpeed = 12.5,
			Damage = 10,
			AttackRange = 4.5,
			AttackCooldown = 1.6,
			AttackWindup = 0.6,
			AggroRange = 80,
			ShopDrain = 0,
			ShopDrainInterval = 2,
			HipHeight = 1.4,
			PerNight = { WalkSpeed = 0.2, Damage = 0.5, MaxHealth = 2, AggroRange = 0 },
			Caps = { WalkSpeed = 13.5, Damage = 14, MaxHealth = 36, AggroRange = 80 },
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
