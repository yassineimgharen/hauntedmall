-- Level 10: Day "Special Delivery" / Night "Return to Sender".
--
-- Day:   ten parcels turned up at the loading dock overnight. Inspect one (hold E) to read
--        its label, shine a flashlight on it to check for a UV handprint, then DELIVER it
--        (E) or QUARANTINE it (Q). The manifest board lists trusted suppliers; anything with
--        a handprint is infected, whatever its label says. A wrong call costs you (an
--        infected parcel delivered hatches tonight) but the parcel comes back with its UV
--        status showing, so the day can always be finished. After five correct calls the
--        delivery truck's cab opens: the driver's logbook says where the boxes come from.
-- Night: infected cargo nests (four, pulsing) hatch awake Parcel Mimics, and sleeping ones
--        hide among identical real parcels. Burn the nests with the flashlight (NestSeconds
--        of beam, shared). When the last nest dies every sleeper wakes; once they're all
--        dead the infestation is over and dawn comes early (FoodCourtRules.ClearedDawn).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local ParcelMimic = require(script.Parent.Parent.Enemies.ParcelMimic)
local CombatService = require(script.Parent.Parent.Services.CombatService)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local FoodCourtRules = require(script.Parent.FoodCourtRules)

local Deliveries = {}

local R = FoodCourtRules.L10
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local CARDBOARD = Color3.fromRGB(196, 154, 104)
local INFECTION = Color3.fromRGB(170, 60, 255)
local CAB = CFrame.lookAt(Vector3.new(-137.4, 0, -102), Vector3.new(-120, 0, -102))

local dayFolder: Folder? = nil
local nightFolder: Folder? = nil
local dayToken: {}? = nil
local nightToken: {}? = nil
local wrongDeliveries = 0 -- infected parcels delivered by mistake (hatch tonight)
local sorted = 0
local wrongCalls = 0
local logbookRead = false
local tipped: { [string]: { [Player]: boolean } } = {}
local mimicAnnounced = false
local litTargets: { Model } = {}
local killedConnection: any = nil
local rng = Random.new()

local function vec(point: { number }): Vector3
	return Vector3.new(point[1], point[2], point[3])
end

-- A one-time on-screen tip for this player (per stage).
local function tip(player: Player, key: string, text: string)
	local seen = tipped[key]
	if not seen then
		seen = {}
		tipped[key] = seen
	end
	if not seen[player] then
		seen[player] = true
		Notify.effect(player, "Popup", { Text = text, Color = "Gold", Y = 0.62 })
	end
end

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
	gui.Size = UDim2.fromOffset(290, 112)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
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
	text.Text = FoodCourtRules.parcelLabel(info :: any, FoodCourtRules.newParcel())
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
	-- the handprints UV light reveals: on top and on both long sides, so a parcel up on the
	-- conveyor (its top above eye level) still shows one
	local handprints: { BasePart } = {}
	for _, cf in
		{
			CFrame.new(0.3, size.Y / 2 + 0.03, 0.2) * CFrame.Angles(0, 0.5, 0),
			CFrame.new(0, 0, -size.Z / 2 - 0.03) * CFrame.Angles(math.rad(90), 0, 0.3),
			CFrame.new(0, 0, size.Z / 2 + 0.03) * CFrame.Angles(math.rad(90), 0, -0.3),
		}
	do
		table.insert(
			handprints,
			Builder.decor({
				Parent = model,
				Size = Vector3.new(1.2, 0.05, 1.4),
				CFrame = box.CFrame * cf,
				Color = INFECTION,
				Material = Enum.Material.Neon,
				Transparency = 1,
			})
		)
	end
	local gui, text = parcelLabel(box, info)
	local state = FoodCourtRules.newParcel()
	local uvTime = 0
	local function showUV()
		if info.Infected then
			for _, print in handprints do
				print.Transparency = 0
			end
		end
		text.Text = FoodCourtRules.parcelLabel(info :: any, state)
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
			-- gamepad Y opens the shop, so Quarantine uses B
			GamepadKeyCode = if i == 1 then Enum.KeyCode.ButtonX else Enum.KeyCode.ButtonB,
			HoldDuration = 0.6,
			MaxActivationDistance = 8,
			Enabled = false,
		})
		table.insert(choices, prompt)
		prompt.Triggered:Connect(function(player)
			if dayToken ~= myToken then
				return
			end
			local quarantine = i == 2
			local result, firstMistake = FoodCourtRules.callParcel(info :: any, state, quarantine)
			if result == "Refused" then
				return
			end
			for _, p in choices do
				p.Enabled = false
			end
			if result == "Wrong" then
				wrongCalls += 1
				MissionEvents.record(player, "WrongCall")
				if info.Infected and firstMistake then
					wrongDeliveries += 1
				end
				showUV()
				Notify.effect(player, "WorldPopup", {
					Position = at + Vector3.new(0, 4, 0),
					Text = "❌ WRONG CALL",
					Color = "Red",
				})
				Notify.all(
					if info.Infected
						then "☣ An INFECTED parcel was delivered! It's back at the dock, but something will hatch tonight..."
						else "🗑️ A clean parcel was quarantined. It's back at the dock: read its UV line and call it again.",
					"danger"
				)
				task.delay(1.5, function()
					if dayToken == myToken and not state.Settled then
						for _, p in choices do
							p.Enabled = true
						end
					end
				end)
				return
			end
			-- the right call: this parcel is finished
			markDone(box, nil)
			CombatService.UnregisterLightTarget(model)
			sorted += 1
			MissionEvents.record(player, "ParcelSorted")
			Notify.effect(player, "WorldPopup", {
				Position = at + Vector3.new(0, 4, 0),
				Text = if quarantine then "☣ QUARANTINED ✓" else "📦 DELIVERED ✓",
				Color = "Green",
			})
			Notify.all(
				string.format(
					"📦 %s %s a parcel correctly (%d/%d).",
					player.DisplayName,
					if quarantine then "quarantined" else "delivered",
					math.min(sorted, R.SortTarget),
					R.SortTarget
				),
				"success"
			)
			if quarantine then
				box.Color = Color3.fromRGB(150, 40, 40)
				text.Text = "☣ QUARANTINED"
				task.delay(3, function()
					gui.Enabled = false
				end)
			else
				-- it goes off to the restaurant: nothing solid or floating stays behind
				gui.Enabled = false
				box.CanCollide = false
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						TweenService:Create(part, TweenInfo.new(0.8), { Transparency = 1 }):Play()
					end
				end
				task.delay(1, function()
					model:Destroy()
				end)
			end
			if sorted == #R.Parcels and wrongCalls == 0 then
				MissionEvents.record(nil, "PerfectSort")
				Notify.all("🏅 Every parcel sorted without a single mistake!", "levelup")
			end
			if sorted == R.LogbookAfter then
				Notify.all("🚚 The delivery truck's side door clicked open: read the driver's logbook!", "info")
			end
			if sorted == R.SortTarget and not logbookRead then
				Notify.effectAll("Banner", {
					Title = "📦 DELIVERIES SORTED",
					Subtitle = "Next: read the driver's logbook at the delivery truck's side door.",
					Color = "Green",
					Sound = "PowerUp",
				})
			end
		end)
	end
	inspect.Triggered:Connect(function(player)
		if dayToken ~= myToken or state.Inspected then
			return
		end
		state.Inspected = true
		inspect.Enabled = false
		gui.Enabled = true
		for _, p in choices do
			p.Enabled = true
		end
		MissionEvents.record(player, "ParcelInspected")
		tip(
			player,
			"Inspect",
			"🔦 Press 1 and shine your flashlight on it. Handprint = Quarantine (Q). Clean = Deliver (E)."
		)
	end)
	-- the flashlight reveals the UV status (for everyone looking at the label)
	table.insert(litTargets, model)
	CombatService.RegisterLightTarget(model, function(player, dt)
		if state.UV or dayToken ~= myToken then
			return
		end
		uvTime += dt
		if uvTime >= R.UVSeconds then
			state.UV = true
			showUV()
			Notify.effect(player, "WorldPopup", {
				Position = at + Vector3.new(0, 4, 0),
				Text = if info.Infected then "☣ UV HANDPRINT!" else "✓ UV CLEAN",
				Color = if info.Infected then "Purple" else "Green",
			})
		end
	end, { Parts = { box }, Radius = { math.max(size.X, size.Z) / 2 } })
end

local function buildLogbook(parent: Instance, myToken: {})
	local door = Builder.part({
		Name = "TruckCab",
		Parent = parent,
		Size = Vector3.new(3, 4, 0.4), -- CAB faces out of the truck: its X runs along the side
		CFrame = CAB * CFrame.new(0, 4.5, 0),
		Color = Color3.fromRGB(90, 70, 150),
		Material = Enum.Material.Metal,
		CanCollide = false,
		Tags = { "TruckCab" },
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 30)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = FONT
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = door
	local prompt = Builder.prompt(door, {
		ActionText = "Locked",
		ObjectText = "Driver's Logbook",
		HoldDuration = 0,
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
		logbookRead = true
		gui.Enabled = false
		MissionEvents.record(player, "DriverLogFound")
		local entry =
			'"Every night the order comes from BELOW the kitchen. Nobody signs. Something knocks inside the boxes."'
		Notify.all("📓 Driver's log: " .. entry, "info")
		Notify.effectAll("Banner", {
			Title = "📓 THE DRIVER'S LOG",
			Subtitle = entry,
			Color = "Purple",
			Sound = "MonsterSpawn",
		})
	end)
	task.spawn(function()
		while dayToken == myToken and not door:GetAttribute("Done") do
			local open = sorted >= R.LogbookAfter
			prompt.ActionText = if open
				then "Read Logbook"
				else string.format("Locked: sort %d more", R.LogbookAfter - sorted)
			prompt.HoldDuration = if open then 2 else 0
			label.Text = if open
				then "📓 DRIVER'S LOGBOOK: READ ME"
				else string.format("🔒 LOGBOOK: sort %d more parcels", R.LogbookAfter - sorted)
			label.TextColor3 = if open then Palette.NeonGold else Color3.fromRGB(200, 200, 210)
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
	logbookRead = false
	table.clear(tipped)
	local folder = Instance.new("Folder")
	folder.Name = "SpecialDeliveryDay"
	folder.Parent = workspace
	dayFolder = folder
	buildManifest(folder)
	buildLogbook(folder, myToken)
	for i, info in R.Parcels do
		buildParcel(folder, info, vec(R.ParcelSpots[i]), myToken)
	end
	task.delay(4, function()
		if dayToken == myToken then
			Notify.effectAll("Banner", {
				Title = "📦 MYSTERY DELIVERIES",
				Subtitle = "Loading dock: inspect each parcel, check it with your flashlight, then deliver or quarantine.",
				Color = "Gold",
			})
		end
	end)
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

local function onRevealed(enemy: any)
	Notify.effectAll("WorldPopup", {
		Position = enemy.Root.Position + Vector3.new(0, 5, 0),
		Text = "😱 MIMIC!",
		Color = "Purple",
	})
	if not mimicAnnounced then
		mimicAnnounced = true
		Notify.all("😱 Parcel Mimic! Burn it with your flashlight and leave the purple landing circles.", "danger")
	end
end

-- A mimic at this floor point: sleeping (disguised) or hatched and already awake.
local function spawnMimic(at: Vector3, disguised: boolean): any?
	local enemy = EnemyService.Spawn("ParcelMimic", at, R.Tier)
	if enemy then
		enemy.Custom.Tier = R.Tier
		enemy.Custom.OnReveal = onRevealed
		if disguised then
			ParcelMimic.disguise(enemy, at.Y)
		else
			enemy.Custom.Wake = true
		end
	end
	return enemy
end

local function isCreature(enemy: any): boolean
	return (enemy.Type == "ParcelMimic" or enemy.Type == "ParcelMite") and not enemy.Dead
end

-- Creatures alive; awakeOnly leaves out mimics still asleep in their disguise.
local function creatures(awakeOnly: boolean): number
	local count = 0
	for _, enemy in EnemyService.GetAll() do
		if
			isCreature(enemy)
			and (not awakeOnly or enemy.Type == "ParcelMite" or enemy.Custom.Revealed or enemy.Custom.Wake)
		then
			count += 1
		end
	end
	return count
end

type Nest = {
	Model: Model,
	Core: BasePart,
	Hatch: Vector3,
	Progress: number,
	Done: boolean,
	NextHatch: number,
	Bar: Frame,
}

local burned = 0

local function buildNest(parent: Instance, spec: { [string]: any }, index: number, myToken: {}): Nest
	local at = vec(spec.At)
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
	local pulse =
		TweenService:Create(core, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Size = Vector3.one * 4,
		})
	pulse:Play()
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
	gui.MaxDistance = 400 -- nests show through walls so you always know what's left
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
		Hatch = vec(spec.Hatch),
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
			pulse:Cancel()
			TweenService:Create(core, TweenInfo.new(0.8), { Transparency = 1, Size = Vector3.one * 0.5 }):Play()
			task.delay(4, function()
				gui.Enabled = false
			end)
			burned += 1
			MissionEvents.record(player, "NestBurned")
			Notify.effectAll(
				"WorldPopup",
				{ Position = core.Position + Vector3.new(0, 2, 0), Text = "🔥 NEST BURNED!", Color = "Gold" }
			)
			Notify.all(
				string.format("🔥 %s burned an infected nest (%d/%d)!", player.DisplayName, burned, #R.Nests),
				"success"
			)
		end
	end, { Parts = { core }, Radius = { 2 } })
	return nest
end

local function runNests(nests: { Nest }, myToken: {})
	local allBurned, cleared = false, false
	while nightToken == myToken and not cleared do
		task.wait(1)
		local now = os.clock()
		local cap = FoodCourtRules.mimicCap(#Players:GetPlayers())
		local left = 0
		for _, nest in nests do
			if not nest.Done then
				left += 1
				if now >= nest.NextHatch then
					nest.NextHatch = now + R.NestEvery
					if creatures(true) < cap and spawnMimic(nest.Hatch, false) then
						Notify.all("📦 A Parcel Mimic hatched from an infected nest!", "warning")
					end
				end
			end
		end
		if left == 0 and not allBurned then
			-- the nests are gone: the sleepers wake and come for you, then it's over
			allBurned = true
			for _, enemy in EnemyService.GetAll() do
				if enemy.Type == "ParcelMimic" and not enemy.Dead then
					enemy.Custom.Wake = true
				end
			end
			Notify.effectAll("Banner", {
				Title = "🔥 ALL NESTS BURNED",
				Subtitle = "The last creatures are waking. Destroy them, or survive until dawn.",
				Color = "Gold",
				Sound = "PowerUp",
			})
		end
		if FoodCourtRules.infestationCleared(left, creatures(false)) then
			cleared = true
			GameStateService.ShortenPhase(R.ClearedDawn)
			Notify.effectAll("Banner", {
				Title = "✅ INFESTATION CLEARED",
				Subtitle = string.format("Dawn in %d seconds.", R.ClearedDawn),
				Color = "Green",
				Sound = "LevelUp",
			})
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
	table.clear(tipped)
	folder.Parent = workspace
	nightFolder = folder
	burned = 0
	mimicAnnounced = false
	local nests = {}
	for index, spec in R.Nests do
		table.insert(nests, buildNest(folder, spec, index, myToken))
	end
	-- real parcels everywhere; sleeping mimics beside some of them (more if infected
	-- parcels were delivered today)
	local hides = table.clone(R.Hides)
	for index = #hides, 2, -1 do
		local other = rng:NextInteger(1, index)
		hides[index], hides[other] = hides[other], hides[index]
	end
	for _, hide in hides do
		ParcelMimic.decoy(folder, vec(hide.Box), rng:NextNumber(0, math.pi * 2))
	end
	for i = 1, math.min(FoodCourtRules.initialMimics(#Players:GetPlayers(), wrongDeliveries), #hides) do
		spawnMimic(vec(hides[i].Mimic), true)
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
				if enemy.Type == "ParcelMimic" then
					tip(player, "Split", "📦💥 It burst! Burn the little mites too.")
				end
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
