-- Plays every level, day and night, on the real server code in the fake engine: a bot that can
-- only do what a player can (walk at speed along real paths, hold prompts, aim the beam, read the
-- HUD state) and the real day/night clock. Simulated gameplay, not Roblox: see docs/qa/QA_REPORT.md.
--   .tools/bin/lune run tests/Levels.spec.luau
--   QA_FILTER=L05 .tools/bin/lune run tests/Levels.spec.luau      (one level)
--   QA_SEEDS=10 ...                                              (seeds per level)

local process = require("@lune/process")
local Check = require("./harness/Check")
local Sim = require("./harness/Sim")
local Strategies = require("./harness/Strategies")
local CampaignConfig = require("../src/shared/Campaign/CampaignConfig")

Check.suite("Levels", "Simulated gameplay tested")
local test, eq, truthy, note = Check.test, Check.eq, Check.truthy, Check.note

local SEEDS = tonumber(process.env.QA_SEEDS) or 3
local filter = process.env.QA_FILTER
local PLAYER_SPEED = 16

local function required(stage: any): { any }
	local list = {}
	for _, objective in stage.Objectives do
		if not objective.Optional then
			table.insert(list, objective)
		end
	end
	return list
end

-- Watches for rows whose marker has nothing to point at, while the bot is focused on them.
local function watchMarkers(run: any)
	local watch = { Worst = 0, Row = nil, Since = {} }
	local previous = run.OnStep
	local nextCheck = 0
	run.OnStep = function(world: any)
		if previous then
			previous(world)
		end
		if world.Now < nextCheck then
			return
		end
		nextCheck = world.Now + 1
		local bot = run.Bots[1]
		local row = bot:focusRow()
		if row and row.Marker and (row.Marker.Tag or row.Marker.Shop) then
			local target = bot:markerTarget(row)
			if target then
				watch.Since[row.Id] = nil
			else
				watch.Since[row.Id] = watch.Since[row.Id] or world.Now
				local waited = world.Now - watch.Since[row.Id]
				if waited > watch.Worst then
					watch.Worst, watch.Row = waited, row.Id
				end
			end
		end
	end
	return watch
end

local function firstRequiredDone(run: any, stage: any, record: any)
	local previous = run.OnStep
	local goal = required(stage)
	run.OnStep = function(world: any)
		if previous then
			previous(world)
		end
		if record.At then
			return
		end
		local rows = Sim.rows(run.Bots[1])
		for _, objective in goal do
			local row = rows[objective.Id]
			if objective.Kind ~= nil or not row or not row.Done then
				if not (objective.Kind ~= nil) then
					return
				end
			end
		end
		record.At = world.Now
	end
end

for _, level in CampaignConfig.Levels do
	if not level.Implemented or (filter and not level.Id:find(filter)) then
		continue
	end
	local id = level.Id
	local s = Strategies[id] or {}

	-- ── nobody does anything, then each half alone, then the full level again ─────
	local run = Sim.start(id, 1, { Seed = 11 })
	local world, bot = run.World, run.Bots[1]
	local function campaign(): any
		return Sim.campaign(world, bot.Player)
	end

	Sim.idleStage(run, "Day")
	test(id .. " Day: an idle player makes no progress on required objectives", function()
		for _, objective in required(level.Day) do
			if objective.Kind == nil or objective.Kind == "Count" then
				eq(run.StageEnd.Day[1][objective.Id].Progress, 0, objective.Id)
			end
		end
		eq(campaign().DayCleared[id], nil, "day cleared by standing still")
	end)
	Sim.idleStage(run, "Night")
	Sim.toDawn(run)
	test(id .. " Night: the clock moves on with nobody doing anything; no credit for it", function()
		eq(campaign().Completed[id], nil, "completed")
		local results = bot:results()
		truthy(results[#results], "dawn showed a result")
		eq(results[#results].Cash, 0, "cash")
		eq(results[#results].XP, 0, "xp")
	end)

	local watchDay = watchMarkers(run)
	local dayDone = {}
	firstRequiredDone(run, level.Day, dayDone)
	local startedDay
	world:waitForPhase("Day", 200)
	startedDay = world.Now
	Sim.playStage(run, "Day", s.Day, s.Per)
	test(id .. " Day: a solo player clears it on foot before dusk", function()
		truthy(dayDone.At, "required objectives done")
		eq(#bot.Failures, 0, "bot: " .. (bot.Failures[1] and bot.Failures[1].Message or ""))
		eq(campaign().DayCleared[id], true, "recorded")
	end)
	if dayDone.At then
		note(id .. ".DaySeconds", string.format("%.0f of %d", dayDone.At - startedDay, level.Day.Duration))
	end
	test(id .. " Day: markers always have something to point at while an objective is in focus", function()
		truthy(
			watchDay.Worst <= 15,
			string.format("%s had no target for %.0f s", tostring(watchDay.Row), watchDay.Worst)
		)
	end)
	test(id .. " Day: no server errors", function()
		Check.noServerErrors(world)
	end)

	run.OnStep = nil
	Sim.idleStage(run, "Night")
	Sim.toDawn(run)
	test(id .. " Night: a cleared day plus an idle night doesn't complete the level", function()
		local onlyWaiting = true
		for _, objective in required(level.Night) do
			if objective.Kind ~= "Survive" and objective.Kind ~= "Avoid" then
				onlyWaiting = false
			end
		end
		if onlyWaiting then
			note(id .. ".IdleNight", if campaign().Completed[id] then "completes: survive-only night" else "fails")
		else
			eq(campaign().Completed[id], nil, "completed by idling")
		end
	end)

	-- retry: the day stays cleared, so only the night is needed (a hard night can take a few goes;
	-- the first go here skips the day's preparations, the later ones redo them as a player would)
	if not campaign().Completed[id] then
		world:waitForPhase("Day", 200)
		test(id .. " Night: the day's credit survives a failed night", function()
			eq(campaign().DayCleared[id], true, "day credit")
		end)
		Sim.idleStage(run, "Day")
		local watch = Sim.watchEnemies(run)
		local watchNight = watchMarkers(run)
		local cashBefore = bot.Player:GetAttribute("Cash")
		local xpBefore = bot.Player:GetAttribute("XP")
		local attempts = 0
		local last
		while attempts < 6 do
			attempts += 1
			Sim.playStage(run, "Night", s.Night, s.Per)
			Sim.toDawn(run)
			local results = bot:results()
			last = results[#results]
			if campaign().Completed[id] or attempts == 6 then
				break
			end
			Sim.playStage(run, "Day", s.Day, s.Per)
		end
		note(id .. ".RetryAttempts", attempts)
		test(id .. " Night: retrying completes the level", function()
			eq(last and last.Heading, "LEVEL COMPLETE", "heading: " .. tostring(last and last.Reason))
			truthy(campaign().Completed[id], "recorded")
			eq(#bot.Failures, 0, "bot: " .. (bot.Failures[1] and bot.Failures[1].Message or ""))
		end)
		test(id .. " Night: rewards are exactly what the level promises", function()
			if not campaign().Completed[id] then
				error("not completed")
			end
			eq(last.Cash, level.Rewards.Cash, "cash shown")
			eq(last.XP, level.Rewards.XP, "xp shown")
			local cash = bot.Player:GetAttribute("Cash")
			truthy(type(cashBefore) ~= "number" or cash - cashBefore >= level.Rewards.Cash, "cash paid")
			local data = world:require("Services.DataService").Get(bot.Player)
			truthy(data.XP ~= xpBefore or data.Level > 1, "xp paid")
		end)
		test(id .. " Night: no monster spawns on top of a player or outruns one", function()
			local closest, kind = math.huge, nil
			for _, spawned in watch.Spawns do
				-- (a Phantom appears where the player just unmasked a shopper with their own beam)
				if spawned.Type ~= "PhantomShopper" and spawned.Nearest < closest then
					closest, kind = spawned.Nearest, spawned.Type
				end
			end
			if closest < math.huge then
				note(id .. ".ClosestSpawn", string.format("%.0f studs (%s)", closest, tostring(kind)))
			end
			truthy(closest >= 8, string.format("%s spawned %.1f studs from a player", tostring(kind), closest))
			truthy(
				watch.TopSpeed < PLAYER_SPEED,
				string.format("%s walks at %.1f", tostring(watch.TopSpeedType), watch.TopSpeed)
			)
		end)
		test(id .. " Night: markers always have something to point at while an objective is in focus", function()
			-- (L07: the arrow points at cannons; while they recharge the job is burning the queen)
			truthy(
				watchNight.Worst <= (if id == "L07" then 60 else 20),
				string.format("%s had no target for %.0f s", tostring(watchNight.Row), watchNight.Worst)
			)
		end)
		test(id .. " Night: no server errors", function()
			Check.noServerErrors(world)
		end)
		run.OnStep = nil
	else
		Check.skip(
			id .. " Night: a retry completes the level without redoing the day",
			"the idle night already completed it"
		)
	end

	-- ── replay: a quarter of the reward, nothing first-clear pays twice ───────────
	local before = campaign()
	local stamp = before.Completed[id]
	local chapterStamp = before.Chapters[tostring(level.Chapter)]
	Sim.playLevel(run, s.Day, s.Night, s.Per)
	local results = bot:results()
	local last = results[#results]
	test(id .. " Night: a replay pays the reduced reward and keeps the first-clear record", function()
		if not stamp then
			error("level wasn't completed earlier")
		end
		if last.Heading == "LEVEL REPLAYED" then
			eq(last.Cash, math.floor(level.Rewards.Cash * CampaignConfig.ReplayFraction), "replay cash")
			eq(last.Chapter, nil, "chapter reward not repeated")
		else
			eq(last.Heading, "LEVEL FAILED", "heading")
			eq(last.Cash, 0, "failed replay pays nothing")
		end
		truthy(last.Heading == "LEVEL REPLAYED" or last.Heading == "LEVEL FAILED", "heading " .. tostring(last.Heading))
		eq(campaign().Completed[id], stamp, "first-clear time kept")
		eq(campaign().Chapters[tostring(level.Chapter)], chapterStamp, "chapter record kept")
	end)
	Check.noServerErrors(world)
	world:shutdown()

	-- ── several seeds in a fresh world: how reliably a solo player finishes ────────
	local clears = 0
	local failures = {}
	for seed = 1, SEEDS do
		local r = Sim.start(id, 1, { Seed = seed * 37 })
		Sim.playLevel(r, s.Day, s.Night, s.Per)
		local c = Sim.campaign(r.World, r.Bots[1].Player)
		if c and c.Completed[id] then
			clears += 1
		else
			local rr = r.Bots[1]:results()
			table.insert(failures, string.format("seed %d: %s", seed * 37, tostring(rr[#rr] and rr[#rr].Reason)))
		end
		if #r.World.Errors > 0 then
			table.insert(failures, string.format("seed %d: server error %s", seed * 37, r.World.Errors[1].Message))
		end
		r.World:shutdown()
	end
	note(id .. ".SoloClears", string.format("%d of %d seeds", clears, SEEDS))
	test(id .. " Night: a solo player can finish it, with no server errors on any seed", function()
		truthy(clears >= 1, table.concat(failures, "; "))
		for _, failure in failures do
			truthy(not failure:find("server error", 1, true), failure)
		end
	end)
end

Check.finish()
