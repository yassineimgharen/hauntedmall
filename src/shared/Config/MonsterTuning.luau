--!strict
-- Ability timings for the Chapter 2 monsters (stats like HP and speed are in EnemyConfig).
-- Pure data so tests/Chapter2.spec.luau can check fairness: every telegraph leaves time
-- to step out of it at walking speed, and nothing that chases is faster than a player.

local MonsterTuning = {
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
		PounceCrouch = 0.6, -- landing circle shown; it crouches this long before leaping
		PounceRadius = 4.5,
		PounceSpeed = 30, -- leap speed: the leap takes longer the further it has to go
		PounceSlack = 0.2, -- one AI tick of grace to arrive
		PounceReach = 7, -- it only hurts anyone if it really got this close to the spot
		PounceCooldown = 3.5,
		PounceMin = 7,
		PounceMax = 16,
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

-- Seconds from the start of a pounce until the mimic leaps, and until it lands.
function MonsterTuning.pounceTimes(distance: number): (number, number)
	local m = MonsterTuning.Mimic
	local leap = math.max(0.35, distance / m.PounceSpeed)
	return m.PounceCrouch, m.PounceCrouch + leap + m.PounceSlack
end

return MonsterTuning
