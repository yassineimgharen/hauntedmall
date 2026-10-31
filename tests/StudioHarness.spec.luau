-- Smoke test of the Studio harness in the fake engine: it runs start to finish and its checks make
-- sense. This tests the harness's own code; it says NOTHING about the real engine. Only running it
-- in Studio does that (docs/qa/STUDIO_HARNESS.md).
--   .tools/bin/lune run tests/StudioHarness.spec.luau

local Check = require("./harness/Check")
local Engine = require("./harness/Engine")

Check.suite("StudioHarness", "Integration-tested")
local test, eq, truthy = Check.test, Check.eq, Check.truthy

test("the harness runs to the end in the fake engine with no failed checks and no crash", function()
	local world = Engine.new({ Seed = 2, Attributes = { QA_Levels = "L01,L12,L14", QA_Walk = 1, QA_NoPhysics = true } })
	world:boot()
	world:addPlayer("Tester")
	world:runFile("tools/studio/NightShiftQA.server.luau")
	local done = world:runUntil(function()
		return world.Workspace:GetAttribute("QA_Result") ~= nil
	end, 900)
	truthy(done, "finished")
	Check.noServerErrors(world)
	local result = world.Workspace:GetAttribute("QA_Result")
	local passed, failed = result:match("(%d+) passed, (%d+) failed")
	local said = {}
	for _, warning in world.Warnings do
		if warning.Message:find("[QA]", 1, true) then
			table.insert(said, warning.Message)
		end
	end
	truthy(passed, "summary: " .. tostring(result) .. " " .. table.concat(said, " | "))
	truthy(tonumber(passed) > 10, "ran its checks")
	-- Two checks can't pass here, by the fake engine's limits (not the game's): its path search gives
	-- up on the longest routes, and its raycasts only see anchored parts (bosses are welded rigs).
	local unexplained = {}
	for _, line in said do
		local known = line:find("has a real path", 1, true) or line:find("can be hit by a beam raycast", 1, true)
		if not known and not line:find("FAILED:", 1, true) then
			table.insert(unexplained, line)
		end
	end
	eq(table.concat(unexplained, " | "), "", "unexplained failures (" .. tostring(failed) .. " total)")
end)

test("the harness refuses to run when a real DataStore is connected", function()
	local world = Engine.new({ Seed = 3, DataStore = {}, Attributes = { QA_Levels = "L01" } })
	world:boot()
	world:addPlayer("Tester", 999)
	world:runFile("tools/studio/NightShiftQA.server.luau")
	world:run(5)
	eq(world.Workspace:GetAttribute("QA_Result"), nil, "stopped before doing anything")
	local stopped = false
	for _, warning in world.Warnings do
		if warning.Message:find("Stopping", 1, true) then
			stopped = true
		end
	end
	truthy(stopped, "said why")
end)

-- Runs the harness with fake client physics (see CharacterPhysics in the engine). Again this tests
-- the check, not Roblox: can it tell a working escalator from a broken one?
local function harnessRun(attributes: { [string]: any }, physics: any, players: number?, setup: ((any) -> ())?): any
	local world = Engine.new({ Seed = 4, Attributes = attributes, CharacterPhysics = physics })
	world:boot()
	for i = 1, players or 1 do
		world:addPlayer("Rider" .. i)
	end
	if setup then
		setup(world)
	end
	world:runFile("tools/studio/NightShiftQA.server.luau")
	return world
end

local function finished(world: any, seconds: number)
	truthy(
		world:runUntil(function()
			return world.Workspace:GetAttribute("QA_Result") ~= nil
		end, seconds),
		"finished within its limits"
	)
	Check.noServerErrors(world)
end

local function lines(world: any, marker: string): string
	local found = {}
	for _, warning in world.Warnings do
		if warning.Message:find(marker, 1, true) then
			table.insert(found, warning.Message)
		end
	end
	return table.concat(found, "\n")
end

local function escalatorRun(physics: any, players: number?): (string, string, string)
	local world = harnessRun({ QA_EscalatorsOnly = true, QA_Riders = players or 1 }, physics, players)
	finished(world, 500)
	return world.Workspace:GetAttribute("QA_Result"), lines(world, "[QA] FAIL "), lines(world, "[QA] INCONCLUSIVE ")
end

test("escalator rides pass both ways, standing and walking, when the belts work", function()
	local result, failed = escalatorRun({})
	eq(failed, "", "no failures")
	truthy(tonumber(result:match("(%d+) passed")) >= 11, "ran every ride: " .. result)
end)

test("Studio regression: a client still loading is waited for, not reported as a broken escalator", function()
	-- The first Studio run's "an escalator carries a character: 0,0,0": the check ran before the client
	-- simulated anything. The old harness fails in exactly this world.
	local _, failed = escalatorRun({ ReadyAt = 40 })
	eq(failed, "", "no failures")
end)

test("two players ride the same escalators together", function()
	local result, failed = escalatorRun({}, 2)
	eq(failed, "", "no failures")
	truthy(tonumber(result:match("(%d+) passed")) >= 12, "ran every ride: " .. result)
end)

test("a client that never starts is reported as unmeasured, and the server rider still tests the belts", function()
	local result, failed, unclear = escalatorRun({ ReadyAt = 100000 })
	truthy(unclear:find("never simulated", 1, true), unclear)
	eq(failed, "", "not a game failure")
	truthy(result:find("server", 1, true) == nil and tonumber(result:match("(%d+) passed")) >= 5, result)
end)

test("a real ride uses a rider the server simulates itself, removed afterwards", function()
	local world = harnessRun({ QA_EscalatorsOnly = true }, {})
	finished(world, 500)
	eq(lines(world, "server rider"), "", "no failed server rider")
	eq(world.Workspace:FindFirstChild("QA_Rider"), nil, "cleaned up")
end)

test("the server rider catches a belt that carries nothing, with no client involved", function()
	local _, failed = escalatorRun({ Carry = 0, ReadyAt = 100000 })
	truthy(failed:find("Escalator1 (up): real physics carries a server-owned rider", 1, true), failed)
	truthy(failed:find("Escalator2 (down): real physics carries a server-owned rider", 1, true), failed)
end)

test("a client that doesn't see the belt's speed is a failure", function()
	local world = harnessRun({ QA_EscalatorsOnly = true }, { ReadyAt = 20 })
	world:runUntil(function()
		return world.ReplicatedStorage:FindFirstChild("QA_ClientReport") ~= nil
	end, 60)
	local remote = world.ReplicatedStorage:FindFirstChild("QA_ClientReport")
	remote.OnServerEvent:_fire(world.Players:GetPlayers()[1], "Ready", {
		Ramps = { Escalator1 = 0, Escalator2 = 7 },
		Text = "loaded",
	})
	finished(world, 500)
	local failed = lines(world, "[QA] FAIL ")
	truthy(failed:find("Escalator1 (up): the belt's speed reaches", 1, true), failed)
	eq(failed:find("Escalator2 (down): the belt's speed reaches", 1, true), nil, failed)
end)

test("QA_EscalatorsOnly limits the run, whether ticked or typed; false doesn't", function()
	for _, value in { true, "true" } do
		local world = harnessRun({ QA_EscalatorsOnly = value, QA_Walk = 0 }, {})
		finished(world, 500)
		eq(world:GetPrints("[QA] LEVEL"), "", "no levels ran")
	end
	local world = harnessRun({ QA_EscalatorsOnly = "false", QA_Levels = "L01", QA_Walk = 0, QA_NoPhysics = true }, {})
	finished(world, 300)
	truthy(world:GetPrints("[QA] LEVEL L01 starting") ~= "", "a level ran")
end)

test("the run prints its version, and the docs give the same one, so an old place file shows", function()
	local fs = require("@lune/fs")
	local source = fs.readFile("tools/studio/NightShiftQA.server.luau")
	local version = source:match("local HARNESS_VERSION = (%d+)")
	truthy(fs.readFile("docs/qa/STUDIO_HARNESS.md"):find("harness version " .. version, 1, true), "documented")
	local world = harnessRun({ QA_EscalatorsOnly = true, QA_NoPhysics = true }, {})
	finished(world, 60)
	truthy(world:GetPrints("harness version " .. version .. " starting") ~= "", "printed")
end)

test("QA_From resumes at that level, skips the rides, and runs through the rest", function()
	local world = harnessRun({ QA_From = "L13", QA_Walk = 0 }, {})
	finished(world, 500)
	eq(world:GetPrints("[QA] LEVEL L12 starting"), "", "earlier levels skipped")
	truthy(world:GetPrints("[QA] LEVEL L13 starting") ~= "", "starts there")
	truthy(world:GetPrints("[QA] LEVEL L14 starting") ~= "", "runs on")
	eq(world:GetPrints("Escalator1"), "", "no rides")
end)

test("a QA_From that names no level fails instead of quietly testing nothing", function()
	local world = harnessRun({ QA_From = "L99", QA_NoPhysics = true }, {})
	finished(world, 60)
	truthy(lines(world, "[QA] FAIL QA_From"):find("L99", 1, true), "said so")
end)

test("a disconnect ends the run at once with a summary and the level to resume from", function()
	local world = harnessRun({ QA_From = "L08", QA_Walk = 0 }, {})
	truthy(
		world:runUntil(function()
			return world:GetPrints("[QA] LEVEL L08 starting") ~= ""
		end, 200),
		"reached L08"
	)
	world:run(5)
	world:removePlayer(world.Players:GetPlayers()[1])
	world:run(1)
	local result = world.Workspace:GetAttribute("QA_Result")
	truthy(result and result:find("stopped:", 1, true), "partial result: " .. tostring(result))
	truthy(lines(world, "[QA] STOPPED"):find("disconnected", 1, true), "said why")
	truthy(lines(world, "[QA] RESUME"):find('QA_From = "L08"', 1, true), "said where to resume")
	Check.noServerErrors(world)
end)

test("a stage over its time limit is given up on, and the run carries on", function()
	local world = harnessRun({ QA_Levels = "L01,L02", QA_StageLimit = 1, QA_Walk = 3, QA_From = "L01" }, {})
	finished(world, 500)
	truthy(lines(world, "[QA] INCONCLUSIVE L01 Day: checks"):find("gave up after 1 s", 1, true), "timed out")
	truthy(world:GetPrints("[QA] LEVEL L02 finished") ~= "", "went on to the next level")
end)

test("a character that dies on a walk tries again on its new body and isn't called lost", function()
	local killed = false
	local world
	world = harnessRun({ QA_Levels = "L01", QA_Walk = 1, QA_From = "L01" }, {
		After = function(model)
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if not killed and humanoid and humanoid._moveTarget and world:phase() == "Day" then
				killed = true
				humanoid.Health = 0
			end
		end,
	})
	finished(world, 500)
	truthy(killed, "the death happened")
	eq(lines(world, "[QA] FAIL L01 Day: a character walks"), "", "retried, not failed")
end)

test("a character that really can't get there is a failure saying where it stopped and why", function()
	local world = harnessRun({ QA_Levels = "L01", QA_Walk = 1, QA_From = "L01" }, {
		After = function(model)
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = 0
			end
		end,
	})
	finished(world, 800)
	local failed = lines(world, "a character walks")
	truthy(failed:find("first stuck at waypoint", 1, true), failed)
	truthy(failed:find("ahead:", 1, true) and failed:find("nearest NPC:", 1, true), failed)
end)

local function spawnCheck(setup: ((any) -> ())?): string
	local world = harnessRun({ QA_Levels = "L01", QA_Walk = 0, QA_NoPhysics = true }, nil, 1, setup)
	finished(world, 300)
	return lines(world, "spawn points stand on open floor")
end

test("the spawn check finds a wall in a spawn point and names it, but ignores someone walking past", function()
	eq(spawnCheck(), "", "clean as built")
	local function place(world: any, name: string, anchored: boolean, parent: any)
		local roblox = require("@lune/roblox")
		local part = world.Instance.new("Part")
		part.Name = name
		part.Size = roblox.Vector3.new(4, 6, 4)
		part.CFrame = roblox.CFrame.new(-60, 5, 60)
		part.Anchored = anchored
		part.CanCollide = true
		part.Parent = parent
	end
	truthy(
		spawnCheck(function(world)
			place(world, "StrayWall", true, world.Workspace)
		end):find("StrayWall", 1, true),
		"named the wall"
	)
	eq(
		spawnCheck(function(world)
			place(world, "Passerby", false, world.Workspace)
		end),
		"",
		"a loose body isn't a wall"
	)
end)

test("L05's daytime vault doesn't count against a night-only spawn marker, and every night is clean", function()
	local world = harnessRun({ QA_Walk = 0, QA_NoPhysics = true }, nil)
	finished(world, 1500)
	eq(lines(world, "spawn points stand on open floor"), "", "every level, every night")
	truthy(world:GetPrints("L05 Night: monster spawn points") ~= "", "the night check ran")
	eq(world:GetPrints("L05 Day: monster spawn points"), "", "not checked by day")
end)

test("the check fails when a belt moves but doesn't carry anyone", function()
	local _, failed = escalatorRun({ Carry = 0 })
	truthy(failed:find("Escalator1 (up): carries a standing", 1, true), failed)
	truthy(failed:find("Escalator2 (down): carries a standing", 1, true), failed)
end)

test("the check fails when a belt carries too slowly", function()
	local _, failed = escalatorRun({ Carry = 0.3 })
	truthy(failed:find("carries a standing", 1, true), failed)
end)

test("the check fails on teleporting riders", function()
	local _, failed = escalatorRun({
		After = function(character, dt)
			if math.random() < dt / 2 then
				character:PivotTo(character:GetPivot() + character:GetPivot().LookVector * 8)
			end
		end,
	})
	truthy(failed:find("carries a standing", 1, true), failed)
end)

test("the check fails on jitter", function()
	local signs = {}
	local _, failed = escalatorRun({
		After = function(character)
			signs[character] = -(signs[character] or 1)
			character:PivotTo(character:GetPivot() + character:GetPivot().RightVector * signs[character] * 1.5)
		end,
	})
	truthy(failed:find("carries a standing", 1, true), failed)
end)

test("the shipped project doesn't include the harness", function()
	local serde = require("@lune/serde")
	local fs = require("@lune/fs")
	local project = serde.decode("json", fs.readFile("default.project.json"))
	eq(project.tree.ServerScriptService.NightShiftQA, nil, "production tree")
	eq(project.tree.StarterPlayer.StarterPlayerScripts.NightShiftQAClient, nil, "no client helper either")
	local qa = serde.decode("json", fs.readFile("qa.project.json"))
	truthy(qa.tree.StarterPlayer.StarterPlayerScripts.NightShiftQAClient, "the QA place has it")
end)

Check.finish()
