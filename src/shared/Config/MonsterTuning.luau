--!strict
-- Ability timings for the Chapter 2 monsters (stats like HP and speed are in EnemyConfig).
-- Pure data so tests/Chapter2.spec.luau can check fairness: every telegraph leaves time
-- to step out of it at walking speed, and nothing that chases is faster than a player.

return {
	PlayerSpeed = 16,

	Cart = {
		Aim = 1.0, -- red lane shown before the charge
		ChargeSpeed = 32,
		ChargeTime = 1.1,
		Dizzy = 1.6, -- spun out after a charge: free hits
		Cooldown = 4.5,
		MinRange = 8,
		MaxRange = 34,
		HitRadius = 4.2,
		LaneWidth = 5,
	},

	Mimic = {
		RevealRange = 9,
		RevealPause = 0.8, -- bursts open, then a moment before it acts
		PounceWarn = 0.9, -- landing circle shown before it lands
		PounceRadius = 4.5,
		PounceSpeed = 26,
		PounceCooldown = 3.5,
		PounceMin = 7,
		PounceMax = 18,
		Split = 2, -- Parcel Mites released when it dies
	},

	Wraith = {
		BreathWarn = 1.2,
		BreathLength = 16,
		BreathWidth = 7,
		BreathDamage = 12,
		BreathCooldown = 6,
		LitSlow = 0.35, -- speed multiplier while a flashlight is on it
	},

	Bloater = {
		ExhaleWarn = 1.2,
		ExhaleRadius = 8,
	},
}
