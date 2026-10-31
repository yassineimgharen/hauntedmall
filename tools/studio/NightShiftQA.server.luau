-- NIGHT SHIFT QA HARNESS: runs inside Roblox Studio, with the real engine: real collisions,
-- PathfindingService, raycasts, Humanoid walking, welds, conveyors. It exists to check what the
-- Lune simulation (tests/) can't. It is NOT part of the game: only qa.project.json includes it.
--
-- How to run (see docs/qa/STUDIO_HARNESS.md):
--   rojo build qa.project.json -o NightShiftQA.rbxl   then open it in Studio and press Play (F5).
-- Workspace attributes, all optional, set before pressing Play:
--   QA_Levels = "L01,L12"   only these levels (default: all of them; about 20 minutes)
--   QA_Walk   = 3           prompts per stage a real character walks to (default 3; 0 = none)
-- Results: lines starting [QA] in the Output window, and a summary at the end.
--
-- Safety: only runs in Studio; refuses to run if a real DataStore is connected, so it can't touch
-- saved data; never fires purchases, and never changes settings outside this Play session.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local passed, failed = 0, 0
local failures: { string } = {}

local function report(ok: boolean, name: string, detail: string?)
	if ok then
		passed += 1
		print(string.format("[QA] PASS %s%s", name, if detail then " (" .. detail .. ")" else ""))
	else
		failed += 1
		local line = string.format("%s%s", name, if detail then ": " .. detail else "")
		table.insert(failures, line)
		warn("[QA] FAIL " .. line)
	end
end

local function character(player: Player): (Model?, Humanoid?, BasePart?)
	local model = player.Character
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	return model, humanoid, root
end

local function waitAlive(player: Player): (Model, Humanoid, BasePart)
	while true do
		local model, humanoid, root = character(player)
		if model and humanoid and root and humanoid.Health > 0 then
			return model, humanoid, root
		end
		task.wait(0.5)
	end
end

local function phase(): string?
	return ReplicatedStorage:GetAttribute("Phase")
end

local function skipTo(wanted: string, seconds: number?): boolean
	local deadline = os.clock() + (seconds or 120)
	while phase() ~= wanted and os.clock() < deadline do
		workspace:SetAttribute("SkipPhase", true)
		task.wait(0.5)
	end
	task.wait(2)
	return phase() == wanted
end

local function promptPoint(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return nil
end

local function worldParams(exclude: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	return params
end

local function newPath(): Path
	return PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
end

-- A real path to within activation range, or the reason there isn't one. Many prompts sit on
-- solid things (a till, a crate), so it also tries the floor around them.
local function pathTo(from: Vector3, point: Vector3, range: number): (Path?, string?)
	local why = "no route"
	local reachOut = math.max(range * 0.7, 2)
	for _, offset in { Vector3.zero, Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local path = newPath()
		local goal = point + offset * reachOut
		local ok, err = pcall(function()
			path:ComputeAsync(from, goal)
		end)
		if not ok then
			why = tostring(err)
		elseif path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			local last = waypoints[#waypoints]
			if last and (last.Position + Vector3.new(0, 3, 0) - point).Magnitude <= range + 3 then
				return path, nil
			end
			why = "path ends out of range"
		else
			why = path.Status.Name
		end
	end
	return nil, why
end

local function enabledPrompts(): { ProximityPrompt }
	local list = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Enabled then
			table.insert(list, d)
		end
	end
	return list
end

-- ── what each stage checks ──────────────────────────────────────────────────

-- Things legitimately out of reach when a stage starts (the same list as tests/World.spec.luau).
local LOCKED = { L11Day = { ["Chip the Ice"] = true } }

local function checkPrompts(prefix: string, player: Player, key: string): { ProximityPrompt }
	local model, _, root = waitAlive(player)
	local reachable = {}
	local prompts = enabledPrompts()
	local bad, sightBad = {}, {}
	for i, prompt in prompts do
		local point = promptPoint(prompt)
		local locked = LOCKED[key] and LOCKED[key][prompt.ActionText]
		if point and not locked then
			local path, why = pathTo(root.Position, point, prompt.MaxActivationDistance)
			if path then
				table.insert(reachable, prompt)
				if prompt.RequiresLineOfSight then
					local waypoints = path:GetWaypoints()
					local eye = waypoints[#waypoints].Position + Vector3.new(0, 4.5, 0)
					local hit = workspace:Raycast(eye, point - eye, worldParams({ model, prompt.Parent :: Instance }))
					if
						hit
						and hit.Instance:FindFirstAncestorOfClass("Model")
							~= prompt.Parent:FindFirstAncestorOfClass("Model")
					then
						table.insert(
							sightBad,
							string.format("%q blocked by %s", prompt.ActionText, hit.Instance:GetFullName())
						)
					end
				end
			else
				table.insert(
					bad,
					string.format(
						"%q (%s) at %s: %s",
						prompt.ActionText,
						prompt.ObjectText,
						tostring(point),
						tostring(why)
					)
				)
			end
		end
		if i % 5 == 0 then
			task.wait() -- pathfinding has a budget
		end
	end
	report(
		#bad == 0,
		prefix .. " every enabled prompt has a real path",
		string.format("%d prompts. %s", #prompts, table.concat(bad, "; "))
	)
	report(#sightBad == 0, prefix .. " prompts needing line of sight can be seen", table.concat(sightBad, "; "))
	return reachable
end

-- A real character really walks there: collisions, doors, stairs, ramps.
local function checkWalks(prefix: string, player: Player, prompts: { ProximityPrompt }, count: number)
	if count <= 0 or #prompts == 0 or workspace:GetAttribute("QA_NoPhysics") then
		return
	end
	local _, _, root = waitAlive(player)
	table.sort(prompts, function(a, b)
		local pa, pb = promptPoint(a), promptPoint(b)
		return pa ~= nil and pb ~= nil and (pa - root.Position).Magnitude > (pb - root.Position).Magnitude
	end)
	for i = 1, math.min(count, #prompts) do
		local prompt = prompts[i]
		local point = promptPoint(prompt)
		local _, humanoid, walker = waitAlive(player)
		if point then
			local path = pathTo(walker.Position, point, prompt.MaxActivationDistance)
			local arrived = false
			if path then
				for _, waypoint in path:GetWaypoints() do
					if waypoint.Action == Enum.PathWaypointAction.Jump then
						humanoid.Jump = true
					end
					humanoid:MoveTo(waypoint.Position)
					local deadline = os.clock() + 8
					while os.clock() < deadline and (walker.Position - waypoint.Position).Magnitude > 5 do
						task.wait(0.1)
					end
				end
				arrived = (walker.Position - point).Magnitude <= prompt.MaxActivationDistance + 1
			end
			report(
				arrived,
				string.format("%s a character walks to %q", prefix, prompt.ActionText),
				string.format("ended %.1f studs away", (walker.Position - point).Magnitude)
			)
		end
	end
end

local function checkSpawns(prefix: string)
	local bad, count = {}, 0
	for _, tag in { "EnemySpawn", "FoodCourtSpawn" } do
		for _, point in CollectionService:GetTagged(tag) do
			if point:IsA("BasePart") then
				count += 1
				local hit = workspace:Raycast(point.Position, Vector3.new(0, -12, 0), worldParams({ point }))
				if not hit then
					table.insert(bad, tag .. " at " .. tostring(point.Position) .. " has no floor")
				end
				local overlap = OverlapParams.new()
				overlap.RespectCanCollide = true
				if
					#workspace:GetPartBoundsInBox(
						CFrame.new(point.Position + Vector3.new(0, 2, 0)),
						Vector3.new(2, 3, 2),
						overlap
					) > 0
				then
					table.insert(bad, tag .. " at " .. tostring(point.Position) .. " is inside something")
				end
			end
		end
	end
	report(
		#bad == 0,
		prefix .. " monster spawn points stand on open floor",
		string.format("%d points. %s", count, table.concat(bad, "; "))
	)
end

local function checkLevelSpecific(id: string, stage: string, prefix: string)
	if stage ~= "Night" then
		return
	end
	if id == "L14" or id == "L07" then
		task.wait(12) -- the intro
		local arenaName, modelName = "ChefArena", "GorgingChef"
		if id == "L07" then
			arenaName, modelName = "QueenArena", "ShadowQueen"
		end
		local arena = workspace:FindFirstChild(arenaName, true)
		local boss = arena and arena:FindFirstChild(modelName, true)
		report(boss ~= nil, prefix .. " the boss exists")
		if boss then
			local count = 0
			for _, part in boss:GetDescendants() do
				if part:IsA("BasePart") and part.Name:find("Weakpoint", 1, true) then
					count += 1
					local root = (boss :: Model).PrimaryPart
					local distance = root and (part.Position - root.Position).Magnitude or math.huge
					report(
						distance < 40,
						prefix .. " " .. part.Name .. " is on the body, welds intact",
						string.format("%.1f studs from root", distance)
					)
					local from = part.Position + Vector3.new(0, 2, 30)
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Include
					params.FilterDescendantsInstances = { boss }
					local hit = workspace:Raycast(from, part.Position - from, params)
					report(hit ~= nil, prefix .. " " .. part.Name .. " can be hit by a beam raycast")
				end
			end
			report(count > 0, prefix .. " the boss has weak points", tostring(count))
		end
	end
	if id == "L12" then
		local ramp = workspace:FindFirstChild("BasementRamp", true) :: BasePart?
		report(ramp ~= nil, prefix .. " the basement ramp exists")
		if ramp then
			local path = pathTo(Vector3.new(ramp.Position.X, 3, ramp.Position.Z - 30), ramp.Position, 60)
			report(path ~= nil, prefix .. " the basement ramp has a real path (BUG-01)")
		end
	end
end

local function checkMovers(prefix: string, seconds: number)
	-- monsters and shoppers really walk under the real Humanoid
	local function rootsIn(): { [BasePart]: Vector3 }
		local out = {}
		for _, model in workspace:GetDescendants() do
			if model:IsA("Humanoid") and model.Parent and not Players:GetPlayerFromCharacter(model.Parent) then
				local root = model.Parent:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					out[root] = root.Position
				end
			end
		end
		return out
	end
	local before = rootsIn()
	task.wait(seconds)
	local total, moved = 0, 0
	for root, position in before do
		if root.Parent then
			total += 1
			if (root.Position - position).Magnitude > 2 then
				moved += 1
			end
		end
	end
	if total > 0 then
		report(
			moved > 0,
			prefix .. " NPCs and monsters move on their own",
			string.format("%d of %d moved in %d s", moved, total, seconds)
		)
	end
end

-- ── one-off checks ──────────────────────────────────────────────────────────

local function checkOnce(player: Player)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	report(remotes ~= nil, "the Remotes folder exists")
	local names = {}
	for _, remote in (remotes and remotes:GetChildren()) or {} do
		table.insert(names, remote.Name)
	end
	report(#names >= 13, "all remotes are created", table.concat(names, ","))

	if workspace:GetAttribute("QA_NoPhysics") then
		return -- the fake engine's smoke test: nothing below means anything without real physics
	end
	-- conveyors (escalators) really carry a character
	local conveyors = {}
	for _, part in workspace:GetDescendants() do
		if part:IsA("BasePart") and part.Anchored and part.AssemblyLinearVelocity.Magnitude > 1 then
			table.insert(conveyors, part)
		end
	end
	report(#conveyors > 0, "escalators exist", tostring(#conveyors))
	local conveyor = conveyors[1]
	if conveyor then
		local model, _, root = waitAlive(player)
		local top = conveyor.Position + Vector3.new(0, conveyor.Size.Y / 2 + 3.2, 0)
		model:PivotTo(CFrame.new(top))
		task.wait(1.5)
		local carried = (root.Position - top) * conveyor.AssemblyLinearVelocity.Unit
		report(
			carried.X + carried.Y + carried.Z > 0.5 or root.Position.Y > top.Y,
			"an escalator carries a character",
			tostring(root.Position - top)
		)
	end

	-- nothing solid hanging in the void, nothing with broken numbers
	local bad = 0
	for _, part in workspace:GetDescendants() do
		if part:IsA("BasePart") then
			local p = part.Position
			if
				p.X ~= p.X
				or p.Y ~= p.Y
				or p.Z ~= p.Z
				or math.abs(p.X) > 5000
				or math.abs(p.Y) > 5000
				or math.abs(p.Z) > 5000
			then
				bad += 1
			end
		end
	end
	report(bad == 0, "no parts at impossible positions", tostring(bad))
end

-- ── the run ─────────────────────────────────────────────────────────────────

local function levelIds(): { string }
	local wanted = workspace:GetAttribute("QA_Levels")
	local list = {}
	if type(wanted) == "string" and wanted ~= "" then
		for id in wanted:gmatch("[^,%s]+") do
			table.insert(list, id)
		end
	else
		local Config = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
		for _, level in Config.Levels do
			if level.Implemented then
				table.insert(list, level.Id)
			end
		end
	end
	return list
end

local function run()
	local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
	while player:GetAttribute("DataLoaded") ~= true do
		task.wait(0.25)
	end
	if player:GetAttribute("DataMock") ~= true then
		warn("[QA] A real DataStore is connected (Studio API access is on). Stopping, so saved data can't be touched.")
		warn("[QA] Turn off Game Settings → Security → Enable Studio Access to API Services, then run again.")
		return
	end
	local walks = workspace:GetAttribute("QA_Walk")
	local walkCount = if type(walks) == "number" then walks else 3
	print("[QA] Night Shift Studio harness starting")
	checkOnce(player)
	for _, id in levelIds() do
		workspace:SetAttribute("MissionTest_Level", id)
		skipTo("Dawn", 120)
		local onLevel = skipTo("Day", 120) and ReplicatedStorage:GetAttribute("LevelId") == id
		report(onLevel, id .. " loads")
		if onLevel then
			for _, stage in { "Day", "Night" } do
				if stage == "Night" then
					skipTo("Night", 60)
				end
				local prefix = id .. " " .. stage .. ":"
				waitAlive(player)
				local reachable = checkPrompts(prefix, player, id .. stage)
				checkSpawns(prefix)
				checkLevelSpecific(id, stage, prefix)
				checkMovers(prefix, 15)
				checkWalks(prefix, player, reachable, walkCount)
			end
		end
	end
	print(string.format("[QA] DONE: %d passed, %d failed", passed, failed))
	for _, line in failures do
		warn("[QA] FAILED: " .. line)
	end
	workspace:SetAttribute("QA_Result", string.format("%d passed, %d failed", passed, failed))
end

task.spawn(function()
	local ok, err = xpcall(run, debug.traceback)
	if not ok then
		warn("[QA] harness crashed: " .. tostring(err))
		workspace:SetAttribute("QA_Result", "crashed")
	end
end)
