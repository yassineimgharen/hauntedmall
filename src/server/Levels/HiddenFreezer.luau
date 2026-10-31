-- Level 11: Day "Cold Trail" / Night "Deep Freeze".
--
-- Day:   frost footprints lead from Frost Bite Creamery through the maintenance corridor
--        into the walk-in freezer. They're invisible until a flashlight beam passes over
--        them. They end at the freezer's west wall: a lever frozen in ice (melt it with
--        light, then pull it) slides the false wall away. The hidden freezer behind it
--        chills you fast (cold meter): chip the frozen logbooks out of the ice and warm
--        up at the heat lamp outside before you freeze solid.
-- Night: the Frost Wraith comes out of the hidden freezer. Light can't hurt it, only slow
--        it. Its aura and frost breath fill your cold meter; at full you freeze solid for
--        a moment. It ignores anyone inside a heat lamp's glow. The way out, the north
--        emergency exit, is iced over: melt it with flashlights (the cracking draws the
--        wraith), then get out onto the landing.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local CombatService = require(script.Parent.Parent.Services.CombatService)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local Layout = require(script.Parent.Parent.World.Layout)
local FoodCourtRules = require(script.Parent.FoodCourtRules)

local HiddenFreezer = {}

local R = FoodCourtRules.L11
local F = Layout.FoodCourt
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local ICE = Color3.fromRGB(180, 225, 255)
local HEAT = Color3.fromRGB(255, 140, 50)
local PRINTS = {
	Vector3.new(-169, 0, 58),
	Vector3.new(-173, 0, 66),
	Vector3.new(-177, 0, 74),
	Vector3.new(-178, 0, 82),
	Vector3.new(-189, 0, 85),
	Vector3.new(-203, 0, 80),
	Vector3.new(-216, 0, 76),
	Vector3.new(-233, 0, 67),
	Vector3.new(-245, 0, 64),
}
local LEVER = CFrame.lookAt(Vector3.new(-248.4, 0, 55), Vector3.new(-230, 0, 55))
local LOGS = {
	{
		At = Vector3.new(-280, 0, 58),
		Text = "Day 1: The new chef never leaves the kitchen. The walk-in is always locked.",
	},
	{
		At = Vector3.new(-280, 0, 82),
		Text = "Day 9: Deliveries come at 3 AM now. Unlabelled. The chef signs for them himself.",
	},
	{
		At = Vector3.new(-262, 0, 80),
		Text = "Day 14: Marco went into the back freezer and came out... cold. He doesn't blink.",
	},
	{
		At = Vector3.new(-266, 0, 58),
		Text = "Day 20: The chef is GROWING. He says the food court is hungry. I'm sealing this door.",
	},
}
local DAY_LAMPS = { Vector3.new(-236, 0, 58) }
local NIGHT_LAMPS = {
	Vector3.new(-236, 0, 58),
	Vector3.new(-125, 0, -20),
	Vector3.new(-160, 0, 25),
	Vector3.new(-210, 0, -10),
	Vector3.new(-150, 0, 85),
	Vector3.new(-130, 0, -100),
	Vector3.new(-215, 0, -75),
}
local PATROL = {
	Vector3.new(-141, 0, 0),
	Vector3.new(-217, 0, 0),
	Vector3.new(-141, 0, 85),
	Vector3.new(-129, 0, -110),
	Vector3.new(-110, 0, -30),
	Vector3.new(-170, 0, 30),
}
local NORTH = F.Exits.North
local WRAITH_HOME = Vector3.new(-269, 0, 70)

type Chill = { Cold: number, FrozenUntil: number, EverFrozen: boolean, Character: Model?, Block: BasePart? }

local folder: Folder? = nil
local token: {}? = nil
local stage: "Day" | "Night" | nil = nil
local lamps: { Vector3 } = {}
local chill: { [Player]: Chill } = {}
local targets: { Model } = {}
local escaped: { [Player]: boolean } = {}
local iceWall: BasePart? = nil
local wallOpen = false

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

local function register(model: Model, onLit: (Player, number) -> (), part: BasePart, radius: number)
	table.insert(targets, model)
	CombatService.RegisterLightTarget(model, function(player, dt)
		onLit(player, dt)
	end, { Parts = { part }, Radius = { radius } })
end

local function unregisterAll()
	for _, model in targets do
		CombatService.UnregisterLightTarget(model)
	end
	table.clear(targets)
end

local function progressBar(part: BasePart, title: string, offset: number): (Frame, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(150, 32)
	gui.StudsOffset = Vector3.new(0, offset, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Text = title
	label.TextScaled = true
	label.TextColor3 = ICE
	label.FontFace = FONT
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 8)
	back.Position = UDim2.fromOffset(0, 22)
	back.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = HEAT
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = part
	return fill, label
end

-- ── the false wall ──────────────────────────────────────────────────────────

local function falseWall(): BasePart?
	for _, part in CollectionService:GetTagged("FalseWall") do
		if part:IsA("BasePart") then
			if part:GetAttribute("ClosedCFrame") == nil then
				part:SetAttribute("ClosedCFrame", part.CFrame)
			end
			return part
		end
	end
	return nil
end

local function openWall(instant: boolean?)
	local wall = falseWall()
	if not wall or wallOpen then
		return
	end
	wallOpen = true
	local closed = wall:GetAttribute("ClosedCFrame") :: CFrame
	wall.CanCollide = false
	local goal = closed - Vector3.new(0, 9.3, 0)
	if instant then
		wall.CFrame = goal
	else
		TweenService:Create(wall, TweenInfo.new(2.4, Enum.EasingStyle.Quad), { CFrame = goal }):Play()
	end
end

local function closeWall()
	local wall = falseWall()
	if not wall then
		return
	end
	wallOpen = false
	wall.CFrame = wall:GetAttribute("ClosedCFrame") :: CFrame
	wall.CanCollide = true
end

-- ── heat lamps and the cold meter ───────────────────────────────────────────

local function buildLamp(parent: Instance, at: Vector3)
	local model = Builder.model("HeatLamp", parent)
	Builder.part({
		Parent = model,
		Size = Vector3.new(0.4, 7, 0.4),
		CFrame = CFrame.new(at + Vector3.new(0, 3.5, 0)),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Metal,
	})
	local head = Builder.decor({
		Parent = model,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.6,
		CFrame = CFrame.new(at + Vector3.new(0, 7.2, 0)),
		Color = HEAT,
		Material = Enum.Material.Neon,
		Tags = { "HeatLamp" },
	})
	Builder.light("PointLight", head, { Color = HEAT, Range = R.HeatRadius + 6, Brightness = 2.2, Shadows = false })
	Builder.decor({
		Parent = model,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.08, R.HeatRadius * 2, R.HeatRadius * 2),
		CFrame = CFrame.new(at + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = HEAT,
		Material = Enum.Material.Neon,
		Transparency = 0.82,
	})
	table.insert(lamps, at)
end

local function inHeat(position: Vector3): boolean
	for _, at in lamps do
		if
			Vector3.new(position.X - at.X, 0, position.Z - at.Z).Magnitude <= R.HeatRadius
			and math.abs(position.Y - at.Y) < 7
		then
			return true
		end
	end
	return false
end

local function inBox(p: Vector3, box: { MinX: number, MaxX: number, MinZ: number, MaxZ: number }): boolean
	return p.X >= box.MinX and p.X <= box.MaxX and p.Z >= box.MinZ and p.Z <= box.MaxZ and p.Y < 16
end

local function wraiths(): { any }
	local list = {}
	for _, enemy in EnemyService.GetAll() do
		if enemy.Type == "FrostWraith" and not enemy.Dead then
			table.insert(list, enemy)
		end
	end
	return list
end

local function chillOf(player: Player): Chill
	local state = chill[player]
	if not state or state.Character ~= player.Character then
		if state and state.Block then
			state.Block:Destroy()
		end
		state = {
			Cold = 0,
			FrozenUntil = 0,
			EverFrozen = if state then state.EverFrozen else false,
			Character = player.Character,
			Block = nil,
		}
		chill[player] = state
	end
	return state
end

local function freeze(player: Player, state: Chill, root: BasePart, now: number)
	state.FrozenUntil = now + R.FrozenSeconds
	state.EverFrozen = true
	player:SetAttribute("MoveScale", 0)
	EnemyService.HitPlayer(player, R.ChillDamage, root.Position)
	MissionEvents.record(player, "FrozenSolid")
	Notify.effect(player, "Popup", { Text = "❄️ FROZEN SOLID!", Color = "Cyan", Y = 0.45 })
	local block = Builder.decor({
		Name = "IceBlock",
		Parent = folder,
		Size = Vector3.new(4.5, 6.5, 4.5),
		CFrame = CFrame.new(root.Position - Vector3.new(0, 0.3, 0)),
		Color = ICE,
		Material = Enum.Material.Glass,
		Transparency = 0.45,
	})
	state.Block = block
	task.delay(R.FrozenSeconds, function()
		block:Destroy()
		if state.Block == block then
			state.Block = nil
		end
	end)
end

local function stepCold(dt: number)
	local now = os.clock()
	local hunters = if stage == "Night" then wraiths() else {}
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		local state = chillOf(player)
		if not root then
			continue
		end
		local position = root.Position
		if now < state.FrozenUntil then
			player:SetAttribute("Meter_Cold", 1)
			continue
		end
		local nearest = nil
		for _, wraith in hunters do
			local d = (wraith.Root.Position - position).Magnitude
			nearest = if nearest then math.min(nearest, d) else d
		end
		local place = {
			InHeat = inHeat(position),
			InHiddenFreezer = inBox(position, F.HiddenFreezer),
			InWalkIn = inBox(position, F.Freezer),
			WraithDistance = nearest,
		}
		if state.FrozenUntil > 0 and state.Cold >= 1 then
			state.Cold = R.ThawTo -- just thawed
		end
		state.Cold = FoodCourtRules.coldStep(state.Cold, dt, place)
		if state.Cold >= 1 then
			freeze(player, state, root, now)
		end
		local relevant = stage == "Night" or state.Cold > 0 or place.InHiddenFreezer
		player:SetAttribute("Meter_Cold", if relevant then state.Cold else nil)
		local scale = if now < state.FrozenUntil then 0 elseif state.Cold > 0.75 then 0.75 else nil
		if player:GetAttribute("MoveScale") ~= scale then
			player:SetAttribute("MoveScale", scale)
		end
	end
end

local function runCold(myToken: {})
	local last = os.clock()
	while token == myToken do
		task.wait(0.25)
		local now = os.clock()
		stepCold(now - last)
		last = now
		if stage == "Night" then
			HiddenFreezer._checkEscapes()
		end
	end
end

local function clearPlayers()
	for player, state in chill do
		if state.Block then
			state.Block:Destroy()
		end
		if player.Parent then
			player:SetAttribute("Meter_Cold", nil)
			player:SetAttribute("MoveScale", nil)
		end
	end
	table.clear(chill)
end

-- ── day ─────────────────────────────────────────────────────────────────────

local function buildPrints(parent: Instance, myToken: {})
	local prints = {}
	local revealed = 0
	local function tagNext()
		for _, print in prints do
			CollectionService:RemoveTag(print.Anchor, "FrostPrintNext")
		end
		for _, print in prints do
			if not print.Done then
				CollectionService:AddTag(print.Anchor, "FrostPrintNext")
				return
			end
		end
	end
	for index, at in PRINTS do
		local model = Builder.model("FrostPrint" .. index, parent)
		local nextAt = PRINTS[index + 1] or (LEVER.Position + Vector3.new(4, 0, 0))
		local facing = CFrame.lookAt(at, Vector3.new(nextAt.X, at.Y, nextAt.Z))
		local parts = {}
		for _, side in { -0.6, 0.6 } do
			table.insert(
				parts,
				Builder.decor({
					Name = "Footprint",
					Parent = model,
					Size = Vector3.new(0.8, 0.05, 1.7),
					CFrame = facing * CFrame.new(side, 0.05, if side < 0 then 0.5 else -0.5),
					Color = Color3.fromRGB(190, 235, 255),
					Material = Enum.Material.Neon,
					Transparency = 1,
				})
			)
		end
		local anchor = Builder.part({
			Name = "PrintAnchor",
			Parent = model,
			Size = Vector3.new(1, 0.2, 1),
			CFrame = facing * CFrame.new(0, 0.1, 0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		model.PrimaryPart = anchor
		local print = { Anchor = anchor, Done = false, Lit = 0 }
		table.insert(prints, print)
		register(model, function(player, dt)
			if print.Done or token ~= myToken then
				return
			end
			print.Lit += dt
			if print.Lit < R.PrintRevealSeconds then
				return
			end
			print.Done = true
			markDone(anchor, nil)
			CombatService.UnregisterLightTarget(model)
			for _, part in parts do
				TweenService:Create(part, TweenInfo.new(0.4), { Transparency = 0.15 }):Play()
			end
			revealed += 1
			MissionEvents.record(player, "FrostPrintFound")
			Notify.effect(
				player,
				"WorldPopup",
				{ Position = at + Vector3.new(0, 2, 0), Text = "👣 FROSTY PRINTS!", Color = "Cyan" }
			)
			if revealed == 1 then
				Notify.all("👣 Frozen footprints! Keep your flashlight on the floor and follow them.", "info")
			end
			tagNext()
		end, anchor, 1.6)
	end
	tagNext()
end

local function buildLever(parent: Instance, myToken: {})
	local model = Builder.model("FrozenLever", parent)
	Builder.part({
		Parent = model,
		Size = Vector3.new(3, 4, 0.8),
		CFrame = LEVER * CFrame.new(0, 4, 0),
		Color = Palette.DarkMetal,
		Material = Enum.Material.DiamondPlate,
	})
	local handle = Builder.part({
		Name = "Handle",
		Parent = model,
		Size = Vector3.new(0.5, 2.4, 0.5),
		CFrame = LEVER * CFrame.new(0, 4, -0.9) * CFrame.Angles(math.rad(-30), 0, 0),
		Color = Palette.NeonRed,
		Tags = { "FrozenLever" },
	})
	local ice = Builder.part({
		Name = "Ice",
		Parent = model,
		Size = Vector3.new(4, 5, 3),
		CFrame = LEVER * CFrame.new(0, 4, -0.8),
		Color = ICE,
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		CanCollide = false,
	})
	model.PrimaryPart = ice
	local fill, label = progressBar(ice, "🧊 FROZEN: MELT WITH LIGHT", 3.6)
	local prompt = Builder.prompt(handle, {
		ActionText = "Pull",
		ObjectText = "Frozen Lever",
		HoldDuration = R.LeverHold,
		MaxActivationDistance = 8,
		Enabled = false,
	})
	local melted = 0
	register(model, function(_player, dt)
		if token ~= myToken or melted >= R.IceLeverSeconds then
			return
		end
		melted = math.min(melted + dt, R.IceLeverSeconds)
		fill.Size = UDim2.fromScale(melted / R.IceLeverSeconds, 1)
		ice.Transparency = 0.35 + 0.6 * melted / R.IceLeverSeconds
		if melted >= R.IceLeverSeconds then
			CombatService.UnregisterLightTarget(model)
			ice:Destroy()
			prompt.Enabled = true
			label.Text = "✅ THAWED: PULL IT"
		end
	end, ice, 2.5)
	prompt.Triggered:Connect(function(player)
		if token ~= myToken or handle:GetAttribute("Done") then
			return
		end
		markDone(handle, prompt)
		TweenService:Create(
			handle,
			TweenInfo.new(0.3),
			{ CFrame = LEVER * CFrame.new(0, 4, -0.9) * CFrame.Angles(math.rad(30), 0, 0) }
		):Play()
		openWall()
		MissionEvents.record(player, "HiddenFreezerOpened")
		Notify.effectAll("Banner", {
			Title = "🧊 A HIDDEN FREEZER",
			Subtitle = "It's freezing in there: grab the logbooks and warm up at the heat lamp!",
			Color = "Cyan",
			Sound = "PowerUp",
		})
	end)
end

local function buildLogs(parent: Instance, myToken: {})
	for index, info in LOGS do
		local model = Builder.model("FrozenLog" .. index, parent)
		local block = Builder.part({
			Name = "IceBlock",
			Parent = model,
			Size = Vector3.new(3.4, 3.4, 3.4),
			CFrame = CFrame.new(info.At + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, index, 0),
			Color = ICE,
			Material = Enum.Material.Glass,
			Transparency = 0.3,
			Tags = { "FrozenLog" },
		})
		Builder.decor({
			Parent = model,
			Size = Vector3.new(1.4, 0.4, 1.8),
			CFrame = block.CFrame * CFrame.Angles(0.3, 0, 0.2),
			Color = Color3.fromRGB(110, 60, 40),
			Material = Enum.Material.Leather,
		})
		local prompt = Builder.prompt(block, {
			ActionText = "Chip the Ice",
			ObjectText = "Frozen Logbook",
			HoldDuration = R.ChipSeconds,
			MaxActivationDistance = 8,
		})
		prompt.Triggered:Connect(function(player)
			if token ~= myToken or block:GetAttribute("Done") or not wallOpen then
				return
			end
			markDone(block, prompt)
			TweenService:Create(block, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			MissionEvents.record(player, "FrozenLogRecovered")
			Notify.all("📓 " .. info.Text, "info")
		end)
	end
end

function HiddenFreezer.StartDay()
	HiddenFreezer.EndNight()
	local myToken = {}
	token = myToken
	stage = "Day"
	local newFolder = Instance.new("Folder")
	newFolder.Name = "ColdTrailDay"
	newFolder.Parent = workspace
	folder = newFolder
	for _, at in DAY_LAMPS do
		buildLamp(newFolder, at)
	end
	buildPrints(newFolder, myToken)
	buildLever(newFolder, myToken)
	buildLogs(newFolder, myToken)
	task.spawn(runCold, myToken)
end

function HiddenFreezer.EndDay()
	-- the wall stays open into the night: that's where the wraith comes from
	token = nil
	stage = nil
	unregisterAll()
	clearPlayers()
	table.clear(lamps)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

-- ── night ───────────────────────────────────────────────────────────────────

local function buildIceWall(parent: Instance, myToken: {})
	local door = NORTH.Door
	local seconds = FoodCourtRules.iceWallSeconds(#Players:GetPlayers())
	local model = Builder.model("IceWall", parent)
	local wall = Builder.part({
		Name = "IceWall",
		Parent = model,
		Size = Vector3.new(2.6, 9, 8.4),
		CFrame = CFrame.new(door + Vector3.new(0, 4.5, 0)),
		Color = ICE,
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Tags = { "IceWall" },
	})
	model.PrimaryPart = wall
	iceWall = wall
	local fill, label = progressBar(wall, "🧊 ICED-OVER EXIT", 6)
	local melted = 0
	local lastLure = 0
	register(model, function(player, dt)
		if token ~= myToken or melted >= seconds then
			return
		end
		melted = math.min(melted + dt, seconds)
		fill.Size = UDim2.fromScale(melted / seconds, 1)
		wall.Transparency = 0.2 + 0.6 * melted / seconds
		local now = os.clock()
		if now - lastLure > 8 then
			lastLure = now
			for _, wraith in wraiths() do
				wraith.Custom.LureTo = door - Vector3.new(6, 0, 0)
				task.delay(8, function()
					wraith.Custom.LureTo = nil
				end)
			end
			Notify.all("🧊 The ice is cracking... the wraith heard it!", "warning")
		end
		if melted >= seconds then
			CombatService.UnregisterLightTarget(model)
			markDone(wall, nil)
			wall.CanCollide = false
			label.Text = "✅ MELTED: GET OUT!"
			TweenService:Create(wall, TweenInfo.new(1), { Transparency = 1 }):Play()
			MissionEvents.record(player, "IceWallMelted")
			Notify.effectAll("Banner", {
				Title = "THE EXIT IS OPEN",
				Subtitle = "Run for the north emergency exit!",
				Color = "Green",
				Sound = "PowerUp",
			})
		end
	end, wall, 4)
	Builder.part({
		Name = "EscapeZone",
		Parent = parent,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(NORTH.Outside + Vector3.new(0, 3, 0)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Tags = { "EscapeZone" },
	})
end

function HiddenFreezer._checkEscapes()
	local wall = iceWall
	if not wall or not wall:GetAttribute("Done") then
		return
	end
	local outside = NORTH.Outside
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if root and not escaped[player] then
			local offset = root.Position - outside
			if offset.X >= -7 and offset.X <= 8 and math.abs(offset.Z) <= 9 and math.abs(offset.Y) < 8 then
				escaped[player] = true
				MissionEvents.record(player, "FreezerEscaped")
				local state = chill[player]
				if not (state and state.EverFrozen) then
					MissionEvents.record(player, "CleanEscape")
				end
				Notify.all(string.format("🚪 %s escaped the Frost Wraith!", player.DisplayName), "success")
			end
		end
	end
end

function HiddenFreezer.StartNight()
	local myToken = {}
	token = myToken
	stage = "Night"
	table.clear(escaped)
	local newFolder = Instance.new("Folder")
	newFolder.Name = "DeepFreezeNight"
	newFolder.Parent = workspace
	folder = newFolder
	for _, at in NIGHT_LAMPS do
		buildLamp(newFolder, at)
	end
	buildIceWall(newFolder, myToken)
	openWall(true) -- it came out of there
	Notify.effectAll("Banner", {
		Title = "❄️ THE FROST WRAITH",
		Subtitle = "Light only slows it. Heat lamps hide you. Melt the north exit and escape!",
		Color = "Cyan",
		Sound = "MonsterSpawn",
	})
	task.spawn(runCold, myToken)
	task.delay(4, function()
		if token ~= myToken then
			return
		end
		while token == myToken and EnemyService.PlayerNear(WRAITH_HOME, 18) do
			task.wait(1) -- it wakes once nobody's standing over it
		end
		if token ~= myToken then
			return
		end
		for i = 1, FoodCourtRules.wraithCount(#Players:GetPlayers()) do
			local enemy = EnemyService.Spawn("FrostWraith", WRAITH_HOME + Vector3.new(0, 0, (i - 1) * 6), R.Tier)
			if enemy then
				enemy.Custom.IsSafe = inHeat
				enemy.Custom.Patrol = PATROL
				enemy.Custom.OnBreath = function(player: Player)
					local state = chillOf(player)
					state.Cold = math.min(1, state.Cold + R.Breath)
				end
			end
		end
	end)
end

function HiddenFreezer.EndNight()
	token = nil
	stage = nil
	unregisterAll()
	clearPlayers()
	table.clear(lamps)
	table.clear(escaped)
	iceWall = nil
	closeWall()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return HiddenFreezer
