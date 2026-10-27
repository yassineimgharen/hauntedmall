-- Level 3 night, "Impostors": Phantom Shoppers hide among trapped late-night shoppers.
--
-- 9 identical-looking shoppers wander the ground floor: 5 real, 4 Phantoms.
--   Tells   Phantoms blend in, then stalk a real shopper; they glitch (flicker), stare at
--           nearby players and talk in corrupted text. A stalked shopper panics ("😰").
--   Threat  a Phantom that stays next to its victim for TAKE_SECONDS takes them.
--   Counter hold the flashlight on a suspect: TO_UNMASK seconds unmasks a Phantom into a
--           pale crawler (an enemy that must be burned). A real shopper lit for ACCUSE
--           seconds shields their eyes: that's a false accusation (optional objective).

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local CombatService = require(script.Parent.Parent.Services.CombatService)
local CustomerService = require(script.Parent.Parent.Services.CustomerService)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)

local Impostors = {}

local REAL = 5
local PHANTOMS = 4
local TO_UNMASK = 1.5
local ACCUSE = 0.8
local TAKE_SECONDS = 5
local TAKE_RANGE = 4
local TIER = 3

-- ground-floor wander points, clear of the fountain, escalators and corridor planters
local POINTS = {
	Vector3.new(0, 0, 30),
	Vector3.new(0, 0, -30),
	Vector3.new(-18, 0, -28),
	Vector3.new(20, 0, -26),
	Vector3.new(-20, 0, 26),
	Vector3.new(18, 0, 30),
	Vector3.new(-45, 0, -45),
	Vector3.new(45, 0, -45),
	Vector3.new(-48, 0, 20),
	Vector3.new(48, 0, 30),
	Vector3.new(88, 0, -8),
	Vector3.new(126, 0, 6),
	Vector3.new(126, 0, -6),
	Vector3.new(160, 0, 6),
}

local CHATTER =
	{ "Hello? Anyone?", "Where's the exit?", "I just wanted shoes…", "Is the mall closed?", "My phone died…" }
local GLITCH = {
	"h̷e̷l̷l̷o̷",
	"🙂",
	"sh̴op̴ ̴w̴ith̴ ̴u̴s̴",
	"🙂🙂🙂",
	"c̸l̸o̸s̸i̸n̸g̸ ̸t̸i̸m̸e̸",
}

type Shopper = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Bubble: TextLabel,
	Phantom: boolean,
	Gone: boolean,
	Lit: number,
	LastLit: number,
	AccusedAt: number,
	Path: Path,
	Goal: Vector3?,
	Waypoints: { Vector3 }?,
	WaypointIndex: number,
	RepathAt: number,
	IdleUntil: number,
	-- phantoms
	Victim: Shopper?,
	StalkUntil: number,
	NextStalk: number,
	Taking: number,
	NextGlitch: number,
	-- real shoppers
	FleeUntil: number,
	PanicAt: number,
}

local shoppers: { Shopper } = {}
local folder: Folder? = nil
local token: {}? = nil
local rng = Random.new()

local function say(shopper: Shopper, text: string?, seconds: number?)
	local gui = shopper.Bubble.Parent and shopper.Bubble.Parent.Parent :: BillboardGui?
	if not gui then
		return
	end
	if text then
		shopper.Bubble.Text = text
		gui.Size = UDim2.fromOffset(math.clamp(#text * 9, 44, 200), 44)
		gui.Enabled = true
		local stamp = text
		task.delay(seconds or 3, function()
			if shopper.Bubble.Text == stamp then
				gui.Enabled = false
			end
		end)
	else
		gui.Enabled = false
	end
end

local function fadeOut(shopper: Shopper, color: Color3)
	shopper.Gone = true
	CombatService.UnregisterLightTarget(shopper.Model)
	shopper.Humanoid.WalkSpeed = 0
	for _, part in shopper.Model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.Color = part.Color:Lerp(color, 0.6)
			TweenService:Create(part, TweenInfo.new(1.4), { Transparency = 1 }):Play()
		end
	end
	task.delay(1.5, function()
		shopper.Model:Destroy()
	end)
end

local function alive(list: { Shopper }, phantom: boolean): { Shopper }
	local result = {}
	for _, shopper in list do
		if not shopper.Gone and shopper.Phantom == phantom then
			table.insert(result, shopper)
		end
	end
	return result
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- ── movement ────────────────────────────────────────────────────────────────

local function steer(shopper: Shopper, goal: Vector3, now: number)
	if not shopper.Goal or (shopper.Goal - goal).Magnitude > 4 or now > shopper.RepathAt then
		shopper.Goal = goal
		shopper.RepathAt = now + 3
		shopper.WaypointIndex = 1
		shopper.Waypoints = nil
		local path = shopper.Path
		local ok = pcall(function()
			path:ComputeAsync(shopper.Root.Position, goal)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local points = {}
			for i, waypoint in path:GetWaypoints() do
				if i > 1 then
					table.insert(points, waypoint.Position)
				end
			end
			shopper.Waypoints = points
		end
	end
	local waypoints = shopper.Waypoints
	if waypoints then
		local waypoint = waypoints[shopper.WaypointIndex]
		if waypoint and flatDistance(shopper.Root.Position, waypoint) < 2.5 then
			shopper.WaypointIndex += 1
			waypoint = waypoints[shopper.WaypointIndex]
		end
		shopper.Humanoid:MoveTo(waypoint or goal)
	else
		shopper.Humanoid:MoveTo(goal)
	end
end

local function randomPoint(from: Vector3): Vector3
	for _ = 1, 6 do
		local point = POINTS[rng:NextInteger(1, #POINTS)]
		if flatDistance(point, from) > 12 then
			return point + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		end
	end
	return POINTS[rng:NextInteger(1, #POINTS)]
end

local function wander(shopper: Shopper, now: number)
	if now < shopper.IdleUntil then
		shopper.Humanoid:MoveTo(shopper.Root.Position)
		return
	end
	local goal = shopper.Goal
	if not goal or flatDistance(shopper.Root.Position, goal) < 3 then
		shopper.IdleUntil = now + rng:NextNumber(2, 5)
		shopper.Goal = randomPoint(shopper.Root.Position)
		shopper.RepathAt = 0
		if not shopper.Phantom and rng:NextNumber() < 0.3 then
			say(shopper, CHATTER[rng:NextInteger(1, #CHATTER)])
		end
		return
	end
	steer(shopper, goal, now)
end

local function nearestPlayerRoot(position: Vector3, range: number): BasePart?
	local best, bestDistance = nil, range
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = root, distance
			end
		end
	end
	return best
end

-- ── outcomes ────────────────────────────────────────────────────────────────

local function unmask(shopper: Shopper, player: Player)
	if shopper.Gone then
		return
	end
	local position = shopper.Root.Position
	shopper.Gone = true
	CombatService.UnregisterLightTarget(shopper.Model)
	shopper.Model:Destroy()
	MissionEvents.record(player, "PhantomUnmasked")
	Notify.all(string.format("👻 %s unmasked a Phantom Shopper! Burn it!", player.DisplayName), "danger")
	Notify.effectAll("PhantomUnmasked", { Position = position })
	EnemyService.Spawn("PhantomShopper", Vector3.new(position.X, 0, position.Z), TIER)
end

local function take(victim: Shopper)
	if victim.Gone then
		return
	end
	say(victim, "😱")
	fadeOut(victim, Color3.fromRGB(60, 20, 90))
	MissionEvents.record(nil, "ShopperTaken")
	Notify.all(string.format("😱 A shopper was taken! (%d real shoppers left)", #alive(shoppers, false)), "danger")
end

local function onLit(shopper: Shopper, player: Player, dt: number)
	if shopper.Gone then
		return
	end
	local now = os.clock()
	shopper.LastLit = now
	shopper.Lit += dt
	if shopper.Phantom then
		if shopper.Lit >= TO_UNMASK then
			unmask(shopper, player)
		elseif rng:NextNumber() < 0.3 then
			say(shopper, "!!!", 0.6)
		end
	elseif shopper.Lit >= ACCUSE and now - shopper.AccusedAt > 6 then
		shopper.AccusedAt = now
		say(shopper, "🙈 Hey! I'm real!")
		MissionEvents.record(player, "FalseAccusation")
		Notify.player(player, "That was a real shopper. Watch who's following whom before you shine.", "warning")
		shopper.FleeUntil = now + 3
		shopper.Goal = randomPoint(shopper.Root.Position)
		shopper.RepathAt = 0
	end
end

-- ── behaviour ───────────────────────────────────────────────────────────────

local function glitch(shopper: Shopper)
	local parts: { [BasePart]: number } = {}
	for _, part in shopper.Model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			parts[part] = part.Transparency
		end
	end
	for _ = 1, 2 do
		for part in parts do
			part.Transparency = 0.75
		end
		task.wait(0.08)
		if shopper.Gone then
			return
		end
		for part, original in parts do
			part.Transparency = original
		end
		task.wait(0.1)
	end
	if rng:NextNumber() < 0.6 then
		say(shopper, GLITCH[rng:NextInteger(1, #GLITCH)], 2)
	end
end

local function thinkPhantom(shopper: Shopper, now: number)
	if now >= shopper.NextGlitch then
		shopper.NextGlitch = now + rng:NextNumber(6, 11)
		task.spawn(glitch, shopper)
	end
	local victim = shopper.Victim
	if victim and (victim.Gone or now > shopper.StalkUntil) then
		shopper.Victim = nil
		shopper.Taking = 0
		shopper.NextStalk = now + rng:NextNumber(12, 22)
		victim = nil
	end
	if not victim and now >= shopper.NextStalk then
		local candidates = alive(shoppers, false)
		if #candidates > 0 then
			victim = candidates[rng:NextInteger(1, #candidates)]
			shopper.Victim = victim
			shopper.StalkUntil = now + 22
		else
			shopper.NextStalk = now + 10
		end
	end
	if victim then
		local distance = flatDistance(shopper.Root.Position, victim.Root.Position)
		shopper.Humanoid.WalkSpeed = 13.5
		if distance < TAKE_RANGE then
			shopper.Taking += 0.25
			shopper.Humanoid:MoveTo(victim.Root.Position)
			if shopper.Taking >= TAKE_SECONDS then
				take(victim)
			end
		else
			shopper.Taking = math.max(0, shopper.Taking - 0.25)
			if distance < 14 then
				shopper.Humanoid:MoveTo(victim.Root.Position)
			else
				steer(shopper, victim.Root.Position, now)
			end
		end
		if distance < 10 and now - victim.PanicAt > 6 then
			victim.PanicAt = now
			say(victim, "😰 Someone's following me!")
			victim.FleeUntil = now + 2.5
			victim.Goal = randomPoint(victim.Root.Position)
			victim.RepathAt = 0
		end
		return
	end
	shopper.Humanoid.WalkSpeed = 12
	wander(shopper, now)
	if now < shopper.IdleUntil then -- the stare: idle Phantoms turn to watch you
		local root = nearestPlayerRoot(shopper.Root.Position, 25)
		if root then
			local flat = Vector3.new(root.Position.X, shopper.Root.Position.Y, root.Position.Z)
			shopper.Root.CFrame = CFrame.lookAt(shopper.Root.Position, flat)
		end
	end
end

local function thinkReal(shopper: Shopper, now: number)
	shopper.Humanoid.WalkSpeed = if now < shopper.FleeUntil then 17 else 12
	if now < shopper.FleeUntil then
		shopper.IdleUntil = 0
	end
	wander(shopper, now)
end

local function run(shopper: Shopper, myToken: {})
	while token == myToken and not shopper.Gone and shopper.Model.Parent do
		local now = os.clock()
		if now - shopper.LastLit > 0.3 then
			shopper.Lit = math.max(0, shopper.Lit - 0.25 * 0.5)
		end
		local ok, err = pcall(if shopper.Phantom then thinkPhantom else thinkReal, shopper, now)
		if not ok then
			warn("[Impostors] " .. tostring(err))
		end
		task.wait(0.25)
	end
end

-- ── level hooks ─────────────────────────────────────────────────────────────

local function clear()
	token = nil
	for _, shopper in shoppers do
		CombatService.UnregisterLightTarget(shopper.Model)
	end
	table.clear(shoppers)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function Impostors.StartNight()
	clear()
	local myToken = {}
	token = myToken
	local newFolder = Instance.new("Folder")
	newFolder.Name = "NightShoppers"
	newFolder.Parent = workspace
	folder = newFolder

	local roles = {}
	for _ = 1, REAL do
		table.insert(roles, false)
	end
	for _ = 1, PHANTOMS do
		table.insert(roles, true)
	end
	local spots = table.clone(POINTS)
	local now = os.clock()
	for _, phantom in roles do
		local spot = table.remove(spots, rng:NextInteger(1, #spots)) :: Vector3
		local npc = CustomerService.CreateNpc("Shopper", CFrame.new(spot + Vector3.new(0, 3, 0)), newFolder)
		if not npc then
			warn("[Impostors] shopper rigs not loaded; skipping a shopper")
			continue
		end
		local shopper: Shopper = {
			Model = npc.Model,
			Humanoid = npc.Humanoid,
			Root = npc.Root,
			Bubble = npc.Bubble,
			Phantom = phantom,
			Gone = false,
			Path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false }),
			Lit = 0,
			LastLit = 0,
			AccusedAt = 0,
			Goal = nil,
			Waypoints = nil,
			WaypointIndex = 1,
			RepathAt = 0,
			IdleUntil = now + rng:NextNumber(0, 3),
			Victim = nil,
			StalkUntil = 0,
			NextStalk = now + rng:NextNumber(18, 40), -- blend in first
			Taking = 0,
			NextGlitch = now + rng:NextNumber(4, 10),
			FleeUntil = 0,
			PanicAt = 0,
		}
		table.insert(shoppers, shopper)
		CombatService.RegisterLightTarget(npc.Model, function(player, dt)
			onLit(shopper, player, dt)
		end)
		task.spawn(run, shopper, myToken)
	end
end

function Impostors.EndNight()
	for _, shopper in shoppers do
		if not shopper.Gone then
			say(shopper, if shopper.Phantom then "🙂" else "😊 Thank you!")
			fadeOut(shopper, if shopper.Phantom then Color3.fromRGB(60, 20, 90) else Color3.new(1, 1, 1))
		end
	end
	token = nil
	local oldFolder = folder
	folder = nil
	table.clear(shoppers)
	task.delay(2, function()
		if oldFolder then
			oldFolder:Destroy()
		end
	end)
end

return Impostors
