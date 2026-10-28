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
