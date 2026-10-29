-- Unit tests for Chapter 2 (the Haunted Food Court, Levels 8–14), run outside Roblox:
--   .tools/bin/lune run tests/Chapter2.spec.luau     (also part of scripts/check.sh)
-- Per level: the mission completes with the right events (and not without them), the
-- level module records every event its objectives need, and its pure rules are fair for
-- solo and team play. Plus monster fairness, progression, rewards, achievements and saves.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local AchievementConfig = require("../src/shared/Campaign/AchievementConfig")
local CampaignConfig = require("../src/shared/Campaign/CampaignConfig")
local Logic = require("../src/shared/Campaign/CampaignLogic")
local EnemyConfig = require("../src/shared/Config/EnemyConfig")
local MonsterTuning = require("../src/shared/Config/MonsterTuning")
local Chef = require("../src/server/Levels/ChefLogic")
local Rules = require("../src/server/Levels/FoodCourtRules")

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ✓ " .. name)
	else
		failed += 1
		print("  ✗ " .. name .. "\n      " .. tostring(err))
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
	end
end

-- Plays a stage: fires each {event, count, key?} and reports whether `key` cleared it.
local function play(stage: any, events: { { any } }, key: any?): boolean
	local tracker = Logic.newTracker(stage.Objectives)
	for _, e in events do
		for _ = 1, e[2] do
			Logic.record(tracker, e[3] or key or 1, e[1])
		end
	end
	return Logic.requiredComplete(tracker, key or 1, true)
end

-- The level module must record every event its objectives count on.
local function recordsAll(level: any, file: string)
	local source = fs.readFile(file)
	for _, stage in { level.Day, level.Night } do
		for _, objective in stage.Objectives do
			if objective.Event and objective.Event ~= "Downed" then
				assert(source:find('"' .. objective.Event .. '"', 1, true), objective.Event .. " is never recorded in " .. file)
			end
		end
	end
end

local function chapter2(): { any }
	local list = {}
	for i = 8, 14 do
		local level = CampaignConfig.Levels[i]
		if level.Implemented then
			table.insert(list, level)
		end
	end
	return list
end

print("Chapter 2: content and progression")

test("Chapter 2 is the Haunted Food Court with the Gorging Chef", function()
	eq(CampaignConfig.Chapters[2].Name, "The Haunted Food Court", "name")
	eq(CampaignConfig.Chapters[2].Boss, "The Gorging Chef", "boss")
	for _, level in chapter2() do
		eq(level.Chapter, 2, level.Id .. " chapter")
		assert(level.Night.Rules.SpawnTag == "FoodCourtSpawn" or level.Night.Rules.NoWaves, level.Id .. " spawns in the food court")
	end
end)

test("Level 8 unlocks only after Level 7; Chapter 2 levels unlock one by one", function()
	local completed = {}
	for i = 1, 6 do
		completed[string.format("L%02d", i)] = 1
	end
	assert(not Logic.isUnlocked(CampaignConfig.Levels, completed, "L08"), "L08 is locked before L07")
	completed.L07 = 1
	assert(Logic.isUnlocked(CampaignConfig.Levels, completed, "L08"), "L08 opens after L07")
	local levels = chapter2()
	for i, level in levels do
		local nextLevel = levels[i + 1]
		if nextLevel then
			assert(not Logic.isUnlocked(CampaignConfig.Levels, completed, nextLevel.Id), nextLevel.Id .. " locked")
		end
		completed[level.Id] = 1
	end
end)

test("every Chapter 2 level pays more than Chapter 1's levels and has full day and night", function()
	for _, level in chapter2() do
		assert(level.Rewards.Cash >= 800 and level.Rewards.XP >= 900, level.Id .. " rewards")
		assert(level.Day.Duration >= 180 and level.Night.Duration >= 180, level.Id .. " durations")
		assert(level.Night.Rules.Preset, level.Id .. " has its own lighting mood")
	end
end)

test("chapter monsters never outrun a player", function()
	for _, id in { "PossessedCart", "ParcelMimic", "ParcelMite", "FrostWraith", "SporeBloater", "Meatball" } do
		local config = EnemyConfig.Types[id]
		assert(config, id .. " is configured")
		assert(config.Caps.WalkSpeed < MonsterTuning.PlayerSpeed, id .. " cap speed")
		for night = 1, 20 do
			assert(EnemyConfig.Scaled(id, night).WalkSpeed < MonsterTuning.PlayerSpeed, id .. " night " .. night)
		end
	end
end)

print("Level 8 · Grand Reopening / Kitchen Nightmare")

local L08 = CampaignConfig.ById.L08
local R8 = Rules.L08

test("L08 day: 8 slime puddles and 4 restaurants clear it, fewer don't", function()
	assert(L08.Implemented, "implemented")
	assert(play(L08.Day, { { "SlimeScrubbed", 8 }, { "RestaurantReopened", 4 } }), "cleared")
	assert(not play(L08.Day, { { "SlimeScrubbed", 7 }, { "RestaurantReopened", 4 } }), "7 puddles")
	assert(not play(L08.Day, { { "SlimeScrubbed", 8 }, { "RestaurantReopened", 3 } }), "3 restaurants")
	assert(R8.SlimePuddles >= 8 + 2, "spare puddles to find")
end)

test("L08 day: the team shares puddle progress; the bonus counts your own", function()
	local tracker = Logic.newTracker(L08.Day.Objectives)
	for _ = 1, 4 do
		Logic.record(tracker, "A", "SlimeScrubbed")
		Logic.record(tracker, "B", "SlimeScrubbed")
	end
	for _ = 1, 4 do
		Logic.record(tracker, "B", "RestaurantReopened")
	end
	assert(Logic.requiredComplete(tracker, "A", true), "A cleared with B's help")
	local optional = Logic.optionalDone(tracker, "A")
	assert(table.find(optional, "myscrub"), "A scrubbed 4 personally")
end)

test("L08 night: 5 exorcisms and surviving clear it; helping earns the bonus", function()
	assert(play(L08.Night, { { "ApplianceExorcised", 5 } }), "cleared")
	assert(not play(L08.Night, { { "ApplianceExorcised", 4 }, { "ExorcismHelped", 9 } }), "help alone isn't enough")
	local tracker = Logic.newTracker(L08.Night.Objectives)
	Logic.record(tracker, "A", "ExorcismHelped")
	Logic.record(tracker, "A", "ExorcismHelped")
	assert(table.find(Logic.optionalDone(tracker, "A"), "myexorcisms"), "bonus")
end)

test("L08 balance: possessions and carts scale with players, gently solo", function()
	eq(Rules.activePossessions(1), 3, "solo appliances")
	eq(Rules.activePossessions(4), 6, "4 players")
	eq(Rules.activePossessions(8), 6, "cap")
	eq(Rules.cartCap(1), 1, "solo carts")
	assert(Rules.cartCap(4) <= 3 and Rules.cartCap(8) == 3, "cart cap")
	assert(Rules.maxVolleysPerMinute() <= 40, "volley rate is capped however many are possessed")
end)

test("L08 fairness: exorcising fits one battery; knife lanes and cart charges are dodgeable", function()
	assert(R8.ExorciseSeconds <= EnemyConfig.Flashlight.BatterySeconds, "one full battery exorcises an appliance")
	local _, done = Rules.exorcise(0, R8.ExorciseSeconds - 0.1)
	assert(not done, "not quite")
	local progress, finished = Rules.exorcise(R8.ExorciseSeconds - 0.1, 0.5)
	assert(finished and progress == R8.ExorciseSeconds, "done and clamped")
	local stepOut = (R8.VolleyWidth / 2 + 1) / MonsterTuning.PlayerSpeed
	assert(stepOut < R8.VolleyWarn * 0.5, "knife lane: half the warning is enough to step out")
	local cart = MonsterTuning.Cart
	assert((cart.HitRadius + 1) / MonsterTuning.PlayerSpeed < cart.Aim * 0.5, "cart lane: easy sidestep")
	assert(cart.Dizzy >= 1.5, "carts are punishable after charging")
end)

test("L08 pacing: enough possessions to finish, never spawned next to a player", function()
	local possible = R8.FirstPossessions + math.floor((L08.Night.Duration - 10) / R8.PossessEvery)
	assert(math.min(possible, R8.MaxPossessions) >= R8.ExorciseTarget + 3, "spare possessions")
	local candidates = { { 0, 0 }, { 40, 0 }, { 80, 0 } }
	eq(Rules.pickPossession(candidates, { { 0, 0 } }), 2, "nearest one that's far enough")
	eq(Rules.pickPossession(candidates, { { 0, 0 }, { 40, 5 }, { 80, -5 } }), nil, "nothing far enough")
end)

test("L08 module records every event its objectives need", function()
	recordsAll(L08, "src/server/Levels/GrandReopening.luau")
end)

print("Level 9 · Live Wires / Grease Fire")

local L09 = CampaignConfig.ById.L09
local R9 = Rules.L09

test("L09 cables: team progress caps at 5; the personal bonus counts your own", function()
	local tracker = Logic.newTracker(L09.Day.Objectives)
	for _ = 1, 3 do
		Logic.record(tracker, "A", "CableSpliced")
	end
	Logic.record(tracker, "B", "CableSpliced")
	eq(Logic.value(tracker, "A", L09.Day.Objectives[1]), 4, "team at 4")
	Logic.record(tracker, "B", "CableSpliced")
	Logic.record(tracker, "B", "CableSpliced")
	eq(Logic.value(tracker, "A", L09.Day.Objectives[1]), 5, "capped at 5 (6 spliced)")
	assert(table.find(Logic.optionalDone(tracker, "A"), "mysplice"), "A spliced 2+")
	eq(R9.CableTarget, L09.Day.Objectives[1].Target, "the module unlocks the breakers at the objective's target")
	assert(R9.Cables > R9.CableTarget, "a spare cable")
end)

test("L09 cables: the safe window fits a splice with time to react; live shocks", function()
	assert(R9.Safe >= R9.SpliceSeconds + 1, "a second of slack")
	local cycle = R9.Live + R9.Safe
	local live, left = Rules.cablePhase(0.5, 0)
	eq(live, "Live", "starts live")
	assert(math.abs(left - (R9.Live - 0.5)) < 1e-9, "time left")
	eq((Rules.cablePhase(R9.Live + 0.1, 0)), "Safe", "then safe")
	eq((Rules.cablePhase(cycle + 0.1, 0)), "Live", "and repeats")
	assert(R9.ShockDamage <= 15, "shocks sting, not kill")
end)

test("L09 breakers: second breaker in time completes; late resets; re-pulling restarts", function()
	local w = R9.Window
	local s = { Held = nil, Since = 0 }
	eq(Rules.pullBreaker(s, "A", 0, w), "Armed", "first breaker holds")
	eq(s.Held, "A", "A held")
	eq(Rules.pullBreaker(s, "B", w - 0.1, w), "Done", "second just in time")
	eq(s.Held, nil, "nothing held after")

	local late = { Held = nil, Since = 0 }
	Rules.pullBreaker(late, "A", 0, w)
	assert(not Rules.breakerExpired(late, w - 0.1, w), "still running")
	eq(Rules.breakerLeft(late, w - 2, w), 2, "seconds left")
	assert(Rules.breakerExpired(late, w + 0.1, w), "expires after the window")
	eq(late.Held, nil, "released")
	eq(Rules.pullBreaker(late, "B", w + 0.5, w), "Armed", "too late: B just starts a new attempt")
	eq(Rules.pullBreaker(late, "B", w + 3, w), "Restarted", "pulling the held one again restarts its timer")
	eq(Rules.breakerLeft(late, w + 3, w), w, "full time again")
	eq(Rules.pullBreaker(late, "A", w + 3 + w - 0.5, w), "Done", "then A in time")

	local stale = { Held = nil, Since = 0 }
	Rules.pullBreaker(stale, "A", 0, w)
	eq(Rules.pullBreaker(stale, "B", w + 1, w), "Armed", "a held breaker that ran out never completes it")
end)

test("L09 breakers: solo gets a longer window, and it's a sprint, not a coin flip", function()
	eq(Rules.leverWindow(1), R9.SoloWindow, "solo")
	eq(Rules.leverWindow(0), R9.SoloWindow, "empty server counts as solo")
	eq(Rules.leverWindow(3), R9.Window, "team")
	local run = R9.LeverDistance / MonsterTuning.PlayerSpeed
	local solo = run + R9.LeverSeconds + 1.5 -- turning round and reacting
	assert(solo <= R9.SoloWindow - 2, string.format("solo needs %.1fs of %ds", solo, R9.SoloWindow))
	assert(run > R9.SoloWindow * 0.4, "still a real sprint")
	assert(R9.Window >= R9.LeverSeconds + 3, "a teammate waiting at the other breaker has time")
end)

test("L09 day: the switchboard completes the day; missing it doesn't", function()
	assert(play(L09.Day, { { "CableSpliced", 5 }, { "SwitchboardReset", 1 } }), "cleared")
	assert(not play(L09.Day, { { "CableSpliced", 4 }, { "SwitchboardReset", 1 } }), "4 cables")
	assert(not play(L09.Day, { { "CableSpliced", 6 } }), "no switchboard: the day isn't cleared (the reported case)")
	local source = fs.readFile("src/server/Levels/KitchenFire.luau")
	assert(source:find('if result == "Done" then', 1, true), "a completed pull is handled")
	assert(source:find('MissionEvents.record(player, "SwitchboardReset")', 1, true), "and recorded")
	assert(source:find('"Done", if on then true else nil', 1, true), "a held breaker hands the guide arrow to the other")
end)

test("L09 fire grid: kitchen and hall, aligned to the kitchen wall; restaurants stay safe", function()
	eq(R9.OriginX + R9.WallCol * R9.Cell, -184, "the wall is a column edge")
	eq(R9.OriginZ, -48, "south edge = restaurant fronts")
	eq(R9.OriginZ + R9.Rows * R9.Cell, 48, "north edge")
	assert(R9.OriginX + R9.Cols * R9.Cell <= -99, "doesn't reach past the hall's east wall")
	eq((Rules.cellAt(-141, -57)), nil, "a south restaurant is outside the grid")
	local c, r = Rules.cellAt(-247.9, -47.9)
	eq(c, 1, "first column")
	eq(r, 1, "first row")
	local x, z = Rules.cellCenter(1, 1)
	eq(x, -244, "centre x")
	eq(z, -44, "centre z")
end)

test("L09 fire: crosses the kitchen wall only at the doorways", function()
	local w = R9.WallCol
	for _, row in R9.DoorRows do
		local doorZ = R9.OriginZ + (row - 0.5) * R9.Cell
		local inDoor = (doorZ >= -31 and doorZ <= -19) or (doorZ >= -7 and doorZ <= 7) or (doorZ >= 19 and doorZ <= 31)
		assert(inDoor, "door row " .. row .. " (z " .. doorZ .. ") overlaps a doorway")
		assert(Rules.canSpread(w, row, w + 1, row), "through the door, row " .. row)
	end
	assert(not Rules.canSpread(w, 1, w + 1, 1), "solid wall at row 1")
	assert(not Rules.canSpread(w + 1, 12, w, 12), "solid wall the other way")
	assert(Rules.canSpread(w, 1, w, 2), "along the wall is fine")
	assert(Rules.canSpread(3, 5, 4, 5), "open floor")
	local grid = Rules.fireGrid()
	Rules.ignite(grid, w, 1, 0)
	for _ = 1, 50 do
		Rules.spread(grid, 0, 1, function()
			return 0.01 -- always tries the +x neighbour (through the wall)
		end)
	end
	eq(grid.Smolder[Rules.cellKey(grid, w + 1, 1)], nil, "never through the solid wall")
end)

test("L09 fire: a cell smoulders (harmless warning) before it bursts into flame", function()
	local grid = Rules.fireGrid()
	assert(Rules.ignite(grid, 5, 5, 0), "start fire")
	local i = 0
	local lit = Rules.spread(grid, 0, 1, function()
		i += 1
		return if i % 2 == 1 then 0 else 0.3 -- chance passes, then direction -x
	end)
	eq(#lit, 1, "one neighbour caught")
	local key = lit[1]
	assert(grid.Smolder[key] and not grid.Burning[key], "smouldering first: no damage yet")
	eq(#Rules.advance(grid, R9.SmolderSeconds - 0.1), 0, "not yet")
	eq(#Rules.advance(grid, R9.SmolderSeconds + 0.1), 1, "then flames")
	assert(grid.Burning[key] and not grid.Smolder[key], "burning now")
	eq(grid.Count, 2, "count includes both")
	assert(R9.SmolderSeconds >= 2, "long enough to step away")
end)

test("L09 fire: respects protected and wet cells and the cap", function()
	local grid = Rules.fireGrid()
	assert(Rules.ignite(grid, 5, 5, 0), "lights")
	assert(not Rules.ignite(grid, 5, 5, 0), "already burning")
	grid.Protected[Rules.cellKey(grid, 6, 5)] = true
	assert(not Rules.ignite(grid, 6, 5, 0), "protected")
	assert(not Rules.smolder(grid, 6, 5, 0), "protected from smoulder too")
	eq(#Rules.spread(grid, 0, 0, function()
		return 0
	end), 0, "chance 0: no spread")
	local full = Rules.fireGrid()
	for c = 1, R9.Cols do
		for r = 1, R9.Rows do
			Rules.smolder(full, c, r, 0)
		end
	end
	eq(full.Count, R9.MaxBurning, "never above the cap")
end)

test("L09 extinguisher: a spray puts out a cross (burning or smouldering) and leaves it wet", function()
	local grid = Rules.fireGrid()
	Rules.ignite(grid, 5, 5, 0)
	Rules.ignite(grid, 6, 5, 0)
	Rules.smolder(grid, 5, 6, 0)
	Rules.ignite(grid, 7, 5, 0) -- outside the cross
	local out = Rules.extinguish(grid, 5, 5, 10)
	eq(#out, 3, "two burning and one smouldering put out")
	eq(grid.Count, 1, "the far one keeps burning")
	assert(grid.Burning[Rules.cellKey(grid, 7, 5)], "out of reach")
	assert(not Rules.ignite(grid, 4, 5, 10 + R9.WetSeconds - 1), "foam: neighbour still wet")
	assert(Rules.ignite(grid, 4, 5, 10 + R9.WetSeconds + 1), "dries out")
	assert(R9.Charges * 5 >= 30, "one extinguisher can put out a lot of fire")
end)

test("L09 gas valves: each slows the fire, all three stop it and finish the objective", function()
	local last = math.huge
	for closed = 0, R9.Valves do
		local chance = Rules.spreadChance(closed)
		assert(chance < last, "slower with each valve")
		last = chance
	end
	eq(Rules.spreadChance(R9.Valves), 0, "stopped")
	eq(Rules.spreadChance(R9.Valves + 2), 0, "clamped")
	local tracker = Logic.newTracker(L09.Night.Objectives)
	Logic.record(tracker, "A", "GasValveClosed")
	Logic.record(tracker, "B", "GasValveClosed")
	assert(not Logic.isDone(tracker, "A", L09.Night.Objectives[1]), "2 of 3")
	Logic.record(tracker, "A", "GasValveClosed")
	assert(Logic.isDone(tracker, "B", L09.Night.Objectives[1]), "3 of 3 for the whole team")
end)

test("L09 emergency exit: detection on the landing only", function()
	assert(Rules.onDockLanding(0, 3, 0), "centre of the landing")
	assert(Rules.onDockLanding(8, 3, -7), "corner")
	assert(not Rules.onDockLanding(0, 3, 9), "still inside the dock (north of the door)")
	assert(not Rules.onDockLanding(12, 3, 0), "beside the landing")
	assert(not Rules.onDockLanding(0, 20, 0), "above it")
	local source = fs.readFile("src/server/Levels/KitchenFire.luau")
	assert(source:find("if valvesClosed < R.Valves then", 1, true), "escape counts only once the exit is open")
end)

test("L09 night: everyone escaping brings dawn early", function()
	assert(not Rules.allEscaped({}, {}), "empty server")
	assert(not Rules.allEscaped({ "A", "B" }, { A = true }), "B still inside")
	assert(Rules.allEscaped({ "A", "B" }, { A = true, B = true }), "all out")
	assert(R9.AllOutDawn <= 15, "short wait")
end)

test("L09 fairness: fire hurts but can be crossed", function()
	local secondsToDown = 100 / R9.FireDamage * EnemyConfig.Combat.PlayerHitGrace
	assert(secondsToDown >= 8, string.format("%.1fs standing in fire before going down", secondsToDown))
	assert(R9.MaxBurning < R9.Cols * R9.Rows / 3, "most of the floor never burns at once")
end)

test("L09 night: gas off is shared, but everyone must escape themselves", function()
	local tracker = Logic.newTracker(L09.Night.Objectives)
	for _ = 1, 3 do
		Logic.record(tracker, "A", "GasValveClosed")
	end
	Logic.record(tracker, "A", "FireEscaped")
	assert(Logic.requiredComplete(tracker, "A", true), "A escaped")
	assert(not Logic.requiredComplete(tracker, "B", true), "B is still inside")
	Logic.record(tracker, "B", "FireExtinguished", 12)
	assert(table.find(Logic.optionalDone(tracker, "B"), "fires"), "12 fires out in one go counts")
end)

test("L09 completion: needs the day cleared; then Level 10 unlocks; rewards pay once", function()
	local function outcome(dayCleared: boolean, already: boolean)
		return Logic.outcome({
			Eligible = true,
			InRoster = true,
			DayCleared = dayCleared,
			NightSuccess = true,
			AlreadyCompleted = already,
		})
	end
	eq(outcome(false, false), "DayMissing", "night done but switchboard missed: no level credit")
	eq(outcome(true, false), "FirstClear", "day and night done")
	local completed = {}
	for i = 1, 8 do
		completed[string.format("L%02d", i)] = 1
	end
	assert(not Logic.isUnlocked(CampaignConfig.Levels, completed, "L10"), "L10 locked before L09")
	eq(Logic.nextLevel(CampaignConfig.Levels, completed).Id, "L09", "L09 stays next after a DayMissing night")
	completed.L09 = 1
	assert(Logic.isUnlocked(CampaignConfig.Levels, completed, "L10"), "L10 unlocks")
	eq(outcome(true, true), "Replay", "replaying is a replay")
	local first = Logic.reward(L09.Rewards, true, CampaignConfig.ReplayFraction)
	local replay = Logic.reward(L09.Rewards, false, CampaignConfig.ReplayFraction)
	eq(first.Cash, L09.Rewards.Cash, "full first time")
	assert(replay.Cash < first.Cash, "reduced afterwards")
	eq(L09.ChapterReward, nil, "no chapter reward on Level 9")
end)

test("L09 module records every event its objectives need", function()
	recordsAll(L09, "src/server/Levels/KitchenFire.luau")
end)

print("Level 10 · Special Delivery / Return to Sender")

local L10 = CampaignConfig.ById.L10
local R10 = Rules.L10

test("L10 day: 8 correct calls and the logbook clear it; the perfect bonus needs real work", function()
	assert(play(L10.Day, { { "ParcelSorted", 8 }, { "DriverLogFound", 1 } }), "cleared")
	assert(not play(L10.Day, { { "ParcelSorted", 7 }, { "DriverLogFound", 1 } }), "7 calls")
	local idle = Logic.newTracker(L10.Day.Objectives)
	assert(not table.find(Logic.optionalDone(idle, "A"), "nowrong"), "doing nothing doesn't earn 'no wrong calls'")
	local tracker = Logic.newTracker(L10.Day.Objectives)
	Logic.record(tracker, nil, "PerfectSort")
	assert(table.find(Logic.optionalDone(tracker, "B"), "nowrong"), "a perfect sort counts for the whole team")
	local source = fs.readFile("src/server/Levels/Deliveries.luau")
	assert(source:find("sorted == #R.Parcels and wrongCalls == 0", 1, true), "only all 10 with no mistakes")
end)

test("L10 parcels: 4 infected, 2 of them only visible by UV; 8 correct calls possible", function()
	local infected, hidden = 0, 0
	for _, parcel in R10.Parcels do
		if parcel.Infected then
			infected += 1
			if Rules.isTrusted(parcel.Sender) then
				hidden += 1 -- the label looks legitimate: only the flashlight catches it
			end
		else
			assert(Rules.isTrusted(parcel.Sender), "clean parcels come from trusted suppliers: " .. parcel.Sender)
		end
		assert(Rules.isCorrectCall(parcel, parcel.Infected), "quarantine infected, deliver clean")
		assert(not Rules.isCorrectCall(parcel, not parcel.Infected), "the other call is wrong")
	end
	eq(#R10.Parcels, 10, "parcels")
	eq(infected, 4, "infected")
	assert(hidden >= 2, "some infected parcels need the flashlight")
	assert(#R10.Parcels - R10.SortTarget >= 2, "room for two mistakes")
	assert(R10.LogbookAfter <= R10.SortTarget, "the logbook opens before the day's goal")
end)

test("L10 night: 4 nests and surviving clear it", function()
	assert(play(L10.Night, { { "NestBurned", 4 } }), "cleared")
	assert(not play(L10.Night, { { "NestBurned", 3 }, { "ParcelCreatureKilled", 20 } }), "kills don't replace nests")
end)

test("L10 balance: creature caps grow gently; day mistakes add mimics", function()
	eq(Rules.mimicCap(1), 2, "solo")
	eq(Rules.mimicCap(4), 5, "team of 4")
	eq(Rules.mimicCap(10), 5, "cap")
	eq(Rules.initialMimics(1, 0), 2, "solo start")
	eq(Rules.initialMimics(1, 2), 4, "two infected parcels delivered")
	eq(Rules.initialMimics(8, 9), 6, "hard cap")
	assert(R10.NestSeconds <= EnemyConfig.Flashlight.BatterySeconds, "a nest burns in one battery")
end)

test("L10 mimics: disguise, a visible pounce warning, a split into mites", function()
	local m = MonsterTuning.Mimic
	assert(m.RevealRange >= 8, "you see it wake up before it can reach you")
	assert(m.RevealPause + m.PounceWarn >= 1.5, "time to react after it bursts open")
	assert((m.PounceRadius + 1) / MonsterTuning.PlayerSpeed < m.PounceWarn, "the landing circle can be left in time")
	eq(m.Split, 2, "two mites")
	local mite = EnemyConfig.Types.ParcelMite
	assert(mite.MaxHealth <= 20 and mite.Damage <= 8, "mites are weak")
end)

test("L10 module records every event its objectives need", function()
	recordsAll(L10, "src/server/Levels/Deliveries.luau")
end)

print("Level 11 · Cold Trail / Deep Freeze")

local L11 = CampaignConfig.ById.L11
local R11 = Rules.L11

test("L11 day: prints, the hidden freezer and 3 logbooks clear it", function()
	assert(play(L11.Day, { { "FrostPrintFound", 6 }, { "HiddenFreezerOpened", 1 }, { "FrozenLogRecovered", 3 } }), "cleared")
	assert(not play(L11.Day, { { "FrostPrintFound", 6 }, { "FrozenLogRecovered", 3 } }), "freezer still sealed")
	assert(R11.Prints > R11.PrintTarget and R11.Logs > R11.LogTarget, "spares")
end)

test("L11 night: melting is shared, escaping is personal; the clean bonus needs an escape", function()
	local tracker = Logic.newTracker(L11.Night.Objectives)
	Logic.record(tracker, "A", "IceWallMelted")
	Logic.record(tracker, "B", "FreezerEscaped")
	assert(Logic.requiredComplete(tracker, "B", true), "B escaped")
	assert(not Logic.requiredComplete(tracker, "A", true), "A melted it but stayed inside")
	assert(not table.find(Logic.optionalDone(tracker, "A"), "nofreeze"), "never freezing isn't enough on its own")
	Logic.record(tracker, "B", "CleanEscape")
	assert(table.find(Logic.optionalDone(tracker, "B"), "nofreeze"), "escaped without freezing")
end)

local function secondsUntilFrozen(place)
	local cold, t = 0, 0
	while cold < 1 and t < 600 do
		cold = Rules.coldStep(cold, 0.25, place)
		t += 0.25
	end
	return t
end

test("L11 cold: the hidden freezer gives time to work; heat always wins", function()
	local freezer = secondsUntilFrozen({ InHeat = false, InHiddenFreezer = true, InWalkIn = false })
	assert(freezer >= 20, string.format("%.1fs in the hidden freezer", freezer))
	assert(freezer >= R11.ChipSeconds * 2 + 8, "two logbooks per trip")
	local warm = Rules.coldStep(1, 1, { InHeat = true, InHiddenFreezer = true, InWalkIn = false, WraithDistance = 1 })
	eq(warm, 1 - R11.Fall.Heat, "heat lamps warm even next to the wraith")
	eq(Rules.coldStep(0.5, 1, { InHeat = false, InHiddenFreezer = false, InWalkIn = false }), 0.5 - R11.Fall.Normal, "warms slowly elsewhere")
	eq(Rules.coldStep(0, 1, { InHeat = false, InHiddenFreezer = false, InWalkIn = false }), 0, "never negative")
end)

test("L11 wraith: escapable chill, a dodgeable breath, light slows it, never outruns you", function()
	local close = secondsUntilFrozen({ InHeat = false, InHiddenFreezer = false, InWalkIn = false, WraithDistance = 3 })
	assert(close >= 7, string.format("%.1fs right next to it before freezing", close))
	local near = secondsUntilFrozen({ InHeat = false, InHiddenFreezer = false, InWalkIn = false, WraithDistance = 15 })
	assert(near > close, "further away chills slower")
	local w = MonsterTuning.Wraith
	assert((w.BreathWidth / 2 + 1) / MonsterTuning.PlayerSpeed < w.BreathWarn * 0.5, "breath lane is dodgeable")
	assert(EnemyConfig.Types.FrostWraith.LightScale == 0, "light can't kill it")
	assert(EnemyConfig.Types.FrostWraith.WalkSpeed * w.LitSlow < 6, "light slows it to a crawl")
	assert(R11.FrozenSeconds <= 3, "frozen briefly")
end)

test("L11 balance: one wraith solo, two for bigger teams; the ice takes teamwork to scale", function()
	eq(Rules.wraithCount(1), 1, "solo")
	eq(Rules.wraithCount(2), 1, "duo")
	eq(Rules.wraithCount(4), 2, "team")
	local solo = Rules.iceWallSeconds(1)
	-- solo: a full battery, then waiting for it to recharge, in turns
	local battery = EnemyConfig.Flashlight
	local cycle = battery.BatterySeconds + battery.RechargeDelay + 1 / battery.RechargePerSecond
	local soloTime = math.ceil(solo / battery.BatterySeconds) * cycle
	assert(soloTime <= L11.Night.Duration * 0.5, string.format("solo melts it in ~%ds", soloTime))
	assert(Rules.iceWallSeconds(4) / 4 < solo, "per person it gets easier with a team")
end)

test("L11 module records every event its objectives need", function()
	recordsAll(L11, "src/server/Levels/HiddenFreezer.luau")
end)

print("Level 12 · Under the Floor / The Shifting Maze")

local L12 = CampaignConfig.ById.L12
local R12 = Rules.L12

local function seeded(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

test("L12 day: anomalies and chalk marks clear it", function()
	assert(play(L12.Day, { { "AnomalyFound", 4 }, { "RouteChalked", 4 } }), "cleared")
	assert(not play(L12.Day, { { "AnomalyFound", 3 }, { "RouteChalked", 5 } }), "3 anomalies")
	assert(#R12.Anomalies > R12.AnomalyTarget and R12.ChalkSpots > R12.ChalkTarget, "spares")
end)

test("L12 night: seals are shared, escape is personal; quick escape is a bonus", function()
	local tracker = Logic.newTracker(L12.Night.Objectives)
	for _ = 1, 4 do
		Logic.record(tracker, "A", "SealCollected")
	end
	Logic.record(tracker, "B", "MazeEscaped")
	Logic.record(tracker, "B", "QuickEscape")
	assert(Logic.requiredComplete(tracker, "B", true), "B escaped")
	assert(not Logic.requiredComplete(tracker, "A", true), "A still inside")
	assert(table.find(Logic.optionalDone(tracker, "B"), "escaped"), "quick")
end)

test("L12 maze: every generated layout connects every cell (100 seeds)", function()
	for seed = 1, 100 do
		local walls = Rules.maze(seeded(seed), R12.ExtraOpenings)
		assert(Rules.mazeConnected(walls), "seed " .. seed)
		for _, seal in R12.Seals do
			assert(Rules.mazePath(walls, R12.Entrance, seal), "seal reachable, seed " .. seed)
		end
		assert(Rules.mazePath(walls, R12.Entrance, R12.Heart), "heart reachable")
	end
end)

test("L12 maze: a carved maze is a spanning tree; extra openings add loops", function()
	local all = #Rules.allWalls()
	eq(all, 2 * R12.Cols * (R12.Rows - 1), "interior walls")
	local function standing(walls)
		local n = 0
		for _ in walls do
			n += 1
		end
		return n
	end
	local perfect = Rules.maze(seeded(7), 0)
	eq(all - standing(perfect), R12.Cols * R12.Rows - 1, "cells - 1 passages")
	local loopy = Rules.maze(seeded(7), R12.ExtraOpenings)
	eq(standing(perfect) - standing(loopy), R12.ExtraOpenings, "extra openings")
end)

test("L12 shifts: the diff raises and sinks exactly the changed walls; warning is generous", function()
	local a, b = Rules.maze(seeded(1), 10), Rules.maze(seeded(2), 10)
	local rise, sink = Rules.mazeDiff(a, b)
	for _, key in rise do
		assert(b[key] and not a[key], "rises " .. key)
	end
	for _, key in sink do
		assert(a[key] and not b[key], "sinks " .. key)
	end
	assert(#rise + #sink > 0, "a shift changes something")
	local stepOff = 2 / MonsterTuning.PlayerSpeed
	assert(R12.ShiftWarn >= stepOff + 2, "red lines show long before walls rise")
	assert(R12.ShiftEvery >= 15, "enough time to make progress between shifts")
	local day = Rules.maze(seeded(R12.DaySeed), R12.ExtraOpenings)
	local again = Rules.maze(seeded(R12.DaySeed), R12.ExtraOpenings)
	local same = true
	for _, key in Rules.allWalls() do
		same = same and (day[key] == again[key])
	end
	assert(same, "the same seed gives the same layout")
end)

test("L12 scanner: louder when closer, silent far away", function()
	eq(Rules.signal(0), 1, "on top")
	eq(Rules.signal(R12.SignalRange + 5), 0, "out of range")
	assert(Rules.signal(10) > Rules.signal(30), "closer is louder")
	assert(R12.RevealRange < R12.SignalRange / 4, "the meter matters before it appears")
end)

test("L12 module records every event its objectives need", function()
	recordsAll(L12, "src/server/Levels/ShiftingMaze.luau")
end)

print("Level 13 · Fresh Air / Toxic Bloom")

local L13 = CampaignConfig.ById.L13
local R13 = Rules.L13

test("L13 day: three fans and the airflow clear it", function()
	assert(play(L13.Day, { { "VentFanRepaired", 3 }, { "AirflowBalanced", 1 } }), "cleared")
	assert(not play(L13.Day, { { "VentFanRepaired", 2 }, { "AirflowBalanced", 1 } }), "2 fans")
end)

test("L13 airflow puzzle: every starting position is solvable in at most five flips", function()
	for mask = 0, 2 ^ R13.Dampers - 1 do
		local vents = {}
		for i = 1, R13.Dampers do
			vents[i] = (mask // 2 ^ (i - 1)) % 2 == 1
		end
		local presses = Rules.solveAirflow(vents)
		assert(presses, "unsolvable start " .. mask)
		local state = vents
		for _, i in presses :: { number } do
			state = Rules.toggleDamper(state, i)
		end
		assert(Rules.airflowSolved(state), "solution works " .. mask)
		assert(#(presses :: { number }) <= R13.Dampers, "short")
	end
	local flipped = Rules.toggleDamper({ true, true, true, true, true }, 1)
	assert(not flipped[5] and not flipped[1] and not flipped[2] and flipped[3] and flipped[4], "ring neighbours")
end)

test("L13 night: purges are shared; the clean-air bonus needs purging, not hiding", function()
	assert(play(L13.Night, { { "ZonePurged", 8 } }), "cleared")
	assert(not play(L13.Night, { { "ZonePurged", 7 } }), "7 purges")
	local idle = Logic.newTracker(L13.Night.Objectives)
	assert(not table.find(Logic.optionalDone(idle, "A"), "nochoke"), "hiding all night earns nothing")
	local source = fs.readFile("src/server/Levels/Ventilation.luau")
	assert(source:find("not state.EverChoked and state.Purged", 1, true), "never choked AND purged")
end)

test("L13 zones: the food court splits into six gas zones; the atrium is clean air", function()
	eq(Rules.zoneAt(-217, 0), "Kitchen", "kitchen")
	eq(Rules.zoneAt(-160, 0), "HallWest", "hall west")
	eq(Rules.zoneAt(-120, 0), "HallEast", "hall east")
	eq(Rules.zoneAt(-141, 70), "NorthWing", "north restaurants")
	eq(Rules.zoneAt(-129, -110), "SouthWing", "dock")
	eq(Rules.zoneAt(-217, -70), "BackRooms", "storage")
	eq(Rules.zoneAt(-217, 70), "BackRooms", "freezer")
	eq(Rules.zoneAt(0, 0), nil, "atrium")
	eq(Rules.zoneAt(-85, 0), nil, "promenade")
	for zone, list in R13.Adjacent do
		for _, other in list do
			assert(table.find(R13.Adjacent[other], zone), zone .. " <-> " .. other)
		end
	end
end)

test("L13 gas: sources fill, neighbours leak, purges clear and shield", function()
	local levels = Rules.gasStep({}, { Kitchen = true }, {}, 10, 0)
	assert(math.abs(levels.Kitchen - 10 * R13.SourceRise) < 1e-9, "source rises")
	eq(levels.HallWest, 0, "no leak below the threshold")
	levels.Kitchen = 0.9
	local leaked = Rules.gasStep(levels, { Kitchen = true }, {}, 10, 0)
	assert(leaked.HallWest > 0 and leaked.BackRooms > 0, "spreads to neighbours")
	eq(leaked.HallEast, 0, "only to neighbours")
	local purged = Rules.gasStep({ Kitchen = 1 }, { Kitchen = true }, { Kitchen = 100 }, R13.PurgeSeconds, 0)
	eq(purged.Kitchen, 0, "a purge clears even an open source")
	assert(R13.PurgeShield >= 20, "and keeps it clear for a while")
end)

test("L13 fairness: time to choke, oxygen tanks, dodgeable exhales, bloaters capped", function()
	local meter, t = 0, 0
	while meter < 1 do
		meter = Rules.gasMeterStep(meter, 1, 0.25)
		t += 0.25
	end
	assert(t >= 7, string.format("%.1fs in thick gas before choking", t))
	eq(Rules.gasMeterStep(0.5, 0, 1), 0.5 - R13.MeterFall, "clean air clears it")
	assert(R13.StationDrop >= 0.5, "one breath at a tank buys real time")
	local b = MonsterTuning.Bloater
	assert((b.ExhaleRadius + 1) / MonsterTuning.PlayerSpeed < b.ExhaleWarn, "exhale circle can be left")
	assert(EnemyConfig.Types.SporeBloater.Damage == 0, "bloaters never bite")
	eq(Rules.bloaterCap(1), 2, "solo")
	eq(Rules.bloaterCap(8), 6, "cap")
	assert(R13.ChokeDamage / R13.ChokeEvery <= 4, "choking hurts slowly: time to reach air")
end)

test("L13 module records every event its objectives need", function()
	recordsAll(L13, "src/server/Levels/Ventilation.luau")
end)

print("Level 14 · Patient Zero / The Gorging Chef")

local L14 = CampaignConfig.ById.L14
local R14 = Rules.L14
local CT = Chef.Tuning

test("L14 day: samples, the antidote and finding the source clear it", function()
	assert(
		play(L14.Day, { { "SampleCollected", 4 }, { "AntidoteBrewed", 1 }, { "InfectionSourceFound", 1 } }),
		"cleared"
	)
	assert(not play(L14.Day, { { "SampleCollected", 4 }, { "AntidoteBrewed", 1 } }), "source not found")
	assert(R14.Growths > R14.SampleTarget, "a spare growth")
end)

test("L14 growths: the calm window fits a sample; the spit is announced", function()
	local calm = R14.SpitEvery - R14.SpitWarn - R14.SpitRecover
	assert(calm >= R14.SampleSeconds + 1, string.format("%.1fs calm for a %.1fs sample", calm, R14.SampleSeconds))
	eq((Rules.growthPhase(0.1, 0)), "Spitting", "just spat")
	eq((Rules.growthPhase(R14.SpitRecover + 0.1, 0)), "Calm", "then calm")
	eq((Rules.growthPhase(R14.SpitEvery - 0.5, 0)), "Warning", "then the warning circle")
	assert((R14.SpitRadius + 1) / MonsterTuning.PlayerSpeed < R14.SpitWarn, "the circle can be left in time")
end)

test("L14 brewing goes Chop, Boil, Bottle in order", function()
	eq(Rules.nextBrewStep(0), "Chop", "first")
	eq(Rules.nextBrewStep(1), "Boil", "second")
	eq(Rules.nextBrewStep(2), "Bottle", "third")
	eq(Rules.nextBrewStep(3), nil, "done")
end)

test("L14 night: defeating him is the team's; serving laced dishes earns the bonus", function()
	assert(play(L14.Night, { { "ChefDefeated", 1 } }), "cleared")
	local tracker = Logic.newTracker(L14.Night.Objectives)
	Logic.record(tracker, "A", "LacedDishServed")
	Logic.record(tracker, "A", "LacedDishServed")
	assert(table.find(Logic.optionalDone(tracker, "A"), "feeder"), "bonus")
	local source = fs.readFile("src/server/Levels/GorgingChef.luau")
	assert(source:find('MissionEvents.record(nil, "ChefDefeated")', 1, true), "victory is a team event")
end)

test("chef: greased until a laced meal; plain dishes heal; an empty pass enrages", function()
	local f = Chef.new(1, 0)
	eq(f.State, "Greased", "starts greased")
	local blocked = Chef.applyLight(f, 1, 50)
	assert(blocked.Blocked and blocked.Dealt == 0, "light blocked")
	assert(Chef.serve(f, "Laced"), "serve")
	local ok, reason = Chef.serve(f, "Dish")
	assert(not ok and reason == "Full", "one dish at a time")
	eq(Chef.eat(f, 30), "Sick", "laced → sick")
	eq(f.Pass, "Empty", "plate cleared")
	assert(Chef.isVulnerable(f, 30 + CT.SickSeconds - 0.1), "vulnerable for SickSeconds")
	local hit = Chef.applyLight(f, 31, 50)
	eq(hit.Dealt, 50, "light hurts")
	eq(Chef.update(f, 30 + CT.SickSeconds), "Sick", "wears off")
	eq(f.State, "Greased", "greased again")
	f.Hp -= 100
	local before = f.Hp
	Chef.serve(f, "Dish")
	eq(Chef.eat(f, 100), "Healed", "plain dish")
	assert(f.Hp > before, "it healed him")
	eq(Chef.eat(f, 200), "Ravenous", "empty pass")
	eq(Chef.attackGap(f), CT.AttackGap[1] * CT.RavenousGapScale, "attacks faster")
	assert(Chef.speed(f) < MonsterTuning.PlayerSpeed, "still slower than you")
	eq(Chef.attackGap({ Defeated = false, State = "Sick", Phase = 1 } :: any), nil, "no attacks while sick")
end)

test("chef: phases at 66% and 33%; victory reported once", function()
	local f = Chef.new(1, 0)
	Chef.serve(f, "Laced")
	Chef.eat(f, 0)
	local r1 = Chef.applyLight(f, 1, f.MaxHp * 0.35)
	eq(r1.PhaseChanged, 2, "phase 2")
	local r2 = Chef.applyLight(f, 2, f.MaxHp * 0.35)
	eq(r2.PhaseChanged, 3, "phase 3")
	local r3 = Chef.applyLight(f, 3, f.MaxHp)
	assert(r3.Defeated and f.State == "Defeated", "defeated")
	local r4 = Chef.applyLight(f, 4, 10)
	assert(not r4.Defeated and r4.Dealt == 0, "only once")
	local ok = Chef.serve(f, "Laced")
	assert(not ok, "no serving after victory")
end)

test("chef balance: HP scales; meatballs only from phase 2 and capped", function()
	eq(Chef.maxHp(1), CT.BaseHP + CT.HPPerPlayer, "solo")
	eq(Chef.maxHp(4), CT.BaseHP + CT.HPPerPlayer * 4, "team")
	eq(Chef.meatballCap(1, 4), 0, "none in phase 1")
	eq(Chef.meatballCap(2, 1), 2, "solo phase 2")
	eq(Chef.meatballCap(3, 1), 3, "solo phase 3")
	eq(Chef.meatballCap(3, 10), CT.MaxMeatballs, "cap")
	assert(EnemyConfig.Scaled("Meatball", CT.MeatballTier[3]).WalkSpeed < MonsterTuning.PlayerSpeed, "meatballs are slower")
end)

test("chef fairness: every attack is telegraphed long enough to dodge", function()
	for phase = 1, 3 do
		local warn = CT.Cleaver.Warn[phase]
		assert((CT.Cleaver.Width / 2 + 1) / MonsterTuning.PlayerSpeed < warn * 0.5, "cleaver lane phase " .. phase)
	end
	assert((CT.Pan.Radius + 1) / MonsterTuning.PlayerSpeed < CT.Pan.Warn * 0.5, "pan circle")
	assert((CT.Flare.Width / 2 + 1) / MonsterTuning.PlayerSpeed < CT.Flare.Warn * 0.5, "stove flare")
	assert(CT.FirstHunger >= CT.CookSeconds + CT.LaceSeconds + CT.ServeSeconds + 12, "time to prepare the first dish")
	assert(CT.Grease.Slow >= 0.5, "grease slows, never roots")
end)

-- A whole fight: the team cooks a laced dish for every ORDER UP with probability `prep`,
-- and keeps `accuracy` of its beams on him while he's sick (battery limited).
local function simulateKill(players: number, accuracy: number, prep: number): number
	local f = Chef.new(players, CT.IntroSeconds)
	local battery = EnemyConfig.Flashlight
	local charge = {}
	for i = 1, players do
		charge[i] = battery.BatterySeconds
	end
	local seed = 3
	local function roll()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local t, dt = 0, 0.1
	while t < 240 and not f.Defeated do
		t += dt
		Chef.update(f, t)
		if Chef.isHungry(f, t) then
			if roll() < prep then
				Chef.serve(f, "Laced")
			end
			Chef.eat(f, t)
		end
		for i = 1, players do
			if Chef.isVulnerable(f, t) and charge[i] > 0 then
				charge[i] -= dt
				Chef.applyLight(f, t, Chef.lightDamage(battery.DPS, dt, 0, false) * accuracy)
			else
				charge[i] = math.min(battery.BatterySeconds, charge[i] + battery.BatterySeconds * battery.RechargePerSecond * dt)
			end
		end
	end
	return if f.Defeated then t else math.huge
end

test("chef: a solo player wins well before dawn; teams do too", function()
	local solo = simulateKill(1, 0.7, 0.8)
	assert(solo < L14.Night.Duration * 0.6, string.format("solo kill at %.0fs", solo))
	local team = simulateKill(4, 0.6, 0.9)
	assert(team < L14.Night.Duration - 60, string.format("team of 4 at %.0fs", team))
	print(string.format("      (simulated: solo %.0fs, team of 4 %.0fs of a %ds night)", solo, team, L14.Night.Duration))
end)

test("Chapter 2 reward is paid once; Food Court Hero follows", function()
	local campaign = { Completed = {}, DayCleared = {}, OptionalDone = {}, Chapters = { ["1"] = 1 }, Achievements = {} }
	local reward = Logic.claimChapter(campaign, L14, 100)
	assert(reward, "first clear pays")
	eq(reward.Title, "Head Chef of the Night", "title")
	eq(Logic.claimChapter(campaign, L14, 200), nil, "second clear: nothing")
	local stored = serde.decode("json", serde.encode("json", campaign))
	eq(Logic.claimChapter(stored, L14, 300), nil, "after save/load: nothing")
	local earned = Logic.unlockAchievements(stored, AchievementConfig.List, 400)
	local ids = {}
	for _, a in earned do
		ids[a.Id] = true
	end
	assert(ids.FoodCourtHero and ids.QueenSlayer, "both chapter achievements")
end)

test("L14 module records every event its objectives need", function()
	recordsAll(L14, "src/server/Levels/GorgingChef.luau")
end)

print("Rewards, achievements and saves")

test("achievements: earned once from saved progress, paid once, survive save/load", function()
	local campaign = { Completed = { L07 = 1 }, DayCleared = {}, OptionalDone = {}, Chapters = { ["1"] = 5 } }
	local first = Logic.unlockAchievements(campaign, AchievementConfig.List, 100)
	eq(#first, 1, "Queen Slayer for a finished Chapter 1")
	eq(first[1].Id, "QueenSlayer", "which")
	eq(#Logic.unlockAchievements(campaign, AchievementConfig.List, 101), 0, "never twice")
	campaign.OptionalDone["L08/myexorcisms"] = true
	local stored = serde.decode("json", serde.encode("json", campaign))
	local second = Logic.unlockAchievements(stored, AchievementConfig.List, 102)
	eq(#second, 1, "only the new one after a reload")
	eq(second[1].Id, "KitchenExorcist", "which")
end)

test("achievements reference real optional objectives and pay something", function()
	for _, achievement in AchievementConfig.List do
		assert(achievement.Cash > 0 and achievement.XP > 0, achievement.Id .. " pays")
		local optional = achievement.Rule.Optional
		if optional then
			local levelId, objectiveId = optional:match("^(L%d%d)/(.+)$")
			local level = CampaignConfig.ById[levelId]
			assert(level, achievement.Id .. " level " .. tostring(levelId))
			if not level.Implemented then
				continue -- checked once that level is built
			end
			local found = false
			for _, stage in { level.Day, level.Night } do
				for _, objective in stage.Objectives do
					if objective.Id == objectiveId then
						assert(objective.Optional, achievement.Id .. " points at an optional objective")
						found = true
					end
				end
			end
			assert(found, achievement.Id .. " objective " .. objectiveId)
		end
	end
end)

test("chapter keys: old numeric saves are normalised (no sparse arrays), rewards stay once", function()
	local campaign = { Completed = {}, DayCleared = {}, OptionalDone = {}, Chapters = { [1] = 10 } }
	Logic.normalizeChapters(campaign)
	eq(campaign.Chapters["1"], 10, "moved to a string key")
	eq(campaign.Chapters[1], nil, "numeric key gone")
	assert(Logic.chapterDone(campaign, 1), "still done")
	eq(Logic.claimChapter(campaign, CampaignConfig.ById.L07, 20), nil, "Chapter 1 not paid again")
	-- a fresh Studio profile testing Chapter 2 first: only chapter 2 is set, still a valid map
	local fresh = { Completed = {}, DayCleared = {}, OptionalDone = {}, Chapters = {} }
	fresh.Chapters["2"] = 30
	local encoded = serde.encode("json", fresh)
	assert(encoded:find('"2"', 1, true), "string key survives encoding")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
