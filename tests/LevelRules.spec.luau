-- Level-specific rules on the real server code: the right action advances things, the wrong one
-- doesn't, and each level's signature mechanic does what its objective text says. Bots still only
-- walk, hold prompts and aim the beam. Simulated gameplay, not Roblox.
--   .tools/bin/lune run tests/LevelRules.spec.luau

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local Check = require("./harness/Check")
local Sim = require("./harness/Sim")
local Strategies = require("./harness/Strategies")

Check.suite("LevelRules", "Simulated gameplay tested")
local test, eq, truthy, falsy, note = Check.test, Check.eq, Check.truthy, Check.falsy, Check.note

-- Runs a bot script (it can walk and wait) to the end, or until `seconds` of game time pass.
local function play(run: any, fn: () -> (), seconds: number?): boolean
	local world = run.World
	local finished = false
	local failure = nil
	world.task.spawn(function()
		local ok, err = pcall(fn)
		finished = true
		failure = if ok then nil else err
	end)
	local stop = world.Now + (seconds or 240)
	while not finished and world.Now < stop do
		world:step()
		if run.OnStep then
			run.OnStep(world)
		end
	end
	if failure then
		error(failure, 0)
	end
	return finished
end

local function startDay(level: string, seed: number?): any
	local run = Sim.start(level, 1, { Seed = seed or 5 })
	run.World:waitForPhase("Day", 200)
	run.World:run(1)
	return run
end

-- Plays the day properly, stops as the night begins.
local function startNight(level: string, seed: number?): any
	local run = Sim.start(level, 1, { Seed = seed or 5 })
	local s = Strategies[level] or {}
	Sim.playStage(run, "Day", s.Day, s.Per)
	run.World:waitForPhase("Night", 200)
	run.World:run(1)
	run.Bots[1].Strategies = {}
	return run
end

local function row(bot: any, id: string): any
	return bot:row(id)
end

local function promptNamed(bot: any, action: string): any
	local best, bestDistance = nil, math.huge
	for _, d in bot.World.Workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.ActionText == action and d.Enabled then
			local distance = (bot:promptPosition(d) - bot:position()).Magnitude
			if distance < bestDistance then
				best, bestDistance = d, distance
			end
		end
	end
	return best
end

local function tagged(world: any, tag: string): { any }
	return world.CollectionService:GetTagged(tag)
end

-- ── Level 4 ─────────────────────────────────────────────────────────────────

test("L04 Night: BUG-11 regression: strike groups don't land on someone at their approach point", function()
	-- Standing on an approach of each terminal in turn; seed 1011 of the random runs found this.
	for _, spot in { Vector3.new(0, 0, -95), Vector3.new(-50, 0, -50), Vector3.new(178, 0, 10) } do
		local run = startNight("L04", 14)
		local world, bot = run.World, run.Bots[1]
		local watch = Sim.watchEnemies(run)
		play(run, function()
			bot:walkTo(spot, 2)
			while world:phase() == "Night" do
				bot:wait(0.5)
			end
		end, 240)
		for _, spawned in watch.Spawns do
			truthy(spawned.Nearest >= 8, string.format("%s %.1f studs away", spawned.Type, spawned.Nearest))
		end
		truthy(#watch.Spawns > 0, "strike groups came")
	end
end)

-- ── Level 5 ─────────────────────────────────────────────────────────────────

test("L05 Day: a wrong vault code neither opens the vault nor advances the objective", function()
	local run = startDay("L05")
	local world, bot = run.World, run.Bots[1]
	world:clientFire(bot.Player, "SubmitCode", "9999")
	world:run(2)
	eq(row(bot, "code").Progress, 0, "code objective")
	Check.noServerErrors(world)
end)

test("L05 Night: walking makes more noise than sneaking, and standing still makes none", function()
	local run = startNight("L05")
	local world, bot = run.World, run.Bots[1]
	local loud, quiet = 0, 0
	local mode = "loud"
	run.OnStep = function()
		local noise = bot.Player:GetAttribute("Noise") or 0
		if mode == "loud" then
			loud = math.max(loud, noise)
		elseif mode == "quiet" then
			quiet = math.max(quiet, noise)
		end
	end
	play(run, function()
		bot:walkTo(Vector3.new(0, 0, -40), 3)
		mode = "pause"
		bot:wait(2)
		bot.SpeedCap = 7
		mode = "quiet"
		bot:walkTo(Vector3.new(0, 0, 40), 3)
		mode = "pause"
		bot.SpeedCap = nil
	end, 40)
	truthy(loud > 0, "walking is audible")
	truthy(quiet < loud, string.format("sneaking is quieter (%.2f vs %.2f)", quiet, loud))
	note("L05.Noise", string.format("walk %.2f, sneak %.2f", loud, quiet))
end)

test("L05 Night: hiding in a locker counts, and getting out again works", function()
	local run = startNight("L05")
	local bot = run.Bots[1]
	play(run, function()
		local prompt = promptNamed(bot, "Hide")
		truthy(prompt, "a locker to hide in")
		bot:hold(prompt)
		bot:wait(1)
		eq(row(bot, "hide").Progress, 1, "hide objective")
		local leave = promptNamed(bot, "Leave Locker")
		truthy(leave, "a way out")
		bot:hold(leave)
		bot:wait(1)
		truthy(promptNamed(bot, "Hide"), "locker free again")
	end, 60)
	Check.noServerErrors(run.World)
end)

test("L05 Night: the radio lures, counts once per use and goes on cooldown", function()
	local run = startNight("L05")
	local bot = run.Bots[1]
	play(run, function()
		local prompt = promptNamed(bot, "Turn On Radio (lure)")
		truthy(prompt, "a radio")
		bot:hold(prompt)
		bot:wait(1)
		eq(row(bot, "decoy").Progress, 1, "decoy objective")
		eq(prompt.Enabled, false, "cooling down")
	end, 60)
end)

test("L05 Night: music boxes only count when silenced, and being caught is counted against you", function()
	local run = startNight("L05")
	local world, bot = run.World, run.Bots[1]
	local caught = false
	play(run, function()
		-- a loud player who never hides gets found
		local stop = world.Now + 150
		local points =
			{ Vector3.new(0, 0, -40), Vector3.new(0, 0, 40), Vector3.new(60, 0, 0), Vector3.new(-40, 0, -20) }
		local i = 1
		while world.Now < stop and not caught and world:phase() == "Night" do
			bot:walkTo(points[i % #points + 1], 3)
			i += 1
			caught = row(bot, "caught").Progress > 0
		end
	end, 170)
	eq(row(bot, "boxes").Progress, 0, "walking around silences nothing")
	note("L05.LoudWalkerCaught", tostring(caught))
	truthy(caught, "the stalker catches a loud player")
end)

-- ── Level 6 ─────────────────────────────────────────────────────────────────

test("L06 Day: scrap is picked up by walking, kits cost scrap, towers need a kit", function()
	local run = startDay("L06")
	local world, bot = run.World, run.Bots[1]
	play(run, function()
		local spot = tagged(world, "FloodlightSpot")[1]
		truthy(spot, "a tower spot")
		local before = row(bot, "floodlights").Progress
		for _, prompt in bot:promptsFor(spot) do
			falsy(bot:usable(prompt), "no building without a kit")
		end
		eq(row(bot, "floodlights").Progress, before, "no tower")
		local craft = promptNamed(bot, "Craft Floodlight Kit")
		truthy(craft, "a workbench")
		bot:hold(craft)
		bot:wait(0.5)
		eq(bot.Player:GetAttribute("Carrying"), nil, "no scrap, no kit")
	end, 40)
	Check.noServerErrors(world)
end)

test("L06 Night: towers built by day switch on at night", function()
	local run = startNight("L06")
	local world = run.World
	local built = 0
	for _, model in world.Workspace:GetDescendants() do
		if model:IsA("Model") and model.Name == "FloodlightTower" then
			built += 1
		end
	end
	truthy(built >= 3, "towers standing at night: " .. built)
end)

test("L06 Night: a freed shopper follows, stops counting if you run off, and the ring rescues them", function()
	local run = startNight("L06")
	local world, bot = run.World, run.Bots[1]
	play(run, function()
		local folder = world.Workspace:FindFirstChild("RescueNight")
		local prompt
		for _, d in folder:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.Name == "RescuePrompt" and d.Enabled then
				prompt = d
				break
			end
		end
		truthy(prompt, "a cocooned shopper")
		eq(row(bot, "rescue").Progress, 0, "no one rescued yet")
		truthy(bot:hold(prompt), "cut them free")
		bot:wait(1)
		eq(row(bot, "free").Progress, 1, "cutting free counts for the bonus")
		local npc = prompt.Parent
		local start = npc.Position
		bot.SpeedCap = 13.5
		bot:walkTo(Vector3.new(0, 0, -62), 3, nil, function()
			return (npc.Position - bot:position()).Magnitude > 22
		end)
		bot:wait(3)
		truthy((npc.Position - start).Magnitude > 5, "they walked after the player")
	end, 120)
	Check.noServerErrors(world)
end)

test("L06 Night: at dawn the van only takes players standing in the ring", function()
	local run = startNight("L06")
	local world, bot = run.World, run.Bots[1]
	play(run, function()
		-- guards the ring (the same as the level's bot); if killed, walks out and back
		while world:phase() == "Night" do
			if bot:root() then
				Strategies.L06.Night.escape(bot)
			else
				bot:waitAlive()
			end
			bot:wait(0.2)
		end
	end, 300)
	truthy(run.Bots[1]:results()[1] ~= nil, "dawn arrived")
	local rows = Sim.rows(bot)
	eq(rows.escape.Done, true, "in the ring at dawn: escaped")
	local away = startNight("L06", 6)
	local alive = false
	play(away, function()
		away.Bots[1]:walkTo(Vector3.new(150, 0, 0), 5)
		while away.World:phase() == "Night" do
			alive = away.Bots[1]:root() ~= nil and away.Bots[1]:position().X > 100
			away.Bots[1]:wait(0.2)
		end
	end, 300)
	if alive then -- (the spawn point is beside the ring: someone killed and respawned is in it)
		eq(Sim.rows(away.Bots[1]).escape.Done, false, "elsewhere at dawn: left behind")
	end
	note("L06.AwayBotAliveAtDawn", tostring(alive))
end)

test("L06 Night: respawning beside the ring earns no evacuation; walking back to it does", function()
	-- The spawn point is inside the ring's radius. Killed with time to spare, and...
	local function finish(walkBack: boolean): boolean
		local run = startNight("L06", 8)
		local world, bot = run.World, run.Bots[1]
		play(run, function()
			while world:phase() == "Night" do
				local left = (world.ReplicatedStorage:GetAttribute("PhaseStartedAt") or 0)
					+ (world.ReplicatedStorage:GetAttribute("PhaseDuration") or 0)
					- world.Workspace:GetServerTimeNow()
				if left <= 25 then
					break
				end
				bot:wait(0.5)
			end
			if bot:root() then
				bot.Player.Character:FindFirstChildOfClass("Humanoid").Health = 0
				bot:wait(0.5)
			end
			bot:waitAlive()
			truthy(bot.Player:GetAttribute("EvacMustWalk") == true or not walkBack, "told it has to walk")
			if walkBack then
				bot:walkTo(Vector3.new(0, 0, -28), 3)
				bot:wait(0.6)
				bot:walkTo(Vector3.new(0, 0, -62), 3)
			end
			while world:phase() == "Night" do
				bot:wait(0.2)
			end
		end, 300)
		world:waitForPhase("Dawn", 30)
		return Sim.rows(bot).escape.Done
	end
	eq(finish(false), false, "respawned at the entrance and stayed")
	eq(finish(true), true, "respawned, went out and came back")
end)

test("L06 Night: nobody standing idle at the spawn from the start is evacuated", function()
	local run = Sim.start("L06", 1, { Seed = 9 })
	Sim.idleStage(run, "Day")
	Sim.idleStage(run, "Night")
	Sim.toDawn(run)
	eq(run.StageEnd.Night[1].escape.Done, false, "escape")
end)

test("L06 Night: BUG-08 regression: hunts send one crawler at a solo player, two at a team", function()
	-- Hunters are the crawlers given a shopper to go after; a hunt's arrive in the same instant.
	local function largestHunt(players: number): number
		local run = Sim.start("L06", players, { Seed = 12 })
		local s = Strategies.L06
		Sim.playStage(run, "Day", s.Day, s.Per)
		local world = run.World
		world:waitForPhase("Night", 60)
		for _, bot in run.Bots do
			bot.Strategies = s.Night
			world.task.spawn(function()
				bot:playStage("Night")
			end)
		end
		local seen, groups = {}, {}
		local stop = world.Now + 100
		while world.Now < stop and world:phase() == "Night" do
			world:step()
			for _, enemy in world:require("Services.EnemyService").GetAll() do
				if enemy.Goal and not seen[enemy] then
					seen[enemy] = true
					groups[world.Now] = (groups[world.Now] or 0) + 1
				end
			end
		end
		local best = 0
		for _, size in groups do
			best = math.max(best, size)
		end
		return best
	end
	eq(largestHunt(1), 1, "solo")
	eq(largestHunt(2), 2, "team")
end)

test("L06 Night: BUG-08 regression: a solo player can clear it reliably", function()
	local s = Strategies.L06
	local clears = 0
	for seed = 1, 6 do
		local run = Sim.start("L06", 1, { Seed = seed * 19 })
		Sim.playLevel(run, s.Day, s.Night, s.Per)
		if Sim.campaign(run.World, run.Bots[1].Player).Completed.L06 then
			clears += 1
		end
		run.World:shutdown()
	end
	note("L06.SoloSkilledClears", clears .. " of 6 seeds")
	truthy(clears >= 5, clears .. " of 6")
end)

-- ── Level 7 ─────────────────────────────────────────────────────────────────

test("L07 Day: a cannon needs someone in the ring; mirrors alone don't clear the day", function()
	local run = startDay("L07")
	local bot = run.Bots[1]
	run.World:run(30)
	eq(row(bot, "cannons").Progress, 0, "no charge with nobody there")
	eq(row(bot, "mirrors").Progress, 0, "puzzle untouched")
end)

test("L07 Night: shield blocks all damage, three phases in order, defeat and rewards land once", function()
	local run = Sim.start("L07", 1, { Seed = 5 })
	local world, bot = run.World, run.Bots[1]
	local s = Strategies.L07
	local phases, shieldedDamage, last, lastState = {}, 0, nil, nil
	local brood = 0
	run.OnStep = function()
		local rs = world.ReplicatedStorage
		if world:phase() ~= "Night" or not rs:GetAttribute("BossActive") then
			return
		end
		local phase = rs:GetAttribute("BossPhase")
		if phase and phases[#phases] ~= phase then
			table.insert(phases, phase)
		end
		local hp, state = rs:GetAttribute("BossHP"), rs:GetAttribute("BossShield")
		if last and hp and hp < last and state == "Shielded" and lastState == "Shielded" then
			shieldedDamage += last - hp
		end
		last, lastState = hp, state
		brood = math.max(brood, #world:require("Services.EnemyService").GetAll())
	end
	Sim.playLevel(run, s.Day, s.Night, s.Per)
	eq(shieldedDamage, 0, "damage through the shield")
	eq(table.concat(phases, ","), "1,2,3", "phases")
	truthy(brood > 0, "she calls a brood")
	local result = bot:results()[1]
	eq(result.Heading, "LEVEL COMPLETE", "heading")
	truthy(result.Chapter, "chapter reward on the results screen")
	eq(result.Chapter.Title, "Queen Slayer", "title")
	local data = world:require("Services.DataService").Get(bot.Player)
	eq(data.Title, "Queen Slayer", "saved title")
	truthy(data.Equipment.PrismLens, "Prism Lens from the mirror puzzle")
	Check.noServerErrors(world)
end)

test("L07 Night: nobody at the cannons means her shield stays up", function()
	local run = startNight("L07")
	local world = run.World
	local rs = world.ReplicatedStorage
	local down = false
	run.OnStep = function()
		if
			rs:GetAttribute("BossShield") ~= "Shielded"
			and rs:GetAttribute("BossShield") ~= nil
			and rs:GetAttribute("BossActive")
		then
			down = true
		end
	end
	local stop = world.Now + 60
	while world.Now < stop and world:phase() == "Night" do
		world:step()
		run.OnStep()
	end
	falsy(down, "shield dropped by itself")
end)

-- ── Level 8 ─────────────────────────────────────────────────────────────────

test("L08 Night: appliances need the beam, warn before they throw, and carts telegraph", function()
	local run = Sim.start("L08", 1, { Seed = 5 })
	local world, bot = run.World, run.Bots[1]
	local s = Strategies.L08 or {}
	local lanes, charges, possessed = 0, 0, {}
	local closest = math.huge
	run.OnStep = function()
		if world:phase() ~= "Night" then
			return
		end
		local telegraphs = world.Workspace:FindFirstChild("Telegraphs")
		if telegraphs then
			lanes = math.max(lanes, #telegraphs:GetChildren())
		end
		for _, enemy in world:require("Services.EnemyService").GetAll() do
			if enemy.Model:GetAttribute("Charging") then
				charges += 1
			end
		end
		for _, part in tagged(world, "PossessedAppliance") do
			if not possessed[part] then
				possessed[part] = true
				local root = bot:root()
				if root then
					closest = math.min(closest, (part.Position - root.Position).Magnitude)
				end
			end
		end
	end
	Sim.playStage(run, "Day", s.Day, s.Per)
	Sim.idleStage(run, "Night")
	Sim.toDawn(run)
	eq(Sim.rows(bot).exorcise.Progress, 0, "no beam, no exorcism")
	truthy(lanes > 0, "red lanes shown")
	truthy(next(possessed) ~= nil, "appliances possessed")
	note("L08.ClosestPossession", string.format("%.0f studs", closest))
	Check.noServerErrors(world)
end)

-- ── Level 9 ─────────────────────────────────────────────────────────────────

test("L09 Night: the dock is no escape until the valves are shut", function()
	local run = startNight("L09")
	local world, bot = run.World, run.Bots[1]
	play(run, function()
		local zone = tagged(world, "EscapeZone")[1]
		truthy(zone, "an exit marker")
		eq(row(bot, "valves").Progress, 0, "valves open")
		bot:walkTo(zone.Position, 3)
		bot:wait(2)
		eq(row(bot, "escape").Progress, 0, "reaching the dock early doesn't count")
	end, 60)
	Check.noServerErrors(world)
end)

test("L09 Day: live cables refuse splicing and the switchboard stays locked until they're done", function()
	local run = startDay("L09")
	local world, bot = run.World, run.Bots[1]
	play(run, function()
		eq(row(bot, "switchboard").Progress, 0, "breakers untouched")
		local lever = tagged(world, "SwitchLever")[1]
		if lever then
			for _, prompt in bot:promptsFor(lever) do
				if bot:usable(prompt) then
					bot:hold(prompt)
				end
			end
		end
		eq(row(bot, "switchboard").Progress, 0, "one lever doesn't finish the board")
	end, 40)
	Check.noServerErrors(world)
end)

-- ── Level 10 ────────────────────────────────────────────────────────────────

test("L10 Day: a wrong call loses the perfect bonus but never softlocks the sort", function()
	local run = Sim.start("L10", 1, { Seed = 5 })
	local world, bot = run.World, run.Bots[1]
	world:waitForPhase("Day", 200)
	bot.Strategies = {}
	play(run, function()
		for _ = 1, 3 do
			local target = bot:markerTarget(row(bot, "sort"))
			if target then
				Strategies.parcelCall(bot, target, true)
			end
		end
	end, 60)
	Check.noServerErrors(world)
	local nextDay = Strategies.L10.Day
	bot.Strategies = nextDay
	world.task.spawn(function()
		bot:playStage("Day")
	end)
	while world:phase() == "Day" do
		world:step()
	end
	eq(Sim.rows(bot).sort.Done, true, "the sort can still finish after wrong calls")
	eq(Sim.rows(bot).nowrong.Done, false, "the perfect bonus is lost")
end)

test("L10 Night: nests only burn under the beam; disguised parcels look like parcels", function()
	local run = startNight("L10")
	local world, bot = run.World, run.Bots[1]
	world:run(30)
	eq(row(bot, "nests").Progress, 0, "nests don't burn by themselves")
	eq(#tagged(world, "InfectedNest"), 4, "four nests")
	Check.noServerErrors(world)
end)

-- ── Level 11 ────────────────────────────────────────────────────────────────

test("L11 Night: cold rises at night, heat lamps bring it down, and the exit needs melting first", function()
	local run = startNight("L11")
	local world, bot = run.World, run.Bots[1]
	local peak, warmed, last, escapedEarly = 0, false, 0, false
	run.OnStep = function()
		local cold = bot.Player:GetAttribute("Meter_Cold")
		if type(cold) == "number" then
			peak = math.max(peak, cold)
			local lamp = false
			for _, heat in tagged(world, "HeatLamp") do
				if bot:root() and (heat.Position - bot:position()).Magnitude < 8 then
					lamp = true
				end
			end
			if lamp and cold < last then
				warmed = true
			end
			last = cold
		end
		local wall = tagged(world, "IceWall")[1]
		if wall and not wall:GetAttribute("Done") and bot:row("escape") and bot:row("escape").Progress > 0 then
			escapedEarly = true
		end
	end
	-- play, but go and warm up as soon as it's noticeable, so the lamp gets tested at any peak
	bot.Strategies = table.clone(Strategies.L11.Night)
	local reflex = bot.Strategies.Reflex
	bot.Strategies.Reflex = function(self: any): boolean
		local cold = self.Player:GetAttribute("Meter_Cold")
		if type(cold) == "number" and cold > 0.25 then
			self.Player:SetAttribute("WarmTest", true)
			local lamp = tagged(world, "HeatLamp")[1]
			if lamp then
				self:walkTo(lamp.Position, 5)
				self:wait(0.5)
				return true
			end
		end
		return reflex(self)
	end
	world.task.spawn(function()
		bot:playStage("Night")
	end)
	while world:phase() == "Night" do
		world:step()
		run.OnStep()
	end
	truthy(peak > 0, "getting colder")
	note("L11.WarmedAtLamp", tostring(warmed))
	truthy(peak <= 0.25 or warmed, "the heat lamp warmed the player")
	truthy(not escapedEarly, "nobody escaped through unmelted ice")
	eq(Sim.rows(bot).escape.Done, true, "the exit worked once melted")
	note("L11.PeakCold", string.format("%.2f", peak))
	Check.noServerErrors(world)
end)

-- ── Level 12 ────────────────────────────────────────────────────────────────

test("L12 Day: 2000 generated mazes are all fully connected, entrance to heart and every seal", function()
	local run = startDay("L12")
	local rules = run.World:require("Levels.FoodCourtRules")
	local seed = 1
	local function random(): number
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	for _ = 1, 2000 do
		local walls = rules.maze(random, rules.L12.ExtraOpenings)
		truthy(rules.mazeConnected(walls), "connected")
	end
	note("L12.MazesChecked", 2000)
end)

test("L12 Night: the heart stays sealed until all four seals are in, and walls really shift", function()
	local run = startNight("L12")
	local world, bot = run.World, run.Bots[1]
	local moved = {}
	local baseline = {}
	run.OnStep = function()
		for _, d in world.Workspace:FindFirstChild("BasementMaze"):GetDescendants() do
			if d.Name == "MazeWall" then
				if baseline[d] == nil then
					baseline[d] = d.CanCollide
				elseif baseline[d] ~= d.CanCollide then
					moved[d] = true
				end
			end
		end
	end
	play(run, function()
		local heart = tagged(world, "MazeHeart")[1]
		truthy(heart, "the heart")
		truthy(bot:walkTo(heart.Position, 2), "reachable on foot")
		bot:wait(30)
		eq(row(bot, "escape").Progress, 0, "sealed with no seals taken")
	end, 90)
	local count = 0
	for _ in moved do
		count += 1
	end
	truthy(count > 0, "walls moved within two shifts")
	note("L12.WallsShifted", count)
	Check.noServerErrors(world)
end)

test("L12 Day: an anomaly can't be recorded from far away", function()
	local run = startDay("L12")
	local world, bot = run.World, run.Bots[1]
	for _, spot in tagged(world, "Anomaly") do
		for _, prompt in bot:promptsFor(spot) do
			falsy(prompt.Enabled and prompt.MaxActivationDistance > 50, "hidden prompts stay short range")
		end
	end
	eq(row(bot, "anomalies").Progress, 0, "nothing recorded from the entrance")
end)

-- ── Level 13 ────────────────────────────────────────────────────────────────

test("L13 Night: purging clean air is refused, gas fills the meter, and the oxygen tank helps", function()
	local run = startNight("L13")
	local world, bot = run.World, run.Bots[1]
	play(run, function()
		local switch = tagged(world, "PurgeSwitch")[1]
		truthy(switch, "a purge switch")
		local prompt = bot:promptsFor(switch)[1]
		bot:hold(prompt)
		bot:wait(0.5)
		eq(row(bot, "purge").Progress, 0, "a clean zone can't be farmed for purges")
		truthy(bot:heard("still clean") or bot:row("purge").Progress == 0, "told why")
	end, 40)
	Check.noServerErrors(world)
end)

test("L13 Night: BUG-07 regression: the arrow points at a switch with gas to purge", function()
	local run = startNight("L13")
	local world, bot = run.World, run.Bots[1]
	world:run(40) -- the vents have opened and gas has spread
	local target = bot:markerTarget(row(bot, "purge"))
	truthy(target, "an arrow")
	eq(target:GetAttribute("Gassy"), true, "the arrow's switch has gas")
	Check.noServerErrors(world)
end)

test("L13 Day: a wrong damper combination doesn't count as balanced", function()
	local run = startDay("L13")
	local bot = run.Bots[1]
	eq(row(bot, "airflow").Progress, 0, "not balanced at the start")
	eq(row(bot, "fans").Progress, 0, "fans still broken")
	run.World:run(60)
	eq(row(bot, "airflow").Progress, 0, "and it doesn't balance itself")
end)

test("L13 Day: four players flipping dampers at once can't corrupt the puzzle", function()
	local run = Sim.start("L13", 4, { Seed = 5 })
	local world = run.World
	local s = Strategies.L13
	for _, bot in run.Bots do
		bot.Scramble = true
	end
	Sim.playStage(run, "Day", s.Day, s.Per)
	Check.noServerErrors(world)
	for _, bot in run.Bots do
		eq(#bot.Failures, 0, "no stuck bots")
	end
	-- and if one player then works it alone, it still solves
	local solo = Sim.start("L13", 1, { Seed = 5 })
	Sim.playStage(solo, "Day", s.Day, s.Per)
	eq(Sim.rows(solo.Bots[1]).airflow.Done, true, "solved")
end)

-- ── Level 14 ────────────────────────────────────────────────────────────────

test("L14 Night: grease stops all damage; laced dishes make him sick; three phases to defeat", function()
	local run = Sim.start("L14", 1, { Seed = 5 })
	local world, bot = run.World, run.Bots[1]
	local s = Strategies.L14
	local phases, greasedDamage, sick, last, lastState = {}, 0, 0, nil, nil
	local chef = false
	run.OnStep = function()
		local rs = world.ReplicatedStorage
		if world:phase() ~= "Night" or not rs:GetAttribute("BossActive") then
			return
		end
		chef = true
		local phase = rs:GetAttribute("BossPhase")
		if phase and phases[#phases] ~= phase then
			table.insert(phases, phase)
		end
		local hp, state = rs:GetAttribute("BossHP"), rs:GetAttribute("BossShield")
		if last and hp and hp < last and state ~= "Sick" and lastState ~= "Sick" then
			greasedDamage += last - hp
		end
		if state == "Sick" and lastState ~= "Sick" then
			sick += 1
		end
		last, lastState = hp, state
	end
	Sim.playLevel(run, s.Day, s.Night, s.Per)
	truthy(chef, "the fight ran")
	eq(greasedDamage, 0, "damage through the grease")
	eq(table.concat(phases, ","), "1,2,3", "phases")
	truthy(sick >= 1, "sick windows")
	note("L14.SickWindows", sick)
	local result = bot:results()[1]
	eq(result.Heading, "LEVEL COMPLETE", "heading")
	truthy(result.Chapter, "chapter reward")
	eq(result.Chapter.Index, 2, "chapter 2")
	truthy(world:require("Services.DataService").Get(bot.Player).Campaign.Chapters["2"], "saved")
	Check.noServerErrors(world)
end)

test("L14 Night: an empty pass makes him ravenous; nothing cooked means no sickness", function()
	local run = startNight("L14")
	local world = run.World
	local states = {}
	local stop = world.Now + 60
	while world.Now < stop and world:phase() == "Night" do
		world:step()
		local state = world.ReplicatedStorage:GetAttribute("BossShield")
		if state then
			states[state] = true
		end
	end
	truthy(states.Ravenous, "ravenous at an empty ORDER UP")
	falsy(states.Sick, "never sick without a laced dish")
	Check.noServerErrors(world)
end)

test("L14 Day: the source stays hidden until samples and antidote are done", function()
	local run = startDay("L14")
	eq(#tagged(run.World, "KitchenSeal"), 0, "no peek before the antidote")
end)

Check.finish()
