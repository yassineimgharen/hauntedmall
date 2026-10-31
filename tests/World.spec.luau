-- Audits the real generated world, with the real server code booted in the fake engine
-- (tests/harness/Engine.luau). Geometry comes from the actual parts; pathing and raycasts are the
-- harness's own, NOT Roblox's: see docs/qa/QA_REPORT.md for what that does and doesn't prove.
--   .tools/bin/lune run tests/World.spec.luau

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local Check = require("./harness/Check")
local Engine = require("./harness/Engine")
local Sim = require("./harness/Sim")

local CampaignConfig = require("../src/shared/Campaign/CampaignConfig")

Check.suite("World", "Integration-tested")
local test, eq, truthy = Check.test, Check.eq, Check.truthy

local world = Engine.new({ Seed = 1 })
world:boot()

test("the server boots with no errors or invalid properties", function()
	Check.noServerErrors(world)
	truthy(world.Stats.InstancesCreated > 1000, "world built")
end)

test("BUG-01 regression: the mall's ground plate leaves the basement ramp open", function()
	local Layout = world:require("World.Layout")
	local ramp = Layout.FoodCourt.Ramp
	local top = Vector3.new(ramp.X, 0, ramp.TopZ - 2)
	truthy(world:findPath(Vector3.new(0, 0, -40), top, 3), "walk to the top of the ramp")
	local bottom = Vector3.new(ramp.X, Layout.FoodCourt.Basement.FloorY, ramp.BottomZ + 4)
	truthy(world:findPath(top, bottom, 3), "walk down the ramp into the basement")
	eq(world.standY(ramp.X, ramp.TopZ + 6, 0.5) < -1, true, "no floor plate over the ramp")
end)

test("every required objective event has a server call that records it", function()
	local fs = require("@lune/fs")
	local source = {}
	local function read(path: string)
		for _, name in fs.readDir(path) do
			local full = path .. "/" .. name
			if fs.isDir(full) then
				read(full)
			elseif name:match("%.luau$") then
				table.insert(source, fs.readFile(full))
			end
		end
	end
	read("src/server")
	local all = table.concat(source, "\n")
	local missing = {}
	for _, level in CampaignConfig.Levels do
		if level.Implemented then
			for _, stage in { level.Day, level.Night } do
				for _, objective in stage.Objectives do
					if objective.Event and not all:find('"' .. objective.Event .. '"', 1, true) then
						table.insert(missing, level.Id .. ":" .. objective.Id .. ":" .. objective.Event)
					end
				end
			end
		end
	end
	eq(table.concat(missing, ", "), "", "events nothing records")
end)

test("BUG-05 regression: every required Count objective tells the player where to go", function()
	-- a marker, or an explicit hint in the text; nothing required may be left to guesswork
	local silent = {}
	for _, level in CampaignConfig.Levels do
		if level.Implemented then
			for _, stage in { level.Day, level.Night } do
				for _, objective in stage.Objectives do
					local kind = objective.Kind or "Count"
					if kind == "Count" and not objective.Optional and not objective.Marker and not objective.Hint then
						table.insert(silent, level.Id .. ":" .. objective.Id)
					end
				end
			end
		end
	end
	eq(table.concat(silent, ", "), "", "no marker and no hint")
	truthy(CampaignConfig.ById.L05.Night.Objectives[1].Marker, "L05's music boxes have an arrow")
end)

world:shutdown()

test("BUG-02 regression: a monster with nowhere to go asks the pathfinder at most once a second", function()
	local run = Sim.start("L02", 1, { Seed = 3 })
	local w = run.World
	w:waitForPhase("Night", 400)
	w:run(45) -- crawlers are out
	local enemies = #w:require("Services.EnemyService").GetAll()
	truthy(enemies > 0, "crawlers on the floor")
	w:removePlayer(run.Bots[1].Player) -- nobody left: they head for the fountain, which is solid
	w:run(3)
	local before = w.Stats.Computes or 0
	local steps = 20
	w:run(steps)
	local alive = math.max(#w:require("Services.EnemyService").GetAll(), 1)
	local rate = ((w.Stats.Computes or 0) - before) / steps / alive
	truthy(rate <= 1.2, string.format("%.2f path requests per monster per second", rate))
	Check.note("BUG02.PathRequestsPerMonsterPerSecond", string.format("%.2f", rate))
	Check.noServerErrors(w)
end)

-- Per level: at the start of each stage every enabled prompt can be reached on foot from the
-- player's spawn, every marker tag has something to point at, and enemies keep off players.
local function promptPosition(prompt: any): any
	local parent = prompt.Parent
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return parent.Position
end

-- Things that are deliberately out of reach or absent when a stage starts. Each is exercised later
-- in tests/Levels.spec.luau, where the bot has to reach or use it to finish the level.
local LATE_MARKERS = {
	L08Night = { PossessedAppliance = "the first possession comes a few seconds into the night" },
	L14Day = { KitchenSeal = "appears once the samples and antidote objectives are done" },
}
local BEHIND_LOCKED_DOORS = {
	L11Day = { ["Chip the Ice"] = "inside the freezer, which the day's levers open" },
}

local function audit(run: any, stageName: string, stage: any)
	local world2 = run.World
	local bot = run.Bots[1]
	local prefix = run.Level .. " " .. stageName .. ": "
	world2:waitForPhase(stageName, 400)
	world2:run(1)

	test(prefix .. "every marker tag on an objective exists in the world", function()
		local missing = {}
		for _, objective in stage.Objectives do
			if objective.Marker and objective.Marker.Tag then
				local late = LATE_MARKERS[run.Level .. stageName]
				if
					#world2.CollectionService:GetTagged(objective.Marker.Tag) == 0
					and not (late and late[objective.Marker.Tag])
				then
					table.insert(missing, objective.Id .. "→" .. objective.Marker.Tag)
				end
			end
		end
		eq(table.concat(missing, ", "), "", "markers with nothing to point at")
	end)

	test(prefix .. "every enabled prompt is reachable on foot", function()
		local start = bot:position() - Vector3.new(0, 3, 0)
		local bad = {}
		local count = 0
		for _, d in world2.Workspace:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.Enabled then
				count += 1
				local position = promptPosition(d)
				local range = math.max(d.MaxActivationDistance - 1, 2)
				local locked = BEHIND_LOCKED_DOORS[run.Level .. stageName]
				if not (locked and locked[d.ActionText]) and not world2:findPathWithin(start, position, nil, range) then
					table.insert(bad, string.format("%q (%s) at %s", d.ActionText, d.ObjectText, tostring(position)))
				end
			end
		end
		eq(#bad, 0, count .. " prompts; unreachable: " .. table.concat(bad, "; "))
	end)
end

for _, level in CampaignConfig.Levels do
	if level.Implemented then
		local run = Sim.start(level.Id, 1, { Seed = 1 })
		audit(run, "Day", level.Day)
		world = run.World
		world:waitForPhase("Night", 400)
		audit(run, "Night", level.Night)
		test(level.Id .. " Night: no server errors while the level runs unattended", function()
			Check.noServerErrors(run.World)
		end)
		run.World:shutdown()
	end
end

Check.finish()
