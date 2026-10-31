-- NIGHT SHIFT QA HARNESS: runs inside Roblox Studio, with the real engine: real collisions,
-- PathfindingService, raycasts, Humanoid walking, welds, conveyors. It exists to check what the
-- Lune simulation (tests/) can't. It is NOT part of the game: only qa.project.json includes it.
--
-- How to run (see docs/qa/STUDIO_HARNESS.md):
--   rojo build qa.project.json -o NightShiftQA.rbxl   then open it in Studio and press Play (F5).
-- Workspace attributes, all optional, set before pressing Play:
--   QA_Levels = "L01,L12"   only these levels (default: all of them; about 20 minutes)
--   QA_Walk   = 3           prompts per stage a real character walks to (default 3; 0 = none)
--   QA_EscalatorsOnly = true  only the one-off checks, including the escalator rides (about 3 minutes)
--   QA_From   = "L08"       resume: start at this level and skip the escalator rides
--   QA_Riders = 2           wait for this many players, and ride together (Test → Clients and Servers)
--   QA_StageLimit = 420     seconds one stage of one level may take before it's given up on
-- Results: lines starting [QA] in the Output window, and a summary at the end. The first line gives
-- HARNESS_VERSION: if it isn't the number in docs/qa/STUDIO_HARNESS.md, an old place file is open.
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

local HARNESS_VERSION = 3
local STAGE_LIMIT = 420
local RESPAWN_LIMIT = 30 -- a character that doesn't come back after this long is a stuck run
local PLAYER_LEFT = "QA_PLAYER_LEFT"
local CHARACTER_GONE = "QA_CHARACTER_GONE"

local passed, failed, inconclusive = 0, 0, 0
local failures: { string } = {}
local unclear: { string } = {}
local finished = false
local startedAt = os.clock()
local currentLevel: string? = nil
local currentStep = "starting"

local function report(ok: boolean, name: string, detail: string?)
	if finished then
		return
	end
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

-- For a result that says nothing either way: neither a pass nor a game bug.
local function reportUnclear(name: string, detail: string)
	if finished then
		return
	end
	inconclusive += 1
	local line = name .. ": " .. detail
	table.insert(unclear, line)
	warn("[QA] INCONCLUSIVE " .. line)
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

local function checkPrompts(prefix: string, player: Player, key: string): { ProximityPrompt }
	local model, _, root = waitAlive(player)
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
local function walkOnce(
	player: Player,
	stage: string,
	prompt: ProximityPrompt,
	point: Vector3
): (boolean, boolean, string)
	local model, humanoid, walker = waitAlive(player)
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
			if player.Character ~= model or humanoid.Health <= 0 then
				return false, true, string.format("the character died at waypoint %d of %d", i, #waypoints)
			end
			if phase() ~= stage then
				shield:Destroy()
				return false, true, "the stage ended during the walk"
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

-- A real character really walks there: collisions, doors, stairs, ramps. A try spoiled by a monster
-- or a death is tried again; if every try is spoiled the route wasn't tested, which isn't a failure.
local function checkWalks(prefix: string, player: Player, stage: string, prompts: { ProximityPrompt }, count: number)
	if count <= 0 or #prompts == 0 or workspace:GetAttribute("QA_NoPhysics") then
		return
	end
	local _, _, root = waitAlive(player)
	local entries = {}
	for _, prompt in prompts do
		local point = promptPoint(prompt)
		if point then
			table.insert(entries, { Prompt = prompt, Point = point, Distance = (point - root.Position).Magnitude })
		end
	end
	table.sort(entries, function(a, b)
		return a.Distance > b.Distance
	end)
	for i = 1, math.min(count, #entries) do
		local entry = entries[i]
		local name = string.format("%s a character walks to %q", prefix, entry.Prompt.ActionText)
		local arrived, spoiled, detail = false, false, ""
		for attempt = 1, 3 do
			currentStep = string.format("%s, try %d", name, attempt)
			arrived, spoiled, detail = walkOnce(player, stage, entry.Prompt, entry.Point)
			if arrived or phase() ~= stage then
				break
			end
		end
		if spoiled and not arrived then
			reportUnclear(name, detail)
		else
			report(arrived, name, detail)
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
-- what it does is Roblox's physics acting on the belt directly. Built like the game's monsters.
local function serverRider(): (Rider, Model)
	local model = Instance.new("Model")
	model.Name = "QA_Rider"
	model:SetAttribute("QA_Rider", true)
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 2
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model
	model.Parent = workspace
	root:SetNetworkOwner(nil)
	return {
		Name = "server rider",
		Get = function()
			return model, humanoid, root
		end,
	}, model
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
	if flag("QA_EscalatorsOnly") or not workspace:GetAttribute("QA_From") then
		checkEscalators()
	else
		print("[QA] Resuming with QA_From: escalator rides skipped")
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

-- Which levels to run: QA_Levels narrows the list, QA_From starts part-way through it.
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

local function stats(label: string)
	local memory, instances = "n/a", "n/a"
	pcall(function()
		local service: any = game:GetService("Stats")
		memory = string.format("%.0f MB", service:GetTotalMemoryUsageMb())
		instances = tostring(service.InstanceCount)
	end)
	print(string.format("[QA] STAT %s: %s since start, memory %s, instances %s", label, elapsed(), memory, instances))
end

-- Always called once at the end, however the run ends: the summary must not depend on a clean finish.
local function finish(stopReason: string?)
	if finished then
		return
	end
	finished = true
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
			warn(string.format('[QA] RESUME: on Workspace set QA_From = "%s" (string), then press Play', currentLevel))
		end
	end
	local summary = string.format("%d passed, %d failed, %d inconclusive", passed, failed, inconclusive)
	print(string.format("[QA] %s: %s (%s)", if stopReason then "PARTIAL" else "DONE", summary, elapsed()))
	for _, line in failures do
		warn("[QA] FAILED: " .. line)
	end
	for _, line in unclear do
		warn("[QA] UNCLEAR: " .. line)
	end
	workspace:SetAttribute("QA_Result", if stopReason then "stopped: " .. summary else summary)
end

-- Runs fn with a time limit, so nothing can hang the run. The player leaving ends the whole run.
local function step(label: string, limit: number, fn: () -> ()): boolean
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
	Players.PlayerRemoving:Connect(function(leaving)
		if leaving == player then
			finish("the player disconnected")
		end
	end)
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
		news.Kind, news.At = tostring(kind), os.clock()
		if type(data) == "table" then
			news.IdleSeconds = data.IdleSeconds or news.IdleSeconds
			news.Ramps = data.Ramps or news.Ramps
		end
		if kind == "Idled" or kind == "Ready" or kind == "Note" then
			print(string.format("[QA] CLIENT %s: %s %s", sender.Name, tostring(kind), tostring(data and data.Text)))
		end
	end)

	local walks = workspace:GetAttribute("QA_Walk")
	local walkCount = if type(walks) == "number" then walks else 3
	local limit = workspace:GetAttribute("QA_StageLimit")
	local stageLimit = if type(limit) == "number" then limit else STAGE_LIMIT
	print(
		string.format(
			"[QA] Night Shift Studio harness version %d starting. QA_EscalatorsOnly=%s QA_From=%s QA_Levels=%s QA_Walk=%d QA_Riders=%s",
			HARNESS_VERSION,
			tostring(flag("QA_EscalatorsOnly")),
			tostring(workspace:GetAttribute("QA_From")),
			tostring(workspace:GetAttribute("QA_Levels")),
			walkCount,
			tostring(workspace:GetAttribute("QA_Riders"))
		)
	)
	if not step("one-off checks", math.max(stageLimit, 600), checkOnce) then
		return
	end
	local ids = if flag("QA_EscalatorsOnly") then {} else levelIds()
	for _, id in ids do
		currentLevel = id
		print(string.format('[QA] LEVEL %s starting (%s). If this run dies: QA_From = "%s"', id, elapsed(), id))
		local before = { passed, failed, inconclusive }
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
				local alive = step(prefix .. " checks", stageLimit, function()
					waitAlive(player)
					currentStep = prefix .. " prompts"
					local reachable = checkPrompts(prefix, player, id .. stage)
					currentStep = prefix .. " spawns"
					checkSpawns(prefix, stage)
					currentStep = prefix .. " level checks"
					checkLevelSpecific(id, stage, prefix)
					currentStep = prefix .. " movers"
					checkMovers(prefix, 15)
					checkWalks(prefix, player, stage, reachable, walkCount)
				end)
				if not alive then
					return
				end
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
