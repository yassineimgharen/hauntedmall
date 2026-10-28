--!strict
-- Pure rules and tuning for Chapter 2 (the Haunted Food Court, Levels 8–14). No Roblox
-- APIs: the level modules do the world side, tests/Chapter2.spec.luau runs these rules.
-- Everything that scales with players is here, so solo and team balance is testable.

local FoodCourtRules = {}

local function players(n: number): number
	return math.max(n, 1)
end

-- ── Level 8 · Grand Reopening / Kitchen Nightmare ───────────────────────────

FoodCourtRules.L08 = {
	SlimePuddles = 12, -- the day needs 8 scrubbed (team)
	ScrubSeconds = 2,
	ReopenSeconds = 2.5,
	ExorciseSeconds = 4, -- seconds of beam (summed over everyone lighting it)
	ExorciseTarget = 5,
	FirstPossessions = 2,
	PossessEvery = 18,
	MaxPossessions = 11, -- over the whole night: always enough to reach the target
	PossessMinDistance = 30, -- a new possession never starts right next to a player
	VolleyWarn = 1.2, -- red knife lane shown before the cutlery flies
	VolleyDamage = 12,
	VolleyLength = 36,
	VolleyWidth = 3.5,
	VolleyRange = 45,
	VolleyGap = 1.6, -- at most one volley (from any appliance) per this many seconds
	ApplianceCooldown = 6,
	CartFirst = 25,
	CartEvery = 22,
	Tier = 3,
}

-- Possessed appliances active at once: 3 solo, one more per extra player, at most 6.
function FoodCourtRules.activePossessions(playerCount: number): number
	return math.min(2 + players(playerCount), 6)
end

-- Runaway carts alive at once: 1 solo, 2 for two or three players, at most 3.
function FoodCourtRules.cartCap(playerCount: number): number
	return math.min(1 + math.floor((players(playerCount) - 1) * 0.6), 3)
end

-- Volleys per minute a single player can face (the global gap caps it however many
-- appliances are possessed).
function FoodCourtRules.maxVolleysPerMinute(): number
	return math.floor(60 / FoodCourtRules.L08.VolleyGap)
end

-- Exorcism progress after `seconds` more of beam; returns (progress, done).
function FoodCourtRules.exorcise(progress: number, seconds: number): (number, boolean)
	local total = math.min(progress + math.max(seconds, 0), FoodCourtRules.L08.ExorciseSeconds)
	return total, total >= FoodCourtRules.L08.ExorciseSeconds
end

-- Which free appliance to possess next: one far enough from every player (nearest such
-- first, so the fight comes to the players), else nil. Positions are {x, z}.
function FoodCourtRules.pickPossession(candidates: { { number } }, playerPositions: { { number } }): number?
	local best, bestScore = nil, math.huge
	for index, candidate in candidates do
		local nearest = math.huge
		for _, p in playerPositions do
			nearest = math.min(nearest, math.sqrt((candidate[1] - p[1]) ^ 2 + (candidate[2] - p[2]) ^ 2))
		end
		if nearest >= FoodCourtRules.L08.PossessMinDistance and nearest < bestScore then
			best, bestScore = index, nearest
		end
	end
	return best
end

return FoodCourtRules
