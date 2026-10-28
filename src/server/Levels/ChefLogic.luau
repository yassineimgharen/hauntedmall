--!strict
-- Pure rules for the Gorging Chef fight (Level 14 night, Chapter 2 boss). No Roblox APIs:
-- GorgingChef.luau does the world side, tests/Chapter2.spec.luau runs these rules.
--
-- He's coated in grease: light slides off. Every so often he bellows "ORDER UP!" and eats
-- whatever is on the serving pass:
--   a LACED dish (cooked at a stove, dosed at an antidote vat) → SICK: light burns him
--   a plain dish → it heals him (cook, then lace!)
--   nothing → RAVENOUS: he chases and attacks faster for a while
-- Phases at 66% / 33% health add grease spills and meatballs, then stove flares.

local ChefLogic = {}

ChefLogic.Tuning = {
	BaseHP = 400,
	HPPerPlayer = 200,
	PhaseAt = { 0.66, 0.33 },
	PrismBonus = 0.5, -- Prism Lens (Level 7): +50% light damage against bosses
	IntroSeconds = 7, -- the cinematic: he does nothing
	FirstAttackDelay = 10, -- after he appears
	FirstHunger = 20,
	HungerEvery = { 22, 19, 16 },
	SickSeconds = 12,
	RavenousSeconds = 10,
	HealFraction = 0.05, -- a plain dish heals this much of his max HP
	AttackGap = { 5.5, 4.5, 3.8 },
	RavenousGapScale = 0.6,
	WalkSpeed = 8,
	RavenousSpeed = 13, -- still slower than players (16)
	CookSeconds = 2,
	LaceSeconds = 1,
	ServeSeconds = 0.6,
	Cleaver = { Length = 30, Width = 6, Warn = { 1.6, 1.4, 1.2 }, Damage = { 22, 26, 30 } },
	Pan = { Radius = 5, Warn = 1.6, Damage = 18 },
	Grease = { Radius = 5, Seconds = 12, Slow = 0.6 },
	Flare = { Width = 5, Warn = 1.5, Damage = 20 },
	MeatballFirst = 6, -- seconds into phase 2
	MeatballEvery = { 0, 22, 18 },
	MeatballTier = { 2, 3, 4 },
	MaxMeatballs = 6,
}

export type State = "Greased" | "Sick" | "Ravenous" | "Defeated"
export type Pass = "Empty" | "Dish" | "Laced"

export type Fight = {
	Hp: number,
	MaxHp: number,
	Phase: number,
	State: State,
	Until: number, -- when Sick / Ravenous ends
	HungerAt: number, -- next "ORDER UP!"
	Pass: Pass,
	Defeated: boolean,
}

function ChefLogic.maxHp(players: number): number
	local t = ChefLogic.Tuning
	return t.BaseHP + t.HPPerPlayer * math.max(players, 1)
end

function ChefLogic.new(players: number, now: number): Fight
	local hp = ChefLogic.maxHp(players)
	return {
		Hp = hp,
		MaxHp = hp,
		Phase = 1,
		State = "Greased",
		Until = 0,
		HungerAt = now + ChefLogic.Tuning.FirstHunger,
		Pass = "Empty",
		Defeated = false,
	}
end

function ChefLogic.phaseFor(fraction: number): number
	local at = ChefLogic.Tuning.PhaseAt
	return if fraction > at[1] then 1 elseif fraction > at[2] then 2 else 3
end

-- Timers: Sick and Ravenous wear off back to Greased. Returns the state that just ended.
function ChefLogic.update(fight: Fight, now: number): State?
	if fight.Defeated then
		return nil
	end
	if (fight.State == "Sick" or fight.State == "Ravenous") and now >= fight.Until then
		local ended: State = fight.State
		fight.State = "Greased" :: State
		return ended
	end
	return nil
end

function ChefLogic.isVulnerable(fight: Fight, now: number): boolean
	return not fight.Defeated and fight.State == "Sick" and now < fight.Until
end

function ChefLogic.isHungry(fight: Fight, now: number): boolean
	return not fight.Defeated and fight.State == "Greased" and now >= fight.HungerAt
end

export type ServeRefusal = "Defeated" | "Full"

-- Puts a dish on the pass. Only one fits: that keeps players from stacking his meals.
function ChefLogic.serve(fight: Fight, dish: Pass): (boolean, ServeRefusal?)
	if fight.Defeated then
		return false, "Defeated" :: ServeRefusal
	elseif fight.Pass ~= "Empty" then
		return false, "Full" :: ServeRefusal
	end
	fight.Pass = dish
	return true, nil
end

export type Meal = "Sick" | "Healed" | "Ravenous"

-- He eats what's on the pass. Must run without yielding (one meal per ORDER UP).
function ChefLogic.eat(fight: Fight, now: number): Meal
	local t = ChefLogic.Tuning
	local pass = fight.Pass
	fight.Pass = "Empty" :: Pass
	local gap = t.HungerEvery[fight.Phase]
	if pass == "Laced" then
		fight.State = "Sick" :: State
		fight.Until = now + t.SickSeconds
		fight.HungerAt = fight.Until + gap
		return "Sick" :: Meal
	elseif pass == "Dish" then
		fight.Hp = math.min(fight.MaxHp, fight.Hp + fight.MaxHp * t.HealFraction)
		fight.HungerAt = now + gap
		return "Healed" :: Meal
	end
	fight.State = "Ravenous" :: State
	fight.Until = now + t.RavenousSeconds
	fight.HungerAt = fight.Until + gap * 0.5 -- hungry again sooner: a second chance
	return "Ravenous" :: Meal
end

function ChefLogic.lightDamage(dps: number, dt: number, lensBonus: number, prism: boolean): number
	return dps * dt * (1 + lensBonus) * (if prism then 1 + ChefLogic.Tuning.PrismBonus else 1)
end

export type LightResult = { Dealt: number, Blocked: boolean, PhaseChanged: number?, Defeated: boolean }

function ChefLogic.applyLight(fight: Fight, now: number, amount: number): LightResult
	if fight.Defeated or amount <= 0 then
		return { Dealt = 0, Blocked = false, PhaseChanged = nil, Defeated = false }
	end
	if not ChefLogic.isVulnerable(fight, now) then
		return { Dealt = 0, Blocked = true, PhaseChanged = nil, Defeated = false }
	end
	local dealt = math.min(amount, fight.Hp)
	fight.Hp -= dealt
	if fight.Hp <= 0 then
		fight.Hp = 0
		fight.Defeated = true
		fight.State = "Defeated" :: State
		return { Dealt = dealt, Blocked = false, PhaseChanged = nil, Defeated = true }
	end
	local phase = ChefLogic.phaseFor(fight.Hp / fight.MaxHp)
	local changed = nil
	if phase > fight.Phase then
		fight.Phase = phase
		changed = phase
	end
	return { Dealt = dealt, Blocked = false, PhaseChanged = changed, Defeated = false }
end

-- Seconds between his attacks right now (none while he's sick: he's retching).
function ChefLogic.attackGap(fight: Fight): number?
	if fight.Defeated or fight.State == "Sick" then
		return nil
	end
	local gap = ChefLogic.Tuning.AttackGap[fight.Phase]
	return if fight.State == "Ravenous" then gap * ChefLogic.Tuning.RavenousGapScale else gap
end

-- Meatballs alive at once: none in phase 1; 2 then 3 solo; +1 per extra player; capped.
function ChefLogic.meatballCap(phase: number, players: number): number
	if phase <= 1 then
		return 0
	end
	local base = if phase == 2 then 2 else 3
	return math.min(ChefLogic.Tuning.MaxMeatballs, base + math.max(players, 1) - 1)
end

function ChefLogic.speed(fight: Fight): number
	local t = ChefLogic.Tuning
	if fight.State == "Sick" then
		return 2.5
	end
	return if fight.State == "Ravenous" then t.RavenousSpeed else t.WalkSpeed
end

return ChefLogic
