-- Level 6 night, "Rescue Mission": escort and extraction.
--
--   * 4 shoppers are cocooned around the mall, each with a crawler guard. Hold E to cut
--     one free; it follows whoever freed it (if they fall, anyone can "Lead" it again).
--   * A shopper brought into the green EVAC ring counts as rescued and waits there for the
--     van. Hunter crawlers go after shoppers who are following or waiting; a shopper at
--     0 HP is lost (even one already waiting).
--   * 30 s before dawn the van is announced; at dawn (BeforeNightEnd) every player
--     standing in the ring has escaped. The player spawn is right beside the ring, so that
--     only counts for someone who has walked away from it (LEAVE_RADIUS) since they last
--     spawned: dying or standing idle at the entrance earns nothing.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local CustomerService = require(script.Parent.Parent.Services.CustomerService)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local Layout = require(script.Parent.Parent.World.Layout)
local NpcMover = require(script.Parent.NpcMover)

local Rescue = {}

local A = Layout.Atrium
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local EVAC = Vector3.new(0, 0, -62)
local EVAC_RADIUS = 9
local ESCAPE_RADIUS = 12
local ESCAPE_HEIGHT = 10 -- the ring is on the ground floor, not the balcony above it
local SHOPPER_HP = 80
local HIT = 10
local TIER = 5
local HUNT_EVERY = 18
local HUNTERS = 2 -- crawlers per hunt with two or more players
local HUNTERS_SOLO = 1
local SPAWN_CLEARANCE = 15 -- crawlers don't appear closer than this to a player
local LEAVE_RADIUS = 30 -- walk this far from the ring since spawning, or the van won't count you
local TRAPPED = {
	Vector3.new(-50, 0, 40),
	Vector3.new(52, A.BalconyY, 30),
	Vector3.new(172, 0, -2),
	Vector3.new(-46, 0, -98),
}

type State = "Trapped" | "Following" | "Stranded" | "Waiting" | "Lost"
type Evacuee = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Bubble: TextLabel,
	Mover: NpcMover.Mover,
	Prompt: ProximityPrompt,
	Cocoon: { BasePart },
	State: State,
	Leader: Player?,
	HP: number,
	Slot: Vector3,
	Goal: EnemyService.Goal,
}

local folder: Folder? = nil
local token: {}? = nil
local evacuees: { Evacuee } = {}
local rng = Random.new()
local tracking: {}? = nil
local walkedOut: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local told: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function isNight(): boolean
	return token ~= nil and GameStateService.GetPhase() == "Night"
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function say(evacuee: Evacuee, text: string)
	local gui = evacuee.Bubble.Parent and evacuee.Bubble.Parent.Parent :: BillboardGui?
	if gui then
		evacuee.Bubble.Text = text
		gui.Size = UDim2.fromOffset(math.clamp(#text * 9, 44, 220), 44)
		gui.Enabled = true
	end
end

local function rootOf(player: Player?): BasePart?
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function playerWithin(position: Vector3, range: number): boolean
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and (root.Position - position).Magnitude < range then
			return true
		end
	end
	return false
end

local function waitingCount(): number
	local count = 0
	for _, evacuee in evacuees do
		if evacuee.State == "Waiting" then
			count += 1
		end
	end
	return count
end

-- ── outcomes ────────────────────────────────────────────────────────────────

local function lose(evacuee: Evacuee)
	if evacuee.State == "Lost" then
		return
	end
	evacuee.State = "Lost"
	evacuee.Prompt.Enabled = false
	say(evacuee, "😱")
	MissionEvents.record(nil, "EvacueeLost")
	Notify.all("😱 A shopper was dragged into the dark!", "danger")
	for _, part in evacuee.Model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			TweenService:Create(part, TweenInfo.new(1.2), { Transparency = 1 }):Play()
		end
	end
	task.delay(1.4, function()
		evacuee.Model:Destroy()
	end)
end

local function hurt(evacuee: Evacuee)
	if evacuee.State ~= "Following" and evacuee.State ~= "Waiting" and evacuee.State ~= "Stranded" then
		return
	end
	evacuee.HP -= HIT
	evacuee.Model:SetAttribute("HP", evacuee.HP)
	if evacuee.HP <= 0 then
		lose(evacuee)
	else
		say(evacuee, string.format("😨 Help! (%d%%)", math.ceil(evacuee.HP / SHOPPER_HP * 100)))
	end
end

-- ── building ────────────────────────────────────────────────────────────────

local function buildEvac(parent: Instance)
	local ring = Builder.decor({
		Name = "EvacRing",
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, EVAC_RADIUS * 2, EVAC_RADIUS * 2),
		CFrame = CFrame.new(EVAC + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.NeonGreen,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
	})
	Builder.light("PointLight", ring, { Range = 20, Brightness = 1.5, Color = Palette.NeonGreen })
	for _, side in { -1, 1 } do
		Builder.part({
			Parent = parent,
			Size = Vector3.new(0.5, 9, 0.5),
			CFrame = CFrame.new(EVAC + Vector3.new(side * (EVAC_RADIUS + 1), 4.5, 0)),
			Color = Palette.DarkMetal,
			Material = Enum.Material.Metal,
		})
	end
	local sign = Builder.decor({
		Parent = parent,
		Size = Vector3.new(EVAC_RADIUS * 2 + 2, 2.2, 0.3),
		CFrame = CFrame.lookAt(EVAC + Vector3.new(0, 9.5, 0), EVAC + Vector3.new(0, 9.5, 10)),
		Color = Color3.fromRGB(14, 30, 20),
	})
	Builder.label(sign, Enum.NormalId.Front, "🚐 EVAC POINT", { Color = Palette.NeonGreen, Font = FONT })
	Builder.label(sign, Enum.NormalId.Back, "🚐 EVAC POINT", { Color = Palette.NeonGreen, Font = FONT })
end

local function spawnEvacuee(parent: Instance, position: Vector3, index: number)
	local npc = CustomerService.CreateNpc("Trapped", CFrame.new(position + Vector3.new(0, 3, 0)), parent)
	if not npc then
		warn("[Rescue] shopper rigs not loaded; skipping a trapped shopper")
		return
	end
	npc.Humanoid.WalkSpeed = 0
	local cocoon = {}
	for i = 1, 4 do
		table.insert(
			cocoon,
			Builder.decor({
				Name = "Cocoon",
				Parent = npc.Model,
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * (if i == 1 then 5.5 else 3.2),
				CFrame = CFrame.new(position + Vector3.new(0, if i == 1 then 3 else 1 + i, 0))
					* CFrame.new(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6)),
				Color = Color3.fromRGB(235, 230, 245),
				Material = Enum.Material.Fabric,
				Transparency = 0.35,
			})
		)
	end
	local slotAngle = (index - 1) / #TRAPPED * math.pi * 2
	local prompt = Builder.prompt(npc.Root, {
		Name = "RescuePrompt",
		ActionText = "Cut Free",
		ObjectText = "Trapped Shopper",
		HoldDuration = 3,
		MaxActivationDistance = 8,
	})
	local evacuee: Evacuee
	evacuee = {
		Model = npc.Model,
		Humanoid = npc.Humanoid,
		Root = npc.Root,
		Bubble = npc.Bubble,
		Mover = NpcMover.new(npc.Humanoid, npc.Root),
		Prompt = prompt,
		Cocoon = cocoon,
		State = "Trapped",
		Leader = nil,
		HP = SHOPPER_HP,
		Slot = EVAC + Vector3.new(math.cos(slotAngle) * 4, 0, math.sin(slotAngle) * 4),
		Goal = {
			Position = position,
			Alive = function()
				local state = evacuee.State
				return token ~= nil and (state == "Following" or state == "Waiting" or state == "Stranded")
			end,
			Hit = function()
				hurt(evacuee)
			end,
		},
	}
	npc.Model:SetAttribute("HP", SHOPPER_HP)
	npc.Model:SetAttribute("MaxHP", SHOPPER_HP)
	table.insert(evacuees, evacuee)
	say(evacuee, "🆘 Help me!")

	prompt.Triggered:Connect(function(player)
		if not isNight() then
			return
		end
		if evacuee.State == "Trapped" then
			for _, part in evacuee.Cocoon do
				part:Destroy()
			end
			evacuee.Humanoid.WalkSpeed = 15
			MissionEvents.record(player, "ShopperFreed")
			Notify.all(
				string.format("✂️ %s cut a shopper free! Lead them to the EVAC ring.", player.DisplayName),
				"success"
			)
		elseif evacuee.State ~= "Stranded" then
			return
		end
		evacuee.State = "Following"
		evacuee.Leader = player
		prompt.Enabled = false
		say(evacuee, "🙏 I'll follow you!")
	end)

	-- the guard
	local guardAt = position + Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(6, 9))
	task.delay(3, function()
		-- never on top of someone: it turns up once they've moved off
		while isNight() and playerWithin(guardAt, SPAWN_CLEARANCE) do
			task.wait(1)
		end
		if isNight() then
			EnemyService.Spawn("ShadowCrawler", guardAt, TIER)
		end
	end)
end

-- ── behaviour ───────────────────────────────────────────────────────────────

local function think(evacuee: Evacuee)
	local state = evacuee.State
	evacuee.Goal.Position = evacuee.Root.Position
	if state == "Following" then
		local leaderRoot = rootOf(evacuee.Leader)
		if not leaderRoot then
			evacuee.State = "Stranded"
			evacuee.Leader = nil
			evacuee.Prompt.ActionText = "Lead Me"
			evacuee.Prompt.HoldDuration = 0
			evacuee.Prompt.Enabled = true
			evacuee.Humanoid:MoveTo(evacuee.Root.Position)
			say(evacuee, "😰 Don't leave me here!")
			return
		end
		if flatDistance(evacuee.Root.Position, EVAC) < EVAC_RADIUS then
			evacuee.State = "Waiting"
			MissionEvents.record(evacuee.Leader, "ShopperRescued")
			evacuee.Leader = nil
			say(evacuee, "😊 Thank you! I'll wait for the van.")
			Notify.all(string.format("🚐 A shopper reached the EVAC point (%d waiting).", waitingCount()), "success")
			return
		end
		if flatDistance(evacuee.Root.Position, leaderRoot.Position) > 6 then
			evacuee.Mover:steer(leaderRoot.Position)
		else
			evacuee.Humanoid:MoveTo(evacuee.Root.Position)
		end
	elseif state == "Waiting" then
		if flatDistance(evacuee.Root.Position, evacuee.Slot) > 2 then
			evacuee.Humanoid:MoveTo(evacuee.Slot)
		end
	end
end

local function nearestSpawnFrom(target: Vector3): Vector3?
	local best, bestDistance = nil, math.huge
	for _, point in CollectionService:GetTagged("EnemySpawn") do
		local position = (point :: BasePart).Position
		local distance = (position - target).Magnitude
		if distance >= 25 and distance < bestDistance and not playerWithin(position, SPAWN_CLEARANCE) then
			best, bestDistance = position, distance
		end
	end
	return best
end

local function runHunters(myToken: {})
	task.wait(15)
	while token == myToken do
		local exposed = {}
		for _, evacuee in evacuees do
			if evacuee.Goal.Alive() then
				table.insert(exposed, evacuee)
			end
		end
		if #exposed > 0 then
			local victim = exposed[rng:NextInteger(1, #exposed)]
			local from = nearestSpawnFrom(victim.Root.Position)
			if from then
				Notify.all("👁️ Crawlers caught the scent of a shopper!", "danger")
				-- a lone player can't guard the ring and fetch the next shopper at once
				for _ = 1, if #Players:GetPlayers() >= 2 then HUNTERS else HUNTERS_SOLO do
					if EnemyService.AliveCount() < 14 then
						local enemy = EnemyService.Spawn("ShadowCrawler", Vector3.new(from.X, from.Y - 3, from.Z), TIER)
						if enemy then
							enemy.Goal = victim.Goal
						end
					end
				end
			end
		end
		local waited = 0
		while waited < HUNT_EVERY and token == myToken do
			task.wait(0.5)
			waited += 0.5
		end
	end
end

local function run(myToken: {})
	local warned = false
	while token == myToken do
		for _, evacuee in evacuees do
			if evacuee.State ~= "Lost" and evacuee.Model.Parent then
				local ok, err = pcall(think, evacuee)
				if not ok then
					warn("[Rescue] " .. tostring(err))
				end
			end
		end
		local remaining = (ReplicatedStorage:GetAttribute("PhaseStartedAt") or 0)
			+ (ReplicatedStorage:GetAttribute("PhaseDuration") or 0)
			- workspace:GetServerTimeNow()
		if not warned and remaining <= 30 then
			warned = true
			Notify.all("🚐 The evac van arrives in 30 seconds! Everyone into the EVAC ring!", "warning")
		end
		task.wait(0.25)
	end
end

-- ── who walked away from the entrance ───────────────────────────────────────

local function trackWalkers(myTracking: {})
	while tracking == myTracking do
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			local character = player.Character
			if root and character then
				if flatDistance(root.Position, EVAC) >= LEAVE_RADIUS then
					walkedOut[character] = true
				end
				local mustWalk = walkedOut[character] ~= true
				if player:GetAttribute("EvacMustWalk") ~= mustWalk then
					player:SetAttribute("EvacMustWalk", mustWalk)
				end
				if mustWalk and not told[character] and isNight() then
					told[character] = true
					Notify.player(
						player,
						"🚐 The van only takes people who came back to it: head out into the mall before you return.",
						"info"
					)
				end
			end
		end
		task.wait(0.25)
	end
end

local function startTracking()
	if not tracking then
		local myTracking = {}
		tracking = myTracking
		task.spawn(trackWalkers, myTracking)
	end
end

-- ── level hooks ─────────────────────────────────────────────────────────────

local function clear()
	token = nil
	table.clear(evacuees)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function Rescue.StartDay()
	startTracking()
end

function Rescue.StartNight()
	clear()
	startTracking()
	local myToken = {}
	token = myToken
	local newFolder = Instance.new("Folder")
	newFolder.Name = "RescueNight"
	newFolder.Parent = workspace
	folder = newFolder
	buildEvac(newFolder)
	for index, position in TRAPPED do
		spawnEvacuee(newFolder, position, index)
	end
	task.spawn(run, myToken)
	task.spawn(runHunters, myToken)
end

-- Dawn: the van leaves with everyone standing in the ring.
function Rescue.BeforeNightEnd()
	if not token then
		return
	end
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local character = player.Character
		if
			root
			and character
			and walkedOut[character]
			and flatDistance(root.Position, EVAC) < ESCAPE_RADIUS
			and math.abs(root.Position.Y - EVAC.Y) < ESCAPE_HEIGHT
		then
			MissionEvents.record(player, "Escaped")
		end
	end
end

function Rescue.EndNight()
	clear()
	tracking = nil
	for _, player in Players:GetPlayers() do
		player:SetAttribute("EvacMustWalk", nil)
	end
end

return Rescue
