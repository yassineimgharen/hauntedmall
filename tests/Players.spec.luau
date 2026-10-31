-- Player behaviour: slow and new players, explorers, wrong-order players, deaths, disconnects,
-- late joins, and teams of 2 to 8. Real server code, simulated players on foot; no teleporting.
--   .tools/bin/lune run tests/Players.spec.luau

local Check = require("./harness/Check")
local Bot = require("./harness/Bot")
local Sim = require("./harness/Sim")
local Strategies = require("./harness/Strategies")
local CampaignConfig = require("../src/shared/Campaign/CampaignConfig")

Check.suite("Players", "Simulated gameplay tested")
local test, eq, truthy, falsy, note = Check.test, Check.eq, Check.truthy, Check.falsy, Check.note

local function ids(): { string }
	local list = {}
	for _, level in CampaignConfig.Levels do
		if level.Implemented then
			table.insert(list, level.Id)
		end
	end
	return list
end

local function completed(run: any, id: string): number
	local count = 0
	for _, bot in run.Bots do
		local campaign = Sim.campaign(run.World, bot.Player)
		if campaign and campaign.Completed[id] then
			count += 1
		end
	end
	return count
end

local function failures(run: any): string
	local out = {}
	for _, bot in run.Bots do
		for _, failure in bot.Failures do
			out[failure.Message:sub(1, 90)] = true
		end
	end
	local list = {}
	for message in out do
		table.insert(list, message)
	end
	return table.concat(list, "; ")
end

-- ── how different players do, per level ─────────────────────────────────────

for _, profile in { "Newcomer", "Slow" } do
	local clears, missed, days, total = {}, {}, 0, 0
	for _, id in ids() do
		local s = Strategies[id] or {}
		local run = Sim.start(id, 1, { Seed = 21, Profile = Bot.Profiles[profile] })
		Sim.playLevel(run, s.Day, s.Night, s.Per)
		local campaign = Sim.campaign(run.World, run.Bots[1].Player)
		total += 1
		if campaign.DayCleared[id] then
			days += 1
		else
			table.insert(missed, id)
		end
		test(
			id .. " Day: a " .. profile:lower() .. " player's run has no server errors and nothing out of reach",
			function()
				Check.noServerErrors(run.World)
				eq(failures(run), "", "bot")
			end
		)
		if campaign.Completed[id] then
			table.insert(clears, id)
		end
		run.World:shutdown()
	end
	note(profile .. ".DaysCleared", string.format("%d of %d", days, total))
	note(profile .. ".DaysMissed", table.concat(missed, " "))
	note(profile .. ".LevelsCleared", table.concat(clears, " "))
	test(profile .. " player: clears the days of most levels", function()
		truthy(days >= total - 3, string.format("%d of %d days", days, total)) -- (see the DaysMissed note)
	end)
end

-- ── teams ───────────────────────────────────────────────────────────────────

for _, size in { 2, 3, 4, 6, 8 } do
	for _, id in ids() do
		local s = Strategies[id] or {}
		local run = Sim.start(id, size, { Seed = 50 + size })
		Sim.playLevel(run, s.Day, s.Night, s.Per)
		local done = completed(run, id)
		test(
			string.format(
				"%s Night: a team of %d plays it: no errors, nothing stuck, everyone gets the same result",
				id,
				size
			),
			function()
				Check.noServerErrors(run.World)
				eq(failures(run), "", "bot")
				truthy(done == 0 or done == size, string.format("%d of %d credited", done, size))
			end
		)
		test(string.format("%s Day: a team of %d clears the day", id, size), function()
			for i, bot in run.Bots do
				local campaign = Sim.campaign(run.World, bot.Player)
				eq(campaign.DayCleared[id], true, "player " .. i)
			end
		end)
		note(string.format("%s.Team%d", id, size), string.format("%d/%d completed", done, size))
		run.World:shutdown()
	end
end

-- ── wrong-order and exploring players ───────────────────────────────────────

for _, id in ids() do
	local level = CampaignConfig.ById[id]
	local s = Strategies[id] or {}
	-- goes for the LAST required objective's marker first, whatever the HUD says, then plays normally
	local run = Sim.start(id, 1, { Seed = 31 })
	local world, bot = run.World, run.Bots[1]
	local dayStrategies = table.clone(s.Day or {})
	local tried = false
	local reflex = dayStrategies.Reflex
	dayStrategies.Reflex = function(self: any): boolean
		if not tried then
			tried = true
			local objectives = level.Day.Objectives
			for i = #objectives, 1, -1 do
				local objective = objectives[i]
				if objective.Marker and objective.Marker.Tag and not objective.Optional then
					local target = world.CollectionService:GetTagged(objective.Marker.Tag)[1]
					if target then
						self:walkTo(target.Position, nil, 8)
						for _, prompt in self:promptsFor(target) do
							if self:usable(prompt) then
								self:hold(prompt)
							end
						end
					end
					break
				end
			end
			return true
		end
		return if reflex then reflex(self) else false
	end
	Sim.playStage(run, "Day", dayStrategies, s.Per)
	test(id .. " Day: doing things in the wrong order doesn't break the day", function()
		Check.noServerErrors(world)
		eq(Sim.campaign(world, bot.Player).DayCleared[id], true, "the day can still be cleared")
	end)
	run.World:shutdown()
end

-- ── deaths and disconnects ──────────────────────────────────────────────────

local function kill(bot: any)
	local character = bot.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
end

for _, id in { "L02", "L06", "L09", "L10", "L12", "L14" } do
	local s = Strategies[id] or {}
	test(id .. " Night: dying a few times mid-night neither corrupts anything nor ends the level", function()
		local run = Sim.start(id, 1, { Seed = 41 })
		Sim.playStage(run, "Day", s.Day, s.Per)
		local world = run.World
		local nextKill = 0
		local deaths = 0
		local stageStart
		run.OnStep = function()
			stageStart = stageStart or world.Now
			if world:phase() == "Night" and world.Now - stageStart > 30 and world.Now >= nextKill and deaths < 3 then
				nextKill = world.Now + 45
				deaths += 1
				kill(run.Bots[1])
			end
		end
		Sim.playStage(run, "Night", s.Night, s.Per)
		Sim.toDawn(run)
		Check.noServerErrors(world)
		truthy(deaths >= 1, "killed") -- (some nights end early once everyone's escaped)
		truthy(run.Bots[1]:results()[1], "dawn result shown")
		truthy(run.Bots[1]:root(), "alive again")
		truthy((run.Bots[1].Player:GetAttribute("Carrying") or "None") == "None", "carrying nothing into the day")
		note(id .. ".AfterThreeDeaths", run.Bots[1]:results()[1].Heading)
	end)
end

for _, id in { "L03", "L04", "L06", "L08", "L09", "L11", "L13", "L14" } do
	local s = Strategies[id] or {}
	test(id .. " Night: a teammate disconnecting mid-stage doesn't block the others or the clock", function()
		local run = Sim.start(id, 3, { Seed = 42 })
		local world = run.World
		local gone = run.Bots[3]
		local nightStart
		run.OnStep = function()
			if world:phase() == "Night" then
				nightStart = nightStart or world.Now
				if world.Now - nightStart > 40 and gone.Player.Parent then
					world:removePlayer(gone.Player)
				end
			end
		end
		Sim.playLevel(run, s.Day, s.Night, s.Per)
		Check.noServerErrors(world)
		eq(gone.Player.Parent, nil, "really left")
		truthy(run.Bots[1]:results()[1], "the others got a result")
		local c1 = Sim.campaign(world, run.Bots[1].Player)
		local c2 = Sim.campaign(world, run.Bots[2].Player)
		eq(c1.Completed[id] ~= nil, c2.Completed[id] ~= nil, "same result for those who stayed")
		note(id .. ".AfterDisconnect", run.Bots[1]:results()[1].Heading)
	end)
end

test("L14 Night: leaving during the boss, with a dish in hand, doesn't jam the fight", function()
	local s = Strategies.L14
	local run = Sim.start("L14", 2, { Seed = 43 })
	local world = run.World
	local gone = run.Bots[2]
	local hpAtLeave, lowest, sickAfter, wasSick = nil, math.huge, 0, false
	run.OnStep = function()
		if world:phase() ~= "Night" then
			return
		end
		local rs = world.ReplicatedStorage
		if gone.Player.Parent and gone.Player:GetAttribute("Carrying") then
			world:removePlayer(gone.Player)
			hpAtLeave = rs:GetAttribute("BossHP")
		end
		if hpAtLeave then
			lowest = math.min(lowest, rs:GetAttribute("BossHP") or lowest)
			local sick = rs:GetAttribute("BossShield") == "Sick"
			if sick and not wasSick then
				sickAfter += 1
			end
			wasSick = sick
		end
	end
	Sim.playLevel(run, s.Day, s.Night, s.Per)
	Check.noServerErrors(world)
	eq(gone.Player.Parent, nil, "left carrying a dish")
	-- the fight goes on: the one left can still serve, sicken and burn him
	truthy(sickAfter >= 1, "another dish landed after the leave")
	truthy(hpAtLeave and lowest < hpAtLeave, "he still takes damage")
	note("L14.BossLeaver", run.Bots[1]:results()[1].Heading)
end)

for _, case in { { "L07", "the queen" }, { "L14", "the chef" } } do
	local id, boss = case[1], case[2]
	test(
		id
			.. " Night: when players leave, "
			.. boss
			.. "'s health follows, keeps its fraction, and comes back with them",
		function()
			local s = Strategies[id]
			local run = Sim.start(id, 3, { Seed = 44 })
			local world = run.World
			local rs = world.ReplicatedStorage
			Sim.playStage(run, "Day", s.Day, s.Per)
			world:waitForPhase("Night", 60)
			world:runUntil(function()
				return rs:GetAttribute("BossActive") == true
			end, 60)
			local logic = world:require(if id == "L07" then "Levels.QueenLogic" else "Levels.ChefLogic")
			eq(rs:GetAttribute("BossMaxHP"), logic.maxHp(3), "starts for three")
			world:removePlayer(run.Bots[3].Player)
			world:removePlayer(run.Bots[2].Player)
			world:run(5)
			eq(rs:GetAttribute("BossMaxHP"), logic.maxHp(3), "a quick drop-out changes nothing yet")
			world:run(8)
			eq(rs:GetAttribute("BossMaxHP"), logic.maxHp(1), "scaled to the one left")
			eq(rs:GetAttribute("BossHP"), logic.maxHp(1), "still full: nothing was given away")
			world:addPlayer("Back", 7001)
			world:addPlayer("Back2", 7002)
			world:run(2)
			eq(rs:GetAttribute("BossMaxHP"), logic.maxHp(3), "rejoining brings it straight back")
			eq(rs:GetAttribute("BossHP"), logic.maxHp(3), "no exploit: full again at full team")
			Check.noServerErrors(world)
		end
	)
end

test("L07 Night: leaving during the boss lowers nothing into a broken state", function()
	local s = Strategies.L07
	local run = Sim.start("L07", 2, { Seed = 43 })
	local world = run.World
	local gone = run.Bots[2]
	run.OnStep = function()
		if world:phase() == "Night" and gone.Player.Parent and world.ReplicatedStorage:GetAttribute("BossActive") then
			world:removePlayer(gone.Player)
		end
	end
	Sim.playLevel(run, s.Day, s.Night, s.Per)
	Check.noServerErrors(world)
	eq(run.Bots[1]:results()[1].Heading, "LEVEL COMPLETE", "heading")
end)

test("everyone leaving at night and someone joining later still gets a working server", function()
	local run = Sim.start("L02", 1, { Seed = 44 })
	local world = run.World
	world:waitForPhase("Night", 400)
	world:run(5)
	world:removePlayer(run.Bots[1].Player)
	world:run(30)
	local later = world:addPlayer("Later", 777)
	world:run(30)
	Check.noServerErrors(world)
	truthy(world:require("Services.DataService").Get(later), "loaded")
end)

test("a player who joins at night is told so at dawn, with no credit and no crash", function()
	local s = Strategies.L02 or {}
	local run = Sim.start("L02", 1, { Seed = 45 })
	local world = run.World
	Sim.playStage(run, "Day", s.Day, s.Per)
	world:waitForPhase("Night", 60)
	world:run(20)
	local late = Bot.new(world, world:addPlayer("Late", 888), nil)
	Sim.playStage({ World = world, Bots = { run.Bots[1], late }, Level = "L02" }, "Night", s.Night, s.Per)
	Sim.toDawn(run)
	Check.noServerErrors(world)
	local results = late:results()
	truthy(results[1], "a result")
	eq(results[1].Outcome, "LateJoin", "outcome")
	eq(results[1].Cash, 0, "no cash")
	falsy(Sim.campaign(world, late.Player).Completed.L02, "no credit")
end)

test("rejoining mid-level keeps cleared days and completed levels (mock DataStore)", function()
	local backing = {}
	local s = Strategies.L01 or {}
	local run = Sim.start("L01", 1, { Seed = 46, DataStore = backing, UserIds = { 901 } })
	Sim.playStage(run, "Day", s.Day, s.Per)
	local world = run.World
	eq(Sim.campaign(world, run.Bots[1].Player).DayCleared.L01, true, "cleared")
	world:removePlayer(run.Bots[1].Player)
	world:run(1)
	local again = world:addPlayer("Back", 901)
	world:run(1)
	eq(Sim.campaign(world, again).DayCleared.L01, true, "still cleared after rejoining")
	local bot = Bot.new(world, again, nil)
	Sim.playStage({ World = world, Bots = { bot }, Level = "L01" }, "Night", s.Night, s.Per)
	world:waitForPhase("Dawn", 60)
	world:run(4)
	Check.noServerErrors(world)
	eq(bot:results()[1].Outcome, "FirstClear", "rejoined before the night: the level counts")
end)

test("campaign gating on a live-style server: a new player gets L01; L02 opens only after it", function()
	local run = Sim.start("L01", 1, { Seed = 47, Attributes = {} })
	local world, bot = run.World, run.Bots[1]
	world.Workspace:SetAttribute("MissionTest_Level", nil)
	Sim.playLevel(run, (Strategies.L01 or {}).Day, (Strategies.L01 or {}).Night, nil)
	local campaign = Sim.campaign(world, bot.Player)
	truthy(campaign.Completed.L01, "first level cleared")
	world:waitForPhase("Day", 100)
	world:run(1)
	eq(world.ReplicatedStorage:GetAttribute("LevelId"), "L02", "the campaign moves on by itself")
end)

test("a guest on someone else's locked level plays along but earns no credit for it", function()
	local run = Sim.start("L09", 1, { Seed = 48, Attributes = {} })
	local world, bot = run.World, run.Bots[1]
	local campaign = Sim.campaign(world, bot.Player)
	eq(campaign.Completed.L08, nil, "the previous level isn't done")
	Sim.idleStage(run, "Day")
	Sim.idleStage(run, "Night")
	Sim.toDawn(run)
	Check.noServerErrors(world)
	eq(Sim.campaign(world, bot.Player).Completed.L09, nil, "no credit")
end)

Check.finish()
