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
}

local EnemyConfig = {
	Types = {
		ShadowCrawler = {
			DisplayName = "Shadow Crawler",
			MaxHealth = 45,
			WalkSpeed = 17,
			Damage = 12,
			AttackRange = 5.5,
			AttackCooldown = 1.2,
			AggroRange = 70,
			ShopDrain = 1,
			ShopDrainInterval = 2,
			HipHeight = 1.4,
		} :: EnemyType,
	},

	Waves = {
		FirstWaveDelay = 5,
		Interval = 18,
		MaxAlive = 14,
		SpawnStagger = 0.45,
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

-- Enemies per wave, scaled by night number and players present.
function EnemyConfig.WaveSize(night: number, players: number): number
	return 3 + math.floor(math.max(players, 1) * 1.5) + (night - 1) * 2
end

return EnemyConfig
