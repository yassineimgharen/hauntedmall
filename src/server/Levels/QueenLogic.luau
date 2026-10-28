--!strict
-- Pure rules for the Shadow Queen fight (Level 7 night). No Roblox APIs: ShadowQueen.luau
-- does the world side, and tests/ShadowQueen.spec.luau runs these rules under Lune.
--
-- Shield cycle: Shielded → a charged cannon fires → Down (light hurts her) → the last
-- `Returning` seconds warn → Shielded again. While Down, more cannons can't fire (no
-- stacking or wasting charges). Darkness pulses (phase 2+) keep cannons from firing.

local QueenLogic = {}

QueenLogic.Tuning = {
	BaseHP = 600,
	HPPerPlayer = 300,
	ShieldDown = 10, -- seconds of vulnerability per cannon shot
	Returning = 3, -- the last seconds of that window show "SHIELD RETURNING"
	PrismBonus = 0.5, -- Prism Lens: +50% light damage against bosses
	PhaseAt = { 0.66, 0.33 }, -- health fractions where phases 2 and 3 begin
	-- cannons (night): every cannon recharges by itself; each player in its ring adds speed
	Recharge = 25,
	ChargeDay = 20, -- day: one person in the ring
	-- attacks per phase
	AttackGap = { 6, 4.8, 4 },
	FirstAttackDelay = 10, -- after she appears: time to read the HUD and reach a cannon
	SlamTelegraph = { 3, 2.4, 2 },
	SlamDamage = { 20, 25, 30 },
	SlamRadius = 9,
	SweepDamage = 25,
	DarkSeconds = 6,
	DarkWarning = 2,
	DarkCooldown = 20,
	-- brood (crawlers): late, small and slower than players; never next to a player
	BroodFirstDelay = 20,
	BroodInterval = { 24, 20, 16 },
	BroodTier = { 2, 3, 4 }, -- EnemyConfig night tier: speed 13.1 / 13.7 / 14.3 (players 16)
	SpawnMinPlayerDistance = 24,
	SpawnMinCannonDistance = 12,
	MaxAliveCap = 10,
}

-- Invisible, queryable spheres the flashlight tests against (offsets from the Queen's root,
-- in her local space: -Z is forward). The builder places her body parts on these.
QueenLogic.Body = {
	{ Name = "Head", Offset = { 0, 3.6, -4.6 }, Radius = 3 },
	{ Name = "Thorax", Offset = { 0, 1.5, 0 }, Radius = 3.6 },
	{ Name = "Abdomen", Offset = { 0, 0.5, 6 }, Radius = 5 },
}

export type Fight = {
	Hp: number,
	MaxHp: number,
	Phase: number,
	ShieldUntil: number, -- clock time; shield is down while now < ShieldUntil
	DarkUntil: number,
	Defeated: boolean,
}

export type Cannon = { Charged: boolean, Progress: number, Fired: boolean }

export type ShieldState = "Shielded" | "Down" | "Returning" | "Defeated"

function QueenLogic.maxHp(players: number): number
	local t = QueenLogic.Tuning
	return t.BaseHP + t.HPPerPlayer * math.max(players, 1)
end

function QueenLogic.new(players: number): Fight
	local hp = QueenLogic.maxHp(players)
	return { Hp = hp, MaxHp = hp, Phase = 1, ShieldUntil = 0, DarkUntil = 0, Defeated = false }
end

function QueenLogic.phaseFor(fraction: number): number
	local at = QueenLogic.Tuning.PhaseAt
	return if fraction > at[1] then 1 elseif fraction > at[2] then 2 else 3
end

function QueenLogic.shieldState(fight: Fight, now: number): ShieldState
	if fight.Defeated then
		return "Defeated"
	elseif now >= fight.ShieldUntil then
		return "Shielded"
	elseif fight.ShieldUntil - now <= QueenLogic.Tuning.Returning then
		return "Returning"
	end
	return "Down"
end

function QueenLogic.isVulnerable(fight: Fight, now: number): boolean
	return not fight.Defeated and now < fight.ShieldUntil
end

export type FireRefusal = "Defeated" | "NotCharged" | "ShieldDown" | "Dark"

function QueenLogic.canFire(fight: Fight, cannon: Cannon, now: number): (boolean, FireRefusal?)
	if fight.Defeated then
		return false, "Defeated" :: FireRefusal
	elseif not cannon.Charged then
		return false, "NotCharged" :: FireRefusal
	elseif now < fight.ShieldUntil then
		return false, "ShieldDown" :: FireRefusal -- one cannon per window: the others stay charged
	elseif now < fight.DarkUntil then
		return false, "Dark" :: FireRefusal
	end
	return true, nil
end

-- Consumes the cannon's charge and drops the shield. Must run without yielding so two
-- players triggering at once can't both succeed.
function QueenLogic.fire(fight: Fight, cannon: Cannon, now: number): (boolean, FireRefusal?)
	local ok, reason: FireRefusal? = QueenLogic.canFire(fight, cannon, now)
	if not ok then
		return false, reason
	end
	cannon.Charged = false
	cannon.Fired = true
	cannon.Progress = 0
	fight.ShieldUntil = now + QueenLogic.Tuning.ShieldDown
	return true, nil
end

-- Light damage for one beam tick (before shield checks).
function QueenLogic.lightDamage(dps: number, dt: number, lensBonus: number, prism: boolean): number
	return dps * dt * (1 + lensBonus) * (if prism then 1 + QueenLogic.Tuning.PrismBonus else 1)
end

export type LightResult = {
	Dealt: number,
	Blocked: boolean, -- the shield was up: tell the player why nothing happened
	PhaseChanged: number?,
	Defeated: boolean, -- true exactly once, on the killing tick
}

function QueenLogic.applyLight(fight: Fight, now: number, amount: number): LightResult
	if fight.Defeated or amount <= 0 then
		return { Dealt = 0, Blocked = false, PhaseChanged = nil, Defeated = false }
	end
	if not QueenLogic.isVulnerable(fight, now) then
		return { Dealt = 0, Blocked = true, PhaseChanged = nil, Defeated = false }
	end
	local dealt = math.min(amount, fight.Hp)
	fight.Hp -= dealt
	if fight.Hp <= 0 then
		fight.Hp = 0
		fight.Defeated = true
		fight.ShieldUntil = 0
		return { Dealt = dealt, Blocked = false, PhaseChanged = nil, Defeated = true }
	end
	local phase = QueenLogic.phaseFor(fight.Hp / fight.MaxHp)
	local changed = nil
	if phase > fight.Phase then
		fight.Phase = phase
		changed = phase
	end
	return { Dealt = dealt, Blocked = false, PhaseChanged = changed, Defeated = false }
end

-- Night recharge per second for a cannon with `inside` players in its ring.
function QueenLogic.nightChargeRate(inside: number): number
	return (1 + math.min(inside, 3)) / QueenLogic.Tuning.Recharge
end

-- Crawlers per summon and the most brood alive at once, by phase and active players.
function QueenLogic.broodSize(phase: number, players: number): number
	local base = if phase <= 1 then 1 else 2
	return base + math.floor((math.max(players, 1) - 1) * 0.75)
end

function QueenLogic.maxBrood(phase: number, players: number): number
	local base = ({ 2, 3, 4 })[math.clamp(phase, 1, 3)]
	return math.min(QueenLogic.Tuning.MaxAliveCap, base + (math.max(players, 1) - 1) * 2)
end

-- How many to spawn now (0 if the cap is reached).
function QueenLogic.broodToSpawn(phase: number, players: number, alive: number): number
	return math.max(0, math.min(QueenLogic.broodSize(phase, players), QueenLogic.maxBrood(phase, players) - alive))
end

local function flat(a: { number }, b: { number }): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
end

-- Index of a candidate {x, z} at least the minimum distance from every player and cannon
-- (the nearest such spot, so crawlers still arrive), or nil: nothing spawns this time.
function QueenLogic.pickSpawn(candidates: { { number } }, players: { { number } }, cannons: { { number } }): number?
	local t = QueenLogic.Tuning
	local best, bestScore = nil, -math.huge
	for i, candidate in candidates do
		local nearestPlayer = math.huge
		for _, p in players do
			nearestPlayer = math.min(nearestPlayer, flat(candidate, p))
		end
		local nearestCannon = math.huge
		for _, c in cannons do
			nearestCannon = math.min(nearestCannon, flat(candidate, c))
		end
		if nearestPlayer >= t.SpawnMinPlayerDistance and nearestCannon >= t.SpawnMinCannonDistance then
			local score = -nearestPlayer
			if score > bestScore then
				best, bestScore = i, score
			end
		end
	end
	return best
end

return QueenLogic
