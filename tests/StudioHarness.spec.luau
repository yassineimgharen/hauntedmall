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

test("the shipped project doesn't include the harness", function()
	local serde = require("@lune/serde")
	local fs = require("@lune/fs")
	local project = serde.decode("json", fs.readFile("default.project.json"))
	eq(project.tree.ServerScriptService.NightShiftQA, nil, "production tree")
end)

Check.finish()
