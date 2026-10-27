-- Level 4, "Security Upgrade" (day) / "Mall Under Attack" (night).
--
-- Day:   repair 4 security cameras, activate 3 terminals, arm 2 alarm panels, and carry
--        planks from the hardware depot to barricade your own shop's door.
-- Night: what you set up is what you have.
--          * Terminals have health. Every ATTACK_INTERVAL a strike group spawns at an
--            approach point and marches on one terminal; a 🚨 alert names it.
--          * Activated terminals show the repaired cameras' feeds ("View Cameras").
--          * Armed alarms lure every crawler nearby for LURE_SECONDS (cooldown applies).
--          * Barricades absorb shop raids before any stock is lost.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
local ShopService = require(script.Parent.Parent.Services.ShopService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local Layout = require(script.Parent.Parent.World.Layout)
local Carry = require(script.Parent.Carry)

local SecuritySystem = {}

local A = Layout.Atrium
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local TERMINAL_HP = 160
local TERMINAL_HIT = 6
local BARRICADE_HP = 14
local ATTACK_INTERVAL = 30
local FIRST_ATTACK = 15
local LURE_RADIUS = 90
local LURE_SECONDS = 8
local ALARM_COOLDOWN = 25
local TIER = 4

local CAMERAS = {
	{ Name = "CAM 1 · ENTRANCE", Position = Vector3.new(-20, 16, -69), Look = Vector3.new(0, 2, -20) },
	{ Name = "CAM 2 · WEST HALL", Position = Vector3.new(-69, 14, -12), Look = Vector3.new(-10, 2, 0) },
	{ Name = "CAM 3 · UPPER LEVEL", Position = Vector3.new(20, 36, 69), Look = Vector3.new(0, A.BalconyY, 30) },
	{ Name = "CAM 4 · EAST WING", Position = Vector3.new(181, 16, 0), Look = Vector3.new(110, 2, 0) },
}

local TERMINALS = {
	{
		Name = "Atrium Terminal",
		Position = Vector3.new(-6, 0, -38),
		Facing = Vector3.new(0, 0, -1),
		Approaches = { Vector3.new(0, 0, -95), Vector3.new(-50, 0, -50) },
	},
	{
		Name = "Upper Level Terminal",
		Position = Vector3.new(40, A.BalconyY, 52),
		Facing = Vector3.new(0, 0, -1),
		Approaches = { Vector3.new(-50, A.BalconyY, 50), Vector3.new(55, A.BalconyY, -50) },
	},
	{
		Name = "East Wing Terminal",
		Position = Vector3.new(128, 0, 0),
		Facing = Vector3.new(-1, 0, 0),
		Approaches = { Vector3.new(178, 0, 10), Vector3.new(178, 0, -10) },
	},
}

local ALARMS = {
	{ Name = "Atrium Alarm", CFrame = CFrame.lookAt(Vector3.new(70, 5, 26), Vector3.new(0, 5, 26)) },
	{ Name = "East Wing Alarm", CFrame = CFrame.lookAt(Vector3.new(182, 5, 4), Vector3.new(0, 5, 4)) },
}

local DEPOT = CFrame.lookAt(Vector3.new(26, 0, -63), Vector3.new(26, 0, 0))

type Camera = { Name: string, Part: BasePart, View: CFrame, Repaired: boolean }
type Terminal = {
	Name: string,
	Part: BasePart,
	Screen: TextLabel,
	ActivatePrompt: ProximityPrompt,
	ViewPrompt: ProximityPrompt,
	Activated: boolean,
	HP: number,
	Alive: boolean,
	Bar: Frame,
	Label: TextLabel,
	Billboard: BillboardGui,
	Front: Vector3,
	Approaches: { Vector3 },
	LastAttacked: number,
	LastNotice: number,
}
type Alarm =
	{ Name: string, Prompt: ProximityPrompt, Light: PointLight, Lamp: BasePart, Armed: boolean, Center: Vector3 }
type Barricade = { HP: number, Planks: { BasePart }, Owner: string }

local dayFolder: Folder? = nil
local systemFolder: Folder? = nil
local cameras: { Camera } = {}
local terminals: { Terminal } = {}
local alarms: { Alarm } = {}
local barricades: { [any]: Barricade } = {}
local nightToken: {}? = nil
local rng = Random.new()

local function phase(): string
	return GameStateService.GetPhase()
end

-- ── cameras ─────────────────────────────────────────────────────────────────

local function buildCamera(parent: Instance, info: { Name: string, Position: Vector3, Look: Vector3 })
	local cf = CFrame.lookAt(info.Position, info.Look)
	local body = Builder.part({
		Name = "SecurityCamera",
		Parent = parent,
		Size = Vector3.new(1.3, 1.1, 2.2),
		CFrame = cf,
		Color = Color3.fromRGB(230, 232, 238),
		Material = Enum.Material.SmoothPlastic,
	})
	Builder.decor({
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 0.9, 0.9),
		CFrame = cf * CFrame.new(0, 0, -1.2) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(20, 22, 30),
		Material = Enum.Material.Glass,
	})
	local led = Builder.decor({
		Parent = parent,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.3,
		CFrame = cf * CFrame.new(0.4, 0.45, -0.8),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Neon,
	})
	local attachment = Instance.new("Attachment")
	attachment.Parent = body
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 240, 180), Color3.fromRGB(255, 160, 60))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.2, 0)
	sparks.Speed = NumberRange.new(5, 10)
	sparks.SpreadAngle = Vector2.new(80, 80)
	sparks.Acceleration = Vector3.new(0, -35, 0)
	sparks.Lifetime = NumberRange.new(0.25, 0.5)
	sparks.Rate = 18
	sparks.Parent = attachment

	body:SetAttribute("Done", false)
	Builder.tag(body, "SecurityCamera")
	local camera: Camera = {
		Name = info.Name,
		Part = body,
		View = CFrame.lookAt(info.Position + cf.LookVector * 1.6, info.Look),
		Repaired = false,
	}
	table.insert(cameras, camera)
	local prompt = Builder.prompt(body, {
		Name = "RepairPrompt",
		ActionText = "Repair Camera",
		ObjectText = info.Name,
		HoldDuration = 2.5,
		MaxActivationDistance = 20,
	})
	prompt.Triggered:Connect(function(player)
		if phase() ~= "Day" or camera.Repaired then
			return
		end
		camera.Repaired = true
		body:SetAttribute("Done", true)
		prompt.Enabled = false
		sparks.Enabled = false
		led.Color = Palette.NeonRed
		Builder.light("PointLight", led, { Range = 4, Brightness = 1, Color = Palette.NeonRed })
		MissionEvents.record(player, "CameraRepaired")
		Notify.all(string.format("📷 %s repaired %s", player.DisplayName, info.Name), "success")
	end)
end

local function feeds(): { { Name: string, CFrame: CFrame } }
	local list = {}
	for _, camera in cameras do
		if camera.Repaired then
			table.insert(list, { Name = camera.Name, CFrame = camera.View })
		end
	end
	return list
end

-- ── terminals ───────────────────────────────────────────────────────────────

local function setTerminalHealth(terminal: Terminal)
	local fraction = math.clamp(terminal.HP / TERMINAL_HP, 0, 1)
	terminal.Bar.Size = UDim2.fromScale(fraction, 1)
	terminal.Bar.BackgroundColor3 = if fraction > 0.5
		then Palette.NeonGreen
		elseif fraction > 0.25 then Palette.NeonGold
		else Palette.NeonRed
	terminal.Label.Text = string.format("🖥️ %s  %d%%", terminal.Name, math.ceil(fraction * 100))
end

local function buildTerminal(parent: Instance, info: any)
	local base = CFrame.lookAt(info.Position, info.Position + info.Facing)
	local model = Builder.model("SecurityTerminal", parent)
	local body = Builder.part({
		Name = "Console",
		Parent = model,
		Size = Vector3.new(3.6, 3.4, 2.2),
		CFrame = base * CFrame.new(0, 1.7, 0),
		Color = Color3.fromRGB(46, 50, 64),
		Material = Enum.Material.Metal,
	})
	local screenPart = Builder.decor({
		Parent = model,
		Size = Vector3.new(3.2, 2, 0.2),
		CFrame = base * CFrame.new(0, 4.1, 0.3) * CFrame.Angles(math.rad(-20), 0, 0),
		Color = Color3.fromRGB(10, 14, 20),
	})
	local _, screen =
		Builder.label(screenPart, Enum.NormalId.Front, "OFFLINE", { Color = Palette.NeonRed, Font = FONT })
	Builder.decor({
		Parent = model,
		Size = Vector3.new(3.8, 0.15, 2.4),
		CFrame = base * CFrame.new(0, 0.08, 0),
		Color = Palette.NeonCyan,
		Material = Enum.Material.Neon,
		Tags = { "NightNeon" },
	})
	body:SetAttribute("Done", false)
	Builder.tag(body, "SecurityTerminal")

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Health"
	billboard.Size = UDim2.fromOffset(200, 46)
	billboard.StudsOffset = Vector3.new(0, 4.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 250
	billboard.LightInfluence = 0
	billboard.Enabled = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 24)
	label.TextScaled = true
	label.FontFace = FONT
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard
	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(10, 28)
	track.Size = UDim2.new(1, -20, 0, 12)
	track.BackgroundColor3 = Color3.fromRGB(20, 16, 30)
	track.Parent = billboard
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BorderSizePixel = 0
	bar.Parent = track
	billboard.Parent = body

	local activate = Builder.prompt(body, {
		Name = "ActivatePrompt",
		ActionText = "Activate Terminal",
		ObjectText = info.Name,
		HoldDuration = 3,
		MaxActivationDistance = 9,
	})
	local view = Builder.prompt(body, {
		Name = "ViewPrompt",
		ActionText = "View Cameras",
		ObjectText = info.Name,
		MaxActivationDistance = 9,
		Enabled = false,
	})
	local terminal: Terminal = {
		Name = info.Name,
		Part = body,
		Screen = screen,
		ActivatePrompt = activate,
		ViewPrompt = view,
		Activated = false,
		HP = TERMINAL_HP,
		Alive = true,
		Bar = bar,
		Label = label,
		Billboard = billboard,
		Front = info.Position + info.Facing * 3,
		Approaches = info.Approaches,
		LastAttacked = 0,
		LastNotice = 0,
	}
	table.insert(terminals, terminal)
	setTerminalHealth(terminal)

	activate.Triggered:Connect(function(player)
		if phase() ~= "Day" or terminal.Activated then
			return
		end
		terminal.Activated = true
		body:SetAttribute("Done", true)
		activate.Enabled = false
		screen.Text = "ONLINE"
		screen.TextColor3 = Palette.NeonGreen
		MissionEvents.record(player, "TerminalActivated")
		Notify.all(string.format("🖥️ %s activated the %s", player.DisplayName, info.Name), "success")
	end)
	view.Triggered:Connect(function(player)
		if phase() ~= "Night" or not terminal.Alive or not terminal.Activated then
			return
		end
		local list = feeds()
		if #list == 0 then
			Notify.player(player, "No working cameras: they weren't repaired today.", "warning")
			return
		end
		MissionEvents.record(player, "CamerasViewed")
		Notify.effect(player, "OpenCameras", { Cameras = list })
	end)
end

local function loseTerminal(terminal: Terminal)
	terminal.Alive = false
	terminal.ViewPrompt.Enabled = false
	terminal.Screen.Text = "DESTROYED"
	terminal.Screen.TextColor3 = Palette.NeonRed
	terminal.Label.Text = "💥 " .. terminal.Name .. " DOWN"
	terminal.Bar.Size = UDim2.fromScale(0, 1)
	MissionEvents.record(nil, "TerminalLost")
	Notify.all(string.format("💥 The %s is down!", terminal.Name), "danger")
end

local function goalFor(terminal: Terminal): EnemyService.Goal
	return {
		Position = terminal.Front,
		Alive = function()
			return terminal.Alive and nightToken ~= nil
		end,
		Hit = function()
			if not terminal.Alive then
				return
			end
			terminal.HP -= TERMINAL_HIT
			setTerminalHealth(terminal)
			if terminal.HP <= 0 then
				loseTerminal(terminal)
			elseif os.clock() - terminal.LastNotice > 8 then
				terminal.LastNotice = os.clock()
				Notify.all(
					string.format(
						"⚠️ The %s is under attack! (%d%%)",
						terminal.Name,
						math.ceil(terminal.HP / TERMINAL_HP * 100)
					),
					"danger"
				)
			end
		end,
	}
end

-- ── alarms ──────────────────────────────────────────────────────────────────

local function buildAlarm(parent: Instance, info: { Name: string, CFrame: CFrame })
	local box = Builder.part({
		Name = "AlarmPanel",
		Parent = parent,
		Size = Vector3.new(2.2, 2.6, 0.8),
		CFrame = info.CFrame * CFrame.new(0, 0, -0.4),
		Color = Color3.fromRGB(200, 30, 40),
		Material = Enum.Material.Metal,
	})
	local lamp = Builder.decor({
		Parent = parent,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.8,
		CFrame = info.CFrame * CFrame.new(0, 1.7, -0.6),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Neon,
	})
	local light = Builder.light("PointLight", lamp, { Range = 16, Brightness = 0, Color = Palette.NeonRed })
	Builder.label(box, Enum.NormalId.Front, "🚨", { Color = Color3.new(1, 1, 1), Lit = true })
	box:SetAttribute("Done", false)
	Builder.tag(box, "AlarmPanel")
	local floor = info.CFrame.Position + info.CFrame.LookVector * 6
	local alarm: Alarm = {
		Name = info.Name,
		Prompt = Builder.prompt(box, {
			Name = "AlarmPrompt",
			ActionText = "Arm Alarm",
			ObjectText = info.Name,
			HoldDuration = 2,
			MaxActivationDistance = 9,
		}),
		Light = light,
		Lamp = lamp,
		Armed = false,
		Center = Vector3.new(floor.X, if floor.Y > 15 then A.BalconyY else 0, floor.Z),
	}
	table.insert(alarms, alarm)
	alarm.Prompt.Triggered:Connect(function(player)
		if phase() == "Day" and not alarm.Armed then
			alarm.Armed = true
			box:SetAttribute("Done", true)
			alarm.Prompt.Enabled = false
			lamp.Color = Palette.NeonGreen
			MissionEvents.record(player, "AlarmArmed")
			Notify.all(string.format("🚨 %s armed the %s", player.DisplayName, info.Name), "success")
		elseif phase() == "Night" and alarm.Armed and nightToken then
			alarm.Prompt.Enabled = false
			local lured = EnemyService.Lure(alarm.Center, LURE_RADIUS, LURE_SECONDS)
			MissionEvents.record(player, "AlarmUsed")
			Notify.all(
				string.format("🚨 %s sounded the %s: %d crawlers lured!", player.DisplayName, info.Name, lured),
				"warning"
			)
			local myToken = nightToken
			task.spawn(function()
				local endsAt = os.clock() + LURE_SECONDS
				while os.clock() < endsAt and nightToken == myToken do
					light.Brightness = if light.Brightness > 0 then 0 else 4
					lamp.Color = if light.Brightness > 0 then Palette.NeonRed else Palette.DarkMetal
					task.wait(0.25)
				end
				light.Brightness = 0
				task.wait(ALARM_COOLDOWN - LURE_SECONDS)
				if nightToken == myToken then
					lamp.Color = Palette.NeonGreen
					alarm.Prompt.Enabled = true
				end
			end)
		end
	end)
end

-- ── barricades ──────────────────────────────────────────────────────────────

local function doorFrame(shop: any): CFrame?
	local door = shop.Model:GetAttribute("P_Door")
	local lane = shop.Model:GetAttribute("P_Lane")
	if typeof(door) ~= "Vector3" or typeof(lane) ~= "Vector3" then
		return nil
	end
	local outward = (lane - door).Unit
	local origin = door - outward * 3 -- P_Door sits 3 studs outside the doorway
	return CFrame.lookAt(origin, origin + outward)
end

local function buildBarricade(shop: any, cf: CFrame)
	local folder = systemFolder
	if not folder then
		return
	end
	local model = Builder.model("Barricade_" .. shop.Id, folder)
	local planks = {}
	for _, side in { -1, 1 } do
		Builder.decor({
			Parent = model,
			Size = Vector3.new(0.5, 10, 0.5),
			CFrame = cf * CFrame.new(side * 4.3, 5, -0.9),
			Color = Palette.DarkMetal,
			Material = Enum.Material.DiamondPlate,
		})
		for _, tilt in { 0.6, -0.6 } do
			table.insert(
				planks,
				Builder.decor({
					Parent = model,
					Size = Vector3.new(11, 0.5, 0.25),
					CFrame = cf * CFrame.new(side * 10, 4.5, -0.95) * CFrame.Angles(0, 0, tilt),
					Color = Palette.Wood,
					Material = Enum.Material.WoodPlanks,
				})
			)
		end
	end
	local barricade: Barricade = { HP = BARRICADE_HP, Planks = planks, Owner = shop.Id }
	barricades[shop] = barricade
end

local function shield(shop: any): (amount: number) -> boolean
	return function(amount: number): boolean
		local barricade = barricades[shop]
		if not barricade or barricade.HP <= 0 then
			return false
		end
		barricade.HP -= amount
		local keep = math.ceil(math.max(barricade.HP, 0) / BARRICADE_HP * #barricade.Planks)
		for i, plank in barricade.Planks do
			plank.Transparency = if i <= keep then 0 else 1
		end
		if barricade.HP <= 0 and shop.Owner then
			Notify.player(shop.Owner, "🪵 Your barricade broke! They're raiding your stock!", "danger")
		end
		return true
	end
end

local function buildSpot(parent: Instance, shop: any)
	local cf = doorFrame(shop)
	if not cf then
		return
	end
	local spotPosition = (cf * CFrame.new(0, 0.1, -3)).Position
	local ring = Builder.decor({
		Name = "BarricadeSpot",
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 5, 5),
		CFrame = CFrame.new(spotPosition) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.Wood,
		Material = Enum.Material.Neon,
		Transparency = 0.5,
	})
	ring:SetAttribute("ShopId", shop.Id)
	ring:SetAttribute("Done", false)
	Builder.tag(ring, "BarricadeSpot")
	local prompt = Builder.prompt(ring, {
		Name = "BuildPrompt",
		ActionText = "Build Barricade",
		ObjectText = "Your Shop",
		HoldDuration = 2,
		MaxActivationDistance = 8,
	})
	prompt:SetAttribute("RequiresCarry", "Planks")
	prompt:SetAttribute("RequiresShop", shop.Id)
	Builder.tag(prompt, "CarryPrompt")
	prompt.Triggered:Connect(function(player)
		if phase() ~= "Day" or ring:GetAttribute("Done") or ShopService.GetShopOf(player) ~= shop then
			return
		end
		if not Carry.consume(player, "Planks") then
			return
		end
		ring:SetAttribute("Done", true)
		prompt:SetAttribute("Done", true)
		prompt.Enabled = false
		ring.Transparency = 1
		buildBarricade(shop, cf)
		MissionEvents.record(player, "BarricadeBuilt")
		Notify.all(string.format("🪵 %s barricaded their shop.", player.DisplayName), "success")
	end)
end

local function buildDepot(parent: Instance)
	local model = Builder.model("HardwareDepot", parent)
	Builder.part({
		Parent = model,
		Size = Vector3.new(8, 1, 4),
		CFrame = DEPOT * CFrame.new(0, 0.5, 0),
		Color = Palette.DarkMetal,
		Material = Enum.Material.DiamondPlate,
	})
	local sign = Builder.decor({
		Parent = model,
		Size = Vector3.new(7, 1.8, 0.3),
		CFrame = DEPOT * CFrame.new(0, 6.4, 1.6),
		Color = Color3.fromRGB(240, 196, 40),
	})
	Builder.label(sign, Enum.NormalId.Front, "⚠ HARDWARE DEPOT", { Color = Color3.fromRGB(30, 24, 20), Font = FONT })
	local bin = Builder.part({
		Name = "SupplyPlanks",
		Parent = model,
		Size = Vector3.new(6, 2.4, 3),
		CFrame = DEPOT * CFrame.new(0, 2.2, 0),
		Color = Color3.fromRGB(60, 56, 70),
		Material = Enum.Material.Metal,
	})
	for i = 0, 3 do
		Builder.decor({
			Parent = model,
			Size = Vector3.new(5.6, 0.4, 0.8),
			CFrame = DEPOT * CFrame.new(0, 3.6 + i * 0.42, -0.8 + (i % 2) * 0.9),
			Color = Palette.Wood,
			Material = Enum.Material.WoodPlanks,
		})
	end
	Builder.tag(bin, "SupplyPlanks")
	local prompt = Builder.prompt(bin, {
		Name = "TakePrompt",
		ActionText = "Take Planks",
		ObjectText = "Hardware Depot",
		MaxActivationDistance = 9,
	})
	prompt.Triggered:Connect(function(player)
		if phase() ~= "Day" then
			return
		end
		if not ShopService.GetShopOf(player) then
			Notify.player(player, "Claim a shop first: the planks are for your own shop's door.", "warning")
			return
		end
		if Carry.pickUp(player, "Planks") then
			Notify.player(player, "🪵 Planks in hand: carry them to your shop's door.", "info")
		end
	end)
end

-- ── night attacks ───────────────────────────────────────────────────────────

local function watchWave(wave: { any }, terminal: Terminal, myToken: {})
	while nightToken == myToken do
		task.wait(1)
		local remaining = 0
		for _, enemy in wave do
			if not enemy.Dead then
				remaining += 1
			end
		end
		if remaining == 0 then
			if terminal.Alive and nightToken == myToken then
				MissionEvents.record(nil, "AttackRepelled")
				Notify.all(string.format("✅ Attack on the %s repelled!", terminal.Name), "success")
			end
			return
		end
	end
end

local function attackLoop(myToken: {})
	task.wait(FIRST_ATTACK)
	while nightToken == myToken do
		local candidates = {}
		for _, terminal in terminals do
			if terminal.Alive then
				table.insert(candidates, terminal)
			end
		end
		if #candidates == 0 then
			return
		end
		table.sort(candidates, function(a, b)
			return a.LastAttacked < b.LastAttacked
		end)
		local terminal = candidates[1]
		terminal.LastAttacked = os.clock()
		Notify.all(string.format("🚨 CAMERA ALERT: a strike group is heading for the %s!", terminal.Name), "danger")
		local wave = {}
		local count = math.min(2 + #Players:GetPlayers(), 6)
		for i = 1, count do
			if EnemyService.AliveCount() >= 14 then
				break
			end
			local base = terminal.Approaches[(i - 1) % #terminal.Approaches + 1]
			local position = base + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
			local enemy = EnemyService.Spawn("ShadowCrawler", position, TIER)
			if enemy then
				enemy.Goal = goalFor(terminal)
				table.insert(wave, enemy)
			end
			task.wait(0.3)
		end
		if #wave > 0 then
			task.spawn(watchWave, wave, terminal, myToken)
		end
		local waited = 0
		while waited < ATTACK_INTERVAL and nightToken == myToken do
			task.wait(0.5)
			waited += 0.5
		end
	end
end

-- ── level hooks ─────────────────────────────────────────────────────────────

local function clearAll()
	nightToken = nil
	Carry.clearAll()
	for shop in barricades do
		ShopService.SetShield(shop, nil)
	end
	table.clear(barricades)
	for _, shop in ShopService.GetAllShops() do
		ShopService.SetShield(shop, nil)
	end
	table.clear(cameras)
	table.clear(terminals)
	table.clear(alarms)
	for _, folder in { dayFolder, systemFolder } do
		if folder then
			folder:Destroy()
		end
	end
	dayFolder, systemFolder = nil, nil
end

function SecuritySystem.StartDay()
	clearAll()
	local day = Instance.new("Folder")
	day.Name = "SecurityDay"
	day.Parent = workspace
	dayFolder = day
	local system = Instance.new("Folder")
	system.Name = "SecuritySystem"
	system.Parent = workspace
	systemFolder = system

	for _, info in CAMERAS do
		buildCamera(system, info)
	end
	for _, info in TERMINALS do
		buildTerminal(system, info)
	end
	for _, info in ALARMS do
		buildAlarm(system, info)
	end
	buildDepot(day)
	for _, shop in ShopService.GetAllShops() do
		buildSpot(day, shop)
	end
end

function SecuritySystem.EndDay()
	Carry.clearAll()
	if dayFolder then
		dayFolder:Destroy()
		dayFolder = nil
	end
	for _, camera in cameras do
		local prompt = camera.Part:FindFirstChild("RepairPrompt") :: ProximityPrompt?
		if prompt then
			prompt.Enabled = false
		end
	end
	for _, terminal in terminals do
		terminal.ActivatePrompt.Enabled = false
	end
	for _, alarm in alarms do
		alarm.Prompt.Enabled = false
	end
end

function SecuritySystem.StartNight()
	if not systemFolder then
		return
	end
	local myToken = {}
	nightToken = myToken
	for _, terminal in terminals do
		terminal.HP = TERMINAL_HP
		terminal.Alive = true
		terminal.Billboard.Enabled = true
		terminal.ViewPrompt.Enabled = terminal.Activated
		setTerminalHealth(terminal)
	end
	for _, alarm in alarms do
		alarm.Prompt.ActionText = "Sound Alarm"
		alarm.Prompt.HoldDuration = 0
		alarm.Prompt.Enabled = alarm.Armed
	end
	for shop in barricades do
		ShopService.SetShield(shop, shield(shop))
	end
	task.spawn(attackLoop, myToken)
end

function SecuritySystem.EndNight()
	clearAll()
end

return SecuritySystem
