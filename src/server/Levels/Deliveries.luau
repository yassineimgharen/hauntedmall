-- Level 10: Day "Special Delivery" / Night "Return to Sender".
--
-- Day:   ten parcels turned up at the loading dock overnight. Inspect one (hold E) to read
--        its label, shine a flashlight on it to check for a UV handprint, then DELIVER it
--        (E) or QUARANTINE it (Q). The manifest board lists trusted suppliers; anything with
--        a handprint is infected, whatever its label says. After five calls the delivery
--        truck's cab opens: the driver's logbook says where the boxes come from.
-- Night: infected cargo nests (four, pulsing) hatch Parcel Mimics that hide among real
--        parcels. Burn the nests with the flashlight (NestSeconds of beam, shared). Every
--        infected parcel delivered by mistake during the day hatches tonight as well.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local CombatService = require(script.Parent.Parent.Services.CombatService)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local FoodCourtRules = require(script.Parent.FoodCourtRules)

local Deliveries = {}

local R = FoodCourtRules.L10
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local CARDBOARD = Color3.fromRGB(196, 154, 104)
local INFECTION = Color3.fromRGB(170, 60, 255)
local SPOTS = {
	Vector3.new(-122, 0.6, -102),
	Vector3.new(-115, 0.6, -102),
	Vector3.new(-122, 0.6, -110),
	Vector3.new(-115, 0.6, -110),
	Vector3.new(-102, 3.1, -118),
	Vector3.new(-102, 3.1, -104),
	Vector3.new(-170, 0, -85),
	Vector3.new(-130, 0, -85),
	Vector3.new(-152, 0, -96),
	Vector3.new(-128, 0, -122),
}
local NESTS = {
	Vector3.new(-118, 0, -116),
	Vector3.new(-172, 0, -85),
	Vector3.new(-108, 0, -70),
	Vector3.new(-141, 0, 68),
}
local DECOYS = {
	Vector3.new(-120, 0, -30),
	Vector3.new(-160, 0, 20),
	Vector3.new(-135, 0, -40),
	Vector3.new(-178, 0, -2),
	Vector3.new(-118, 0, 36),
	Vector3.new(-150, 0, -88),
	Vector3.new(-200, 0, -70),
	Vector3.new(-130, 0, -98),
}
local CAB = CFrame.lookAt(Vector3.new(-136.8, 0, -102), Vector3.new(-120, 0, -102))

local dayFolder: Folder? = nil
local nightFolder: Folder? = nil
local dayToken: {}? = nil
local nightToken: {}? = nil
local wrongDeliveries = 0 -- infected parcels delivered by mistake (hatch tonight)
local sorted = 0
local wrongCalls = 0
local litTargets: { Model } = {}
local killedConnection: any = nil
local rng = Random.new()

local function markDone(part: BasePart, prompt: ProximityPrompt?)
	part:SetAttribute("Done", true)
	if prompt then
		prompt:SetAttribute("Done", true)
		prompt.Enabled = false
	end
end

local function unregisterAll()
	for _, model in litTargets do
		CombatService.UnregisterLightTarget(model)
	end
	table.clear(litTargets)
end

-- ── day ─────────────────────────────────────────────────────────────────────

local function buildManifest(parent: Instance)
	local board = Builder.decor({
		Name = "Manifest",
		Parent = parent,
		Size = Vector3.new(10, 6, 0.3),
		CFrame = CFrame.lookAt(Vector3.new(-99.4, 6, -112), Vector3.new(-90, 6, -112)) * CFrame.Angles(0, math.pi, 0),
		Color = Color3.fromRGB(240, 236, 220),
	})
	local lines = { "📋 DELIVERY MANIFEST", "Trusted suppliers:" }
	for _, sender in R.Trusted do
		table.insert(lines, "✓ " .. sender)
	end
	table.insert(lines, "☣ UV HANDPRINT = INFECTED")
	table.insert(lines, "Shine your flashlight on every parcel!")
	Builder.label(board, Enum.NormalId.Front, table.concat(lines, "\n"), {
		Color = Color3.fromRGB(30, 26, 40),
		Font = FONT,
		Lit = true,
	})
end

local function parcelLabel(part: BasePart, info: { [string]: any }): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(210, 96)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.MaxDistance = 40
	gui.LightInfluence = 0
	gui.Enabled = false
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(245, 240, 225)
	back.BackgroundTransparency = 0.05
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = back
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, -12, 1, -8)
	text.Position = UDim2.fromOffset(6, 4)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = Color3.fromRGB(30, 26, 40)
	text.FontFace = FONT
	text.Text =
		string.format("FROM: %s\nTO: %s\nCONTENTS: %s\nUV: (shine a light)", info.Sender, info.For, info.Contents)
	text.Parent = back
	gui.Parent = part
	return gui, text
end

local function buildParcel(parent: Instance, info: { [string]: any }, at: Vector3, myToken: {})
	local model = Builder.model("Parcel", parent)
	local size = Vector3.new(rng:NextNumber(2.4, 3.2), rng:NextNumber(1.8, 2.6), rng:NextNumber(2.2, 3))
	local box = Builder.part({
		Name = "Parcel",
		Parent = model,
		Size = size,
		CFrame = CFrame.new(at + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
		Color = CARDBOARD,
		Material = Enum.Material.Cardboard,
		Tags = { "DeliveryParcel" },
	})
	model.PrimaryPart = box
	Builder.decor({
		Parent = model,
		Size = Vector3.new(size.X + 0.05, 0.4, 0.3),
		CFrame = box.CFrame * CFrame.new(0, size.Y / 2 - 0.15, 0),
		Color = Color3.fromRGB(150, 120, 80),
		Material = Enum.Material.Fabric,
	})
	local handprint = Builder.decor({
		Parent = model,
		Size = Vector3.new(1.2, 0.05, 1.4),
		CFrame = box.CFrame * CFrame.new(0.3, size.Y / 2 + 0.03, 0.2) * CFrame.Angles(0, 0.5, 0),
		Color = INFECTION,
		Material = Enum.Material.Neon,
		Transparency = 1,
	})
	local gui, text = parcelLabel(box, info)
	local inspected, uvChecked, decided = false, false, false
	local uvTime = 0
	local function refreshLabel()
		local uv = if not uvChecked
			then "UV: (shine a light)"
			elseif info.Infected then "☣ UV HANDPRINT!"
			else "UV: clean ✓"
		text.Text = string.format("FROM: %s\nTO: %s\nCONTENTS: %s\n%s", info.Sender, info.For, info.Contents, uv)
	end

	local inspect = Builder.prompt(box, {
		ActionText = "Inspect",
		ObjectText = "Mystery Parcel",
		HoldDuration = R.InspectSeconds,
		MaxActivationDistance = 8,
	})
	local choices: { ProximityPrompt } = {}
	for i, choice in { { "Deliver", Enum.KeyCode.E, -1 }, { "Quarantine", Enum.KeyCode.Q, 1 } } do
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(choice[3] * (size.X / 2 + 0.6), 0, 0)
		attachment.Parent = box
		local prompt = Builder.prompt(attachment, {
			ActionText = choice[1],
			ObjectText = if i == 1 then "Send it to the restaurant" else "Seal it away",
			KeyboardKeyCode = choice[2],
			GamepadKeyCode = if i == 1 then Enum.KeyCode.ButtonX else Enum.KeyCode.ButtonY,
			HoldDuration = 0.6,
			MaxActivationDistance = 8,
			Enabled = false,
		})
		table.insert(choices, prompt)
		prompt.Triggered:Connect(function(player)
			if dayToken ~= myToken or decided or not inspected then
				return
			end
			decided = true
			local quarantine = i == 2
			for _, p in choices do
				p.Enabled = false
			end
			markDone(box, nil)
			CombatService.UnregisterLightTarget(model)
			local correct = FoodCourtRules.isCorrectCall(info, quarantine)
			if correct then
				sorted += 1
				MissionEvents.record(player, "ParcelSorted")
				Notify.all(
					string.format(
						"📦 %s %s a parcel correctly (%d sorted).",
						player.DisplayName,
						if quarantine then "quarantined" else "delivered",
						sorted
					),
					"success"
				)
			else
				wrongCalls += 1
				MissionEvents.record(player, "WrongCall")
				if info.Infected then
					wrongDeliveries += 1
				end
				Notify.all(
					if info.Infected
						then "☣ An INFECTED parcel was delivered! Something will hatch tonight..."
						else "🗑️ A clean parcel was quarantined. Check for the UV handprint first!",
					"danger"
				)
			end
			if quarantine then
				box.Color = Color3.fromRGB(150, 40, 40)
				text.Text = "☣ QUARANTINED"
			else
				TweenService:Create(box, TweenInfo.new(1), { Transparency = 1 }):Play()
				gui.Enabled = false
			end
			if sorted == #R.Parcels and wrongCalls == 0 then
				MissionEvents.record(nil, "PerfectSort")
				Notify.all("🏅 Every parcel sorted without a single mistake!", "levelup")
			end
			if sorted == R.LogbookAfter then
				Notify.all("🚚 The delivery truck's cab clicked open. Check the driver's logbook!", "info")
			end
		end)
	end
	inspect.Triggered:Connect(function(player)
		if dayToken ~= myToken or inspected then
			return
		end
		inspected = true
		inspect.Enabled = false
		gui.Enabled = true
		for _, p in choices do
			p.Enabled = true
		end
		MissionEvents.record(player, "ParcelInspected")
	end)
	-- the flashlight reveals the UV status (for everyone looking at the label)
	table.insert(litTargets, model)
	CombatService.RegisterLightTarget(model, function(_player, dt)
		if uvChecked or dayToken ~= myToken then
			return
		end
		uvTime += dt
		if uvTime >= R.UVSeconds then
			uvChecked = true
			if info.Infected then
				handprint.Transparency = 0
			end
			refreshLabel()
			gui.Enabled = gui.Enabled or inspected
		end
	end, { Parts = { box }, Radius = { math.max(size.X, size.Z) / 2 } })
end

local function buildLogbook(parent: Instance, myToken: {})
	local door = Builder.part({
		Name = "TruckCab",
		Parent = parent,
		Size = Vector3.new(0.4, 4, 3),
		CFrame = CAB * CFrame.new(0, 4.5, 0),
		Color = Color3.fromRGB(90, 70, 150),
		Material = Enum.Material.Metal,
		CanCollide = false,
		Tags = { "TruckCab" },
	})
	local prompt = Builder.prompt(door, {
		ActionText = "Read Logbook",
		ObjectText = "Locked: sort 5 parcels first",
		HoldDuration = 2,
		MaxActivationDistance = 9,
	})
	prompt.Triggered:Connect(function(player)
		if dayToken ~= myToken or door:GetAttribute("Done") then
			return
		end
		if sorted < R.LogbookAfter then
			Notify.player(
				player,
				string.format("🔒 The cab is locked. Sort %d more parcels.", R.LogbookAfter - sorted),
				"warning"
			)
			return
		end
		markDone(door, prompt)
		MissionEvents.record(player, "DriverLogFound")
		Notify.effectAll("Banner", {
			Title = "📓 THE DRIVER'S LOG",
			Subtitle = '"Every night the order comes from BELOW the kitchen. Nobody signs. Something knocks inside the boxes."',
			Color = "Purple",
			Sound = "MonsterSpawn",
		})
	end)
	task.spawn(function()
		while dayToken == myToken and not door:GetAttribute("Done") do
			prompt.ObjectText = if sorted >= R.LogbookAfter
				then "Driver's Logbook"
				else string.format("Locked: sort %d more", R.LogbookAfter - sorted)
			task.wait(0.5)
		end
	end)
end

function Deliveries.StartDay()
	Deliveries.EndDay()
	local myToken = {}
	dayToken = myToken
	sorted = 0
	wrongCalls = 0
	wrongDeliveries = 0
	local folder = Instance.new("Folder")
	folder.Name = "SpecialDeliveryDay"
	folder.Parent = workspace
	dayFolder = folder
	buildManifest(folder)
	buildLogbook(folder, myToken)
	for i, info in R.Parcels do
		buildParcel(folder, info, SPOTS[i], myToken)
	end
end

function Deliveries.EndDay()
	dayToken = nil
	unregisterAll()
	if dayFolder then
		dayFolder:Destroy()
		dayFolder = nil
	end
end

-- ── night ───────────────────────────────────────────────────────────────────

local function decoy(parent: Instance, at: Vector3)
	local size = Vector3.new(rng:NextNumber(2.6, 3.2), rng:NextNumber(2, 2.6), rng:NextNumber(2.6, 3.2))
	Builder.part({
		Name = "Parcel",
		Parent = parent,
		Size = size,
		CFrame = CFrame.new(at + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
		Color = CARDBOARD,
		Material = Enum.Material.Cardboard,
	})
end

local function spawnMimic(near: Vector3): any?
	local angle = rng:NextNumber(0, math.pi * 2)
	local enemy =
		EnemyService.Spawn("ParcelMimic", near + Vector3.new(math.cos(angle) * 5, 0, math.sin(angle) * 5), R.Tier)
	if enemy then
		enemy.Custom.Tier = R.Tier
	end
	return enemy
end

local function creatures(): number
	local count = 0
	for _, enemy in EnemyService.GetAll() do
		if (enemy.Type == "ParcelMimic" or enemy.Type == "ParcelMite") and not enemy.Dead then
			count += 1
		end
	end
	return count
end

type Nest = { Model: Model, Core: BasePart, Progress: number, Done: boolean, NextHatch: number, Bar: Frame }

local function buildNest(parent: Instance, at: Vector3, index: number, myToken: {}): Nest
	local model = Builder.model("InfectedNest" .. index, parent)
	Builder.part({
		Parent = model,
		Size = Vector3.new(5, 0.6, 5),
		CFrame = CFrame.new(at + Vector3.new(0, 0.3, 0)),
		Color = Color3.fromRGB(150, 110, 70),
		Material = Enum.Material.WoodPlanks,
	})
	for k = 0, 3 do
		Builder.part({
			Parent = model,
			Size = Vector3.new(2.2, 2, 2.2),
			CFrame = CFrame.new(at + Vector3.new((k % 2 - 0.5) * 2.4, 1.6 + (k // 2) * 0.4, (k // 2 - 0.5) * 2.2))
				* CFrame.Angles(0, k, 0),
			Color = CARDBOARD:Lerp(INFECTION, 0.25),
			Material = Enum.Material.Cardboard,
		})
	end
	local core = Builder.part({
		Name = "NestCore",
		Parent = model,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 3.4,
		CFrame = CFrame.new(at + Vector3.new(0, 3.6, 0)),
		Color = INFECTION,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		Tags = { "InfectedNest" },
	})
	model.PrimaryPart = core
	TweenService:Create(core, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Size = Vector3.one * 4,
	}):Play()
	local glow = Instance.new("PointLight")
	glow.Color = INFECTION
	glow.Range = 16
	glow.Brightness = 1.8
	glow.Parent = core
	local goo = Instance.new("ParticleEmitter")
	goo.Texture = "rbxasset://textures/particles/smoke_main.dds"
	goo.Color = ColorSequence.new(INFECTION, Color3.fromRGB(30, 10, 40))
	goo.Transparency = NumberSequence.new(0.5, 1)
	goo.Size = NumberSequence.new(2, 4)
	goo.Lifetime = NumberRange.new(1, 2)
	goo.Rate = 5
	goo.Speed = NumberRange.new(0.5, 1.5)
	goo.Parent = core
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(140, 30)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 18)
	title.BackgroundTransparency = 1
	title.Text = "☣ INFECTED NEST"
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(230, 190, 255)
	title.FontFace = FONT
	title.TextStrokeTransparency = 0.3
	title.Parent = gui
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 8)
	back.Position = UDim2.fromOffset(0, 22)
	back.BackgroundColor3 = Color3.fromRGB(30, 16, 50)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Palette.NeonGold
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = core

	local nest: Nest = {
		Model = model,
		Core = core,
		Progress = 0,
		Done = false,
		NextHatch = os.clock() + R.NestEvery * (0.5 + index * 0.15),
		Bar = fill,
	}
	table.insert(litTargets, model)
	CombatService.RegisterLightTarget(model, function(player, dt)
		if nest.Done or nightToken ~= myToken then
			return
		end
		nest.Progress = math.min(nest.Progress + dt, R.NestSeconds)
		fill.Size = UDim2.fromScale(nest.Progress / R.NestSeconds, 1)
		if nest.Progress >= R.NestSeconds then
			nest.Done = true
			CombatService.UnregisterLightTarget(model)
			markDone(core, nil)
			goo.Enabled = false
			glow.Enabled = false
			title.Text = "🔥 BURNED"
			TweenService:Create(core, TweenInfo.new(0.8), { Transparency = 1, Size = Vector3.one * 0.5 }):Play()
			MissionEvents.record(player, "NestBurned")
			Notify.effectAll(
				"WorldPopup",
				{ Position = core.Position + Vector3.new(0, 2, 0), Text = "🔥 NEST BURNED!", Color = "Gold" }
			)
			Notify.all(string.format("🔥 %s burned an infected nest!", player.DisplayName), "success")
		end
	end, { Parts = { core }, Radius = { 2 } })
	return nest
end

local function runNests(nests: { Nest }, myToken: {})
	while nightToken == myToken do
		task.wait(1)
		local now = os.clock()
		local cap = FoodCourtRules.mimicCap(#Players:GetPlayers())
		for _, nest in nests do
			if not nest.Done and now >= nest.NextHatch then
				nest.NextHatch = now + R.NestEvery
				if creatures() < cap and spawnMimic(nest.Core.Position - Vector3.new(0, 3.6, 0)) then
					Notify.all("📦 Something hatched from an infected nest...", "warning")
				end
			end
		end
	end
end

local function clearNight()
	nightToken = nil
	unregisterAll()
	if killedConnection then
		killedConnection:Disconnect()
		killedConnection = nil
	end
	if nightFolder then
		nightFolder:Destroy()
		nightFolder = nil
	end
end

function Deliveries.StartNight()
	clearNight()
	local myToken = {}
	nightToken = myToken
	local folder = Instance.new("Folder")
	folder.Name = "ReturnToSenderNight"
	folder.Parent = workspace
	nightFolder = folder
	local nests = {}
	for index, at in NESTS do
		table.insert(nests, buildNest(folder, at, index, myToken))
	end
	for _, at in DECOYS do
		decoy(folder, at)
	end
	-- disguised mimics among the decoys (more if infected parcels were delivered today)
	local count = FoodCourtRules.initialMimics(#Players:GetPlayers(), wrongDeliveries)
	local spots = table.clone(DECOYS)
	for i = 1, count do
		local spot = table.remove(spots, rng:NextInteger(1, #spots))
		if spot then
			spawnMimic(spot)
		end
		if i > #DECOYS then
			break
		end
	end
	if wrongDeliveries > 0 then
		Notify.all(
			string.format(
				"☣ %d infected parcel(s) were delivered today... they're waiting in the dark.",
				wrongDeliveries
			),
			"danger"
		)
	end
	killedConnection = EnemyService.Killed:Connect(function(enemy, contributors)
		if nightToken ~= myToken or (enemy.Type ~= "ParcelMimic" and enemy.Type ~= "ParcelMite") then
			return
		end
		for player in contributors do
			if player.Parent then
				MissionEvents.record(player, "ParcelCreatureKilled")
			end
		end
	end)
	task.spawn(runNests, nests, myToken)
end

function Deliveries.EndNight()
	clearNight()
	wrongDeliveries = 0
end

return Deliveries
