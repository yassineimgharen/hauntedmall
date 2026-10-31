-- Unit tests for the campaign rules and content, run outside Roblox with Lune:
--   .tools/bin/lune run tests/Campaign.spec.luau     (also part of scripts/check.sh)

local process = require("@lune/process")
local CampaignConfig = require("../src/shared/Campaign/CampaignConfig")
local Logic = require("../src/shared/Campaign/CampaignLogic")
local MirrorGrid = require("../src/server/Levels/MirrorGrid")

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

test("no implemented level repeats a required objective event from an earlier level", function()
	local seen = {}
	for _, level in CampaignConfig.Levels do
		if not level.Implemented then
			break
		end
		local mine = {}
		for _, stage in { level.Day, level.Night } do
			for _, objective in stage.Objectives do
				if not objective.Optional and objective.Event then
					assert(
						not seen[objective.Event],
						level.Id
							.. " repeats required event "
							.. objective.Event
							.. " from "
							.. tostring(seen[objective.Event])
					)
					mine[objective.Event] = level.Id
				end
			end
		end
		for event, id in mine do
			seen[event] = id
		end
	end
	assert(L02.Night.Rules.Blackout and not L01.Night.Rules.Blackout, "only night 2 is a blackout")
end)

test("avoid objectives declare a non-negative tolerance", function()
	for _, level in CampaignConfig.Levels do
		if level.Implemented then
			for _, stage in { level.Day, level.Night } do
				for _, objective in stage.Objectives do
					if objective.Kind == "Avoid" then
						assert((objective.Allow or 0) >= 0, level.Id .. "/" .. objective.Id)
					end
				end
			end
		end
	end
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

test("team avoid fails only past its tolerance", function()
	local L03 = CampaignConfig.ById.L03
	local t = Logic.newTracker(L03.Night.Objectives)
	Logic.record(t, nil, "PhantomDefeated", 4)
	Logic.record(t, nil, "ShopperTaken", 2)
	eq(Logic.requiredComplete(t, 1, true), true, "2 lost is allowed")
	eq(#Logic.optionalDone(t, 1), 1, "saveall failed, noaccuse kept")
	Logic.record(t, nil, "ShopperTaken")
	eq(Logic.requiredComplete(t, 1, true), false, "3 lost fails")
	local row = Logic.rows(t, 1, false)[2]
	eq(row.Failed, true, "row shows failure")
	eq(row.Progress, 3, "lost count")
	eq(row.Target, 2, "tolerance")
end)

test("personal avoid is per player", function()
	local L03 = CampaignConfig.ById.L03
	local t = Logic.newTracker(L03.Night.Objectives)
	Logic.record(t, 1, "FalseAccusation")
	local noaccuse = L03.Night.Objectives[5]
	eq(Logic.isFailed(t, 1, noaccuse), true, "player 1")
	eq(Logic.isFailed(t, 2, noaccuse), false, "player 2")
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
	eq(Logic.nextLevel(levels, { L01 = 1, L02 = 1 }).Id, "L03", "after L02")
	local all, firstPlanned = {}, nil
	for _, level in levels do
		if level.Implemented then
			all[level.Id] = 1
		elseif not firstPlanned then
			firstPlanned = level.Id
		end
	end
	eq(Logic.nextLevel(levels, all), nil, "all available done")
	eq(Logic.isUnlocked(levels, {}, "L02"), false, "L02 locked")
	eq(Logic.isUnlocked(levels, { L01 = 1 }, "L02"), true, "L02 unlocked")
	eq(Logic.isUnlocked(levels, { L01 = 1 }, "L01"), true, "replay allowed")
	eq(Logic.isUnlocked(levels, all, firstPlanned), false, "planned level never unlocks")
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

print("Level 7 light puzzle")

test("mirror puzzle: solved exactly when the three route mirrors are '/'", function()
	local solutions = 0
	for mask = 0, 63 do
		local states = {}
		for i = 1, 6 do
			states[i] = if bit32.extract(mask, i - 1) == 1 then "/" else "\\"
		end
		local solved = MirrorGrid.solved(states)
		if solved then
			solutions += 1
		end
		eq(solved, states[1] == "/" and states[2] == "/" and states[3] == "/", "mask " .. mask)
	end
	eq(solutions, 8, "solutions")
end)

test("mirror puzzle: the solved route ends at the receiver", function()
	local cells, dir, hit = MirrorGrid.trace({ "/", "/", "/", "\\", "\\", "\\" })
	eq(hit, true, "hit")
	local last = cells[#cells]
	eq(last[1] .. "," .. last[2], "3,4", "last cell")
	eq(dir[1] .. "," .. dir[2], "0,1", "leaves north")
end)

test("BUG-03 regression: shop chores can be covered without moving other objectives", function()
	local tracker = Logic.newTracker({
		{ Id = "serve", Text = "", Event = "Served", Target = 3, NeedsShop = true },
		{ Id = "serve6", Text = "", Event = "Served", Target = 6, Optional = true },
		{ Id = "team", Text = "", Event = "BarricadeBuilt", Target = 3, Scope = "Team", Optional = true },
		{ Id = "built", Text = "", Event = "BarricadeBuilt", NeedsShop = true },
		{ Id = "lamp", Text = "", Event = "Upgraded" },
	})
	eq(Logic.coverShopChores(tracker, 1), true, "first time changes")
	eq(Logic.coverShopChores(tracker, 1), false, "second time doesn't")
	local rows = {}
	for _, row in Logic.rows(tracker, 1) do
		rows[row.Id] = row
	end
	eq(rows.serve.Done, true, "serve covered")
	eq(rows.built.Done, true, "barricade covered")
	eq(rows.serve6.Progress, 0, "bonus untouched")
	eq(rows.team.Progress, 0, "team bonus untouched")
	eq(rows.lamp.Done, false, "other required objectives still needed")
	eq(Logic.requiredComplete(tracker, 1, true), false, "not the whole stage")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
