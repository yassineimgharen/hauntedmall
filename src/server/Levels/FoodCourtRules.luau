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

-- ── Level 9 · Live Wires / Grease Fire ──────────────────────────────────────

FoodCourtRules.L09 = {
	-- day: cables cycle Live (sparking: no splicing, shocks anyone close) → Safe
	Cables = 6, -- 5 to splice (team)
	Live = 2,
	Safe = 3.2,
	SpliceSeconds = 1.4, -- must fit in the safe window, with time to react
	ShockRadius = 5,
	ShockDamage = 10,
	-- the switchboard: both levers within Window seconds (one player can sprint it)
	LeverDistance = 74,
	LeverSeconds = 0.5,
	Window = 8,
	-- night: the fire grid over the grand kitchen and dining hall
	Cols = 19,
	Rows = 12,
	Cell = 8,
	OriginX = -250, -- west edge
	OriginZ = -48, -- south edge
	StartFires = 3,
	SpreadEvery = 3,
	SpreadChance = { 0.25, 0.15, 0.07, 0 }, -- by gas valves closed (0..3)
	MaxBurning = 55,
	WetSeconds = 25, -- a sprayed cell can't reignite for this long
	FireDamage = 12, -- per hit (players can't be hit more than once per PlayerHitGrace)
	Charges = 8, -- sprays per extinguisher
	Valves = 3,
	ValveSeconds = 3,
	Tier = 2,
}

export type FireGrid = {
	Cols: number,
	Rows: number,
	Burning: { [number]: boolean },
	Wet: { [number]: number }, -- key → clock time it can burn again
	Protected: { [number]: boolean }, -- never burns (extinguisher stations, valves)
	Count: number,
}

function FoodCourtRules.fireGrid(): FireGrid
	local r = FoodCourtRules.L09
	return { Cols = r.Cols, Rows = r.Rows, Burning = {}, Wet = {}, Protected = {}, Count = 0 }
end

function FoodCourtRules.cellKey(grid: FireGrid, c: number, r: number): number?
	if c < 1 or r < 1 or c > grid.Cols or r > grid.Rows then
		return nil
	end
	return c + (r - 1) * grid.Cols
end

function FoodCourtRules.cellOf(grid: FireGrid, key: number): (number, number)
	return (key - 1) % grid.Cols + 1, (key - 1) // grid.Cols + 1
end

-- World x/z → cell (or nil outside the grid); and a cell's centre.
function FoodCourtRules.cellAt(x: number, z: number): (number?, number?)
	local r = FoodCourtRules.L09
	local c, row = math.floor((x - r.OriginX) / r.Cell) + 1, math.floor((z - r.OriginZ) / r.Cell) + 1
	if c < 1 or row < 1 or c > r.Cols or row > r.Rows then
		return nil, nil
	end
	return c, row
end

function FoodCourtRules.cellCenter(c: number, row: number): (number, number)
	local r = FoodCourtRules.L09
	return r.OriginX + (c - 0.5) * r.Cell, r.OriginZ + (row - 0.5) * r.Cell
end

-- Lights a cell; false if it's outside, already burning, protected, still wet or at the cap.
function FoodCourtRules.ignite(grid: FireGrid, c: number, r: number, now: number): boolean
	local key = FoodCourtRules.cellKey(grid, c, r)
	if not key or grid.Burning[key] or grid.Protected[key] or grid.Count >= FoodCourtRules.L09.MaxBurning then
		return false
	end
	if (grid.Wet[key] or 0) > now then
		return false
	end
	grid.Burning[key] = true
	grid.Count += 1
	return true
end

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- One spread step: every burning cell may light one neighbour. random() → [0, 1).
-- Returns the newly burning keys.
function FoodCourtRules.spread(grid: FireGrid, now: number, chance: number, random: () -> number): { number }
	local current = {}
	for key in grid.Burning do
		table.insert(current, key)
	end
	table.sort(current)
	local lit = {}
	for _, key in current do
		if random() < chance then
			local c, r = FoodCourtRules.cellOf(grid, key)
			local d = NEIGHBOURS[math.floor(random() * 4) + 1]
			if FoodCourtRules.ignite(grid, c + d[1], r + d[2], now) then
				table.insert(lit, FoodCourtRules.cellKey(grid, c + d[1], r + d[2]) :: number)
			end
		end
	end
	return lit
end

-- A spray puts out the cell and its four neighbours and keeps them wet for WetSeconds.
-- Returns the keys that were burning.
function FoodCourtRules.extinguish(grid: FireGrid, c: number, r: number, now: number): { number }
	local out = {}
	for _, d in { { 0, 0 }, table.unpack(NEIGHBOURS) } do
		local key = FoodCourtRules.cellKey(grid, c + d[1], r + d[2])
		if key then
			if grid.Burning[key] then
				grid.Burning[key] = nil
				grid.Count -= 1
				table.insert(out, key)
			end
			grid.Wet[key] = now + FoodCourtRules.L09.WetSeconds
		end
	end
	return out
end

function FoodCourtRules.spreadChance(valvesClosed: number): number
	local chances = FoodCourtRules.L09.SpreadChance
	return chances[math.clamp(valvesClosed, 0, #chances - 1) + 1]
end

-- A cable's state at clock time t: "Live" or "Safe", and seconds until it changes.
function FoodCourtRules.cablePhase(t: number, offset: number): ("Live" | "Safe", number)
	local r = FoodCourtRules.L09
	local cycle = r.Live + r.Safe
	local at = (t + offset) % cycle
	if at < r.Live then
		return "Live", r.Live - at
	end
	return "Safe", cycle - at
end

-- Pulling one of the two switchboard levers ("A" / "B"). Returns true when this pull
-- completes the reset (the other lever was pulled within Window seconds).
function FoodCourtRules.pullLever(pulled: { [string]: number }, lever: string, now: number): boolean
	local other = if lever == "A" then "B" else "A"
	local at = pulled[other]
	if at and now - at <= FoodCourtRules.L09.Window then
		table.clear(pulled)
		return true
	end
	pulled[lever] = now
	return false
end

-- ── Level 10 · Special Delivery / Return to Sender ──────────────────────────

-- The ten parcels at the dock. Infected ones always carry a UV handprint (seen only in a
-- flashlight beam); some also have a sender that isn't on the manifest, others look
-- perfectly legitimate, so reading labels alone isn't enough.
FoodCourtRules.L10 = {
	Trusted = { "Patty Co.", "Noodle House Supply", "Dairy Direct", "Sunrise Produce", "Dough Bros.", "Sugar Mill" },
	Parcels = {
		{ Sender = "Patty Co.", For = "Moonlight Burgers", Contents = "Frozen patties", Infected = false },
		{ Sender = "Dairy Direct", For = "Frost Bite Creamery", Contents = "Soft-serve mix", Infected = false },
		{ Sender = "KITCHEN B-13", For = "(no recipient)", Contents = "L I V E", Infected = true },
		{ Sender = "Noodle House Supply", For = "Lucky Wok", Contents = "Rice noodles", Infected = false },
		{ Sender = "Sunrise Produce", For = "Taco Eclipse", Contents = "Avocados", Infected = true },
		{ Sender = "Dough Bros.", For = "Slice of Night", Contents = "Flour sacks", Infected = false },
		{ Sender = "████████", For = "THE CHEF", Contents = "KEEP FED", Infected = true },
		{ Sender = "Sugar Mill", For = "Midnight Donuts", Contents = "Glaze syrup", Infected = false },
		{ Sender = "Dough Bros.", For = "Slice of Night", Contents = "Mozzarella", Infected = true },
		{ Sender = "Sunrise Produce", For = "Lucky Wok", Contents = "Bok choy", Infected = false },
	},
	SortTarget = 8, -- of 10: two mistakes still clear the day
	InspectSeconds = 1.2,
	UVSeconds = 0.4, -- of beam to reveal a parcel's UV status
	LogbookAfter = 5, -- sorted parcels before the truck's cab opens
	Nests = 4,
	NestSeconds = 6, -- of beam to burn a nest (shared)
	NestEvery = 25, -- each nest hatches a mimic this often
	Tier = 3,
}

function FoodCourtRules.isTrusted(sender: string): boolean
	return table.find(FoodCourtRules.L10.Trusted, sender) ~= nil
end

-- Quarantine infected parcels, deliver clean ones.
function FoodCourtRules.isCorrectCall(parcel: { Infected: boolean }, quarantine: boolean): boolean
	return parcel.Infected == quarantine
end

-- Parcel creatures alive at once: 2 solo, +1 per extra player, at most 5.
function FoodCourtRules.mimicCap(playerCount: number): number
	return math.min(1 + players(playerCount), 5)
end

-- Disguised mimics waiting when the night starts: infected parcels delivered by
-- mistake during the day hatch too.
function FoodCourtRules.initialMimics(playerCount: number, wrongDeliveries: number): number
	return math.min(2 + math.floor((players(playerCount) - 1) / 2) + wrongDeliveries, 6)
end

return FoodCourtRules
