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

-- ── Level 11 · Cold Trail / Deep Freeze ─────────────────────────────────────

FoodCourtRules.L11 = {
	Prints = 9, -- frost footprints (revealed by light), 6 needed
	PrintTarget = 6,
	PrintRevealSeconds = 0.3,
	IceLeverSeconds = 5, -- of beam to melt the ice off the secret lever
	LeverHold = 2,
	Logs = 4, -- frozen logbooks in the hidden freezer, 3 needed
	LogTarget = 3,
	ChipSeconds = 3,
	-- the cold meter (0..1): per second
	Rise = { HiddenFreezer = 1 / 25, WalkIn = 1 / 70, WraithNear = 0.07, WraithClose = 0.12 },
	Fall = { Normal = 0.05, Heat = 0.3 },
	Breath = 0.3, -- added by a frost breath hit
	AuraRadius = 18, -- within this of the wraith you chill (WraithClose under half of it)
	HeatRadius = 9,
	FrozenSeconds = 2.5, -- frozen solid at a full meter, then thawed to ThawTo
	ThawTo = 0.7,
	ChillDamage = 6, -- every 2 s while the meter is full
	IceWallSeconds = 20, -- of beam to melt the exit's ice (shared)
	IceWallPerPlayer = 6,
	Tier = 4,
}

export type ColdPlace = {
	InHeat: boolean,
	InHiddenFreezer: boolean,
	InWalkIn: boolean,
	WraithDistance: number?, -- nearest wraith (nil: none)
}

-- The cold meter after dt seconds in `place`. Heat always wins; a wraith's aura stacks
-- with a freezer's chill.
function FoodCourtRules.coldStep(cold: number, dt: number, place: ColdPlace): number
	local r = FoodCourtRules.L11
	if place.InHeat then
		return math.max(0, cold - r.Fall.Heat * dt)
	end
	local rise = 0
	if place.InHiddenFreezer then
		rise += r.Rise.HiddenFreezer
	elseif place.InWalkIn then
		rise += r.Rise.WalkIn
	end
	local d = place.WraithDistance
	if d and d <= r.AuraRadius then
		rise += if d <= r.AuraRadius / 2 then r.Rise.WraithClose else r.Rise.WraithNear
	end
	if rise <= 0 then
		return math.max(0, cold - r.Fall.Normal * dt)
	end
	return math.min(1, cold + rise * dt)
end

function FoodCourtRules.wraithCount(playerCount: number): number
	return if players(playerCount) >= 3 then 2 else 1
end

function FoodCourtRules.iceWallSeconds(playerCount: number): number
	local r = FoodCourtRules.L11
	return r.IceWallSeconds + r.IceWallPerPlayer * (players(playerCount) - 1)
end

-- ── Level 12 · Under the Floor / The Shifting Maze ──────────────────────────

FoodCourtRules.L12 = {
	Cols = 8,
	Rows = 8,
	Entrance = { 2, 1 }, -- where the storage ramp comes down
	Heart = { 5, 5 }, -- the escape portal
	Seals = { { 1, 8 }, { 8, 8 }, { 8, 1 }, { 1, 4 } },
	Anomalies = { { 3, 6 }, { 7, 7 }, { 6, 2 }, { 2, 5 }, { 4, 3 } },
	AnomalyTarget = 4,
	RevealRange = 7, -- an anomaly shows itself this close
	SignalRange = 48, -- the scanner hears it from this far
	RecordSeconds = 2,
	ChalkSpots = 5, -- along the day's route from the entrance to the heart
	ChalkTarget = 4,
	DaySeed = 812,
	ExtraOpenings = 10, -- walls knocked out after carving: a few loops make it fairer
	ShiftEvery = 22,
	ShiftWarn = 3, -- red lines on the floor before walls rise
	ShiftMove = 1.5,
	QuickEscapeLeft = 60, -- escape with this many seconds of night left for the bonus
	Tier = 3,
}

-- Walls are keys: "V:c:r" between (c, r) and (c + 1, r); "H:c:r" between (c, r) and (c, r + 1).
export type Walls = { [string]: boolean }

local function wallBetween(a: { number }, b: { number }): string
	if a[1] ~= b[1] then
		return string.format("V:%d:%d", math.min(a[1], b[1]), a[2])
	end
	return string.format("H:%d:%d", a[1], math.min(a[2], b[2]))
end

function FoodCourtRules.allWalls(): { string }
	local r = FoodCourtRules.L12
	local list = {}
	for c = 1, r.Cols do
		for row = 1, r.Rows do
			if c < r.Cols then
				table.insert(list, string.format("V:%d:%d", c, row))
			end
			if row < r.Rows then
				table.insert(list, string.format("H:%d:%d", c, row))
			end
		end
	end
	return list
end

local function neighbours(cell: { number }): { { number } }
	local r = FoodCourtRules.L12
	local list = {}
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local c, row = cell[1] + d[1], cell[2] + d[2]
		if c >= 1 and row >= 1 and c <= r.Cols and row <= r.Rows then
			table.insert(list, { c, row })
		end
	end
	return list
end

-- A maze carved by randomised depth-first search (every cell reachable), then `extra`
-- walls knocked out for loops. random() → [0, 1).
function FoodCourtRules.maze(random: () -> number, extra: number?): Walls
	local r = FoodCourtRules.L12
	local walls: Walls = {}
	for _, key in FoodCourtRules.allWalls() do
		walls[key] = true
	end
	local visited = { [r.Entrance[1] + r.Entrance[2] * 100] = true }
	local stack = { r.Entrance }
	while #stack > 0 do
		local cell = stack[#stack]
		local options = {}
		for _, n in neighbours(cell) do
			if not visited[n[1] + n[2] * 100] then
				table.insert(options, n)
			end
		end
		if #options == 0 then
			table.remove(stack)
		else
			local n = options[math.floor(random() * #options) + 1]
			walls[wallBetween(cell, n)] = nil
			visited[n[1] + n[2] * 100] = true
			table.insert(stack, n)
		end
	end
	local remaining = {}
	for _, key in FoodCourtRules.allWalls() do
		if walls[key] then
			table.insert(remaining, key)
		end
	end
	for _ = 1, math.min(extra or 0, #remaining) do
		local index = math.floor(random() * #remaining) + 1
		walls[remaining[index]] = nil
		table.remove(remaining, index)
	end
	return walls
end

-- Shortest route (list of cells, from first to last) or nil if `to` can't be reached.
function FoodCourtRules.mazePath(walls: Walls, from: { number }, to: { number }): { { number } }?
	local key = function(cell: { number }): number
		return cell[1] + cell[2] * 100
	end
	local previous: { [number]: { number } } = {}
	local seen = { [key(from)] = true }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local cell = queue[head]
		head += 1
		if cell[1] == to[1] and cell[2] == to[2] then
			local path = { cell }
			while previous[key(path[1])] do
				table.insert(path, 1, previous[key(path[1])])
			end
			return path
		end
		for _, n in neighbours(cell) do
			if not seen[key(n)] and not walls[wallBetween(cell, n)] then
				seen[key(n)] = true
				previous[key(n)] = cell
				table.insert(queue, n)
			end
		end
	end
	return nil
end

-- Every cell reachable from the entrance.
function FoodCourtRules.mazeConnected(walls: Walls): boolean
	local r = FoodCourtRules.L12
	for c = 1, r.Cols do
		for row = 1, r.Rows do
			if not FoodCourtRules.mazePath(walls, r.Entrance, { c, row }) then
				return false
			end
		end
	end
	return true
end

-- What a shift does: walls that rise and walls that sink.
function FoodCourtRules.mazeDiff(from: Walls, to: Walls): ({ string }, { string })
	local rise, sink = {}, {}
	for _, key in FoodCourtRules.allWalls() do
		if to[key] and not from[key] then
			table.insert(rise, key)
		elseif from[key] and not to[key] then
			table.insert(sink, key)
		end
	end
	return rise, sink
end

-- The anomaly scanner: 1 right on top of it, 0 at SignalRange or further.
function FoodCourtRules.signal(distance: number): number
	return math.clamp(1 - distance / FoodCourtRules.L12.SignalRange, 0, 1)
end

-- ── Level 13 · Fresh Air / Toxic Bloom ──────────────────────────────────────

FoodCourtRules.L13 = {
	Fans = 3,
	FanSeconds = 3,
	Dampers = 5, -- the airflow puzzle: damper i flips vents i-1, i, i+1 (in a ring)
	-- night: gas per zone (0..1)
	Zones = { "Kitchen", "HallWest", "HallEast", "NorthWing", "SouthWing", "BackRooms" },
	Adjacent = {
		Kitchen = { "HallWest", "BackRooms" },
		HallWest = { "Kitchen", "HallEast", "NorthWing", "SouthWing" },
		HallEast = { "HallWest", "NorthWing", "SouthWing" },
		NorthWing = { "HallWest", "HallEast", "BackRooms" },
		SouthWing = { "HallWest", "HallEast", "BackRooms" },
		BackRooms = { "Kitchen", "NorthWing", "SouthWing" },
	},
	SourceRise = 1 / 45, -- a zone with an open spore vent
	SpreadRise = 1 / 90, -- from a neighbour above SpreadFrom
	SpreadFrom = 0.5,
	PurgeSeconds = 6, -- a purge clears its zone over this long...
	PurgeShield = 30, -- ...and keeps it clear this long
	PurgeHold = 2.5,
	PurgeTarget = 8,
	FirstSources = 2,
	NewSourceEvery = 45,
	MaxSources = 4,
	-- your gas meter (0..1)
	MeterRise = 0.12, -- per second, times the zone's gas
	MeterFall = 0.15, -- per second in clean air (zone gas under CleanBelow, or outside)
	CleanBelow = 0.15,
	StationDrop = 0.6, -- an oxygen tank breath
	StationCooldown = 6,
	ChokeDamage = 6, -- every ChokeEvery seconds while the meter is full
	ChokeEvery = 2,
	Exhale = 0.35, -- a bloater's exhale adds this to your meter
	PopGas = 0.25, -- a burst bloater adds this to its zone (and to anyone within PopRadius)
	PopRadius = 10,
	BloaterFirst = 20,
	BloaterEvery = 20,
	Tier = 4,
}

-- The airflow panel: returns the vents after flipping damper i.
function FoodCourtRules.toggleDamper(vents: { boolean }, i: number): { boolean }
	local n = #vents
	local result = table.clone(vents)
	for _, k in { i - 1, i, i + 1 } do
		local index = (k - 1) % n + 1
		result[index] = not result[index]
	end
	return result
end

function FoodCourtRules.airflowSolved(vents: { boolean }): boolean
	for _, open in vents do
		if not open then
			return false
		end
	end
	return true
end

-- Dampers to press (each at most once) that open every vent, or nil if impossible.
function FoodCourtRules.solveAirflow(vents: { boolean }): { number }?
	local n = #vents
	for mask = 0, 2 ^ n - 1 do
		local state = vents
		local presses = {}
		for i = 1, n do
			if (mask // 2 ^ (i - 1)) % 2 == 1 then
				state = FoodCourtRules.toggleDamper(state, i)
				table.insert(presses, i)
			end
		end
		if FoodCourtRules.airflowSolved(state) then
			return presses
		end
	end
	return nil
end

-- Which gas zone a point is in (nil = outside the food court: clean air).
function FoodCourtRules.zoneAt(x: number, z: number): string?
	if x < -250 or x > -98 or z < -128 or z > 92 then
		return nil
	end
	if x < -184 then
		if z >= -96 and z <= -48 or z >= 48 then
			return "BackRooms"
		end
		return if z > -48 and z < 48 then "Kitchen" else nil
	end
	if z >= 48 then
		return "NorthWing"
	elseif z <= -48 then
		return "SouthWing"
	end
	return if x < -141 then "HallWest" else "HallEast"
end

-- One gas step for every zone. purgedUntil[zone] = clock time its purge shield ends.
function FoodCourtRules.gasStep(
	levels: { [string]: number },
	sources: { [string]: boolean },
	purgedUntil: { [string]: number },
	dt: number,
	now: number
): { [string]: number }
	local r = FoodCourtRules.L13
	local nextLevels = {}
	for _, zone in r.Zones do
		local level = levels[zone] or 0
		if now < (purgedUntil[zone] or 0) then
			level = math.max(0, level - dt / r.PurgeSeconds)
		else
			local rise = if sources[zone] then r.SourceRise else 0
			for _, other in r.Adjacent[zone] do
				if (levels[other] or 0) >= r.SpreadFrom then
					rise += r.SpreadRise
				end
			end
			level = math.min(1, level + rise * dt)
		end
		nextLevels[zone] = level
	end
	return nextLevels
end

-- A player's gas meter after dt seconds in air of the given gas level.
function FoodCourtRules.gasMeterStep(meter: number, gas: number, dt: number): number
	local r = FoodCourtRules.L13
	if gas < r.CleanBelow then
		return math.max(0, meter - r.MeterFall * dt)
	end
	return math.min(1, meter + r.MeterRise * gas * dt)
end

-- Spore Bloaters alive at once: 2 solo, +1 per extra player, at most 6.
function FoodCourtRules.bloaterCap(playerCount: number): number
	return math.min(1 + players(playerCount), 6)
end

return FoodCourtRules
