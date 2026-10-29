-- Level 9: Day "Live Wires" / Night "Grease Fire".
--
-- Day:   the food court's wiring is shot (the lights flicker). Six broken cables cycle
--        between LIVE (sparks, shocks anyone close, can't be touched) and SAFE: hold E to
--        splice one while it's safe. Once five are spliced the switchboard in the
--        maintenance corridor unlocks: pull either breaker (it stays on and a countdown
--        starts on everyone's screen), then the other one before the timer runs out
--        (FoodCourtRules.leverWindow: 10 s solo, 8 s with teammates). Too slow and both
--        snap back: just try again. Pulling a held breaker again restarts its timer.
-- Night: a grease fire breaks out in the grand kitchen and spreads cell by cell over the
--        kitchen and dining hall (FoodCourtRules fire grid). A cell about to catch glows
--        and smokes first (harmless warning), then bursts into flame; fire only crosses
--        the kitchen wall at its doorways. Standing in flames hurts. Extinguishers from
--        the red wall cabinets (8 sprays each) put out a cell and its neighbours and
--        leave foam that can't reignite for a while. Shut the three gas valves to stop
--        the spread and unlock the loading dock's emergency exit; walk out onto the
--        landing to escape. The south restaurants are fire-free refuges on the way.
--        Once everyone is out, dawn comes AllOutDawn seconds later.
--
-- Studio helper: Workspace FireTest_CloseValves = true (before the night) starts it with
-- the gas off and the exit open.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local DataService = require(script.Parent.Parent.Services.DataService)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
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
local FIRE = Color3.fromRGB(255, 120, 30)
local EMBER = Color3.fromRGB(255, 70, 20)
local CHAR = Color3.fromRGB(34, 28, 26)
local FOAM = Color3.fromRGB(225, 240, 255)

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

type Cell = { Glow: BasePart, Scorch: BasePart, Flames: ParticleEmitter, Smoke: ParticleEmitter?, Light: PointLight? }

local dayFolder: Folder? = nil
local nightFolder: Folder? = nil
local dayToken: {}? = nil
local nightToken: {}? = nil
local spliced = 0
local switchboardDone = false
local valvesClosed = 0
local grid: FoodCourtRules.FireGrid = FoodCourtRules.fireGrid()
local cells: { [number]: Cell } = {}
local scorches: { [number]: BasePart } = {}
local charges: { [Player]: number } = {}
local escaped: { [Player]: boolean } = {}
local burnToldAt: { [Player]: number } = {}
local exitBarrier: BasePart? = nil
local exitBeacon: BasePart? = nil
local allOut = false
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

local function billboard(part: BasePart, offset: number, size: Vector2?, maxDistance: number?): TextLabel
	local dims = size or Vector2.new(160, 30)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(dims.X, dims.Y)
	gui.StudsOffset = Vector3.new(0, offset, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = maxDistance or 70
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = FONT
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = part
	return label
end

-- On-screen countdown for everyone (MeterController draws it).
local function countdown(text: string?, seconds: number?)
	ReplicatedStorage:SetAttribute("Countdown_Text", text)
	ReplicatedStorage:SetAttribute("Countdown_Total", seconds)
	ReplicatedStorage:SetAttribute("Countdown_Ends", if seconds then workspace:GetServerTimeNow() + seconds else nil)
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

type Breaker = {
	Name: string,
	CFrame: CFrame,
	Handle: BasePart,
	Light: BasePart,
	Prompt: ProximityPrompt,
	Label: TextLabel,
}

local OTHER = { A = "B", B = "A" }

local function setHandle(breaker: Breaker, on: boolean)
	TweenService:Create(breaker.Handle, TweenInfo.new(0.2), {
		CFrame = breaker.CFrame * CFrame.new(0, 4.6, -1) * CFrame.Angles(math.rad(if on then 35 else -35), 0, 0),
	}):Play()
	breaker.Light.Color = if on then Palette.NeonGreen else Palette.NeonRed
	-- a held breaker is "done" for the guide arrow, which then points at the other one
	breaker.Handle:SetAttribute("Done", if on then true else nil)
end

local function buildSwitchboard(parent: Instance, myToken: {}): (() -> (), () -> ())
	local state: FoodCourtRules.Breakers = { Held = nil, Since = 0 }
	local breakers: { [string]: Breaker } = {}
	local window = R.Window
	local unlocked = false

	local function labelAll()
		for name, breaker in breakers do
			if switchboardDone then
				breaker.Label.Text = "💡 POWER ON"
				breaker.Label.TextColor3 = Palette.NeonGreen
			elseif not unlocked then
				breaker.Label.Text =
					string.format("🔒 BREAKER %s · splice cables %d/%d", name, spliced, R.CableTarget)
				breaker.Label.TextColor3 = Color3.fromRGB(200, 200, 210)
			elseif state.Held == name then
				breaker.Label.Text = string.format("✅ BREAKER %s ON", name)
				breaker.Label.TextColor3 = Palette.NeonGreen
			elseif state.Held then
				local left = FoodCourtRules.breakerLeft(state, os.clock(), window)
				breaker.Label.Text = string.format("⚡ PULL BREAKER %s! %.1fs", name, left)
				breaker.Label.TextColor3 = if left < 3 then Palette.NeonRed else Palette.NeonGold
			else
				breaker.Label.Text = string.format("⚡ BREAKER %s · PULL", name)
				breaker.Label.TextColor3 = Palette.NeonGold
			end
		end
	end

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
		local light = Builder.decor({
			Parent = model,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.9,
			CFrame = cf * CFrame.new(1.3, 6.2, -0.6),
			Color = Palette.NeonRed,
			Material = Enum.Material.Neon,
		})
		Builder.light("PointLight", light, { Color = Palette.NeonGold, Range = 14, Brightness = 1.5 })
		local prompt = Builder.prompt(handle, {
			ActionText = "Pull Breaker " .. name,
			ObjectText = "Locked: splice the cables first",
			HoldDuration = R.LeverSeconds,
			MaxActivationDistance = 9,
			Enabled = false,
		})
		local breaker: Breaker = {
			Name = name,
			CFrame = cf,
			Handle = handle,
			Light = light,
			Prompt = prompt,
			Label = billboard(handle, 5.5, Vector2.new(280, 44), 260),
		}
		breakers[name] = breaker
		prompt.Triggered:Connect(function(player)
			if dayToken ~= myToken or switchboardDone or not unlocked then
				return
			end
			window = FoodCourtRules.leverWindow(#Players:GetPlayers())
			local now = os.clock()
			local previous = state.Held
			local result = FoodCourtRules.pullBreaker(state, name, now, window)
			if result == "Done" then
				switchboardDone = true
				setHandle(breaker, true)
				for _, b in breakers do
					b.Prompt.Enabled = false
					b.Handle:SetAttribute("Done", true)
				end
				countdown(nil, nil)
				ReplicatedStorage:SetAttribute("PowerFlicker", false)
				MissionEvents.record(player, "SwitchboardReset")
				Notify.all(
					string.format("💡 %s threw breaker %s in time: SWITCHBOARD RESET!", player.DisplayName, name),
					"success"
				)
				Notify.effectAll("Banner", {
					Title = "✅ POWER RESTORED",
					Subtitle = "Switchboard reset: the food court's wiring holds. For now...",
					Color = "Green",
					Sound = "PowerUp",
				})
				labelAll()
				return
			end
			if previous and previous ~= name then
				-- the other breaker had already run out: start over from this one
				setHandle(breakers[previous], false)
			end
			setHandle(breaker, true)
			local other = OTHER[name]
			countdown(string.format("⚡ PULL BREAKER %s", other), window)
			Notify.effectAll("Banner", {
				Title = if result == "Restarted"
					then string.format("⏱️ BREAKER %s: TIMER RESTARTED", name)
					else string.format("⚡ BREAKER %s ON", name),
				Subtitle = string.format(
					"Now pull BREAKER %s at the other end of the corridor within %d seconds!",
					other,
					window
				),
				Color = "Gold",
				Sound = "Warning",
			})
			labelAll()
		end)
	end

	-- timer: snap back when it runs out, keep the labels counting
	task.spawn(function()
		while dayToken == myToken and not switchboardDone do
			task.wait(0.1)
			if unlocked then
				local held = state.Held
				if held and FoodCourtRules.breakerExpired(state, os.clock(), window) then
					setHandle(breakers[held], false)
					countdown(nil, nil)
					Notify.effectAll("Banner", {
						Title = "⏱️ TOO SLOW: BREAKERS RESET",
						Subtitle = string.format(
							"Try again: pull either breaker, then reach the other within %d s. Teammates can wait at one!",
							window
						),
						Color = "Red",
						Sound = "UIClick",
					})
				end
			end
			labelAll()
		end
	end)
	labelAll()

	local function unlock()
		unlocked = true
		window = FoodCourtRules.leverWindow(#Players:GetPlayers())
		for _, breaker in breakers do
			breaker.Prompt.Enabled = true
			breaker.Prompt.ObjectText = "Main Breaker"
			breaker.Light.Color = Palette.NeonRed
		end
		labelAll()
		Notify.effectAll("Banner", {
			Title = "🔌 CABLES SPLICED",
			Subtitle = string.format(
				"Maintenance corridor: pull BREAKER A and BREAKER B within %d seconds of each other.",
				window
			),
			Color = "Cyan",
			Sound = "PowerUp",
		})
	end
	return unlock, labelAll
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
	local unlock, refreshBreakers = buildSwitchboard(folder, myToken)
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
				string.format(
					"🔌 %s spliced the %s cable (%d/%d).",
					player.DisplayName,
					info.Name,
					math.min(spliced, R.CableTarget),
					R.CableTarget
				),
				"success"
			)
			if spliced == R.CableTarget then
				unlock()
			end
			refreshBreakers()
		end)
	end
	task.spawn(runCables, cables, myToken)
end

function KitchenFire.EndDay()
	dayToken = nil
	countdown(nil, nil)
	ReplicatedStorage:SetAttribute("PowerFlicker", false)
	if dayFolder then
		dayFolder:Destroy()
		dayFolder = nil
	end
end

-- ── night: the fire ─────────────────────────────────────────────────────────

local function burstEmitter(parent: BasePart, name: string, color: ColorSequence, size: NumberSequence): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = color
	e.Size = size
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(4, 9)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	e.Enabled = false
	e.Parent = parent
	return e
end

-- The charred floor a fire leaves behind (stays after it's out; foam while it's wet).
local function scorch(key: number): BasePart?
	local existing = scorches[key]
	if existing or not nightFolder then
		return existing
	end
	local c, r = FoodCourtRules.cellOf(grid, key)
	local x, z = FoodCourtRules.cellCenter(c, r)
	local part = Builder.decor({
		Name = "Scorch",
		Parent = nightFolder,
		Size = Vector3.new(R.Cell - 0.2, 0.06, R.Cell - 0.2),
		CFrame = CFrame.new(x, 0.04, z) * CFrame.Angles(0, (c * 7 + r * 3) % 4 * math.pi / 2, 0),
		Color = CHAR,
		Material = Enum.Material.Slate,
		Transparency = 0.15,
	})
	burstEmitter(part, "Foam", ColorSequence.new(FOAM), NumberSequence.new(1.5, 4))
	burstEmitter(
		part,
		"Steam",
		ColorSequence.new(Color3.fromRGB(200, 200, 205), Color3.fromRGB(110, 110, 115)),
		NumberSequence.new(3, 8)
	)
	scorches[key] = part
	return part
end

local function sprayPrompt(part: BasePart, key: number)
	local prompt = Builder.prompt(part, {
		ActionText = "Spray",
		ObjectText = "Fire",
		HoldDuration = 0.4,
		MaxActivationDistance = 11,
	})
	prompt:SetAttribute("RequiresCarry", "Extinguisher")
	Builder.tag(prompt, "CarryPrompt")
	prompt.Triggered:Connect(function(player)
		KitchenFire._spray(player, key)
	end)
end

-- A cell catching: a dark-red glowing patch with a thin smoke column (the warning).
local function smolderCell(key: number)
	if cells[key] or not nightFolder then
		return
	end
	local c, r = FoodCourtRules.cellOf(grid, key)
	local x, z = FoodCourtRules.cellCenter(c, r)
	scorch(key)
	local glow = Builder.decor({
		Name = "Fire",
		Parent = nightFolder,
		Size = Vector3.new(R.Cell - 1.6, 0.12, R.Cell - 1.6),
		CFrame = CFrame.new(x, 0.12, z),
		Color = Color3.fromRGB(140, 30, 10),
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		Tags = { "FireCell" },
	})
	glow.CanQuery = false
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 80, 78))
	smoke.Transparency = NumberSequence.new(0.55, 1)
	smoke.Size = NumberSequence.new(1.5, 5)
	smoke.Lifetime = NumberRange.new(1.5, 2.2)
	smoke.Speed = NumberRange.new(2, 4)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Shape = Enum.ParticleEmitterShape.Box
	smoke.Rate = 3
	smoke.Parent = glow
	local flames = Instance.new("ParticleEmitter")
	flames.Name = "Flames"
	flames.Texture = "rbxasset://textures/particles/fire_main.dds"
	flames.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 150)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 150, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 40, 10)),
	})
	flames.LightEmission = 1
	flames.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4.5),
		NumberSequenceKeypoint.new(0.5, 3.2),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	flames.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	flames.Lifetime = NumberRange.new(0.6, 1)
	flames.Speed = NumberRange.new(6, 10)
	flames.SpreadAngle = Vector2.new(12, 12)
	flames.RotSpeed = NumberRange.new(-60, 60)
	flames.Shape = Enum.ParticleEmitterShape.Box
	flames.EmissionDirection = Enum.NormalId.Top
	flames.Rate = 8 -- few, big flames: readable and cheap on low-end PCs
	flames.Enabled = false
	flames.Parent = glow
	cells[key] = { Glow = glow, Scorch = scorch(key) :: BasePart, Flames = flames, Smoke = smoke, Light = nil }
	sprayPrompt(glow, key)
end

-- The cell bursts into flame: bright embers, tall flames, smoke and (on some) light.
local function igniteCell(key: number)
	if not cells[key] then
		smolderCell(key)
	end
	local cell = cells[key]
	if not cell then
		return
	end
	local c, r = FoodCourtRules.cellOf(grid, key)
	cell.Glow.Size = Vector3.new(R.Cell - 0.6, 0.2, R.Cell - 0.6)
	cell.Glow.Color = EMBER
	cell.Glow.Transparency = 0.3
	cell.Flames.Enabled = true
	cell.Flames:Emit(6)
	local smoke = cell.Smoke
	if smoke then
		if (c + r) % 3 == 0 then
			-- a heavier black column on every third cell
			smoke.Color = ColorSequence.new(Color3.fromRGB(45, 40, 40))
			smoke.Size = NumberSequence.new(4, 11)
			smoke.Lifetime = NumberRange.new(3, 4)
			smoke.Rate = 1.5
		else
			smoke.Enabled = false
		end
	end
	if (c + r) % 4 == 0 then
		local light = Instance.new("PointLight")
		light.Color = FIRE
		light.Range = 20
		light.Brightness = 2.5
		light.Parent = cell.Glow
		cell.Light = light
	end
end

local function douse(key: number)
	local cell = cells[key]
	if not cell then
		return
	end
	cells[key] = nil
	local glow = cell.Glow
	for _, child in glow:GetChildren() do
		if child:IsA("ParticleEmitter") then
			child.Enabled = false
		elseif child:IsA("ProximityPrompt") or child:IsA("Light") then
			child:Destroy()
		end
	end
	TweenService:Create(glow, TweenInfo.new(0.5), { Transparency = 1 }):Play()
	task.delay(1.2, function()
		glow:Destroy()
	end)
	-- foam and steam where it was; the foam fades back to char when it dries
	local floor = cell.Scorch
	local foam = floor:FindFirstChild("Foam") :: ParticleEmitter?
	local steam = floor:FindFirstChild("Steam") :: ParticleEmitter?
	if foam then
		foam:Emit(10)
	end
	if steam then
		steam:Emit(6)
	end
	floor.Color = FOAM
	floor.Material = Enum.Material.SmoothPlastic
	floor.Transparency = 0.25
	task.delay(R.WetSeconds, function()
		if floor.Parent and not cells[key] then
			TweenService:Create(floor, TweenInfo.new(2), { Color = CHAR, Transparency = 0.15 }):Play()
			floor.Material = Enum.Material.Slate
		end
	end)
end

function KitchenFire._spray(player: Player, key: number)
	if not nightToken or Carry.item(player) ~= "Extinguisher" then
		return
	end
	if not grid.Burning[key] and not grid.Smolder[key] then
		return
	end
	local c, r = FoodCourtRules.cellOf(grid, key)
	local out = FoodCourtRules.extinguish(grid, c, r, os.clock())
	for _, putOut in out do
		douse(putOut)
	end
	charges[player] = (charges[player] or R.Charges) - 1
	local left = charges[player]
	if #out > 0 then
		MissionEvents.record(player, "FireExtinguished", #out)
		local x, z = FoodCourtRules.cellCenter(c, r)
		Notify.effect(player, "WorldPopup", {
			Position = Vector3.new(x, 4, z),
			Text = string.format("💨 %d FIRE%s OUT!", #out, if #out == 1 then "" else "S"),
			Color = "Cyan",
		})
	end
	if left <= 0 then
		charges[player] = nil
		Carry.consume(player, "Extinguisher")
		Notify.effect(
			player,
			"Popup",
			{ Text = "🧯 EMPTY! Grab another from a red cabinet", Color = "Red", Y = 0.62 }
		)
	else
		Notify.effect(
			player,
			"Popup",
			{ Text = string.format("🧯 %d/%d sprays left", left, R.Charges), Color = "Cyan", Y = 0.62 }
		)
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
		local label = billboard(cabinet, 3.4, Vector2.new(150, 26), 60)
		label.Text = "🧯 EXTINGUISHER"
		label.TextColor3 = Color3.fromRGB(255, 120, 110)
		local prompt = Builder.prompt(cabinet, {
			ActionText = "Take Extinguisher",
			ObjectText = "Fire Cabinet",
			HoldDuration = 0,
			MaxActivationDistance = 9,
		})
		prompt.Triggered:Connect(function(player)
			if nightToken and Carry.pickUp(player, "Extinguisher") then
				charges[player] = R.Charges
				Notify.effect(player, "Popup", {
					Text = string.format("🧯 Extinguisher: %d sprays. Hold E at flames", R.Charges),
					Color = "Cyan",
					Y = 0.62,
				})
			end
		end)
		local c, r = FoodCourtRules.cellAt(cf.Position.X, cf.Position.Z)
		local key = c and r and FoodCourtRules.cellKey(grid, c, r)
		if key then
			grid.Protected[key] = true
		end
	end
end

local function openExit()
	local barrier = exitBarrier
	if barrier and not barrier:GetAttribute("Done") then
		barrier.CanCollide = false
		barrier:SetAttribute("Done", true)
		TweenService:Create(barrier, TweenInfo.new(1.5), { CFrame = barrier.CFrame + Vector3.new(0, 11, 0) }):Play()
	end
	local beacon = exitBeacon
	if beacon then
		beacon.Transparency = 0.55
		local label = beacon:FindFirstChildWhichIsA("BillboardGui")
		if label then
			label.Enabled = true
		end
	end
end

local function buildValves(parent: Instance, myToken: {})
	local remaining: { [string]: boolean } = {}
	for _, info in VALVES do
		remaining[info.Name] = true
	end
	for _, info in VALVES do
		local cf: CFrame = info.CFrame
		local model = Builder.model("GasValve", parent)
		Builder.beam(cf.Position, cf.Position + Vector3.new(0, 9, 0), 0.7, {
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
		Builder.light("PointLight", wheel, { Color = Palette.NeonRed, Range = 12, Brightness = 1.5 })
		-- visible through walls from across the court: these are the ones still to shut
		local label = billboard(wheel, 3, Vector2.new(240, 34), 400)
		label.Text = "🔥 " .. string.upper(info.Name) .. ": ON"
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
			label.Text = "✅ " .. string.upper(info.Name) .. ": OFF"
			label.TextColor3 = Palette.NeonGreen
			task.delay(6, function()
				local gui = label.Parent :: BillboardGui?
				if gui then
					gui.Enabled = false -- only the valves still open stay marked
				end
			end)
			remaining[info.Name] = nil
			valvesClosed += 1
			MissionEvents.record(player, "GasValveClosed")
			if valvesClosed >= R.Valves then
				Notify.all("✅ All gas shut off: the fire stops spreading. The DOCK EXIT is open: get out!", "success")
				Notify.effectAll("Banner", {
					Title = "🚪 EXIT UNLOCKED",
					Subtitle = "Escape through the loading dock's emergency exit (green light)!",
					Color = "Green",
					Sound = "PowerUp",
				})
				openExit()
			else
				local left = {}
				for name in remaining do
					table.insert(left, name)
				end
				table.sort(left)
				Notify.all(
					string.format(
						"🔧 %s shut the %s (%d/%d). Still open: %s",
						player.DisplayName,
						info.Name,
						valvesClosed,
						R.Valves,
						table.concat(left, ", ")
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
	-- a green light column on the landing, lit once the exit opens
	local beacon = Builder.decor({
		Name = "ExitBeacon",
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(40, 3, 3),
		CFrame = CFrame.new(EXIT.Outside + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.NeonGreen,
		Material = Enum.Material.Neon,
		Transparency = 1,
	})
	local label = billboard(beacon, 0, Vector2.new(200, 40), 500)
	label.Text = "🚪 EMERGENCY EXIT"
	label.TextColor3 = Palette.NeonGreen
	local gui = label.Parent :: BillboardGui
	gui.Enabled = false
	exitBeacon = beacon
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
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if root and root.Position.Y < 8 then
			local c, r = FoodCourtRules.cellAt(root.Position.X, root.Position.Z)
			local key = c and r and FoodCourtRules.cellKey(grid, c, r)
			if key and grid.Burning[key] then
				EnemyService.HitPlayer(player, R.FireDamage, root.Position + Vector3.new(0, -2, 0))
				if now - (burnToldAt[player] or 0) > 2.5 then
					burnToldAt[player] = now
					Notify.effect(player, "Popup", { Text = "🔥 YOU'RE BURNING! GET OUT!", Color = "Red", Y = 0.45 })
				end
			end
		end
	end
end

-- What escaping means for this player's level progress (the night ends at dawn).
local function escapeNote(player: Player): string
	local levelId = ReplicatedStorage:GetAttribute("LevelId")
	local data = DataService.Get(player)
	local campaign = data and data.Campaign
	if type(levelId) == "string" and campaign and campaign.DayCleared[levelId] ~= true then
		return "⚠️ You're out, but this level's DAY isn't cleared (the switchboard?): it won't complete tonight. Clear the day next shift."
	end
	return "✅ You're out! Night objectives done: the level completes at dawn."
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
			if FoodCourtRules.onDockLanding(offset.X, offset.Y, offset.Z) then
				escaped[player] = true
				MissionEvents.record(player, "FireEscaped")
				Notify.all(string.format("🚪 %s escaped the fire!", player.DisplayName), "success")
				Notify.player(player, escapeNote(player), "info")
			end
		end
	end
	if not allOut and FoodCourtRules.allEscaped(Players:GetPlayers(), escaped) then
		allOut = true
		GameStateService.ShortenPhase(R.AllOutDawn)
		Notify.effectAll("Banner", {
			Title = "🚪 EVERYONE'S OUT!",
			Subtitle = string.format("The fire burns itself out. Dawn in %d seconds.", R.AllOutDawn),
			Color = "Green",
			Sound = "LevelUp",
		})
	end
end

local function runFire(myToken: {})
	for _, start in FIRE_STARTS do
		local c, r = FoodCourtRules.cellAt(start[1], start[2])
		if c and r and FoodCourtRules.ignite(grid, c, r, os.clock()) then
			igniteCell(FoodCourtRules.cellKey(grid, c, r) :: number)
		end
	end
	local lastSpread = os.clock()
	while nightToken == myToken do
		task.wait(0.25)
		local now = os.clock()
		for _, key in FoodCourtRules.advance(grid, now) do
			igniteCell(key)
		end
		if now - lastSpread >= R.SpreadEvery then
			lastSpread = now
			for _, key in
				FoodCourtRules.spread(grid, now, FoodCourtRules.spreadChance(valvesClosed), function()
					return rng:NextNumber()
				end)
			do
				smolderCell(key)
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
	table.clear(scorches)
	table.clear(escaped)
	table.clear(burnToldAt)
	exitBarrier = nil
	exitBeacon = nil
	allOut = false
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
		Subtitle = "Shut the 3 gas mains (red markers), then escape through the loading dock.",
		Color = "Red",
		Sound = "Warning",
	})
	task.spawn(runFire, myToken)
	if RunService:IsStudio() and workspace:GetAttribute("FireTest_CloseValves") == true then
		-- Studio helper: start with the gas off and the exit open (test the escape)
		valvesClosed = R.Valves
		openExit()
	end
end

function KitchenFire.EndNight()
	clearNight()
end

return KitchenFire
