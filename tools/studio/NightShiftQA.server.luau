-- NIGHT SHIFT QA HARNESS: runs inside Roblox Studio, with the real engine: real collisions,
-- PathfindingService, raycasts, Humanoid walking, welds, conveyors. It exists to check what the
-- Lune simulation (tests/) can't. It is NOT part of the game: only qa.project.json includes it.
--
-- How to run (see docs/qa/STUDIO_HARNESS.md):
--   rojo build qa.project.json -o NightShiftQA.rbxl   then open it in Studio.
--   Run (F8): no player and no client, so nothing can freeze or disconnect. Every level's routes,
--     spawn points and collisions, walked by a rider the server simulates.
--   Play (F5): a real player. Adds what needs one: monsters, bosses, a client's physics.
-- Workspace attributes, all optional, set before pressing Run or Play:
--   QA_Batch  = 3           levels two at a time: 1 = L01,L02 ... 7 = L13,L14
--   QA_Levels = "L01,L12"   only these levels (default: all of them)
--   QA_From   = "L08"       resume: start at this level
--   QA_Stage  = "Night"     only this stage of each level
--   QA_Walk   = 3           prompts per stage a character walks to (default 3; 0 = none)
--   QA_EscalatorsOnly = true  only the one-off checks, including the escalator rides
--   QA_Riders = 2           wait for this many players, and ride together (Test → Clients and Servers)
--   QA_SessionLimit = 900   Play only: stop cleanly between levels after this many seconds (0 = never)
--   QA_StageLimit = 420     seconds one stage of one level may take in all
-- Results: lines starting [QA] in the Output window, as they happen, so a run that dies keeps them;
-- a coverage table at the end. The first line gives HARNESS_VERSION: if it isn't the number in
-- docs/qa/STUDIO_HARNESS.md, an old place file is open.
--
-- Safety: only runs in Studio; refuses to run if a real DataStore is connected, so it can't touch
-- saved data; never fires purchases, and never changes settings outside this session.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

if not RunService:IsStudio() then
	return
end

local HARNESS_VERSION = 5
local STAGE_LIMIT = 420
local SESSION_LIMIT = 900 -- under Roblox's 20-minute idle disconnect
local PROMPTS_LIMIT = 240
local CHECK_LIMIT = 60
local WALK_STEP_LIMIT = 200 -- three tries
local RESPAWN_LIMIT = 30 -- a character that doesn't come back after this long is a stuck run
local CLIENT_SILENT = 45 -- the helper script reports every 15 s
local PLAYER_LEFT = "QA_PLAYER_LEFT"
local CHARACTER_GONE = "QA_CHARACTER_GONE"

local serverMode = false -- Run (F8): no players, no client
local passed, failed, inconclusive, skipped = 0, 0, 0, 0
local failures: { string } = {}
local unclear: { string } = {}
local finished = false
local startedAt = os.clock()
local currentLevel: string? = nil
local currentStep = "starting"

-- What happened to each stage ("L05 Night"), for the coverage table at the end.
type StageLog = { Pass: number, Fail: number, Inconclusive: number, Skipped: number, Complete: boolean }
local stageLogs: { [string]: StageLog } = {}

local function stageLog(key: string): StageLog
	local log = stageLogs[key]
	if not log then
		log = { Pass = 0, Fail = 0, Inconclusive = 0, Skipped = 0, Complete = false }
		stageLogs[key] = log
	end
	return log
end

local function logFor(name: string): StageLog
	return stageLog(name:match("^(L%d+ %a+):") or "General")
end

-- One line per result, "[QA] STATUS name :: detail", printed at once. scripts/qa-studio-report.luau
-- merges these lines from any number of sessions.
local function resultLine(status: string, name: string, detail: string?): string
	return string.format("[QA] %s %s%s", status, name, if detail and detail ~= "" then " :: " .. detail else "")
end

local function report(ok: boolean, name: string, detail: string?)
	if finished then
		return
	end
	local log = logFor(name)
	if ok then
		passed += 1
		log.Pass += 1
		print(resultLine("PASS", name, detail))
	else
		failed += 1
		log.Fail += 1
		table.insert(failures, string.format("%s%s", name, if detail then ": " .. detail else ""))
		warn(resultLine("FAIL", name, detail))
	end
end

-- Measured nothing either way: neither a pass nor a game bug.
local function reportUnclear(name: string, detail: string)
	if finished then
		return
	end
	inconclusive += 1
	logFor(name).Inconclusive += 1
	table.insert(unclear, name .. ": " .. detail)
	warn(resultLine("INCONCLUSIVE", name, detail))
end

-- Not attempted, because this mode can't. Never counted as a pass.
local function reportSkipped(name: string, detail: string)
	if finished then
		return
	end
	skipped += 1
	logFor(name).Skipped += 1
	print(resultLine("SKIPPED", name, detail))
end

-- A checked box is true; someone may also have typed the word into a string attribute.
local function flag(name: string): boolean
	local value = workspace:GetAttribute(name)
	return value == true or (type(value) == "string" and value:lower() == "true")
end

local function elapsed(): string
	local seconds = os.clock() - startedAt
	return string.format("%dm%02ds", seconds // 60, seconds % 60)
end

local function character(player: Player): (Model?, Humanoid?, BasePart?)
	local model = player.Character
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	return model, humanoid, root
end

-- Waits for a living character, but never forever: the player may have left, or be stuck out.
local function waitAlive(player: Player): (Model, Humanoid, BasePart)
	local deadline = os.clock() + RESPAWN_LIMIT
	while true do
		if player.Parent ~= Players then
			error(PLAYER_LEFT, 0)
		end
		local model, humanoid, root = character(player)
		if model and humanoid and root and humanoid.Health > 0 then
			return model, humanoid, root
		end
		if os.clock() > deadline then
			error(CHARACTER_GONE, 0)
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

local function newPath(radius: number): Path
	return PathfindingService:CreatePath({ AgentRadius = radius, AgentHeight = 5, AgentCanJump = true })
end

-- A real path to within activation range, or the reason there isn't one. Many prompts sit on
-- solid things (a till, a crate), so it also tries the floor around them.
local function pathTo(from: Vector3, point: Vector3, range: number, radius: number?): (Path?, string?)
	local why = "no route"
	local reachOut = math.max(range * 0.7, 2)
	for _, offset in { Vector3.zero, Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local path = newPath(radius or 2)
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

local function checkPrompts(prefix: string, rider: any, key: string): { ProximityPrompt }
	local model, _, root = rider.Get()
	local reachable = {}
	local prompts = enabledPrompts()
	local bad, sightBad = {}, {}
	local waiting: { { Prompt: ProximityPrompt, Point: Vector3, Why: string? } } = {}

	local function found(prompt: ProximityPrompt, point: Vector3, path: Path)
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
				table.insert(sightBad, string.format("%q blocked by %s", prompt.ActionText, hit.Instance:GetFullName()))
			end
		end
	end

	for i, prompt in prompts do
		local point = promptPoint(prompt)
		local locked = LOCKED[key] and LOCKED[key][prompt.ActionText]
		if point and not locked then
			local path, why = pathTo(root.Position, point, prompt.MaxActivationDistance)
			if path then
				found(prompt, point, path)
			else
				table.insert(waiting, { Prompt = prompt, Point = point, Why = why })
			end
		end
		if i % 5 == 0 then
			task.wait() -- pathfinding has a budget
		end
	end

	-- Roblox rebuilds its navigation mesh a while after parts change, and a stage has just built and
	-- removed a lot of them. A route that appears later was never missing.
	local settled = 0
	for _, pause in { 5, 15 } do
		if #waiting > 0 then
			task.wait(pause)
			local still = {}
			for _, entry in waiting do
				local path, why = pathTo(root.Position, entry.Point, entry.Prompt.MaxActivationDistance)
				if path then
					settled += 1
					found(entry.Prompt, entry.Point, path)
				else
					entry.Why = why
					table.insert(still, entry)
				end
			end
			waiting = still
		end
	end

	-- Asks for a 4-stud wide route first. A character is about 2 wide, so a tighter gap still works.
	local narrow = 0
	for _, entry in waiting do
		local path = pathTo(root.Position, entry.Point, entry.Prompt.MaxActivationDistance, 1)
		if path then
			narrow += 1
			found(entry.Prompt, entry.Point, path)
		else
			table.insert(
				bad,
				string.format(
					"%q at %s (%s): %s, from %s, still after 20 s and with a narrower agent",
					entry.Prompt.ActionText,
					tostring(entry.Point),
					entry.Prompt:GetFullName(),
					tostring(entry.Why),
					tostring(root.Position)
				)
			)
		end
	end
	report(
		#bad == 0,
		prefix .. " every enabled prompt has a real path",
		string.format(
			"%d prompts, %d needed the navmesh to settle, %d only fit a narrower agent. %s",
			#prompts,
			settled,
			narrow,
			table.concat(bad, "; ")
		)
	)
	report(#sightBad == 0, prefix .. " prompts needing line of sight can be seen", table.concat(sightBad, "; "))
	return reachable
end

-- The nearest monster or NPC, and what's solid straight ahead: what the character got caught on.
local function surroundings(model: Model, root: BasePart): (string, boolean)
	local nearestName, nearest = "none", math.huge
	for _, d in workspace:GetDescendants() do
		if d:IsA("Humanoid") and d.Parent and d.Parent ~= model and not Players:GetPlayerFromCharacter(d.Parent) then
			local other = d.Parent:FindFirstChild("HumanoidRootPart") :: BasePart?
			if other and (other.Position - root.Position).Magnitude < nearest then
				nearest = (other.Position - root.Position).Magnitude
				nearestName = d.Parent.Name
			end
		end
	end
	local hit = workspace:Raycast(root.Position, root.CFrame.LookVector * 6, worldParams({ model }))
	local text = string.format(
		"at %s, ahead: %s, nearest NPC: %s (%.0f studs)",
		tostring(root.Position),
		if hit then hit.Instance:GetFullName() else "nothing",
		nearestName,
		nearest
	)
	return text, nearest < 12
end

local WALK_LIMIT = 60
local WAYPOINT_LIMIT = 8

-- One try. Returns whether it arrived, whether something outside the route spoiled the try, and why.
local function walkOnce(rider: any, stage: string, prompt: ProximityPrompt, point: Vector3): (boolean, boolean, string)
	local model, humanoid, walker = rider.Get()
	-- this checks the route, not the fight: monsters shouldn't decide it, so damage is off while walking
	local shield = Instance.new("ForceField")
	shield.Visible = false
	shield.Parent = model
	local path, why = pathTo(walker.Position, point, prompt.MaxActivationDistance)
	if not path then
		shield:Destroy()
		return false, false, "no route from " .. tostring(walker.Position) .. ": " .. tostring(why)
	end
	local waypoints = path:GetWaypoints()
	local stuckAt: number? = nil
	local stalls = 0
	local deadline = os.clock() + WALK_LIMIT
	for i, waypoint in waypoints do
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		humanoid:MoveTo(waypoint.Position)
		local setOffFrom = walker.Position
		local waypointDeadline = os.clock() + WAYPOINT_LIMIT
		while os.clock() < waypointDeadline and (walker.Position - waypoint.Position).Magnitude > 5 do
			task.wait(0.1)
			if model.Parent == nil or humanoid.Health <= 0 then
				return false, true, string.format("the character died at waypoint %d of %d", i, #waypoints)
			end
			if phase() ~= stage then
				shield:Destroy()
				return false,
					true,
					string.format(
						"the stage ended during the walk: now %s, at waypoint %d of %d",
						tostring(phase()),
						i,
						#waypoints
					)
			end
		end
		if (walker.Position - waypoint.Position).Magnitude > 5 then
			stuckAt = stuckAt or i
		end
		-- not moving at all: a jump may free it, but a second stall means it isn't getting anywhere
		if (walker.Position - setOffFrom).Magnitude < 2 and (walker.Position - waypoint.Position).Magnitude > 5 then
			stalls += 1
			humanoid.Jump = true
		else
			stalls = 0
		end
		if stalls >= 2 or os.clock() > deadline then
			break
		end
	end
	shield:Destroy()
	local distance = (walker.Position - point).Magnitude
	if distance <= prompt.MaxActivationDistance + 1 then
		return true, false, string.format("ended %.1f studs away", distance)
	end
	local around, npcClose = surroundings(model, walker)
	return false,
		npcClose,
		string.format(
			"ended %.1f studs away, first stuck at waypoint %s of %d, %s",
			distance,
			tostring(stuckAt or "none"),
			#waypoints,
			around
		)
end

local step: (string, number, () -> ()) -> boolean -- defined below, with the run

-- A real character really walks there: collisions, doors, stairs, ramps. A try spoiled by a monster
-- or a death is tried again; if every try is spoiled the route wasn't tested, which isn't a failure.
-- This level's own prompts come first. The mall's fixtures are walked once per level: they're the
-- same in both stages, and every prompt's route is still checked in every stage.
local function checkWalks(
	prefix: string,
	rider: any,
	stage: string,
	prompts: { ProximityPrompt },
	count: number,
	walkedInLevel: { [string]: boolean }
)
	if count <= 0 or #prompts == 0 or workspace:GetAttribute("QA_NoPhysics") then
		return
	end
	local _, _, root = rider.Get()
	local entries = {}
	for _, prompt in prompts do
		local point = promptPoint(prompt)
		local fullName = prompt:GetFullName()
		local fixture = fullName:find("^Workspace%.Mall%.") ~= nil
		if point and not (fixture and walkedInLevel[fullName]) then
			table.insert(entries, {
				Prompt = prompt,
				Point = point,
				FullName = fullName,
				Fixture = fixture,
				Distance = (point - root.Position).Magnitude,
			})
		end
	end
	table.sort(entries, function(a, b)
		if a.Fixture ~= b.Fixture then
			return b.Fixture
		end
		return a.Distance > b.Distance
	end)
	for i = 1, math.min(count, #entries) do
		local entry = entries[i]
		local name = string.format("%s a character walks to %q", prefix, entry.Prompt.ActionText)
		walkedInLevel[entry.FullName] = true
		local alive = step(name, WALK_STEP_LIMIT, function()
			local arrived, spoiled, detail = false, false, ""
			for attempt = 1, 3 do
				currentStep = string.format("%s, try %d", name, attempt)
				arrived, spoiled, detail = walkOnce(rider, stage, entry.Prompt, entry.Point)
				if arrived or phase() ~= stage then
					break
				end
			end
			if spoiled and not arrived then
				reportUnclear(name, detail)
			else
				report(arrived, name, entry.FullName .. ": " .. detail)
			end
		end)
		if not alive then
			return
		end
	end
end

-- Only at night: monsters only spawn then, and a level's daytime props may sit beside an unused
-- marker (L05's vault wall comes within half a stud of the one at -60, 3, 60, and is gone by night).
local function checkSpawns(prefix: string, stage: string)
	if stage ~= "Night" then
		return
	end
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
				local inside = {}
				for _, part in
					workspace:GetPartBoundsInBox(
						CFrame.new(point.Position + Vector3.new(0, 2, 0)),
						Vector3.new(2, 3, 2),
						overlap
					)
				do
					-- someone passing through a spawn point isn't a wall inside it
					local owner = part:FindFirstAncestorOfClass("Model")
					if part.Anchored and not (owner and owner:FindFirstChildOfClass("Humanoid")) then
						table.insert(inside, part:GetFullName())
					end
				end
				if #inside > 0 then
					table.insert(
						bad,
						tag .. " at " .. tostring(point.Position) .. " is inside " .. table.concat(inside, ", ")
					)
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
		local arenaName, modelName = "ChefArena", "GorgingChef"
		if id == "L07" then
			arenaName, modelName = "QueenArena", "ShadowQueen"
		end
		local boss = nil
		local introEnds = os.clock() + 12 -- at most the intro
		while not boss and os.clock() < introEnds do
			local arena = workspace:FindFirstChild(arenaName, true)
			boss = arena and arena:FindFirstChild(modelName, true)
			if not boss then
				task.wait(0.5)
			end
		end
		if boss or not serverMode then
			report(boss ~= nil, prefix .. " the boss exists")
		else
			reportSkipped(prefix .. " the boss exists", "needs a player: use Play")
		end
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

local MOVER_WATCH = 15 -- how long something gets to move before it counts as stuck
local MOVER_ARRIVAL = 12 -- a night's first monster can take a while (L05's Stalker: 8 s)
local MOVER_LIMIT = 45 -- a level's first waking monster, in Play (L10's first hatchlings: 16 to 24 s)
-- With nobody to hunt these stand where they are, by design (ParcelMimic's prowl).
local HUNTS_PLAYERS_ONLY = { ParcelMimic = true, ParcelMite = true }

-- Watches everything that's meant to walk, including whatever arrives during the check. Stops as soon
-- as something has moved: one mover answers the question. A sleeping mimic isn't meant to walk, and
-- with no player neither is anything that only hunts players; they aren't counted either way.
local function checkMovers(prefix: string, stage: string)
	local name = prefix .. " NPCs and monsters move on their own"
	local watched: { [BasePart]: { From: Vector3, Since: number } } = {}
	local started = os.clock()
	local total, moved, longest, waiting = 0, 0, 0, 0
	while true do
		total, moved, longest, waiting = 0, 0, 0, 0
		local now = os.clock()
		for _, humanoid in workspace:GetDescendants() do
			local owner = humanoid.Parent
			if
				humanoid:IsA("Humanoid")
				and owner
				and not Players:GetPlayerFromCharacter(owner)
				and not owner:GetAttribute("QA_Rider")
				and not owner:GetAttribute("Dead")
			then
				local root = owner:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (owner:GetAttribute("Disguised") or (serverMode and HUNTS_PLAYERS_ONLY[owner.Name])) then
					waiting += 1
				elseif root then
					local entry = watched[root]
					if not entry then
						entry = { From = root.Position, Since = now }
						watched[root] = entry
					end
					total += 1
					longest = math.max(longest, now - entry.Since)
					if (root.Position - entry.From).Magnitude > 2 then
						moved += 1
					end
				end
			end
		end
		local spent = now - started
		local patience = if waiting > 0 and not serverMode
			then MOVER_LIMIT
			elseif stage == "Night" then MOVER_ARRIVAL
			else 1
		if moved > 0 or longest >= MOVER_WATCH or spent >= MOVER_LIMIT or (total == 0 and spent >= patience) then
			break
		end
		task.wait(1)
	end
	local spent = os.clock() - started
	local counts = string.format("%d of %d moved in %.0f s, %d more waiting for a player", moved, total, spent, waiting)
	if moved > 0 or longest >= MOVER_WATCH then
		report(moved > 0, name, counts)
	elseif total > 0 then
		reportUnclear(name, "the check ran out of time before anything had long enough to move: " .. counts)
	elseif waiting > 0 and serverMode then
		reportSkipped(
			name,
			string.format("%d waiting for a player, by design (sleeping or hunting): use Play", waiting)
		)
	elseif waiting > 0 then
		reportUnclear(name, string.format("only %d sleeping, and nothing else appeared in %.0f s", waiting, spent))
	elseif serverMode then
		reportSkipped(name, "none appear without a player: use Play")
	end
end

-- ── escalators ──────────────────────────────────────────────────────────────

local CLIENT_START_TIMEOUT = 90 -- a slow laptop can take a while to load the mall
local RIDE_TIMEOUT = 20
local SETTLE = 0.6 -- a placed character lands before its ride is measured
local LEAVE_TIME = 2.5 -- how long a standing rider gets to step off at the far end
local RIDER_GAP = 8 -- studs between riders sharing an escalator
local MAX_STEP = 6 -- studs between two samples: more than this is a teleport, not a ride
local MAX_LATERAL = 1 -- side-to-side drift off the line of travel
local MAX_BOUNCE = 1.5 -- change in height above the moving surface
local MAX_BACKWARD = 0.5 -- total slipping against the direction of travel

-- A player's character is simulated by their client, and this server script only sees what that
-- client sends back. Until it is running, a character stays exactly where it was put, so nothing can
-- be measured. Lift the character a little and wait for gravity to bring it back.
local function clientSimulating(player: Player): boolean
	local model, _, root = waitAlive(player)
	local liftedY = root.Position.Y + 3
	model:PivotTo(root.CFrame + Vector3.new(0, 3, 0))
	local deadline = os.clock() + CLIENT_START_TIMEOUT
	while os.clock() < deadline do
		task.wait(0.1)
		if root.Position.Y < liftedY - 0.5 then
			task.wait(1)
			return true
		end
	end
	return false
end

-- Whatever is riding: a player's character, or the server's own test rider.
type Rider = { Name: string, Get: () -> (Model, Humanoid, BasePart) }

type Ride = {
	Reached: boolean,
	Left: boolean,
	Speed: number,
	MaxStep: number,
	Lateral: number,
	Bounce: number,
	Backward: number,
	Climb: number,
}

-- Puts a character on the ramp and samples it to the far end. `heading` is 1 to go with the belt and
-- -1 against it; `walk` makes the character walk that way instead of standing still.
local function rideOnce(rider: Rider, ramp: BasePart, heading: number, walk: boolean, slot: number): Ride
	local travel = ramp.AssemblyLinearVelocity.Unit
	local half = ramp.Size.Z / 2
	local surface = ramp.Position + ramp.CFrame.UpVector * ramp.Size.Y / 2
	local model, humanoid, root = rider.Get()
	humanoid:MoveTo(root.Position) -- cancels any walk left over from the ride before
	task.wait(0.3)

	local from = surface + travel * heading * (-half + 5 + (slot - 1) * RIDER_GAP)
	local to = surface + travel * heading * (half - 4)
	local at = from + Vector3.new(0, 3.2, 0)
	local flat = Vector3.new(travel.X, 0, travel.Z) * heading
	model:PivotTo(CFrame.lookAt(at, at + flat))
	task.wait(SETTLE)
	if walk then
		humanoid:MoveTo(to)
	end

	-- distance along the slope, from the horizontal position alone: it doesn't depend on how tall the
	-- character is, and a root above a slope is well ahead of its feet along it
	local flatTravel = Vector3.new(travel.X, 0, travel.Z)
	local function along(p: Vector3): number
		return Vector3.new(p.X - surface.X, 0, p.Z - surface.Z):Dot(flatTravel) / flatTravel:Dot(flatTravel) * heading
	end
	local goal = along(to) - 1.5
	local standHeight = root.Position.Y - (surface + travel * (along(root.Position) * heading)).Y
	local right, up = ramp.CFrame.RightVector, ramp.CFrame.UpVector
	local first, firstTime = root.Position, os.clock()
	local last, lastTime = first, firstTime
	local result: Ride = {
		Reached = false,
		Left = false,
		Speed = 0,
		MaxStep = 0,
		Lateral = 0,
		Bounce = 0,
		Backward = 0,
		Climb = 0,
	}
	local minSide, maxSide = (first - surface):Dot(right), (first - surface):Dot(right)
	local minUp, maxUp = (first - surface):Dot(up), (first - surface):Dot(up)
	local deadline = firstTime + RIDE_TIMEOUT
	while os.clock() < deadline do
		task.wait(0.1)
		local p = root.Position
		result.MaxStep = math.max(result.MaxStep, (p - last).Magnitude)
		result.Backward += math.max(along(last) - along(p), 0)
		local side, height = (p - surface):Dot(right), (p - surface):Dot(up)
		minSide, maxSide = math.min(minSide, side), math.max(maxSide, side)
		minUp, maxUp = math.min(minUp, height), math.max(maxUp, height)
		last, lastTime = p, os.clock()
		if along(p) >= goal then
			result.Reached = true
			break
		end
	end
	result.Speed = (along(last) - along(first)) / math.max(lastTime - firstTime, 0.1)
	result.Lateral = maxSide - minSide
	result.Bounce = maxUp - minUp
	result.Climb = last.Y - first.Y

	-- A rider doesn't stay on the ramp: it should end up standing at the far end, alive.
	if result.Reached and not walk then
		task.wait(LEAVE_TIME)
		local exit = surface + travel * half
		local height = root.Position.Y - exit.Y
		result.Left = along(root.Position) >= along(exit) - 2
			and math.abs(height - standHeight) < 2
			and humanoid.Health > 0
	end
	return result
end

local function describe(rider: Rider, r: Ride): string
	return string.format(
		"%s: speed %.1f, climb %.1f, biggest step %.1f, sideways %.1f, bounce %.1f, slipped %.1f, reached end %s, stepped off %s",
		rider.Name,
		r.Speed,
		r.Climb,
		r.MaxStep,
		r.Lateral,
		r.Bounce,
		r.Backward,
		tostring(r.Reached),
		tostring(r.Left)
	)
end

-- All riders go at once, so a multiplayer run shows the belt carries each of them.
local function rideTogether(
	name: string,
	riders: { Rider },
	ramp: BasePart,
	heading: number,
	walk: boolean,
	judge: (Ride) -> boolean
)
	local pending = #riders
	local ok = true
	local details = {}
	for slot, rider in riders do
		task.spawn(function()
			local ride = rideOnce(rider, ramp, heading, walk, slot)
			ok = ok and judge(ride)
			table.insert(details, describe(rider, ride))
			pending -= 1
		end)
	end
	local deadline = os.clock() + RIDE_TIMEOUT + LEAVE_TIME + 30
	while pending > 0 and os.clock() < deadline do
		task.wait(0.25)
	end
	report(ok and pending == 0, name, if pending > 0 then "a rider never finished" else table.concat(details, " | "))
end

-- A rider the server simulates itself, so no client is involved: nothing can be "still loading", and
-- what it does is Roblox's physics acting on the world directly. It uses the game's own Rig module,
-- as monsters do: a Humanoid set up by hand here once defaulted to R6, which can't stand without leg
-- parts, so it lay on its body block and slid. Sized like a player, and in the players' collision
-- group, so it fits and collides as a player does.
local function serverRider(): (any, Model)
	local Server = ServerScriptService:FindFirstChild("Server") :: Instance
	local Rig = require(Server:FindFirstChild("Enemies"):FindFirstChild("Rig") :: ModuleScript) :: any
	local CollisionGroups =
		require(Server:FindFirstChild("Util"):FindFirstChild("CollisionGroups") :: ModuleScript) :: any
	local model = Instance.new("Model")
	model.Name = "QA_Rider"
	model:SetAttribute("QA_Rider", true)
	local root = Rig.root(model, Vector3.new(2, 2, 1), 2)
	local head = Rig.part(model, {
		Name = "Head",
		Size = Vector3.new(2, 1, 1),
		CFrame = root.CFrame * CFrame.new(0, 1.5, 0),
		CanCollide = true,
	})
	Rig.weld(root, head)
	local humanoid = Rig.humanoid(model, 2, 16)
	CollisionGroups.assign(model, CollisionGroups.Players)
	model.Parent = workspace
	root:SetNetworkOwner(nil)
	return {
		Name = "server rider",
		Get = function()
			if model.Parent == nil then
				error(CHARACTER_GONE, 0)
			end
			return model, humanoid, root
		end,
	},
		model
end

local function standingRide(belt: number, rises: boolean): (Ride) -> boolean
	return function(r: Ride): boolean
		return r.Reached
			and r.MaxStep <= MAX_STEP
			and r.Lateral <= MAX_LATERAL
			and r.Bounce <= MAX_BOUNCE
			and r.Left
			and r.Speed >= belt * 0.6
			and r.Speed <= belt * 1.3
			and r.Backward <= MAX_BACKWARD
			and (r.Climb > 0) == rises
	end
end

local function rampOf(escalator: Instance): (BasePart?, number, string)
	local ramp = escalator:FindFirstChild("Ramp") :: BasePart?
	local belt = if ramp then ramp.AssemblyLinearVelocity.Magnitude else 0
	local rises = ramp ~= nil and ramp.AssemblyLinearVelocity.Y > 0
	return ramp, belt, escalator.Name .. if rises then " (up): " else " (down): "
end

-- What the helper script (NightShiftQAClient) has told us, per player.
local clientNews: { [Player]: { [string]: any } } = {}

local function checkEscalators()
	local models = CollectionService:GetTagged("Escalator")
	table.sort(models, function(a, b)
		return a.Name < b.Name
	end)
	report(#models > 0, "escalators exist", tostring(#models))

	-- First with no client involved at all.
	for _, escalator in models do
		local ramp, belt, prefix = rampOf(escalator)
		report(ramp ~= nil and belt > 1, prefix .. "the ramp is a conveyor", string.format("%.1f studs/s", belt))
		if ramp and belt > 1 then
			currentStep = prefix .. "server rider"
			local rider, model = serverRider()
			rideTogether(
				prefix .. "real physics carries a server-owned rider to the end",
				{ rider },
				ramp,
				1,
				false,
				standingRide(belt, ramp.AssemblyLinearVelocity.Y > 0)
			)
			model:Destroy()
		end
	end

	if serverMode then
		reportSkipped("escalators: real players' rides", "needs a client: use Play")
		return
	end

	-- Then real players, whose characters their own clients simulate.
	local wanted = workspace:GetAttribute("QA_Riders")
	local count = if type(wanted) == "number" then wanted else 1
	local deadline = os.clock() + CLIENT_START_TIMEOUT
	while #Players:GetPlayers() < count and os.clock() < deadline do
		task.wait(0.5)
	end
	local players = Players:GetPlayers()
	report(#players >= count, "escalators: all the riders joined", string.format("%d of %d", #players, count))

	local riders: { Rider } = {}
	for _, player in players do
		currentStep = "waiting for " .. player.Name .. "'s client"
		local live = clientSimulating(player)
		if live then
			table.insert(riders, {
				Name = player.Name,
				Get = function()
					return waitAlive(player)
				end,
			})
		else
			reportUnclear(
				"escalators: " .. player.Name .. "'s client never simulated the character",
				string.format("not within %d s, so that rider's rides weren't measured", CLIENT_START_TIMEOUT)
			)
		end

		-- the belt's speed has to reach the client: that's where a player's physics runs
		local news = clientNews[player]
		local waitUntil = os.clock() + 10
		while not (news and news.Ramps) and os.clock() < waitUntil do
			task.wait(0.25)
			news = clientNews[player]
		end
		if news and news.Ramps then
			for _, escalator in models do
				local _, belt, prefix = rampOf(escalator)
				local seen = news.Ramps[escalator.Name]
				report(
					type(seen) == "number" and math.abs(seen - belt) < 0.5,
					prefix .. "the belt's speed reaches " .. player.Name .. "'s client",
					string.format("server %.1f, client %s", belt, tostring(seen))
				)
			end
		else
			reportUnclear(player.Name .. "'s client view of the belts", "the helper script sent nothing")
		end
	end
	if #riders == 0 then
		return
	end

	for _, escalator in models do
		local ramp, belt, prefix = rampOf(escalator)
		if ramp and belt > 1 then
			local rises = ramp.AssemblyLinearVelocity.Y > 0
			local function smooth(r: Ride): boolean
				return r.Reached and r.MaxStep <= MAX_STEP and r.Lateral <= MAX_LATERAL and r.Bounce <= MAX_BOUNCE
			end
			currentStep = prefix .. "player rides"
			rideTogether(
				prefix .. "carries a standing character to the end",
				riders,
				ramp,
				1,
				false,
				standingRide(belt, rises)
			)
			rideTogether(prefix .. "walking with it is faster", riders, ramp, 1, true, function(r)
				return smooth(r) and r.Speed >= belt * 1.5
			end)
			rideTogether(prefix .. "walking against it still gets there", riders, ramp, -1, true, function(r)
				return smooth(r) and r.Speed >= 2 and r.Speed < 16 -- the belt slows a walker's 16 studs/s
			end)
		end
	end
end

-- ── one-off checks ──────────────────────────────────────────────────────────

local function checkOnce()
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
	-- a run aimed at particular levels leaves the rides out: they have their own run
	local aimed = workspace:GetAttribute("QA_From")
		or workspace:GetAttribute("QA_Levels")
		or workspace:GetAttribute("QA_Batch")
	if flag("QA_EscalatorsOnly") or not aimed then
		checkEscalators()
	else
		print("[QA] Aimed at particular levels: escalator rides left out (QA_EscalatorsOnly runs them)")
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

local BATCH_SIZE = 2

-- Which levels to run: QA_Batch or QA_Levels narrows the list, QA_From starts part-way through it.
local function levelIds(): { string }
	local Config = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
	local all = {}
	for _, level in Config.Levels do
		if level.Implemented then
			table.insert(all, level.Id)
		end
	end
	local list = all
	local wanted = workspace:GetAttribute("QA_Levels")
	local batch = workspace:GetAttribute("QA_Batch")
	if type(wanted) == "string" and wanted ~= "" then
		list = {}
		for id in wanted:gmatch("[^,%s]+") do
			report(table.find(all, id) ~= nil, "QA_Levels names a real level", id)
			if table.find(all, id) then
				table.insert(list, id)
			end
		end
	elseif type(batch) == "number" then
		local count = math.ceil(#all / BATCH_SIZE)
		local valid = batch == math.floor(batch) and batch >= 1 and batch <= count
		report(valid, "QA_Batch names a batch", string.format("%s of %d", tostring(batch), count))
		list = {}
		if valid then
			for i = (batch - 1) * BATCH_SIZE + 1, math.min(batch * BATCH_SIZE, #all) do
				table.insert(list, all[i])
			end
			print(
				string.format(
					"[QA] BATCH %d of %d: %s. %s",
					batch,
					count,
					table.concat(list, ","),
					if batch < count then string.format("Next: QA_Batch = %d", batch + 1) else "This is the last one."
				)
			)
		end
	end
	local from = workspace:GetAttribute("QA_From")
	if type(from) == "string" and from ~= "" then
		local index = table.find(list, from)
		report(index ~= nil, "QA_From names a level in this run", from)
		local rest = {}
		for i = index or #list + 1, #list do
			table.insert(rest, list[i])
		end
		return rest
	end
	return list
end

local function memoryText(): string
	local text = "memory n/a"
	pcall(function()
		local service: any = game:GetService("Stats")
		text = string.format("server memory %.0f MB", service:GetTotalMemoryUsageMb())
	end)
	return text
end

local function stats(label: string)
	local memory, instances = "n/a", "n/a"
	pcall(function()
		local service: any = game:GetService("Stats")
		memory = string.format("%.0f MB", service:GetTotalMemoryUsageMb())
		instances = tostring(service.InstanceCount)
	end)
	print(string.format("[QA] STAT %s: %s since start, memory %s, instances %s", label, elapsed(), memory, instances))
end

local plannedStages: { string } = {}

-- Exactly what this session did and didn't get to, whatever stopped it.
local function printCoverage()
	local complete, partial, notRun = {}, {}, {}
	for _, key in plannedStages do
		local log = stageLogs[key]
		if not log then
			table.insert(notRun, key)
			print(string.format("[QA] COVERAGE %s: NOT RUN", key))
		else
			table.insert(if log.Complete then complete else partial, key)
			print(
				string.format(
					"[QA] COVERAGE %s: %s, %d passed, %d failed, %d inconclusive, %d skipped",
					key,
					if log.Complete then "COMPLETE" else "PARTIAL",
					log.Pass,
					log.Fail,
					log.Inconclusive,
					log.Skipped
				)
			)
		end
	end
	print(
		string.format(
			"[QA] COVERAGE TOTAL: %d complete, %d partial, %d not run, of %d stages",
			#complete,
			#partial,
			#notRun,
			#plannedStages
		)
	)
end

-- Always called once at the end, however the run ends: the summary must not depend on a clean finish.
local function finish(stopReason: string?)
	if finished then
		return
	end
	finished = true
	workspace:SetAttribute("HoldPhase", false)
	if stopReason then
		warn(string.format("[QA] STOPPED after %s: %s, during: %s", elapsed(), stopReason, currentStep))
		for player, news in clientNews do
			warn(
				string.format(
					"[QA] Last news from %s's client: %.0f s ago, idle %.0f s, helper said: %s",
					player.Name,
					os.clock() - (news.At or 0),
					news.IdleSeconds or 0,
					tostring(news.Kind)
				)
			)
		end
		if currentLevel then
			warn(string.format('[QA] RESUME: on Workspace set QA_From = "%s" (string), then start again', currentLevel))
		end
	end
	printCoverage()
	local summary =
		string.format("%d passed, %d failed, %d inconclusive, %d skipped", passed, failed, inconclusive, skipped)
	print(string.format("[QA] %s: %s (%s)", if stopReason then "PARTIAL" else "DONE", summary, elapsed()))
	for _, line in failures do
		warn("[QA] FAILED: " .. line)
	end
	for _, line in unclear do
		warn("[QA] UNCLEAR: " .. line)
	end
	workspace:SetAttribute("QA_Result", if stopReason then "stopped: " .. summary else summary)
end

-- Runs fn with a time limit, so nothing can hang the run or stop the checks after it. Only the
-- player leaving ends the whole run.
step = function(label: string, limit: number, fn: () -> ()): boolean
	currentStep = label
	local done, problem = false, nil
	local thread = task.spawn(function()
		local ok, err = xpcall(fn, function(message)
			return if message == PLAYER_LEFT or message == CHARACTER_GONE
				then message
				else debug.traceback(tostring(message))
		end)
		done, problem = true, if ok then nil else err
	end)
	local deadline = os.clock() + limit
	while not done and not finished and os.clock() < deadline do
		task.wait(0.25)
	end
	if finished then
		return false
	end
	if not done then
		task.cancel(thread)
		reportUnclear(label, string.format("gave up after %d s, during: %s", limit, currentStep))
	elseif problem == PLAYER_LEFT then
		finish("the player left")
		return false
	elseif problem == CHARACTER_GONE then
		reportUnclear(label, string.format("no living character for %d s, during: %s", RESPAWN_LIMIT, currentStep))
	elseif problem then
		report(false, label .. " ran without an error in the harness", tostring(problem))
	end
	return true
end

-- Evidence for a disconnect: when each side went quiet, and what the run was doing at that moment.
local function watchHealth()
	local lastFrame = os.clock()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastFrame > 2 and not finished then
			warn(string.format("[QA] STALL server froze for %.1f s, during: %s", now - lastFrame, currentStep))
		end
		lastFrame = now
	end)
	task.spawn(function()
		while not finished do
			task.wait(5)
			for player, news in clientNews do
				local quiet = os.clock() - (news.At or 0)
				if quiet > CLIENT_SILENT and not news.Silent then
					news.Silent = os.clock()
					warn(
						string.format(
							"[QA] CLIENT SILENT %s: nothing for %.0f s, at %s, during: %s, %s",
							player.Name,
							quiet,
							elapsed(),
							currentStep,
							memoryText()
						)
					)
				end
			end
		end
	end)
end

local function run()
	local mode = workspace:GetAttribute("QA_Mode")
	local okMode, isRunMode = pcall(function()
		return RunService:IsRunMode()
	end)
	serverMode = mode == "Server" or (mode ~= "Play" and okMode and isRunMode == true)

	local player: Player? = nil
	if not serverMode then
		local deadline = os.clock() + 180
		while #Players:GetPlayers() == 0 and os.clock() < deadline do
			task.wait(0.25)
		end
		player = Players:GetPlayers()[1]
		if not player then
			finish("no player joined within 180 s")
			return
		end
		while player:GetAttribute("DataLoaded") ~= true and player.Parent == Players and os.clock() < deadline do
			task.wait(0.25)
		end
		if player:GetAttribute("DataLoaded") ~= true then
			finish("the player's data never loaded")
			return
		end
		if player:GetAttribute("DataMock") ~= true then
			warn(
				"[QA] A real DataStore is connected (Studio API access is on). Stopping, so saved data can't be touched."
			)
			warn("[QA] Turn off Game Settings → Security → Enable Studio Access to API Services, then run again.")
			return
		end
		local main = player
		Players.PlayerRemoving:Connect(function(leaving)
			if leaving == main then
				finish("the player disconnected")
			end
		end)
	end
	game:BindToClose(function()
		finish("the server shut down")
	end)

	-- Output from the helper script in the player's client (NightShiftQAClient).
	local fromClient = Instance.new("RemoteEvent")
	fromClient.Name = "QA_ClientReport"
	fromClient.Parent = ReplicatedStorage
	fromClient.OnServerEvent:Connect(function(sender: Player, kind: any, data: any)
		local news = clientNews[sender] or {}
		clientNews[sender] = news
		if news.Silent then
			print(string.format("[QA] CLIENT BACK %s after %.0f s", sender.Name, os.clock() - news.Silent))
			news.Silent = nil
		end
		news.Kind, news.At = tostring(kind), os.clock()
		if type(data) == "table" then
			news.IdleSeconds = data.IdleSeconds or news.IdleSeconds
			news.Ramps = data.Ramps or news.Ramps
		end
		if kind ~= "Alive" then
			print(string.format("[QA] CLIENT %s: %s %s", sender.Name, tostring(kind), tostring(data and data.Text)))
		end
	end)
	watchHealth()

	local walks = workspace:GetAttribute("QA_Walk")
	local walkCount = if type(walks) == "number" then walks else 3
	local limit = workspace:GetAttribute("QA_StageLimit")
	local stageLimit = if type(limit) == "number" then limit else STAGE_LIMIT
	local session = workspace:GetAttribute("QA_SessionLimit")
	local sessionLimit = if type(session) == "number" then session elseif serverMode then 0 else SESSION_LIMIT
	print(
		string.format(
			"[QA] Night Shift Studio harness version %d starting. MODE %s. QA_EscalatorsOnly=%s QA_Batch=%s QA_From=%s QA_Levels=%s QA_Stage=%s QA_Walk=%d QA_Riders=%s",
			HARNESS_VERSION,
			if serverMode then "Server" else "Play",
			tostring(flag("QA_EscalatorsOnly")),
			tostring(workspace:GetAttribute("QA_Batch")),
			tostring(workspace:GetAttribute("QA_From")),
			tostring(workspace:GetAttribute("QA_Levels")),
			tostring(workspace:GetAttribute("QA_Stage")),
			walkCount,
			tostring(workspace:GetAttribute("QA_Riders"))
		)
	)
	if not step("one-off checks", 600, checkOnce) then
		return
	end

	local stages = { "Day", "Night" }
	local onlyStage = workspace:GetAttribute("QA_Stage")
	if type(onlyStage) == "string" and onlyStage ~= "" then
		report(onlyStage == "Day" or onlyStage == "Night", "QA_Stage names a stage", onlyStage)
		stages = if onlyStage == "Day" or onlyStage == "Night" then { onlyStage } else {}
	end
	local ids = if flag("QA_EscalatorsOnly") then {} else levelIds()
	for _, id in ids do
		for _, stage in stages do
			table.insert(plannedStages, id .. " " .. stage)
		end
	end

	for _, id in ids do
		currentLevel = id
		if sessionLimit > 0 and os.clock() - startedAt > sessionLimit then
			finish(string.format("session limit of %d s reached, by design", sessionLimit))
			return
		end
		print(string.format('[QA] LEVEL %s starting (%s). If this run dies: QA_From = "%s"', id, elapsed(), id))
		local before = { passed, failed, inconclusive }
		local walkedInLevel = {}
		workspace:SetAttribute("MissionTest_Level", id)
		skipTo("Dawn", 120)
		local onLevel = skipTo("Day", 120) and ReplicatedStorage:GetAttribute("LevelId") == id
		report(onLevel, id .. " loads")
		if onLevel then
			-- A stage's clock mustn't end it halfway through a check; skipTo still moves things on.
			workspace:SetAttribute("HoldPhase", true)
			for _, stage in stages do
				if stage == "Night" then
					skipTo("Night", 60)
				end
				local key = id .. " " .. stage
				local prefix = key .. ":"
				local log = stageLog(key)
				local stageEnds = os.clock() + stageLimit
				local rider, riderModel = nil, nil
				if player then
					local main = player
					rider = {
						Name = main.Name,
						Get = function()
							return waitAlive(main)
						end,
					}
				else
					rider, riderModel = serverRider()
					local spawn = workspace:FindFirstChild("PlayerSpawn", true) :: BasePart?
					local at = if spawn then spawn.Position else Vector3.new(0, 1, -52)
					local placed: Model = riderModel
					placed:PivotTo(CFrame.new(at + Vector3.new(0, 3.2, 0)))
					task.wait(1)
				end

				-- Each check has its own limit, and the stage has one over all: a check that's stuck
				-- costs that check, not the ones after it.
				local function check(name: string, seconds: number, fn: () -> ()): boolean
					local left = stageEnds - os.clock()
					if left <= 0 then
						reportUnclear(
							prefix .. " " .. name,
							string.format("not run: the stage used up its %d s", stageLimit)
						)
						return true
					end
					return step(prefix .. " " .. name, math.min(seconds, math.ceil(left)), fn)
				end
				local reachable = {}
				local alive = check("prompts", PROMPTS_LIMIT, function()
					reachable = checkPrompts(prefix, rider, id .. stage)
				end) and check("spawns", CHECK_LIMIT, function()
					checkSpawns(prefix, stage)
				end) and check("level checks", CHECK_LIMIT, function()
					checkLevelSpecific(id, stage, prefix)
				end) and check("movers", CHECK_LIMIT, function()
					checkMovers(prefix, stage)
				end) and check("walks", stageLimit, function()
					checkWalks(prefix, rider, stage, reachable, walkCount, walkedInLevel)
				end)
				if riderModel then
					riderModel:Destroy()
				end
				if not alive then
					return
				end
				log.Complete = true
				print(string.format("[QA] STAGE %s COMPLETE", key))
				stats(prefix)
			end
		end
		print(
			string.format(
				"[QA] LEVEL %s finished: %d passed, %d failed, %d inconclusive",
				id,
				passed - before[1],
				failed - before[2],
				inconclusive - before[3]
			)
		)
	end
	finish()
end

task.spawn(function()
	local ok, err = xpcall(run, debug.traceback)
	if not ok then
		warn("[QA] harness crashed: " .. tostring(err))
		finish("the harness crashed")
	end
end)
