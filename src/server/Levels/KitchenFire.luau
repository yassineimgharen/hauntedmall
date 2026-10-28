-- Level 9: Day "Live Wires" / Night "Grease Fire".
--
-- Day:   the food court's wiring is shot (the lights flicker). Six broken cables cycle
--        between LIVE (sparks, shocks anyone close, can't be touched) and SAFE: hold E to
--        splice one while it's safe. Once five are spliced the switchboard in the
--        maintenance corridor unlocks: its two levers, 74 studs apart, must both be pulled
--        within Window seconds (teammates, or one fast sprint).
-- Night: a grease fire breaks out in the grand kitchen and spreads cell by cell over the
--        kitchen and dining hall (FoodCourtRules fire grid). Standing in fire hurts.
--        Extinguishers from the red wall cabinets (8 sprays each) put out a cell and its
--        neighbours. Shut the three gas valves (kitchen, storage, freezer) to stop the
--        spread and unlock the loading dock's emergency exit; walk out onto the landing to
--        escape. The south restaurants are fire-free refuges on the way to the dock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local Layout = require(script.Parent.Parent.World.Layout)
local Carry = require(script.Parent.Carry)
local FoodCourtRules = require(script.Parent.FoodCourtRules)

local KitchenFire = {}

local R = FoodCourtRules.L09
local F = Layout.FoodCourt
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local SPARK = Color3.fromRGB(150, 220, 255)
local FIRE = Color3.fromRGB(255, 110, 30)

-- cable breaks: centre and the axis the cable lies along
local CABLES = {
	{ Name = "Dining Hall South", At = Vector3.new(-170, 0, -44), Axis = Vector3.xAxis },
	{ Name = "Dining Hall North", At = Vector3.new(-112, 0, 44), Axis = Vector3.xAxis },
	{ Name = "Maintenance Corridor", At = Vector3.new(-150, 0, 88), Axis = Vector3.xAxis },
	{ Name = "Grand Kitchen", At = Vector3.new(-232, 0, 0), Axis = Vector3.zAxis },
	{ Name = "Storage", At = Vector3.new(-240, 0, -60), Axis = Vector3.zAxis },
	{ Name = "Loading Dock", At = Vector3.new(-108, 0, -104), Axis = Vector3.zAxis },
}
local LEVERS = {
	A = CFrame.lookAt(Vector3.new(-104, 0, 90.6), Vector3.new(-104, 0, 80)),
	B = CFrame.lookAt(Vector3.new(-178, 0, 90.6), Vector3.new(-178, 0, 80)),
}
local VALVES = {
	{ Name = "Kitchen Gas Main", CFrame = CFrame.lookAt(Vector3.new(-248.6, 0, -22), Vector3.new(-230, 0, -22)) },
	{ Name = "Storage Gas Main", CFrame = CFrame.lookAt(Vector3.new(-185.6, 0, -62), Vector3.new(-200, 0, -62)) },
	{ Name = "Freezer Gas Main", CFrame = CFrame.lookAt(Vector3.new(-248.6, 0, 84), Vector3.new(-230, 0, 84)) },
}
local EXTINGUISHERS = {
	CFrame.lookAt(Vector3.new(-100.5, 0, -46.6), Vector3.new(-100.5, 0, 0)),
	CFrame.lookAt(Vector3.new(-100.5, 0, 46.6), Vector3.new(-100.5, 0, 0)),
	CFrame.lookAt(Vector3.new(-182.6, 0, -40), Vector3.new(-150, 0, -40)),
	CFrame.lookAt(Vector3.new(-182.6, 0, 40), Vector3.new(-150, 0, 40)),
	CFrame.lookAt(Vector3.new(-185.4, 0, -40), Vector3.new(-220, 0, -40)),
	CFrame.lookAt(Vector3.new(-200, 0, -94.6), Vector3.new(-200, 0, -80)),
}
local FIRE_STARTS = { { -230, 30 }, { -205, -30 }, { -240, 2 } }
local EXIT = F.Exits.Dock

local dayFolder: Folder? = nil
local nightFolder: Folder? = nil
local dayToken: {}? = nil
local nightToken: {}? = nil
local spliced = 0
local switchboardDone = false
local valvesClosed = 0
local grid: FoodCourtRules.FireGrid = FoodCourtRules.fireGrid()
local cells: { [number]: BasePart } = {}
local charges: { [Player]: number } = {}
local escaped: { [Player]: boolean } = {}
local exitBarrier: BasePart? = nil
local rng = Random.new()

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function markDone(part: BasePart, prompt: ProximityPrompt)
	part:SetAttribute("Done", true)
	prompt:SetAttribute("Done", true)
	prompt.Enabled = false
end

local function billboard(part: BasePart, offset: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 30)
	gui.StudsOffset = Vector3.new(0, offset, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = FONT
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = part
	return label
end

-- ── day: cables ─────────────────────────────────────────────────────────────

type Cable = {
	Part: BasePart,
	Prompt: ProximityPrompt,
	Arc: BasePart,
	Label: TextLabel,
	Offset: number,
	Done: boolean,
	Phase: string,
}

local function buildCable(parent: Instance, info: { [string]: any }, index: number): Cable
	local axis: Vector3 = info.Axis
	local at: Vector3 = info.At
	local model = Builder.model("Cable" .. index, parent)
	for _, side in { -1, 1 } do
		local from = at + axis * side * 1.2
		local to = at + axis * side * 7
		Builder.beam(from + Vector3.new(0, 0.35, 0), to + Vector3.new(0, 0.35, 0), 0.6, {
			Parent = model,
			Color = Color3.fromRGB(24, 24, 28),
			Material = Enum.Material.Rubber,
			CanCollide = false,
		})
		Builder.decor({
			Parent = model,
			Size = Vector3.new(0.5, 0.5, 0.5),
			CFrame = CFrame.new(from + Vector3.new(0, 0.35, 0)),
			Color = Palette.Gold,
			Material = Enum.Material.Metal,
		})
	end
	local hub = Builder.part({
		Name = "CableBreak",
		Parent = model,
		Size = Vector3.new(1.6, 0.8, 1.6),
		CFrame = CFrame.new(at + Vector3.new(0, 0.4, 0)),
		Color = Color3.fromRGB(240, 196, 40),
		Material = Enum.Material.Metal,
		CanCollide = false,
		Tags = { "CableBreak" },
	})
	local arc = Builder.decor({
		Parent = model,
		Size = Vector3.new(0.25, 0.25, 2.6),
		CFrame = CFrame.lookAt(at + Vector3.new(0, 0.6, 0), at + axis + Vector3.new(0, 0.6, 0)),
		Color = SPARK,
		Material = Enum.Material.Neon,
	})
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(SPARK)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Lifetime = NumberRange.new(0.2, 0.5)
	sparks.Speed = NumberRange.new(6, 12)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.Rate = 40
	sparks.Parent = arc
	local glow = Instance.new("PointLight")
	glow.Color = SPARK
	glow.Range = 12
	glow.Brightness = 2
	glow.Parent = arc
	local prompt = Builder.prompt(hub, {
		ActionText = "Splice",
		ObjectText = info.Name .. " Cable",
		HoldDuration = R.SpliceSeconds,
		MaxActivationDistance = 8,
	})
	return {
		Part = hub,
		Prompt = prompt,
		Arc = arc,
		Label = billboard(hub, 3),
		Offset = (index - 1) * 1.3,
		Done = false,
		Phase = "",
	}
end

local function runCables(cables: { Cable }, myToken: {})
	while dayToken == myToken do
		local now = os.clock()
		for _, cable in cables do
			if cable.Done then
				continue
			end
			local phase, left = FoodCourtRules.cablePhase(now, cable.Offset)
			if phase ~= cable.Phase then
				cable.Phase = phase
				local live = phase == "Live"
				cable.Prompt.Enabled = not live
				cable.Arc.Transparency = if live then 0 else 1
				for _, child in cable.Arc:GetChildren() do
					if child:IsA("ParticleEmitter") or child:IsA("Light") then
						(child :: any).Enabled = live
					end
				end
				cable.Label.TextColor3 = if live then Palette.NeonRed else Palette.NeonGreen
				if live then
					-- anyone still crouched over it gets a jolt
					for _, player in Players:GetPlayers() do
						local root = livingRoot(player)
						if root and (root.Position - cable.Part.Position).Magnitude <= R.ShockRadius then
							EnemyService.HitPlayer(player, R.ShockDamage, cable.Part.Position)
							Notify.player(player, "⚡ ZAP! Splice only while the cable is SAFE (green).", "warning")
						end
					end
				end
			end
			cable.Label.Text = string.format("%s %.1fs", if phase == "Live" then "⚡ LIVE" else "✅ SAFE", left)
		end
		task.wait(0.1)
	end
end

-- ── day: the switchboard ────────────────────────────────────────────────────

local function buildSwitchboard(parent: Instance, myToken: {})
	local pulled: { [string]: number } = {}
	local handles: { [string]: BasePart } = {}
	local lights: { [string]: BasePart } = {}
	local prompts: { [string]: ProximityPrompt } = {}
	for name, cf in LEVERS do
		local model = Builder.model("Lever" .. name, parent)
		Builder.part({
			Parent = model,
			Size = Vector3.new(4, 6, 1),
			CFrame = cf * CFrame.new(0, 4.5, 0),
			Color = Color3.fromRGB(70, 74, 82),
			Material = Enum.Material.DiamondPlate,
		})
		local panel = Builder.decor({
			Parent = model,
			Size = Vector3.new(3.6, 1, 0.1),
			CFrame = cf * CFrame.new(0, 7, -0.55),
			Color = Color3.fromRGB(16, 14, 20),
		})
		Builder.label(
			panel,
			Enum.NormalId.Front,
			"⚡ MAIN BREAKER " .. name,
			{ Color = Palette.NeonGold, Font = FONT }
		)
		local handle = Builder.part({
			Name = "LeverHandle",
			Parent = model,
			Size = Vector3.new(0.5, 2.6, 0.5),
			CFrame = cf * CFrame.new(0, 4.6, -1) * CFrame.Angles(math.rad(-35), 0, 0),
			Color = Palette.NeonRed,
			Material = Enum.Material.SmoothPlastic,
			Tags = { "SwitchLever" },
		})
		handles[name] = handle
		lights[name] = Builder.decor({
			Parent = model,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.7,
			CFrame = cf * CFrame.new(1.3, 6.2, -0.6),
			Color = Palette.DarkMetal,
			Material = Enum.Material.Neon,
		})
		local prompt = Builder.prompt(handle, {
			ActionText = "Pull Lever",
			ObjectText = "Locked: splice the cables first",
			HoldDuration = R.LeverSeconds,
			MaxActivationDistance = 8,
			Enabled = false,
		})
		prompts[name] = prompt
		prompt.Triggered:Connect(function(player)
			if dayToken ~= myToken or switchboardDone or spliced < 5 then
				return
			end
			local now = os.clock()
			TweenService:Create(
				handle,
				TweenInfo.new(0.2),
				{ CFrame = cf * CFrame.new(0, 4.6, -1) * CFrame.Angles(math.rad(35), 0, 0) }
			):Play()
			lights[name].Color = Palette.NeonGreen
			if FoodCourtRules.pullLever(pulled, name, now) then
				switchboardDone = true
				for _, p in prompts do
					p.Enabled = false
				end
				for _, h in handles do
					h:SetAttribute("Done", true)
				end
				ReplicatedStorage:SetAttribute("PowerFlicker", false)
				MissionEvents.record(player, "SwitchboardReset")
				Notify.all("💡 SWITCHBOARD RESET: the food court has power again!", "success")
				Notify.effectAll("Banner", {
					Title = "POWER RESTORED",
					Subtitle = "The food court's wiring holds. For now...",
					Color = "Cyan",
					Sound = "PowerUp",
				})
				return
			end
			Notify.all(
				string.format("⚡ Breaker %s pulled! Pull the other breaker within %d seconds!", name, R.Window),
				"warning"
			)
			task.delay(R.Window, function()
				if dayToken == myToken and not switchboardDone and pulled[name] == now then
					pulled[name] = nil
					lights[name].Color = Palette.DarkMetal
					TweenService:Create(handle, TweenInfo.new(0.3), {
						CFrame = cf * CFrame.new(0, 4.6, -1) * CFrame.Angles(math.rad(-35), 0, 0),
					}):Play()
					Notify.all("⚡ Too slow: the breaker snapped back. Pull both within the window!", "warning")
				end
			end)
		end)
	end
	return function()
		for _, prompt in prompts do
			prompt.Enabled = true
			prompt.ObjectText = "Main Breaker"
		end
		Notify.all(
			string.format(
				"🔌 Cables spliced! Pull BOTH main breakers in the maintenance corridor within %d s.",
				R.Window
			),
			"info"
		)
	end
end

function KitchenFire.StartDay()
	KitchenFire.EndDay()
	local myToken = {}
	dayToken = myToken
	spliced = 0
	switchboardDone = false
	local folder = Instance.new("Folder")
	folder.Name = "LiveWiresDay"
	folder.Parent = workspace
	dayFolder = folder
	ReplicatedStorage:SetAttribute("PowerFlicker", true)
	local unlock = buildSwitchboard(folder, myToken)
	local cables = {}
	for index, info in CABLES do
		local cable = buildCable(folder, info, index)
		table.insert(cables, cable)
		cable.Prompt.Triggered:Connect(function(player)
			if dayToken ~= myToken or cable.Done or cable.Phase ~= "Safe" then
				return
			end
			cable.Done = true
			markDone(cable.Part, cable.Prompt)
			cable.Arc.Transparency = 1
			for _, child in cable.Arc:GetChildren() do
				if child:IsA("ParticleEmitter") or child:IsA("Light") then
					(child :: any).Enabled = false
				end
			end
			cable.Part.Color = Palette.NeonGreen
			cable.Label.Text = "✅ SPLICED"
			cable.Label.TextColor3 = Palette.NeonGreen
			spliced += 1
			MissionEvents.record(player, "CableSpliced")
			Notify.all(
				string.format("🔌 %s spliced the %s cable (%d/5).", player.DisplayName, info.Name, spliced),
				"success"
			)
			if spliced == 5 then
				unlock()
			end
		end)
	end
	task.spawn(runCables, cables, myToken)
end

function KitchenFire.EndDay()
	dayToken = nil
	ReplicatedStorage:SetAttribute("PowerFlicker", false)
	if dayFolder then
		dayFolder:Destroy()
		dayFolder = nil
	end
end

-- ── night: the fire ─────────────────────────────────────────────────────────

local function cellPart(key: number, parent: Instance): BasePart
	local c, r = FoodCourtRules.cellOf(grid, key)
	local x, z = FoodCourtRules.cellCenter(c, r)
	local part = Builder.part({
		Name = "Fire",
		Parent = parent,
		Size = Vector3.new(R.Cell - 0.4, 0.3, R.Cell - 0.4),
		CFrame = CFrame.new(x, 0.16, z),
		Color = FIRE,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Tags = { "FireCell" },
	})
	local flames = Instance.new("ParticleEmitter")
	flames.Texture = "rbxasset://textures/particles/fire_main.dds"
	flames.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 60, 20))
	flames.LightEmission = 0.8
	flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0.5) })
	flames.Transparency = NumberSequence.new(0.2, 1)
	flames.Lifetime = NumberRange.new(0.7, 1.1)
	flames.Speed = NumberRange.new(5, 8)
	flames.SpreadAngle = Vector2.new(15, 15)
	flames.Shape = Enum.ParticleEmitterShape.Box
	flames.EmissionDirection = Enum.NormalId.Top
	flames.Rate = 10
	flames.Parent = part
	if (c + r) % 3 == 0 then
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(60, 50, 50))
		smoke.Transparency = NumberSequence.new(0.5, 1)
		smoke.Size = NumberSequence.new(4, 10)
		smoke.Lifetime = NumberRange.new(3, 4)
		smoke.Speed = NumberRange.new(3, 5)
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Rate = 2
		smoke.Parent = part
		local light = Instance.new("PointLight")
		light.Color = FIRE
		light.Range = 18
		light.Brightness = 2
		light.Parent = part
	end
	local prompt = Builder.prompt(part, {
		ActionText = "Spray",
		ObjectText = "Fire",
		HoldDuration = 0.4,
		MaxActivationDistance = 10,
	})
	prompt:SetAttribute("RequiresCarry", "Extinguisher")
	Builder.tag(prompt, "CarryPrompt")
	prompt.Triggered:Connect(function(player)
		KitchenFire._spray(player, key)
	end)
	return part
end

local function setBurning(key: number, burning: boolean)
	local existing = cells[key]
	if burning and not existing and nightFolder then
		cells[key] = cellPart(key, nightFolder)
	elseif not burning and existing then
		cells[key] = nil
		existing.CanQuery = false
		for _, child in existing:GetChildren() do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			elseif child:IsA("ProximityPrompt") then
				child:Destroy()
			end
		end
		TweenService:Create(existing, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		task.delay(1.2, function()
			existing:Destroy()
		end)
	end
end

function KitchenFire._spray(player: Player, key: number)
	if not nightToken or Carry.item(player) ~= "Extinguisher" or not grid.Burning[key] then
		return
	end
	local c, r = FoodCourtRules.cellOf(grid, key)
	local out = FoodCourtRules.extinguish(grid, c, r, os.clock())
	for _, putOut in out do
		setBurning(putOut, false)
	end
	if #out > 0 then
		MissionEvents.record(player, "FireExtinguished", #out)
		local x, z = FoodCourtRules.cellCenter(c, r)
		Notify.effect(player, "WorldPopup", { Position = Vector3.new(x, 3, z), Text = "💨 OUT!", Color = "Cyan" })
	end
	charges[player] = (charges[player] or R.Charges) - 1
	if charges[player] <= 0 then
		charges[player] = nil
		Carry.consume(player, "Extinguisher")
		Notify.player(player, "🧯 Extinguisher empty! Grab another from a red cabinet.", "warning")
	end
end

local function buildExtinguishers(parent: Instance)
	for _, cf in EXTINGUISHERS do
		local model = Builder.model("ExtinguisherCabinet", parent)
		local cabinet = Builder.part({
			Name = "SupplyExtinguisher",
			Parent = model,
			Size = Vector3.new(2.4, 3.4, 1),
			CFrame = cf * CFrame.new(0, 4, 0),
			Color = Color3.fromRGB(200, 30, 30),
			Material = Enum.Material.Metal,
			Tags = { "SupplyExtinguisher" },
		})
		Builder.decor({
			Parent = model,
			Size = Vector3.new(0.9, 2.2, 0.9),
			CFrame = cf * CFrame.new(0, 3.8, -0.7),
			Color = Color3.fromRGB(240, 50, 40),
			Material = Enum.Material.SmoothPlastic,
		})
		local sign = Builder.decor({
			Parent = model,
			Size = Vector3.new(2.4, 0.8, 0.1),
			CFrame = cf * CFrame.new(0, 6.3, -0.55),
			Color = Color3.fromRGB(200, 30, 30),
		})
		Builder.label(sign, Enum.NormalId.Front, "🧯 FIRE", { Color = Color3.new(1, 1, 1), Font = FONT })
		local prompt = Builder.prompt(cabinet, {
			ActionText = "Take Extinguisher",
			ObjectText = "Fire Cabinet",
			HoldDuration = 0,
			MaxActivationDistance = 9,
		})
		prompt.Triggered:Connect(function(player)
			if nightToken and Carry.pickUp(player, "Extinguisher") then
				charges[player] = R.Charges
				Notify.player(
					player,
					string.format("🧯 Extinguisher ready (%d sprays): hold E at a fire.", R.Charges),
					"info"
				)
			end
		end)
		local c, r = FoodCourtRules.cellAt(cf.Position.X, cf.Position.Z)
		local key = c and r and FoodCourtRules.cellKey(grid, c, r)
		if key then
			grid.Protected[key] = true
		end
	end
end

local function buildValves(parent: Instance, myToken: {})
	for _, info in VALVES do
		local cf: CFrame = info.CFrame
		local model = Builder.model("GasValve", parent)
		Builder.beam(cf.Position + Vector3.new(0, 0, 0), cf.Position + Vector3.new(0, 9, 0), 0.7, {
			Parent = model,
			Color = Palette.NeonGold:Lerp(Color3.fromRGB(80, 70, 40), 0.5),
			Material = Enum.Material.Metal,
		})
		local wheel = Builder.part({
			Name = "Valve",
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 2.6, 2.6),
			CFrame = cf * CFrame.new(0, 4, -0.9) * CFrame.Angles(0, math.rad(90), 0),
			Color = Palette.NeonRed,
			Material = Enum.Material.Metal,
			Tags = { "GasValve" },
		})
		local label = billboard(wheel, 2.6)
		label.Text = "🔥 GAS ON"
		label.TextColor3 = Palette.NeonRed
		local prompt = Builder.prompt(wheel, {
			ActionText = "Shut Off",
			ObjectText = info.Name,
			HoldDuration = R.ValveSeconds,
			MaxActivationDistance = 8,
		})
		local c, r = FoodCourtRules.cellAt(cf.Position.X, cf.Position.Z)
		local key = c and r and FoodCourtRules.cellKey(grid, c, r)
		if key then
			grid.Protected[key] = true
		end
		prompt.Triggered:Connect(function(player)
			if nightToken ~= myToken or wheel:GetAttribute("Done") then
				return
			end
			markDone(wheel, prompt)
			TweenService:Create(wheel, TweenInfo.new(0.8), { CFrame = wheel.CFrame * CFrame.Angles(math.pi, 0, 0) })
				:Play()
			wheel.Color = Palette.NeonGreen
			label.Text = "✅ GAS OFF"
			label.TextColor3 = Palette.NeonGreen
			valvesClosed += 1
			MissionEvents.record(player, "GasValveClosed")
			if valvesClosed >= R.Valves then
				Notify.all("✅ All gas shut off: the fire stops spreading. The DOCK EXIT is open: get out!", "success")
				Notify.effectAll("Banner", {
					Title = "EXIT UNLOCKED",
					Subtitle = "Escape through the loading dock's emergency exit!",
					Color = "Green",
					Sound = "PowerUp",
				})
				local barrier = exitBarrier
				if barrier then
					barrier.CanCollide = false
					barrier:SetAttribute("Done", true)
					TweenService
						:Create(barrier, TweenInfo.new(1.5), { CFrame = barrier.CFrame + Vector3.new(0, 11, 0) })
						:Play()
				end
			else
				Notify.all(
					string.format(
						"🔧 %s shut a gas main (%d/%d): the fire slows down.",
						player.DisplayName,
						valvesClosed,
						R.Valves
					),
					"success"
				)
			end
		end)
	end
end

local function buildExit(parent: Instance)
	local door = EXIT.Door
	local barrier = Builder.part({
		Name = "ExitBarrier",
		Parent = parent,
		Size = Vector3.new(12, 12, 0.6),
		CFrame = CFrame.new(door + Vector3.new(0, 6, 0)),
		Color = Color3.fromRGB(120, 30, 30),
		Material = Enum.Material.CorrodedMetal,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Builder.label(barrier, face, "🔒 EXIT JAMMED\nShut off all 3 gas mains", {
			Color = Color3.fromRGB(255, 230, 200),
			Font = FONT,
			GuiName = "Gui" .. face.Name,
		})
	end
	exitBarrier = barrier
	Builder.part({
		Name = "EscapeZone",
		Parent = parent,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(EXIT.Outside + Vector3.new(0, 3, 0)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Tags = { "EscapeZone" },
	})
end

local function playersInFire()
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if root and root.Position.Y < 8 then
			local c, r = FoodCourtRules.cellAt(root.Position.X, root.Position.Z)
			local key = c and r and FoodCourtRules.cellKey(grid, c, r)
			if key and grid.Burning[key] then
				EnemyService.HitPlayer(player, R.FireDamage, root.Position + Vector3.new(0, -2, 0))
			end
		end
	end
end

local function checkEscapes()
	if valvesClosed < R.Valves then
		return
	end
	local outside = EXIT.Outside
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if root and not escaped[player] then
			local offset = root.Position - outside
			if math.abs(offset.X) <= 9 and offset.Z <= 7 and offset.Z >= -8 and math.abs(offset.Y) < 8 then
				escaped[player] = true
				MissionEvents.record(player, "FireEscaped")
				Notify.all(string.format("🚪 %s escaped the fire!", player.DisplayName), "success")
			end
		end
	end
end

local function runFire(myToken: {})
	for _, start in FIRE_STARTS do
		local c, r = FoodCourtRules.cellAt(start[1], start[2])
		if c and r and FoodCourtRules.ignite(grid, c, r, os.clock()) then
			setBurning(FoodCourtRules.cellKey(grid, c, r) :: number, true)
		end
	end
	local lastSpread = os.clock()
	while nightToken == myToken do
		task.wait(0.25)
		local now = os.clock()
		if now - lastSpread >= R.SpreadEvery then
			lastSpread = now
			for _, key in
				FoodCourtRules.spread(grid, now, FoodCourtRules.spreadChance(valvesClosed), function()
					return rng:NextNumber()
				end)
			do
				setBurning(key, true)
			end
		end
		playersInFire()
		checkEscapes()
	end
end

local function clearNight()
	nightToken = nil
	for player in charges do
		if Carry.item(player) == "Extinguisher" then
			Carry.drop(player)
		end
	end
	table.clear(charges)
	table.clear(cells)
	table.clear(escaped)
	exitBarrier = nil
	grid = FoodCourtRules.fireGrid()
	valvesClosed = 0
	if nightFolder then
		nightFolder:Destroy()
		nightFolder = nil
	end
end

function KitchenFire.StartNight()
	clearNight()
	local myToken = {}
	nightToken = myToken
	local folder = Instance.new("Folder")
	folder.Name = "GreaseFireNight"
	folder.Parent = workspace
	nightFolder = folder
	buildExtinguishers(folder)
	buildValves(folder, myToken)
	buildExit(folder)
	Notify.effectAll("Banner", {
		Title = "🔥 GREASE FIRE!",
		Subtitle = "Shut the 3 gas mains, then escape through the loading dock.",
		Color = "Red",
		Sound = "Warning",
	})
	task.spawn(runFire, myToken)
	if RunService:IsStudio() and workspace:GetAttribute("FireTest_CloseValves") == true then
		-- Studio helper: start with the gas off and the exit open (test the escape)
		valvesClosed = R.Valves
		if exitBarrier then
			exitBarrier.CanCollide = false
			exitBarrier.Transparency = 0.8
		end
	end
end

function KitchenFire.EndNight()
	clearNight()
end

return KitchenFire
