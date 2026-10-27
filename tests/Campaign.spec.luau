-- Unit tests for the campaign rules and content, run outside Roblox with Lune:
--   .tools/bin/lune run tests/Campaign.spec.luau     (also part of scripts/check.sh)

local process = require("@lune/process")
local CampaignConfig = require("../src/shared/Campaign/CampaignConfig")
local Logic = require("../src/shared/Campaign/CampaignLogic")

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

local L01 = CampaignConfig.ById.L01
local L02 = CampaignConfig.ById.L02

print("Campaign content")

test("6 chapters of 7 levels, ids and indices in order", function()
	eq(#CampaignConfig.Chapters, 6, "chapters")
	eq(#CampaignConfig.Levels, 42, "levels")
	for i, level in CampaignConfig.Levels do
		eq(level.Index, i, "index")
		eq(level.Id, string.format("L%02d", i), "id")
		eq(level.Chapter, math.ceil(i / 7), "chapter of " .. level.Id)
		assert(level.Day.Name and level.Night.Name, level.Id .. " needs day and night names")
	end
end)

test("implemented levels are a prefix and fully specified", function()
	local seenPlanned = false
	for _, level in CampaignConfig.Levels do
		if not level.Implemented then
			seenPlanned = true
			continue
		end
		assert(not seenPlanned, level.Id .. " is implemented after a planned level")
		assert(level.Rewards and level.Rewards.Cash > 0 and level.Rewards.XP > 0, level.Id .. " rewards")
		assert(level.Night.Rules and level.Night.Rules.Tier, level.Id .. " night rules")
		for _, stage in { level.Day, level.Night } do
			assert(stage.Duration and stage.Duration >= 60, level.Id .. " duration")
			local ids = {}
			local required = 0
			for _, objective in stage.Objectives do
				assert(objective.Id and objective.Text, level.Id .. " objective needs Id and Text")
				assert(not ids[objective.Id], level.Id .. " duplicate objective " .. objective.Id)
				ids[objective.Id] = true
				local kind = objective.Kind or "Count"
				if kind ~= "Survive" then
					assert(
						CampaignConfig.Events[objective.Event],
						level.Id .. " unknown event " .. tostring(objective.Event)
					)
				end
				if not objective.Optional then
					required += 1
				end
			end
			assert(required > 0, level.Id .. " stage needs a required objective")
		end
	end
end)

test("day 2 / night 2 share no required objective events with day 1 / night 1", function()
	local function events(stage)
		local set = {}
		for _, objective in stage.Objectives do
			if not objective.Optional and objective.Event then
				set[objective.Event] = true
			end
		end
		return set
	end
	for _, pair in { { L01.Day, L02.Day }, { L01.Night, L02.Night } } do
		local first = events(pair[1])
		for event in events(pair[2]) do
			assert(not first[event], "level 2 repeats required event " .. event)
		end
	end
	assert(L02.Night.Rules.Blackout and not L01.Night.Rules.Blackout, "only night 2 is a blackout")
end)

print("Objective tracking")

test("personal objectives count per player and cap at the target", function()
	local t = Logic.newTracker(L01.Day.Objectives)
	for _ = 1, 5 do
		Logic.record(t, 1, "Served")
	end
	Logic.record(t, 2, "Served")
	local serve = L01.Day.Objectives[3]
	eq(Logic.value(t, 1, serve), 3, "player 1 capped")
	eq(Logic.value(t, 2, serve), 1, "player 2 separate")
	eq(Logic.value(t, 1, L01.Day.Objectives[5]), 5, "optional serve6 counts too")
end)

test("team objectives are shared by everyone", function()
	local t = Logic.newTracker(L02.Day.Objectives)
	Logic.record(t, 1, "PanelRepaired")
	Logic.record(t, 2, "PanelRepaired", 3)
	eq(Logic.isDone(t, 3, L02.Day.Objectives[1]), true, "player 3 sees the team total")
end)

test("required completion ignores optional objectives", function()
	local t = Logic.newTracker(L01.Day.Objectives)
	for _, event in { "ShopClaimed", "Restocked", "Served", "Served", "Served", "Upgraded" } do
		Logic.record(t, 1, event)
	end
	eq(Logic.requiredComplete(t, 1), true, "complete")
	eq(#Logic.optionalDone(t, 1), 0, "serve6 not done")
end)

test("survive completes only at stage end; avoid fails on its event", function()
	local t = Logic.newTracker(L01.Night.Objectives)
	Logic.record(t, 1, "FlashlightEquipped")
	Logic.record(t, 1, "Kill")
	eq(Logic.requiredComplete(t, 1, false), false, "not before dawn")
	eq(Logic.requiredComplete(t, 1, true), true, "at dawn")
	eq(#Logic.optionalDone(t, 1), 1, "nodown done (team6 not)")
	Logic.record(t, 1, "Downed")
	eq(#Logic.optionalDone(t, 1), 0, "nodown failed")
	eq(Logic.requiredComplete(t, 1, true), true, "being downed never fails the level")
end)

test("night 2 fails without the breakers", function()
	local t = Logic.newTracker(L02.Night.Objectives)
	Logic.record(t, 1, "BreakerRestored", 2)
	eq(Logic.requiredComplete(t, 1, true), false, "2/3 breakers")
	Logic.record(t, 2, "BreakerRestored")
	eq(Logic.requiredComplete(t, 1, true), true, "3/3 by anyone")
end)

test("unrelated events change nothing", function()
	local t = Logic.newTracker(L02.Day.Objectives)
	eq(Logic.record(t, 1, "Kill"), false, "no change")
end)

test("completeRequired fills required objectives only", function()
	local t = Logic.newTracker(L02.Day.Objectives)
	Logic.completeRequired(t, { 1 })
	eq(Logic.requiredComplete(t, 1), true, "required")
	eq(#Logic.optionalDone(t, 1), 0, "optional untouched")
end)

print("Progress and selection")

test("next level and unlocks follow completion order", function()
	local levels = CampaignConfig.Levels
	eq(Logic.nextLevel(levels, {}).Id, "L01", "fresh player")
	eq(Logic.nextLevel(levels, { L01 = 1 }).Id, "L02", "after L01")
	eq(Logic.nextLevel(levels, { L01 = 1, L02 = 1 }), nil, "all available done")
	eq(Logic.isUnlocked(levels, {}, "L02"), false, "L02 locked")
	eq(Logic.isUnlocked(levels, { L01 = 1 }, "L02"), true, "L02 unlocked")
	eq(Logic.isUnlocked(levels, { L01 = 1 }, "L01"), true, "replay allowed")
	eq(Logic.isUnlocked(levels, { L01 = 1, L02 = 1 }, "L03"), false, "planned level never unlocks")
end)

test("vote picks the plurality; ties go to the earliest level; Free Shift loses ties", function()
	local index = CampaignConfig.IndexOf
	eq(Logic.pickLevel({ "L02", "L02", "L01" }, index), "L02", "plurality")
	eq(Logic.pickLevel({ "L02", "L01" }, index), "L01", "tie → earliest")
	eq(Logic.pickLevel({ "FREE", "L02" }, index), "L02", "Free Shift loses ties")
	eq(Logic.pickLevel({ "FREE" }, index), "FREE", "solo Free Shift")
	eq(Logic.pickLevel({}, index), nil, "no votes")
end)

test("outcomes protect personal progress", function()
	local base = { Eligible = true, InRoster = true, DayCleared = true, NightSuccess = true, AlreadyCompleted = false }
	local function with(changes)
		local info = table.clone(base)
		for k, v in changes do
			info[k] = v
		end
		return Logic.outcome(info)
	end
	eq(with({}), "FirstClear", "clear")
	eq(with({ AlreadyCompleted = true }), "Replay", "replay")
	eq(with({ Eligible = false }), "Guest", "locked level never credits")
	eq(with({ InRoster = false }), "LateJoin", "joined mid-night")
	eq(with({ NightSuccess = false }), "NightFailed", "night failed")
	eq(with({ DayCleared = false }), "DayMissing", "day not cleared")
end)

test("replays pay a fraction of the first-clear reward", function()
	local first = Logic.reward(L02.Rewards, true, CampaignConfig.ReplayFraction)
	local replay = Logic.reward(L02.Rewards, false, CampaignConfig.ReplayFraction)
	eq(first.Cash, 250, "first cash")
	eq(replay.Cash, 62, "replay cash")
	eq(replay.XP, 75, "replay xp")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
