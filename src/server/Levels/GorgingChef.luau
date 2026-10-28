-- Level 14 (Chapter 2 finale): Day "Patient Zero" / Night "The Gorging Chef".
--
-- Day:   infected growths sprout around the food court. Take a sample from each (hold E)
--        between its spits (a green circle warns). With four samples, brew the antidote in
--        Slice of Night's kitchen: Chop → Boil → Bottle, in order. Then the infection's veins
--        light up and lead to the grand kitchen, sealed shut by a fleshy membrane: peek
--        through it (hold E) to see the source.
-- Night: the boss. The Gorging Chef is greased: light slides off (ChefLogic). Cook a dish
--        at a stove, lace it at a green antidote vat, and put it on the serving pass before
--        he bellows ORDER UP. A laced meal makes him SICK: burn him. A plain dish heals him;
--        an empty pass makes him RAVENOUS. Cleaver chops (red lanes) and thrown pans (red
--        circles) all phase; grease spills and meatballs from phase 2; stove flares in
--        phase 3. Defeating him finishes Chapter 2 (MissionService pays the chapter reward).
--
-- Studio helper (Workspace attribute, set before the night): ChefTest_Phase = 2 or 3.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local CombatService = require(script.Parent.Parent.Services.CombatService)
local DataService = require(script.Parent.Parent.Services.DataService)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
local ProgressionService = require(script.Parent.Parent.Services.ProgressionService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Telegraph = require(script.Parent.Parent.Util.Telegraph)
local Builder = require(script.Parent.Parent.World.Builder)
local Carry = require(script.Parent.Carry)
local ChefLogic = require(script.Parent.ChefLogic)
local FoodCourtRules = require(script.Parent.FoodCourtRules)

local GorgingChef = {}

local T = ChefLogic.Tuning
local D = FoodCourtRules.L14
local FL = EnemyConfig.Flashlight
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local INFECTION = Color3.fromRGB(170, 60, 255)
local SICK = Color3.fromRGB(120, 255, 90)
local JACKET = Color3.fromRGB(236, 232, 224)
local DEFEAT_DAWN_SECONDS = 12

local ARENA = { MinX = -242, MaxX = -192, MinZ = -24, MaxZ = 24 }
local HOME = Vector3.new(-220, 0, 0)
local PASS = CFrame.lookAt(Vector3.new(-236, 0, 0), Vector3.new(-200, 0, 0))
local EAT_SPOT = Vector3.new(-230, 0, 0)
local VATS = { Vector3.new(-198, 0, -18), Vector3.new(-198, 0, 18) }
local STOVES = {
	CFrame.lookAt(Vector3.new(-229, 0, -30.2), Vector3.new(-229, 0, 0)),
	CFrame.lookAt(Vector3.new(-211, 0, -30.2), Vector3.new(-211, 0, 0)),
	CFrame.lookAt(Vector3.new(-220, 0, 30.2), Vector3.new(-220, 0, 0)),
}
local MEATBALL_SPAWNS = {
	Vector3.new(-244, 0, -40),
	Vector3.new(-244, 0, 40),
	Vector3.new(-190, 0, -40),
	Vector3.new(-190, 0, 40),
}
local GROWTHS = {
	Vector3.new(-120, 0, -40),
	Vector3.new(-170, 0, 40),
	Vector3.new(-141, 0, 85),
	Vector3.new(-129, 0, -112),
	Vector3.new(-217, 0, -70),
}
local BREW = {
	Chop = Vector3.new(-150, 0, -57.5),
	Boil = Vector3.new(-141, 0, -57.5),
	Bottle = Vector3.new(-132, 0, -57.5),
}
-- the grand kitchen's doors (sealed by day): centre, size
local SEALS = {
	{ CFrame.new(-184, 7, 0), Vector3.new(1, 14, 12), true },
	{ CFrame.new(-184, 6, -25), Vector3.new(1, 12, 10) },
	{ CFrame.new(-184, 6, 25), Vector3.new(1, 12, 10) },
	{ CFrame.new(-206, 5, -48), Vector3.new(12, 10, 1) },
	{ CFrame.new(-218, 5, 48), Vector3.new(12, 10, 1) },
}

local dayFolder: Folder? = nil
local nightFolder: Folder? = nil
local dayToken: {}? = nil
local nightToken: {}? = nil
local chef: Model? = nil
local chefRoot: BasePart? = nil
local chefParts: { [string]: any } = {}
local fight: ChefLogic.Fight? = nil
local motion: RBXScriptConnection? = nil
local dying = false
local active = false -- false during the intro: he does nothing
local mode = "Idle"
local position = HOME
local facing = Vector3.new(1, 0, 0)
local pose = { Lunge = 0, Sick = false }
local blockedAt: { [Player]: number } = {}
local toldBlocked: { [Player]: boolean } = {}
local pendingDamage: { [Player]: { Amount: number, Position: Vector3 } } = {}
local greasePools: { { Center: Vector3, Until: number } } = {}
local passDish: BasePart? = nil
local rng = Random.new()

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function toServer(clock: number): number
	return serverNow() + (clock - os.clock())
end

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function markDone(part: BasePart, prompt: ProximityPrompt?)
	part:SetAttribute("Done", true)
	if prompt then
		prompt:SetAttribute("Done", true)
		prompt.Enabled = false
	end
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- ── the chef (procedural; anchored root moved by CFrame, everything welded to it) ────

local function buildChef(parent: Instance, at: CFrame): (Model, BasePart, { BasePart }, { number })
	local model = Instance.new("Model")
	model.Name = "GorgingChef"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 2, 2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3, props: { [string]: any }?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = offset
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = true
		for key, value in (props or {}) :: { [string]: any } do
			(p :: any)[key] = value
		end
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	local function ball(name: string, size: Vector3, offset: CFrame, color: Color3, props: { [string]: any }?): BasePart
		local p = part(name, size, offset, color, props)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		return p
	end
	-- legs in checked trousers, big black clogs
	for _, x in { -2.2, 2.2 } do
		part(
			"Leg",
			Vector3.new(2.6, 4.2, 2.6),
			CFrame.new(x, 2.1, 0),
			Color3.fromRGB(34, 34, 40),
			{ Material = Enum.Material.Fabric }
		)
		part("Clog", Vector3.new(3, 1, 4), CFrame.new(x, 0.5, -0.5), Color3.fromRGB(16, 16, 18))
	end
	-- the belly, its stains and the glowing infection in it (the weak spot)
	local belly =
		ball("Belly", Vector3.new(11, 9, 9.5), CFrame.new(0, 8, 0), JACKET, { Material = Enum.Material.Fabric })
	for i = 1, 5 do
		local a = i * 1.3
		ball(
			"Stain",
			Vector3.new(1.6, 1.2, 0.3),
			CFrame.new(math.cos(a) * 3.5, 8 + math.sin(a) * 2.5, -4.55) * CFrame.Angles(0, 0, a),
			Color3.fromRGB(150, 70, 40)
		)
	end
	local core =
		ball("Core", Vector3.new(3.6, 3.6, 0.8), CFrame.new(0, 8.3, -4.7), INFECTION, { Material = Enum.Material.Neon })
	local coreLight = Instance.new("PointLight")
	coreLight.Color = INFECTION
	coreLight.Range = 16
	coreLight.Brightness = 2
	coreLight.Parent = core
	part(
		"Apron",
		Vector3.new(7, 6.5, 0.3),
		CFrame.new(0, 7.2, -4.9) * CFrame.Angles(math.rad(-8), 0, 0),
		Color3.fromRGB(214, 204, 192),
		{ Transparency = 0.15 }
	)
	-- chest, buttons, neckerchief
	part("Chest", Vector3.new(8, 3.2, 6.4), CFrame.new(0, 13.4, 0), JACKET, { Material = Enum.Material.Fabric })
	for _, x in { -1.2, 1.2 } do
		for _, y in { 12.6, 13.8 } do
			ball(
				"Button",
				Vector3.new(0.5, 0.5, 0.3),
				CFrame.new(x, y, -3.25),
				Palette.Gold,
				{ Material = Enum.Material.Metal }
			)
		end
	end
	part(
		"Neckerchief",
		Vector3.new(4.2, 0.9, 4.2),
		CFrame.new(0, 15.2, 0),
		Color3.fromRGB(200, 40, 40),
		{ Material = Enum.Material.Fabric }
	)
	-- head, eyes, mouth, moustache, toque
	ball("Head", Vector3.new(5.2, 5, 5), CFrame.new(0, 17.4, 0), Color3.fromRGB(214, 190, 160))
	local eyes = {}
	for _, x in { -1, 1 } do
		table.insert(
			eyes,
			ball(
				"Eye",
				Vector3.new(0.9, 0.6, 0.3),
				CFrame.new(x, 18, -2.35),
				Palette.NeonGold,
				{ Material = Enum.Material.Neon }
			)
		)
	end
	part("Mouth", Vector3.new(2.6, 0.9, 0.3), CFrame.new(0, 16.4, -2.4), Color3.fromRGB(30, 8, 12))
	for i = -2, 2 do
		part("Tooth", Vector3.new(0.35, 0.4, 0.1), CFrame.new(i * 0.5, 16.75, -2.55), Color3.fromRGB(250, 246, 230))
	end
	for _, side in { -1, 1 } do
		part(
			"Moustache",
			Vector3.new(1.8, 0.5, 0.4),
			CFrame.new(side * 1, 17.05, -2.55) * CFrame.Angles(0, 0, side * -0.3),
			Color3.fromRGB(30, 24, 20)
		)
	end
	part(
		"Toque",
		Vector3.new(3.6, 4.4, 4.4),
		CFrame.new(0, 21.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.new(1, 1, 1),
		{ Shape = Enum.PartType.Cylinder }
	)
	ball("ToquePuff", Vector3.new(5.6, 2.8, 5.6), CFrame.new(0, 23.6, 0), Color3.new(1, 1, 1))
	-- arms on motors (the server swings them for attacks): cleaver right, frying pan left
	local chest = model:FindFirstChild("Chest") :: BasePart
	local arms = {}
	for _, side in { 1, -1 } do
		local arm = Instance.new("Part")
		arm.Name = if side > 0 then "RightArm" else "LeftArm"
		arm.Size = Vector3.new(2.2, 7, 2.2)
		arm.Color = JACKET
		arm.Material = Enum.Material.Fabric
		arm.Anchored = false
		arm.CanCollide = false
		arm.CanQuery = false
		arm.CanTouch = false
		arm.Massless = true
		arm.Parent = model
		local motor = Instance.new("Motor6D")
		motor.Name = arm.Name .. "Joint"
		motor.Part0 = chest
		motor.Part1 = arm
		motor.C0 = CFrame.new(side * 5.1, 1, 0) * CFrame.Angles(0, 0, side * 0.25)
		motor.C1 = CFrame.new(0, 3, 0)
		motor.Parent = chest
		arm.CFrame = chest.CFrame * motor.C0 * motor.C1:Inverse()
		arms[side] = motor
		local hand = Instance.new("Part")
		hand.Name = "Hand"
		hand.Shape = Enum.PartType.Ball
		hand.Size = Vector3.one * 2
		hand.Color = Color3.fromRGB(214, 190, 160)
		hand.CanCollide, hand.CanQuery, hand.CanTouch, hand.Massless = false, false, false, true
		hand.CFrame = arm.CFrame * CFrame.new(0, -3.8, 0)
		hand.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = arm, hand
		w.Parent = hand
		local tool = Instance.new("Part")
		tool.CanCollide, tool.CanQuery, tool.CanTouch, tool.Massless = false, false, false, true
		if side > 0 then
			tool.Name = "Cleaver"
			tool.Size = Vector3.new(0.3, 3.6, 4.4)
			tool.Color = Color3.fromRGB(200, 206, 214)
			tool.Material = Enum.Material.Metal
			tool.CFrame = hand.CFrame * CFrame.new(0, -1.6, -1.6)
			local edge = Instance.new("Part")
			edge.Name = "Edge"
			edge.Size = Vector3.new(0.32, 3.6, 0.25)
			edge.Color = Palette.NeonRed
			edge.Material = Enum.Material.Neon
			edge.CanCollide, edge.CanQuery, edge.CanTouch, edge.Massless = false, false, false, true
			edge.CFrame = tool.CFrame * CFrame.new(0, 0, -2.2)
			edge.Parent = model
			local we = Instance.new("WeldConstraint")
			we.Part0, we.Part1 = tool, edge
			we.Parent = edge
		else
			tool.Name = "Pan"
			tool.Shape = Enum.PartType.Cylinder
			tool.Size = Vector3.new(0.5, 5, 5)
			tool.Color = Color3.fromRGB(40, 40, 46)
			tool.Material = Enum.Material.Metal
			tool.CFrame = hand.CFrame * CFrame.new(0, -1.2, -2.6) * CFrame.Angles(0, 0, math.rad(90))
		end
		tool.Parent = model
		local wt = Instance.new("WeldConstraint")
		wt.Part0, wt.Part1 = hand, tool
		wt.Parent = tool
	end
	-- grease drips and a stench haze
	local drip = Instance.new("ParticleEmitter")
	drip.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	drip.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90))
	drip.Size = NumberSequence.new(0.4, 0.1)
	drip.Lifetime = NumberRange.new(0.6, 1)
	drip.Speed = NumberRange.new(0, 1)
	drip.Acceleration = Vector3.new(0, -30, 0)
	drip.Rate = 10
	drip.Parent = belly
	local stench = Instance.new("ParticleEmitter")
	stench.Name = "Stench"
	stench.Texture = "rbxasset://textures/particles/smoke_main.dds"
	stench.Color = ColorSequence.new(Color3.fromRGB(150, 120, 60), Color3.fromRGB(60, 40, 30))
	stench.Transparency = NumberSequence.new(0.75, 1)
	stench.Size = NumberSequence.new(3, 7)
	stench.Lifetime = NumberRange.new(2, 3)
	stench.Rate = 4
	stench.Speed = NumberRange.new(0.5, 1.5)
	stench.Parent = belly
	-- invisible weak-point spheres the flashlight tests against
	local weakpoints = {
		ball(
			"WeakpointBelly",
			Vector3.one * 10,
			CFrame.new(0, 8, -0.5),
			Color3.new(),
			{ Transparency = 1, CanQuery = true }
		),
		ball(
			"WeakpointHead",
			Vector3.one * 6,
			CFrame.new(0, 17.4, 0),
			Color3.new(),
			{ Transparency = 1, CanQuery = true }
		),
	}
	chefParts = { Eyes = eyes, Core = core, Arms = arms, Stench = stench, Belly = belly }
	model:PivotTo(at)
	model.Parent = parent
	return model, root, weakpoints, { 5, 3 }
end

-- ── publishing ──────────────────────────────────────────────────────────────

local function publish()
	local f = fight
	if not f then
		return
	end
	local now = os.clock()
	ReplicatedStorage:SetAttribute("BossKind", "Chef")
	ReplicatedStorage:SetAttribute("BossHP", math.max(0, math.ceil(f.Hp)))
	ReplicatedStorage:SetAttribute("BossMaxHP", f.MaxHp)
	ReplicatedStorage:SetAttribute("BossPhase", f.Phase)
	ReplicatedStorage:SetAttribute("BossShield", f.State)
	ReplicatedStorage:SetAttribute("BossShielded", f.State ~= "Sick")
	ReplicatedStorage:SetAttribute("BossShieldUntil", if f.Until > now then toServer(f.Until) else 0)
	ReplicatedStorage:SetAttribute("BossHungerAt", toServer(f.HungerAt))
	ReplicatedStorage:SetAttribute("BossPass", f.Pass)
end

local function setEyes(color: Color3)
	for _, eye in chefParts.Eyes or {} do
		eye.Color = color
	end
end

local function resetAttributes()
	ReplicatedStorage:SetAttribute("BossActive", false)
	for _, name in { "BossKind", "BossShield", "BossPass" } do
		ReplicatedStorage:SetAttribute(name, nil)
	end
	ReplicatedStorage:SetAttribute("BossShieldUntil", 0)
	ReplicatedStorage:SetAttribute("BossHungerAt", 0)
end

-- ── day: samples, antidote, the sealed kitchen ──────────────────────────────

local function buildGrowth(parent: Instance, at: Vector3, index: number, myToken: {})
	local model = Builder.model("InfectedGrowth" .. index, parent)
	local blob = Builder.part({
		Name = "Growth",
		Parent = model,
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4.4, 4.4, 4.4),
		CFrame = CFrame.new(at + Vector3.new(0, 1.6, 0)),
		Color = INFECTION:Lerp(Color3.fromRGB(90, 40, 60), 0.4),
		Material = Enum.Material.SmoothPlastic,
		Tags = { "InfectedGrowth" },
	})
	for k = 1, 4 do
		Builder.decor({
			Parent = model,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * (1.2 + k * 0.3),
			CFrame = CFrame.new(at + Vector3.new(math.cos(k * 1.6) * 2.4, 0.6 + k * 0.3, math.sin(k * 1.6) * 2.4)),
			Color = INFECTION,
			Material = Enum.Material.Neon,
			Transparency = 0.3,
		})
	end
	TweenService:Create(blob, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Size = Vector3.one * 5,
	}):Play()
	Builder.light("PointLight", blob, { Color = INFECTION, Range = 14, Brightness = 1.5 })
	local prompt = Builder.prompt(blob, {
		ActionText = "Take Sample",
		ObjectText = "Infected Growth",
		HoldDuration = D.SampleSeconds,
		MaxActivationDistance = 8,
	})
	local offset = index * 1.7
	prompt.Triggered:Connect(function(player)
		if dayToken ~= myToken or blob:GetAttribute("Done") then
			return
		end
		markDone(blob, prompt)
		MissionEvents.record(player, "SampleCollected")
		Notify.effect(
			player,
			"WorldPopup",
			{ Position = at + Vector3.new(0, 5, 0), Text = "🧫 SAMPLE TAKEN", Color = "Green" }
		)
		TweenService:Create(blob, TweenInfo.new(1), { Transparency = 0.7 }):Play()
	end)
	task.spawn(function()
		local last = ""
		while dayToken == myToken and not blob:GetAttribute("Done") do
			local phase = FoodCourtRules.growthPhase(os.clock(), offset)
			if phase ~= last then
				last = phase
				prompt.Enabled = phase == "Calm"
				if phase == "Warning" then
					Telegraph.disc(at, D.SpitRadius, D.SpitWarn, SICK)
				elseif phase == "Spitting" then
					Telegraph.burst(at, D.SpitRadius, SICK)
					for _, victim in Telegraph.playersInCircle(Players:GetPlayers(), at, D.SpitRadius) do
						EnemyService.HitPlayer(victim, D.SpitDamage, at)
					end
				end
			end
			task.wait(0.1)
		end
	end)
end

local function buildBrewing(parent: Instance, myToken: {}, onBrewed: (Player) -> ())
	local done = 0
	local prompts: { [string]: ProximityPrompt } = {}
	local parts: { [string]: BasePart } = {}
	local labels =
		{ Chop = "🔪 Chop the samples", Boil = "🍲 Boil the mixture", Bottle = "🧪 Bottle the antidote" }
	local function samples(): number
		local count = 0
		for _, child in (dayFolder :: Folder):GetDescendants() do
			if child.Name == "Growth" and child:GetAttribute("Done") then
				count += 1
			end
		end
		return count
	end
	local function refresh()
		local step = FoodCourtRules.nextBrewStep(done)
		for name, prompt in prompts do
			prompt.Enabled = name == step and samples() >= D.SampleTarget
			parts[name]:SetAttribute("Done", if name ~= step then true else nil)
		end
	end
	for index, name in D.BrewSteps do
		local at = BREW[name]
		local table_ = Builder.part({
			Name = "BrewStation",
			Parent = parent,
			Size = Vector3.new(3.4, 3.4, 2.4),
			CFrame = CFrame.new(at + Vector3.new(0, 1.7, 0)),
			Color = Color3.fromRGB(176, 182, 190),
			Material = Enum.Material.Metal,
			Tags = { "BrewStation" },
		})
		parts[name] = table_
		local sign = Builder.decor({
			Parent = parent,
			Size = Vector3.new(3.4, 1, 0.1),
			CFrame = CFrame.lookAt(at + Vector3.new(0, 5.2, -1.3), at + Vector3.new(0, 5.2, -10)),
			Color = Color3.fromRGB(16, 14, 20),
		})
		Builder.label(
			sign,
			Enum.NormalId.Front,
			string.format("%d. %s", index, string.upper(name)),
			{ Color = SICK, Font = FONT }
		)
		local prompt = Builder.prompt(table_, {
			ActionText = labels[name],
			ObjectText = "Antidote: step " .. index,
			HoldDuration = D.BrewSeconds[name],
			MaxActivationDistance = 8,
			Enabled = false,
		})
		prompts[name] = prompt
		prompt.Triggered:Connect(function(player)
			if dayToken ~= myToken or FoodCourtRules.nextBrewStep(done) ~= name or samples() < D.SampleTarget then
				return
			end
			done += 1
			Notify.all(
				string.format("🧪 %s: %s done (%d/3).", player.DisplayName, string.lower(name), done),
				"success"
			)
			if not FoodCourtRules.nextBrewStep(done) then
				MissionEvents.record(player, "AntidoteBrewed")
				onBrewed(player)
			end
			refresh()
		end)
	end
	task.spawn(function()
		while dayToken == myToken and FoodCourtRules.nextBrewStep(done) do
			refresh()
			task.wait(1)
		end
	end)
end

local function buildSeals(parent: Instance, myToken: {}): BasePart?
	local main: BasePart? = nil
	for _, info in SEALS do
		local membrane = Builder.part({
			Name = "Membrane",
			Parent = parent,
			Size = info[2],
			CFrame = info[1],
			Color = Color3.fromRGB(120, 40, 80),
			Material = Enum.Material.Fabric,
			Transparency = 0.1,
		})
		Builder.light("PointLight", membrane, { Color = INFECTION, Range = 10, Brightness = 1 })
		if info[3] then
			main = membrane
		end
	end
	local peek = main :: BasePart
	local prompt = Builder.prompt(peek, {
		Name = "PeekPrompt",
		ActionText = "Peek Inside",
		ObjectText = "Locked: brew the antidote first",
		HoldDuration = D.PeekSeconds,
		MaxActivationDistance = 9,
		Enabled = false,
	})
	prompt.Triggered:Connect(function(player)
		if dayToken ~= myToken or peek:GetAttribute("Done") then
			return
		end
		markDone(peek, prompt)
		MissionEvents.record(player, "InfectionSourceFound")
		Notify.effectAll("Cinematic", {
			Shots = {
				{ From = Vector3.new(-188, 9, 0), LookAt = Vector3.new(-220, 8, 0), Duration = 1.6 },
				{ From = Vector3.new(-206, 7, -10), LookAt = Vector3.new(-222, 13, 0), Duration = 2.4 },
			},
			Title = "PATIENT ZERO",
			Subtitle = "The chef is the source. Tonight, he wakes up hungry.",
		})
	end)
	return peek
end

local function buildVeins(parent: Instance)
	for _, at in GROWTHS do
		local from = at + Vector3.new(0, 0.07, 0)
		local to = Vector3.new(-186, 0.07, 0)
		local vein = Builder.beam(from, to, 0.35, {
			Parent = parent,
			Color = INFECTION,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		vein.Size = Vector3.new(0.5, 0.06, vein.Size.Z)
		TweenService:Create(vein, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Transparency = 0.7,
		}):Play()
	end
end

function GorgingChef.StartDay()
	GorgingChef.EndDay()
	local myToken = {}
	dayToken = myToken
	local folder = Instance.new("Folder")
	folder.Name = "PatientZeroDay"
	folder.Parent = workspace
	dayFolder = folder
	for index, at in GROWTHS do
		buildGrowth(folder, at, index, myToken)
	end
	local peek = buildSeals(folder, myToken)
	buildBrewing(folder, myToken, function()
		buildVeins(folder)
		if peek then
			local prompt = peek:FindFirstChild("PeekPrompt") :: ProximityPrompt?
			if prompt then
				prompt.Enabled = true
				prompt.ObjectText = "Sealed Kitchen"
			end
			Builder.tag(peek, "KitchenSeal")
		end
		Notify.effectAll("Banner", {
			Title = "ANTIDOTE READY",
			Subtitle = "The infection's veins glow: follow them to its source!",
			Color = "Green",
			Sound = "PowerUp",
		})
	end)
	-- he's in there, asleep (seen through the peek)
	local sleeping =
		buildChef(folder, CFrame.new(HOME + Vector3.new(-2, -1.5, 0)) * CFrame.Angles(0, math.rad(-90), math.rad(8)))
	sleeping:SetAttribute("Asleep", true)
end

function GorgingChef.EndDay()
	dayToken = nil
	if dayFolder then
		dayFolder:Destroy()
		dayFolder = nil
	end
	chefParts = {}
end

-- ── night: attacks ──────────────────────────────────────────────────────────

local function swing(side: number, raise: number, seconds: number)
	local motor = chefParts.Arms and chefParts.Arms[side]
	if not motor then
		return
	end
	local base = CFrame.new(side * 5.1, 1, 0) * CFrame.Angles(0, 0, side * 0.25)
	TweenService
		:Create(motor, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { C0 = base * CFrame.Angles(raise, 0, 0) })
		:Play()
end

local function targets(): { { Player: Player, Root: BasePart } }
	local list = {}
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if root and root.Position.Y < 12 and root.Position.X < -184 and root.Position.X > -252 then
			table.insert(list, { Player = player, Root = root })
		end
	end
	return list
end

local function nearestTarget(): ({ Player: Player, Root: BasePart }?, number)
	local best, bestDistance = nil, math.huge
	for _, t in targets() do
		local d = (flat(t.Root.Position) - flat(position)).Magnitude
		if d < bestDistance then
			best, bestDistance = t, d
		end
	end
	return best, bestDistance
end

local function cleaver(myToken: {}, target: { Player: Player, Root: BasePart })
	local f = fight :: ChefLogic.Fight
	local from = Vector3.new(position.X, 0, position.Z)
	local direction = flat(target.Root.Position - position)
	direction = if direction.Magnitude > 0.1 then direction.Unit else facing
	facing = direction
	local to = from + direction * T.Cleaver.Length
	local warn = T.Cleaver.Warn[f.Phase]
	Telegraph.lane(from, to, T.Cleaver.Width, warn)
	Notify.effect(target.Player, "Danger", { Windup = warn })
	swing(1, math.rad(-150), warn * 0.8)
	task.delay(warn, function()
		if nightToken ~= myToken or dying then
			return
		end
		swing(1, math.rad(20), 0.15)
		for _, victim in Telegraph.playersInLane(Players:GetPlayers(), from, to, T.Cleaver.Width) do
			EnemyService.HitPlayer(victim, T.Cleaver.Damage[f.Phase], from)
		end
		Notify.effectAll("Shake", { Position = to, Strength = 1 })
		task.delay(0.6, function()
			swing(1, 0, 0.4)
		end)
	end)
end

local function panToss(myToken: {})
	local list = targets()
	if #list == 0 then
		return
	end
	local spots = {}
	for _, t in list do
		if #spots >= 3 then
			break
		end
		table.insert(spots, Telegraph.floorBelow(t.Root.Position))
	end
	if #list == 1 then
		-- solo: a second pan where you're heading
		local v = list[1].Root.AssemblyLinearVelocity
		table.insert(spots, Telegraph.floorBelow(list[1].Root.Position + flat(v) * 0.9))
	end
	swing(-1, math.rad(-120), 0.5)
	for _, spot in spots do
		Telegraph.disc(spot, T.Pan.Radius, T.Pan.Warn)
		local pan = Builder.decor({
			Name = "ThrownPan",
			Parent = nightFolder,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 3.6, 3.6),
			CFrame = CFrame.new(position + Vector3.new(0, 14, 0)),
			Color = Color3.fromRGB(40, 40, 46),
			Material = Enum.Material.Metal,
		})
		local mid = (position + spot) / 2 + Vector3.new(0, 18, 0)
		TweenService:Create(pan, TweenInfo.new(T.Pan.Warn * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(mid) * CFrame.Angles(3, 2, 0),
		}):Play()
		task.delay(T.Pan.Warn * 0.5, function()
			TweenService:Create(pan, TweenInfo.new(T.Pan.Warn * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = CFrame.new(spot + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			}):Play()
		end)
		task.delay(T.Pan.Warn, function()
			if nightToken ~= myToken or dying then
				pan:Destroy()
				return
			end
			for _, victim in Telegraph.playersInCircle(Players:GetPlayers(), spot, T.Pan.Radius) do
				EnemyService.HitPlayer(victim, T.Pan.Damage, spot)
			end
			Telegraph.burst(spot, T.Pan.Radius)
			task.delay(1.5, function()
				pan:Destroy()
			end)
		end)
	end
	task.delay(0.8, function()
		swing(-1, 0, 0.4)
	end)
end

local function greaseSpill()
	for _, t in targets() do
		local angle = rng:NextNumber(0, math.pi * 2)
		local spot = Telegraph.floorBelow(
			t.Root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(7, 10)
		)
		local pool = Builder.decor({
			Name = "Grease",
			Parent = nightFolder,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, T.Grease.Radius * 2, T.Grease.Radius * 2),
			CFrame = CFrame.new(spot + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(230, 190, 60),
			Material = Enum.Material.Glass,
			Reflectance = 0.3,
			Transparency = 0.25,
		})
		table.insert(greasePools, { Center = spot, Until = os.clock() + T.Grease.Seconds })
		task.delay(T.Grease.Seconds, function()
			pool:Destroy()
		end)
	end
	Notify.all("🧈 He splattered grease! Grease pools slow you down.", "warning")
end

local function stoveFlare(myToken: {})
	local lanes = {}
	for _, z in { -25.5, 25.5 } do
		local from, to = Vector3.new(-240, 0, z), Vector3.new(-196, 0, z)
		Telegraph.lane(from, to, T.Flare.Width, T.Flare.Warn, Color3.fromRGB(255, 120, 30))
		table.insert(lanes, { from, to })
	end
	Notify.effectAll("Popup", { Text = "🔥 THE STOVES FLARE: GET OFF THE LINES!", Color = "Red", Y = 0.42 })
	task.delay(T.Flare.Warn, function()
		if nightToken ~= myToken or dying then
			return
		end
		for _, lane in lanes do
			for _, victim in Telegraph.playersInLane(Players:GetPlayers(), lane[1], lane[2], T.Flare.Width) do
				EnemyService.HitPlayer(victim, T.Flare.Damage, lane[1])
			end
			local flame = Builder.decor({
				Parent = nightFolder,
				Size = Vector3.new(T.Flare.Width, 6, (lane[2] - lane[1]).Magnitude),
				CFrame = CFrame.lookAt((lane[1] + lane[2]) / 2 + Vector3.new(0, 3, 0), lane[2] + Vector3.new(0, 3, 0)),
				Color = Color3.fromRGB(255, 120, 30),
				Material = Enum.Material.Neon,
				Transparency = 0.4,
			})
			TweenService:Create(flame, TweenInfo.new(0.8), { Transparency = 1 }):Play()
			task.delay(0.9, function()
				flame:Destroy()
			end)
		end
	end)
end

local function attack(myToken: {})
	local f = fight
	local target = nearestTarget()
	if not f or not target then
		return
	end
	local roll = rng:NextNumber()
	local ravenous = f.State == "Ravenous" -- a ravenous chef only chops
	if not ravenous and f.Phase >= 3 and roll < 0.22 then
		stoveFlare(myToken)
	elseif not ravenous and f.Phase >= 2 and roll < 0.42 then
		greaseSpill()
	elseif ravenous or roll < 0.7 then
		cleaver(myToken, target)
	else
		panToss(myToken)
	end
end

local function meatballs(myToken: {})
	local f = fight
	if not f or f.Phase < 2 or nightToken ~= myToken then
		return
	end
	local alive = 0
	for _, enemy in EnemyService.GetAll() do
		if enemy.Type == "Meatball" and not enemy.Dead then
			alive += 1
		end
	end
	local want = ChefLogic.meatballCap(f.Phase, #Players:GetPlayers()) - alive
	for _ = 1, math.min(want, 2) do
		local best, bestScore = nil, -1
		for _, spot in MEATBALL_SPAWNS do
			local nearest = math.huge
			for _, t in targets() do
				nearest = math.min(nearest, (t.Root.Position - spot).Magnitude)
			end
			if nearest > bestScore then
				best, bestScore = spot, nearest
			end
		end
		if best and bestScore >= 18 then
			EnemyService.Spawn("Meatball", best, T.MeatballTier[f.Phase])
		end
	end
end

-- ── night: eating, damage, defeat ───────────────────────────────────────────

local function setPassDish(kind: ChefLogic.Pass)
	if passDish then
		passDish:Destroy()
		passDish = nil
	end
	if kind ~= "Empty" and nightFolder then
		passDish = Builder.decor({
			Name = "Dish",
			Parent = nightFolder,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 2.6, 2.6),
			CFrame = PASS * CFrame.new(0, 3.9, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = if kind == "Laced" then SICK else Color3.fromRGB(240, 150, 60),
			Material = if kind == "Laced" then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		})
	end
end

local function eat()
	local f = fight :: ChefLogic.Fight
	local meal = ChefLogic.eat(f, os.clock())
	setPassDish("Empty")
	if meal == "Sick" then
		setEyes(SICK)
		pose.Sick = true
		local highlight = Instance.new("Highlight")
		highlight.Name = "SickGlow"
		highlight.FillColor = SICK
		highlight.FillTransparency = 0.65
		highlight.OutlineColor = SICK
		highlight.Parent = chef
		task.delay(T.SickSeconds, function()
			highlight:Destroy()
		end)
		Notify.effectAll("Banner", {
			Title = "🤢 HE'S SICK!",
			Subtitle = string.format("BURN HIM NOW: %d seconds! Aim at his belly.", T.SickSeconds),
			Color = "Green",
			Sound = "PowerUp",
		})
	elseif meal == "Healed" then
		Notify.effectAll("Banner", {
			Title = "😋 IT HEALED HIM",
			Subtitle = "A plain dish! Lace it at a green 🧪 vat before serving.",
			Color = "Red",
			Sound = "Warning",
		})
	else
		setEyes(Palette.NeonRed)
		Notify.effectAll("Banner", {
			Title = "😡 RAVENOUS!",
			Subtitle = "The pass was empty! Run, then serve the next order.",
			Color = "Red",
			Sound = "MonsterSpawn",
		})
	end
	publish()
end

local function flushDamage()
	for player, entry in pendingDamage do
		if player.Parent then
			Notify.effect(player, "BossHit", { Position = entry.Position, Amount = math.floor(entry.Amount + 0.5) })
		end
	end
	table.clear(pendingDamage)
end

local function deathSequence(model: Model, root: BasePart)
	local start = os.clock()
	local base = root.CFrame
	while os.clock() - start < 1.8 and model.Parent do
		root.CFrame = (base + Vector3.new(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5)))
			* CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, math.rad(rng:NextNumber(-6, 6)))
		task.wait(0.05)
	end
	if not model.Parent then
		return
	end
	Notify.effectAll("Shake", { Position = root.Position, Strength = 2 })
	TweenService:Create(root, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = base * CFrame.new(0, -1, 4) * CFrame.Angles(math.rad(80), 0, 0),
	}):Play()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			TweenService:Create(part, TweenInfo.new(3), { Transparency = 1 }):Play()
		elseif part:IsA("ParticleEmitter") then
			part.Enabled = false
		end
	end
	task.wait(3.2)
	model:Destroy()
end

local function defeat(model: Model)
	local root = chefRoot
	dying = true
	if motion then
		motion:Disconnect()
		motion = nil
	end
	flushDamage()
	CombatService.UnregisterLightTarget(model)
	EnemyService.ClearAll()
	Telegraph.clear()
	publish()
	MissionEvents.record(nil, "ChefDefeated")
	Notify.all("👨‍🍳 THE GORGING CHEF HAS FALLEN! Dawn breaks in a few seconds…", "levelup")
	Notify.effectAll("BossDefeated", {
		Title = "CHEF DEFEATED",
		Subtitle = "Dawn breaks soon: Chapter 2 complete!",
		Position = if root then root.Position else nil,
	})
	if root then
		task.spawn(deathSequence, model, root)
	end
	GameStateService.ShortenPhase(DEFEAT_DAWN_SECONDS)
	task.delay(6, function()
		if dying then
			ReplicatedStorage:SetAttribute("BossActive", false)
		end
	end)
end

local function onLit(player: Player, dt: number, part: BasePart)
	local f, model = fight, chef
	if not f or not model or dying or not active then
		return
	end
	local now = os.clock()
	local data = DataService.Get(player)
	local amount = ChefLogic.lightDamage(
		FL.DPS,
		dt,
		ProgressionService.UpgradeBonus(player, "Lens"),
		data ~= nil and data.Equipment.PrismLens == true
	)
	local result = ChefLogic.applyLight(f, now, amount)
	if result.Blocked then
		if now - (blockedAt[player] or 0) > 1.2 then
			blockedAt[player] = now
			Notify.effect(player, "BossBlocked", {
				Position = part.Position,
				Text = "🧈 GREASED",
				Hint = "🧈 GREASED: serve him a LACED dish first",
			})
			if not toldBlocked[player] then
				toldBlocked[player] = true
				Notify.player(
					player,
					"🧈 Light slides off the grease! Serve him a LACED dish to make him sick first.",
					"warning"
				)
			end
		end
		return
	end
	local entry = pendingDamage[player]
	if entry then
		entry.Amount += result.Dealt
		entry.Position = part.Position
	else
		pendingDamage[player] = { Amount = result.Dealt, Position = part.Position }
	end
	ReplicatedStorage:SetAttribute("BossHitAt", serverNow())
	publish()
	if result.PhaseChanged then
		Notify.effectAll("BossPhase", {
			Phase = result.PhaseChanged,
			Title = if result.PhaseChanged == 2 then "PHASE 2: KITCHEN CHAOS" else "FINAL PHASE: INFERNO",
			Subtitle = if result.PhaseChanged == 2
				then "Grease spills slow you, meatballs roll in!"
				else "The stoves flare: stay off the burning lines!",
		})
		Notify.effectAll("Shake", { Position = position, Strength = 1.5 })
	end
	if result.Defeated then
		defeat(model)
	end
end

-- ── night: kitchen stations ─────────────────────────────────────────────────

local function stationPrompt(part: BasePart, props: { [string]: any }, requires: string?): ProximityPrompt
	local prompt = Builder.prompt(part, props)
	if requires then
		prompt:SetAttribute("RequiresCarry", requires)
		Builder.tag(prompt, "CarryPrompt")
	end
	return prompt
end

local function buildStations(parent: Instance, myToken: {})
	for _, cf in STOVES do
		local pot = Builder.part({
			Name = "Stove",
			Parent = parent,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.6, 2.4, 2.4),
			CFrame = cf * CFrame.new(0, 4.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(60, 60, 66),
			Material = Enum.Material.Metal,
			Tags = { "ChefStove" },
		})
		local steam = Instance.new("ParticleEmitter")
		steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
		steam.Color = ColorSequence.new(Color3.fromRGB(240, 240, 240))
		steam.Transparency = NumberSequence.new(0.6, 1)
		steam.Size = NumberSequence.new(1, 3)
		steam.Lifetime = NumberRange.new(1, 1.5)
		steam.Speed = NumberRange.new(2, 3)
		steam.EmissionDirection = Enum.NormalId.Right
		steam.Rate = 4
		steam.Parent = pot
		local prompt = stationPrompt(pot, {
			ActionText = "Cook a Dish",
			ObjectText = "Stove",
			HoldDuration = T.CookSeconds,
			MaxActivationDistance = 9,
		})
		prompt.Triggered:Connect(function(player)
			if nightToken ~= myToken or dying or not active then
				return
			end
			if Carry.item(player) == "Dish" or Carry.item(player) == "LacedDish" then
				Notify.player(player, "You're already carrying a dish!", "info")
				return
			end
			if Carry.pickUp(player, "Dish") then
				Notify.player(player, "🍝 Dish cooked! Lace it at a green 🧪 antidote vat.", "info")
			end
		end)
	end
	for _, at in VATS do
		local vat = Builder.part({
			Name = "AntidoteVat",
			Parent = parent,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(4, 3.4, 3.4),
			CFrame = CFrame.new(at + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(60, 120, 80),
			Material = Enum.Material.Metal,
			Tags = { "ChefVat" },
		})
		local brew = Builder.decor({
			Parent = parent,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 3, 3),
			CFrame = CFrame.new(at + Vector3.new(0, 4.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = SICK,
			Material = Enum.Material.Neon,
		})
		Builder.light("PointLight", brew, { Color = SICK, Range = 12, Brightness = 1.5 })
		local prompt = stationPrompt(vat, {
			ActionText = "Lace Dish",
			ObjectText = "Antidote Vat",
			HoldDuration = T.LaceSeconds,
			MaxActivationDistance = 9,
		}, "Dish")
		prompt.Triggered:Connect(function(player)
			if nightToken ~= myToken or dying or not Carry.consume(player, "Dish") then
				return
			end
			Carry.pickUp(player, "LacedDish")
			Notify.player(player, "🧪 Laced! Put it on the serving pass before ORDER UP.", "info")
		end)
	end
	-- the serving pass: a counter with a heat lamp and an order bell
	local counter = Builder.part({
		Name = "ServingPass",
		Parent = parent,
		Size = Vector3.new(10, 3.6, 3), -- PASS faces +X, so its X axis runs along the wall
		CFrame = PASS * CFrame.new(0, 1.8, 0),
		Color = Color3.fromRGB(176, 182, 190),
		Material = Enum.Material.Metal,
		Tags = { "ChefPass" },
	})
	local lamp = Builder.decor({
		Parent = parent,
		Size = Vector3.new(9, 0.4, 1.4),
		CFrame = PASS * CFrame.new(0, 8, 0),
		Color = Color3.fromRGB(255, 120, 60),
		Material = Enum.Material.Neon,
	})
	Builder.light(
		"SpotLight",
		lamp,
		{ Face = Enum.NormalId.Bottom, Angle = 70, Range = 12, Brightness = 2, Color = Color3.fromRGB(255, 150, 90) }
	)
	local sign = Builder.decor({
		Parent = parent,
		Size = Vector3.new(6, 1.4, 0.2),
		CFrame = PASS * CFrame.new(0, 10, 0.5),
		Color = Color3.fromRGB(16, 14, 20),
	})
	Builder.label(sign, Enum.NormalId.Front, "🔔 ORDER UP", { Color = Palette.NeonGold, Font = FONT })
	for _, kind in { "Dish", "LacedDish" } do
		local prompt = stationPrompt(counter, {
			ActionText = if kind == "LacedDish" then "Serve Laced Dish" else "Serve Plain Dish",
			ObjectText = if kind == "LacedDish" then "Serving Pass" else "Serving Pass (it will HEAL him)",
			HoldDuration = T.ServeSeconds,
			MaxActivationDistance = 10,
		}, kind)
		prompt.Triggered:Connect(function(player)
			local f = fight
			if nightToken ~= myToken or dying or not f or Carry.item(player) ~= kind then
				return
			end
			local dish: ChefLogic.Pass = if kind == "LacedDish" then "Laced" else "Dish"
			local ok, reason = ChefLogic.serve(f, dish)
			if not ok then
				Notify.player(
					player,
					if reason == "Full" then "🍽️ The pass already has a dish on it." else "It's over!",
					"info"
				)
				return
			end
			Carry.consume(player, kind)
			setPassDish(dish)
			publish()
			MissionEvents.record(player, "DishServed")
			if dish == "Laced" then
				MissionEvents.record(player, "LacedDishServed")
				Notify.all(
					string.format("🧪 %s served a LACED dish. Wait for ORDER UP...", player.DisplayName),
					"success"
				)
			else
				Notify.all("⚠️ A PLAIN dish is on the pass: it will heal him!", "warning")
			end
		end)
	end
end

-- ── night: the brain ────────────────────────────────────────────────────────

local function clampArena(p: Vector3): Vector3
	return Vector3.new(math.clamp(p.X, ARENA.MinX, ARENA.MaxX), 0, math.clamp(p.Z, ARENA.MinZ, ARENA.MaxZ))
end

local function runBrain(myToken: {})
	local f = fight :: ChefLogic.Fight
	local nextAttack = os.clock() + T.FirstAttackDelay
	local nextMeatball = 0
	local warned = false
	local lastPhase = f.Phase
	local lastFlush = 0
	while nightToken == myToken and not dying do
		task.wait(0.1)
		local now = os.clock()
		local ended = ChefLogic.update(f, now)
		if ended then
			pose.Sick = false
			setEyes(Palette.NeonGold)
			Notify.all(
				if ended == "Sick"
					then "🧈 He's recovering: the grease is back. Get another laced dish ready!"
					else "😮‍💨 He's calming down. Next ORDER UP is coming...",
				"info"
			)
			publish()
		end
		if f.Phase ~= lastPhase then
			lastPhase = f.Phase
			nextMeatball = now + T.MeatballFirst
		end
		-- ORDER UP
		if f.State == "Greased" and not warned and f.HungerAt - now <= 6 then
			warned = true
			Notify.effectAll(
				"Popup",
				{ Text = "🔔 ORDER UP in 6 s: LACED dish on the pass!", Color = "Gold", Y = 0.36 }
			)
		end
		if ChefLogic.isHungry(f, now) then
			if mode ~= "GoEat" then
				mode = "GoEat"
				Notify.effectAll("Banner", {
					Title = "🔔 ORDER UP!",
					Subtitle = "He's heading for the serving pass...",
					Color = "Gold",
					Sound = "Warning",
				})
			end
			if (flat(position) - flat(EAT_SPOT)).Magnitude <= 2 then
				eat()
				mode = "Idle"
				warned = false
			end
		elseif mode == "GoEat" then
			mode = "Idle"
		end
		-- attacks (never on the way to eat, never while sick)
		local gap = ChefLogic.attackGap(f)
		if gap and mode ~= "GoEat" and now >= nextAttack then
			nextAttack = now + gap
			attack(myToken)
		end
		if f.Phase >= 2 and now >= nextMeatball then
			nextMeatball = now + (T.MeatballEvery[f.Phase] or 20)
			meatballs(myToken)
		end
		-- grease pools slow whoever stands in them
		for i = #greasePools, 1, -1 do
			if now >= greasePools[i].Until then
				table.remove(greasePools, i)
			end
		end
		for _, player in Players:GetPlayers() do
			local root = livingRoot(player)
			local slowed = false
			if root then
				for _, pool in greasePools do
					if (flat(root.Position) - flat(pool.Center)).Magnitude <= T.Grease.Radius then
						slowed = true
					end
				end
			end
			local scale = if slowed then T.Grease.Slow else nil
			if player:GetAttribute("MoveScale") ~= scale then
				player:SetAttribute("MoveScale", scale)
			end
		end
		if now - lastFlush >= 0.3 then
			lastFlush = now
			flushDamage()
		end
	end
end

local function startMotion(myToken: {})
	local f = fight :: ChefLogic.Fight
	motion = RunService.Heartbeat:Connect(function(dt)
		local root = chefRoot
		if not root or nightToken ~= myToken or dying then
			return
		end
		local goal = position
		if active then
			if mode == "GoEat" then
				goal = EAT_SPOT
			elseif f.State == "Sick" then
				goal = position
			else
				local target, distance = nearestTarget()
				if target then
					local keep = if f.State == "Ravenous" then 6 else 12
					local toward = flat(target.Root.Position - position)
					if distance > keep + 2 and toward.Magnitude > 0.1 then
						goal = position + toward.Unit * (distance - keep)
					elseif distance < keep - 3 and toward.Magnitude > 0.1 then
						goal = position - toward.Unit * 3
					end
					if toward.Magnitude > 0.1 then
						facing = facing:Lerp(toward.Unit, math.min(dt * 3, 1))
					end
				else
					goal = HOME
				end
			end
		end
		goal = clampArena(goal)
		local step = flat(goal - position)
		local speed = ChefLogic.speed(f)
		if step.Magnitude > 0.2 then
			local move = step.Unit * math.min(step.Magnitude, speed * dt)
			position = clampArena(position + move)
			if mode == "GoEat" then
				facing = facing:Lerp(step.Unit, math.min(dt * 4, 1))
			end
		end
		local t = os.clock()
		local walking = step.Magnitude > 0.5
		local bob = if walking then math.abs(math.sin(t * 5)) * 0.5 else math.sin(t * 1.5) * 0.15
		local sway = if walking then math.sin(t * 5) * 0.05 else 0
		local hunch = if pose.Sick then CFrame.Angles(math.rad(-18), 0, math.sin(t * 9) * 0.06) else CFrame.new()
		local look = if facing.Magnitude > 0.01 then facing.Unit else Vector3.new(1, 0, 0)
		root.CFrame = CFrame.lookAt(position + Vector3.new(0, bob, 0), position + look + Vector3.new(0, bob, 0))
			* CFrame.Angles(0, 0, sway)
			* hunch
	end)
end

local function clearNight()
	nightToken = nil
	active = false
	dying = false
	mode = "Idle"
	if motion then
		motion:Disconnect()
		motion = nil
	end
	if chef then
		CombatService.UnregisterLightTarget(chef)
	end
	chef, chefRoot, fight = nil, nil, nil
	chefParts = {}
	passDish = nil
	table.clear(greasePools)
	table.clear(pendingDamage)
	table.clear(blockedAt)
	table.clear(toldBlocked)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("MoveScale") ~= nil then
			player:SetAttribute("MoveScale", nil)
		end
		if Carry.item(player) == "Dish" or Carry.item(player) == "LacedDish" then
			Carry.drop(player)
		end
	end
	if nightFolder then
		nightFolder:Destroy()
		nightFolder = nil
	end
	resetAttributes()
end

function GorgingChef.StartNight()
	clearNight()
	local myToken = {}
	nightToken = myToken
	local folder = Instance.new("Folder")
	folder.Name = "ChefArena"
	folder.Parent = workspace
	nightFolder = folder
	position = HOME
	facing = Vector3.new(1, 0, 0)
	local now = os.clock()
	local players = #Players:GetPlayers()
	local newFight = ChefLogic.new(players, now + T.IntroSeconds)
	if RunService:IsStudio() then
		local phase = workspace:GetAttribute("ChefTest_Phase")
		if phase == 2 or phase == 3 then
			newFight.Phase = phase
			newFight.Hp = newFight.MaxHp * (if phase == 2 then 0.6 else 0.3)
		end
	end
	fight = newFight
	local model, root, weakpoints, radii = buildChef(folder, CFrame.lookAt(HOME, HOME + facing))
	chef, chefRoot = model, root
	buildStations(folder, myToken)
	CombatService.RegisterLightTarget(model, onLit, { Parts = weakpoints, Radius = radii })
	ReplicatedStorage:SetAttribute("BossName", "THE GORGING CHEF")
	ReplicatedStorage:SetAttribute("BossActive", true)
	publish()
	Notify.effectAll("Cinematic", {
		Shots = {
			{ From = Vector3.new(-150, 12, 0), LookAt = Vector3.new(-184, 8, 0), Duration = 2 },
			{ From = Vector3.new(-200, 10, 14), LookAt = HOME + Vector3.new(0, 14, 0), Duration = 2.4 },
			{ From = Vector3.new(-196, 22, -26), LookAt = HOME + Vector3.new(0, 6, 0), Duration = 2.6 },
		},
		Title = "THE GORGING CHEF",
		Subtitle = "Chapter 2 Boss · Cook 🍳 → lace 🧪 → serve 🍽️ → burn him!",
	})
	startMotion(myToken)
	task.delay(T.IntroSeconds, function()
		if nightToken ~= myToken then
			return
		end
		active = true
		Notify.effectAll("BossIntro", {
			Title = "THE GORGING CHEF",
			Subtitle = "Cook at a stove 🍳, lace at a green vat 🧪, serve on the pass 🍽️ before ORDER UP!",
		})
		task.spawn(runBrain, myToken)
	end)
end

function GorgingChef.EndNight()
	clearNight()
end

return GorgingChef
