-- Randomized runs with fixed seeds: chaotic players (random walking, prompts, remotes, deaths,
-- disconnects, rejoins) over two shifts of a random level, with invariants checked throughout.
-- Every failure prints a record with the seed and a command that reproduces it.
--   .tools/bin/lune run tests/Properties.spec.luau
--   QA_RUNS=200 QA_FIRST_SEED=1000 .tools/bin/lune run tests/Properties.spec.luau
--   QA_SEED=1234 .tools/bin/lune run tests/Properties.spec.luau       (reproduce one run)

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local Check = require("./harness/Check")
local Bot = require("./harness/Bot")
local Sim = require("./harness/Sim")
local Strategies = require("./harness/Strategies")
local CampaignConfig = require("../src/shared/Campaign/CampaignConfig")

Check.suite("Properties" .. (process.env.QA_SUITE_SUFFIX or ""), "Simulated gameplay tested")
local test, eq, note = Check.test, Check.eq, Check.note

local RUNS = tonumber(process.env.QA_RUNS) or 14
local FIRST = tonumber(process.env.QA_FIRST_SEED) or 1
local ONE = tonumber(process.env.QA_SEED)
local TEAM_SIZES = { 1, 1, 2, 3, 4, 6, 8 }
local REMOTES = {
	"PurchaseUpgrade",
	"Restock",
	"SetBeam",
	"SaveSettings",
	"RequestPurchase",
	"VoteLevel",
	"SubmitCode",
	"AimUpdate",
}
local JUNK: { any } =
	{ true, 0, -1, 0 / 0, 1e300, "", "L14", "Battery", "CashSmall", {}, { Cash = 1e9 }, Vector3.new(0, 1, 0) }
-- how long a stage may run past its configured duration before the clock counts as stuck
local CLOCK_SLACK = 20

local function pick(rng: any, list: { any }): any
	return list[rng:NextInteger(1, #list)]
end

local function levelsList(): { any }
	local list = {}
	for _, level in CampaignConfig.Levels do
		if level.Implemented then
			table.insert(list, level)
		end
	end
	return list
end

-- One chaotic player: each loop does something a real (or malicious) client could do.
local function chaos(run: any, bot: any, rng: any, stats: any)
	local world = run.World
	local level = run.Config
	local strategies = Strategies[level.Id] or {}
	while bot.Player.Parent do
		local root = bot:root()
		if not root then
			bot:waitAlive()
			continue
		end
		local roll = rng:NextNumber()
		if roll < 0.3 then
			-- do the real objective for a while
			local phase = world:phase()
			bot.Strategies = (phase == "Day" and strategies.Day) or (phase == "Night" and strategies.Night) or {}
			local row = bot:focusRow()
			local strategy = row and (bot.Strategies[row.Id] or bot.Strategies[row.Event])
			if strategy then
				strategy(bot, row)
			elseif row then
				local target, label = bot:markerTarget(row)
				if target then
					bot:useTarget(target, label)
				end
			end
		elseif roll < 0.55 then
			local prompts = {}
			for _, d in world.Workspace:GetDescendants() do
				if d:IsA("ProximityPrompt") and d.Enabled then
					table.insert(prompts, d)
				end
			end
			if #prompts > 0 then
				-- nearest of a few, so they aren't all a mile away
				local best, bestDistance = nil, math.huge
				for _ = 1, 4 do
					local prompt = pick(rng, prompts)
					local distance = (bot:promptPosition(prompt) - bot:position()).Magnitude
					if distance < bestDistance then
						best, bestDistance = prompt, distance
					end
				end
				if bot:usable(best) then
					bot:hold(best)
				end
			end
		elseif roll < 0.75 then
			bot:walkTo(Vector3.new(rng:NextInteger(-200, 180), 0, rng:NextInteger(-90, 90)), 6, nil, function()
				return rng:NextNumber() < 0.01
			end)
		elseif roll < 0.9 then
			world:clientFire(bot.Player, pick(rng, REMOTES), pick(rng, JUNK), pick(rng, JUNK))
			bot:wait(0.3)
		elseif roll < 0.94 then
			bot:equip()
			bot:beam(true, Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)))
			bot:wait(rng:NextNumber(0.2, 3))
			bot:beam(false, nil)
		elseif roll < 0.97 then
			local humanoid = bot.Player.Character and bot.Player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = 0
				stats.Deaths += 1
			end
			bot:wait(1)
		else
			bot:wait(rng:NextNumber(0.5, 5))
		end
		bot:wait(0.1)
	end
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function runOne(seed: number): ({ any }, any)
	local state = (seed * 7919) % 2147483647 + 1
	local function nextValue(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	local rng = {
		NextNumber = function(_, a: number?, b: number?): number
			local x = nextValue()
			return if a and b then a + (b - a) * x else x
		end,
		NextInteger = function(_, a: number, b: number): number
			return a + math.floor(nextValue() * (b - a + 1))
		end,
	}
	local levels = levelsList()
	local level = levels[seed % #levels + 1]
	local size = TEAM_SIZES[rng:NextInteger(1, #TEAM_SIZES)]
	local problems: { any } = {}
	local function problem(expected: string, actual: string)
		table.insert(problems, { Expected = expected, Actual = actual })
	end
	local run = Sim.start(level.Id, size, { Seed = seed })
	run.Config = level
	local world = run.World
	world.DefaultPathLimit = 12000 -- random goals are often inside walls: don't search the whole mall
	local stats = { Deaths = 0, Disconnects = 0, Rejoins = 0 }
	local spawnWatch = Sim.watchEnemies(run)
	local paid = {}
	for _, bot in run.Bots do
		world.task.spawn(chaos, run, bot, rng, stats)
	end

	local phaseStart, lastPhase = world.Now, world:phase()
	local shifts = 0
	local nextCheck = 0
	local bots = table.clone(run.Bots)
	local countAfterFirst
	local stop = world.Now + 1100
	while shifts < 2 and world.Now < stop do
		world:step()
		if run.OnStep then
			run.OnStep(world)
		end
		local phase = world:phase()
		if phase ~= lastPhase then
			if lastPhase == "Dawn" then
				shifts += 1
				if shifts == 1 then
					countAfterFirst = #world.Workspace:GetDescendants()
				end
			end
			phaseStart, lastPhase = world.Now, phase
		end
		if world.Now < nextCheck then
			continue
		end
		nextCheck = world.Now + 1
		if process.env.QA_TRACE then
			print(
				string.format(
					"t=%.0f %s wall=%.1f paths=%d rays=%d fails=%d",
					world.Now,
					tostring(phase),
					os.clock(),
					world.Stats.Paths,
					world.Stats.Rays,
					#world.PathFailures
				)
			)
		end

		-- the clock never sticks
		local duration = world.ReplicatedStorage:GetAttribute("PhaseDuration") or 0
		if world.Now - phaseStart > duration + CLOCK_SLACK then
			problem(
				string.format("%s ends after about %d s", phase, duration),
				string.format("still going at %.0f s", world.Now - phaseStart)
			)
			break
		end

		-- disconnects and rejoins, at random times
		if #bots > 1 and rng:NextNumber() < 0.004 then
			local index = rng:NextInteger(1, #bots)
			local gone = table.remove(bots, index)
			stats.Disconnects += 1
			world:removePlayer(gone.Player)
		elseif #bots < size and rng:NextNumber() < 0.01 then
			stats.Rejoins += 1
			local fresh = Bot.new(world, world:addPlayer("Back" .. stats.Rejoins), nil)
			table.insert(bots, fresh)
			world.task.spawn(chaos, run, fresh, rng, stats)
		end

		for _, bot in bots do
			local player = bot.Player
			local data = world:require("Services.DataService").Get(player)
			if data then
				if not (finite(data.Cash) and data.Cash >= 0) then
					problem("cash stays a non-negative number", tostring(data.Cash))
				end
				if not (finite(data.XP) and data.XP >= 0) then
					problem("XP stays a non-negative number", tostring(data.XP))
				end
				local stamp = data.Campaign.Completed[level.Id]
				if stamp then
					if paid[player] and paid[player] ~= stamp then
						problem("first-clear time is set once", tostring(stamp))
					end
					paid[player] = stamp
				end
			end
			local snapshot = bot:snapshot()
			for _, row in (snapshot and snapshot.Rows) or {} do
				if row.Kind == "Count" then
					if row.Progress > row.Target then
						problem(
							"progress never passes its target",
							string.format("%s %d/%d", row.Id, row.Progress, row.Target)
						)
					end
					if row.Done and row.Progress < row.Target then
						problem(
							"done means the target was met",
							string.format("%s %d/%d", row.Id, row.Progress, row.Target)
						)
					end
				end
			end
			for _, result in bot:results() do
				if result.Heading ~= "LEVEL COMPLETE" and result.Heading ~= "LEVEL REPLAYED" and result.Cash ~= 0 then
					problem("only a clear pays at dawn", string.format("%s paid %d", result.Heading, result.Cash))
				end
			end
		end
	end

	if shifts < 2 then
		table.insert(problems, {
			Expected = "two whole shifts go by",
			Actual = string.format("%d in %.0f s, stuck at %s", shifts, world.Now, tostring(world:phase())),
		})
	end
	if #world.Errors > 0 then
		problem("no server errors", world.Errors[1].Message:sub(1, 300))
	end
	for _, spawned in spawnWatch.Spawns do
		if spawned.Nearest < 6 and spawned.Type ~= "PhantomShopper" then
			problem(
				"monsters don't spawn on players",
				string.format("%s %.1f studs away at t=%.0f", spawned.Type, spawned.Nearest, spawned.At)
			)
			break
		end
	end
	local count = #world.Workspace:GetDescendants()
	if countAfterFirst and count > countAfterFirst * 1.5 + 500 then
		problem(
			"the world doesn't keep growing shift after shift",
			string.format("%d → %d instances", countAfterFirst, count)
		)
	end
	local info = { Level = level.Id, Team = size, Stats = stats, Now = world.Now, Instances = count }
	world:shutdown()
	return problems, info
end

local total, failed, teams, disconnects, deaths = 0, 0, {}, 0, 0
local seeds = {}
if ONE then
	table.insert(seeds, ONE)
else
	for i = 0, RUNS - 1 do
		table.insert(seeds, FIRST + i)
	end
end
for _, seed in seeds do
	total += 1
	local ok, problems, info = pcall(runOne, seed)
	if not ok then
		problems, info =
			{ { Expected = "the run finishes", Actual = tostring(problems):sub(1, 400) } },
			{ Level = "?", Team = 0, Stats = {} }
	end
	if #problems > 0 then
		failed += 1
		local first = problems[1]
		print(
			string.format(
				"  FAILURE RECORD\n    seed: %d\n    level: %s\n    scenario: chaos, team of %d, two shifts\n    expected: %s\n    actual: %s\n    reproduce: QA_SEED=%d .tools/bin/lune run tests/Properties.spec.luau",
				seed,
				info.Level,
				info.Team,
				first.Expected,
				first.Actual,
				seed
			)
		)
	else
		teams[info.Team] = (teams[info.Team] or 0) + 1
		disconnects += info.Stats.Disconnects or 0
		deaths += info.Stats.Deaths or 0
	end
	test(string.format("seed %d: %s, team of %d: every invariant held", seed, info.Level, info.Team), function()
		eq(#problems, 0, "failed invariants")
	end)
end
note("Properties.Runs", total)
note("Properties.Failed", failed)
note("Properties.ForcedDeaths", deaths)
note("Properties.Disconnects", disconnects)
local parts = {}
for size, count in teams do
	table.insert(parts, string.format("%d×team of %d", count, size))
end
note("Properties.Teams", table.concat(parts, ", "))

Check.finish()
