-- Level 13: Day "Fresh Air" / Night "Toxic Bloom".
--
-- Day:   the food court's emergency ventilation is dead. Crawl through the maintenance ducts
--        to the three fan rooms and replace each fan's belt (hold E). Then balance the
--        airflow at the panel in the maintenance corridor: each damper lever flips its own
--        vent and both neighbours' (a ring of five); open all five.
-- Night: spore vents crack open and poison gas spreads zone by zone (FoodCourtRules gas
--        model). Your ☣️ meter rises in gas and falls in clean air; full means choking.
--        Pull a zone's PURGE switch to blow its gas out (it stays clear for a while),
--        breathe at the oxygen tanks, and burn Spore Bloaters from a distance: they burst
--        into gas. The dining hall's promenade and the atrium always have clean air.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local FoodCourtRules = require(script.Parent.FoodCourtRules)

local Ventilation = {}

local R = FoodCourtRules.L13
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local GAS = Color3.fromRGB(120, 255, 80)
local PANEL = CFrame.lookAt(Vector3.new(-120, 0, 90.6), Vector3.new(-120, 0, 80))
local ZONE_BOXES = {
	Kitchen = { -250, -184, -48, 48 },
	HallWest = { -184, -141, -48, 48 },
	HallEast = { -141, -98, -48, 48 },
	NorthWing = { -184, -98, 48, 92 },
	SouthWing = { -184, -98, -128, -48 },
	BackRooms = { -250, -184, -96, -48 },
}
local PURGE_MIN_GAS = 0.1 -- a zone with less than this has nothing to purge
local ZONE_NAMES = {
	Kitchen = "Grand Kitchen",
	HallWest = "Dining Hall (west)",
	HallEast = "Dining Hall (east)",
	NorthWing = "North Restaurants",
	SouthWing = "South Restaurants & Dock",
	BackRooms = "Storage & Freezer",
}
local SWITCHES = {
	Kitchen = CFrame.lookAt(Vector3.new(-225, 0, -46.6), Vector3.new(-225, 0, 0)),
	HallWest = CFrame.lookAt(Vector3.new(-182.6, 0, -12), Vector3.new(-150, 0, -12)),
	HallEast = CFrame.lookAt(Vector3.new(-100.5, 0, -14), Vector3.new(-120, 0, -14)),
	NorthWing = CFrame.lookAt(Vector3.new(-160, 0, 90.6), Vector3.new(-160, 0, 80)),
	SouthWing = CFrame.lookAt(Vector3.new(-160, 0, -90.6), Vector3.new(-160, 0, -80)),
	BackRooms = CFrame.lookAt(Vector3.new(-238, 0, -94.6), Vector3.new(-238, 0, -80)),
}
local STATIONS = {
	Vector3.new(-141, 0, -36),
	Vector3.new(-141, 0, 36),
	Vector3.new(-200, 0, 20),
	Vector3.new(-152, 0, -112),
}
local VENTS = {
	Kitchen = Vector3.new(-217, 0, 0),
	SouthWing = Vector3.new(-129, 0, -112),
	HallWest = Vector3.new(-165, 0, -30),
	NorthWing = Vector3.new(-141, 0, 85),
	BackRooms = Vector3.new(-217, 0, -70),
	HallEast = Vector3.new(-115, 0, 20),
}
local SOURCE_ORDER = { "Kitchen", "SouthWing", "NorthWing", "HallWest", "BackRooms", "HallEast" }

type Breath = {
	Meter: number,
	Character: Model?,
	NextChoke: number,
	NextStation: number,
	EverChoked: boolean,
	Purged: boolean,
}

local folder: Folder? = nil
local token: {}? = nil
local stage: string? = nil
local fansFixed = 0
local levels: { [string]: number } = {}
local switchButtons: { [string]: BasePart } = {}
local sources: { [string]: boolean } = {}
local purgedUntil: { [string]: number } = {}
local fog: { [string]: ParticleEmitter } = {}
local breath: { [Player]: Breath } = {}
local killedConnection: any = nil
local rng = Random.new()

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

local function fans(): { Model }
	local list = {}
	for _, model in CollectionService:GetTagged("VentFan") do
		if model:IsA("Model") then
			table.insert(list, model)
		end
	end
	return list
end

local function setFan(model: Model, spinning: boolean)
	model:SetAttribute("Spinning", spinning)
	local status = model:FindFirstChild("Status")
	if status and status:IsA("BasePart") then
		status.Color = if spinning then Palette.NeonGreen else Palette.NeonRed
	end
end

-- ── day ─────────────────────────────────────────────────────────────────────

local function buildFanRepairs(parent: Instance, myToken: {}, onAllFixed: () -> ())
	for _, model in fans() do
		setFan(model, false)
		local status = model:FindFirstChild("Status") :: BasePart?
		if not status then
			continue
		end
		status:SetAttribute("Done", nil)
		Builder.tag(status, "BrokenFan")
		local prompt = Builder.prompt(status, {
			ActionText = "Replace Belt",
			ObjectText = tostring(model:GetAttribute("FanName") or "Vent Fan"),
			HoldDuration = R.FanSeconds,
			MaxActivationDistance = 12,
		})
		parent.Destroying:Connect(function()
			prompt:Destroy()
			CollectionService:RemoveTag(status, "BrokenFan")
		end)
		prompt.Triggered:Connect(function(player)
			if token ~= myToken or status:GetAttribute("Done") then
				return
			end
			markDone(status, prompt)
			setFan(model, true)
			fansFixed += 1
			MissionEvents.record(player, "VentFanRepaired")
			Notify.all(
				string.format(
					"🌀 %s fixed the %s (%d/%d).",
					player.DisplayName,
					tostring(model:GetAttribute("FanName")),
					fansFixed,
					R.Fans
				),
				"success"
			)
			if fansFixed >= R.Fans then
				onAllFixed()
			end
		end)
	end
end

local function buildPanel(parent: Instance, myToken: {}): () -> ()
	local model = Builder.model("AirflowPanel", parent)
	Builder.part({
		Name = "Board",
		Parent = model,
		Size = Vector3.new(20, 7, 0.8),
		CFrame = PANEL * CFrame.new(0, 5.5, 0),
		Color = Color3.fromRGB(50, 56, 66),
		Material = Enum.Material.DiamondPlate,
	})
	local title = Builder.decor({
		Parent = model,
		Size = Vector3.new(14, 1.2, 0.1),
		CFrame = PANEL * CFrame.new(0, 8.4, -0.45),
		Color = Color3.fromRGB(16, 14, 20),
	})
	Builder.label(
		title,
		Enum.NormalId.Front,
		"🌀 AIRFLOW: OPEN ALL FIVE VENTS",
		{ Color = Palette.NeonCyan, Font = FONT }
	)
	local vents = {}
	for i = 1, R.Dampers do
		vents[i] = rng:NextNumber() < 0.5
	end
	if FoodCourtRules.airflowSolved(vents) then
		vents[2] = false
	end
	local gauges: { BasePart } = {}
	local handles: { BasePart } = {}
	local prompts: { ProximityPrompt } = {}
	local solved = false
	local function render()
		for i, gauge in gauges do
			gauge.Color = if vents[i] then Palette.NeonGreen else Palette.NeonRed
		end
	end
	for i = 1, R.Dampers do
		local x = (i - 3) * 3.6
		gauges[i] = Builder.decor({
			Parent = model,
			Size = Vector3.new(2.2, 1.6, 0.1),
			CFrame = PANEL * CFrame.new(x, 6.6, -0.45),
			Material = Enum.Material.Neon,
			Color = Palette.NeonRed,
		})
		local handle = Builder.part({
			Name = "Damper",
			Parent = model,
			Size = Vector3.new(0.5, 2, 0.5),
			CFrame = PANEL * CFrame.new(x, 3.6, -0.9),
			Color = Palette.NeonGold,
			Material = Enum.Material.Metal,
			Tags = { "AirflowDamper" },
		})
		handles[i] = handle
		local prompt = Builder.prompt(handle, {
			ActionText = "Flip Damper " .. i,
			ObjectText = "Locked: fix the fans first",
			HoldDuration = 0.3,
			MaxActivationDistance = 6,
			Enabled = false,
		})
		prompts[i] = prompt
		prompt.Triggered:Connect(function(player)
			if token ~= myToken or solved or fansFixed < R.Fans then
				return
			end
			vents = FoodCourtRules.toggleDamper(vents, i)
			handle.CFrame = handle.CFrame * CFrame.Angles(math.pi, 0, 0)
			render()
			if FoodCourtRules.airflowSolved(vents) then
				solved = true
				for _, p in prompts do
					p.Enabled = false
				end
				for _, h in handles do
					h:SetAttribute("Done", true)
				end
				MissionEvents.record(player, "AirflowBalanced")
				Notify.effectAll("Banner", {
					Title = "AIRFLOW BALANCED",
					Subtitle = "The emergency ventilation is back. You'll need it tonight...",
					Color = "Cyan",
					Sound = "PowerUp",
				})
			end
		end)
	end
	render()
	return function()
		for i, prompt in prompts do
			prompt.Enabled = true
			prompt.ObjectText = "Damper "
				.. i
				.. " flips vents "
				.. ((i - 2) % R.Dampers + 1)
				.. "-"
				.. (i % R.Dampers + 1)
		end
		Notify.all("🌀 All fans spinning! Balance the airflow at the panel in the maintenance corridor.", "info")
	end
end

function Ventilation.StartDay()
	Ventilation.EndNight()
	local myToken = {}
	token = myToken
	stage = "Day"
	fansFixed = 0
	local newFolder = Instance.new("Folder")
	newFolder.Name = "FreshAirDay"
	newFolder.Parent = workspace
	folder = newFolder
	local unlock = buildPanel(newFolder, myToken)
	buildFanRepairs(newFolder, myToken, unlock)
end

function Ventilation.EndDay()
	token = nil
	stage = nil
	if folder then
		folder:Destroy() -- the fans keep spinning into the night
		folder = nil
	end
end

-- ── night ───────────────────────────────────────────────────────────────────

local function breathOf(player: Player): Breath
	local state = breath[player]
	if not state or state.Character ~= player.Character then
		state = {
			Meter = 0,
			Character = player.Character,
			NextChoke = 0,
			NextStation = 0,
			EverChoked = if state then state.EverChoked else false,
			Purged = if state then state.Purged else false,
		}
		breath[player] = state
	end
	return state
end

local function dose(player: Player, amount: number)
	local state = breathOf(player)
	state.Meter = math.min(1, state.Meter + amount)
	player:SetAttribute("Meter_Gas", state.Meter)
end

local function buildFog(parent: Instance)
	for zone, box in ZONE_BOXES do
		local volume = Builder.decor({
			Name = "GasCloud",
			Parent = parent,
			Size = Vector3.new(box[2] - box[1], 8, box[4] - box[3]),
			CFrame = CFrame.new((box[1] + box[2]) / 2, 4, (box[3] + box[4]) / 2),
			Transparency = 1,
		})
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.Color = ColorSequence.new(GAS, Color3.fromRGB(40, 70, 20))
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new(8, 14)
		emitter.Lifetime = NumberRange.new(5, 7)
		emitter.Speed = NumberRange.new(0.3, 1)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.LightEmission = 0.2
		emitter.Rate = 0
		emitter.Parent = volume
		fog[zone] = emitter
	end
end

local function buildVent(parent: Instance, zone: string)
	local at = VENTS[zone]
	local crack = Builder.decor({
		Name = "SporeVent",
		Parent = parent,
		Size = Vector3.new(4, 0.1, 1.2),
		CFrame = CFrame.new(at + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
		Color = GAS,
		Material = Enum.Material.Neon,
	})
	local spew = Instance.new("ParticleEmitter")
	spew.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spew.Color = ColorSequence.new(GAS, Color3.fromRGB(50, 90, 20))
	spew.Transparency = NumberSequence.new(0.3, 1)
	spew.Size = NumberSequence.new(2, 7)
	spew.Lifetime = NumberRange.new(2, 3)
	spew.Speed = NumberRange.new(4, 7)
	spew.EmissionDirection = Enum.NormalId.Top
	spew.SpreadAngle = Vector2.new(20, 20)
	spew.Rate = 8
	spew.Parent = crack
	Builder.light("PointLight", crack, { Color = GAS, Range = 14, Brightness = 1.4 })
	sources[zone] = true
	Notify.all(string.format("☣️ A spore vent burst open in the %s!", ZONE_NAMES[zone]), "danger")
end

-- The guide arrow prefers switches with something to purge (Marker.Prefer = "Gassy").
local function markGassySwitches()
	for zone, button in switchButtons do
		button:SetAttribute("Gassy", if (levels[zone] or 0) >= PURGE_MIN_GAS then true else nil)
	end
end

local function buildSwitches(parent: Instance, myToken: {})
	for zone, cf in SWITCHES do
		local model = Builder.model("PurgeSwitch", parent)
		Builder.part({
			Parent = model,
			Size = Vector3.new(3, 4.4, 1),
			CFrame = cf * CFrame.new(0, 4, 0),
			Color = Color3.fromRGB(150, 30, 30),
			Material = Enum.Material.Metal,
		})
		local button = Builder.part({
			Name = "PurgeButton",
			Parent = model,
			Size = Vector3.new(1.6, 1.6, 0.5),
			CFrame = cf * CFrame.new(0, 4, -0.7),
			Color = Palette.NeonGold,
			Material = Enum.Material.Neon,
			Tags = { "PurgeSwitch" },
		})
		switchButtons[zone] = button
		local label = Builder.decor({
			Parent = model,
			Size = Vector3.new(3, 0.9, 0.1),
			CFrame = cf * CFrame.new(0, 6.7, -0.55),
			Color = Color3.fromRGB(16, 14, 20),
		})
		Builder.label(label, Enum.NormalId.Front, "🌀 PURGE", { Color = Palette.NeonGold, Font = FONT })
		local prompt = Builder.prompt(button, {
			ActionText = "Purge Gas",
			ObjectText = ZONE_NAMES[zone],
			HoldDuration = R.PurgeHold,
			MaxActivationDistance = 8,
		})
		prompt.Triggered:Connect(function(player)
			if token ~= myToken then
				return
			end
			local now = os.clock()
			if now < (purgedUntil[zone] or 0) then
				Notify.player(player, "🌀 This zone is already being purged.", "info")
				return
			end
			if (levels[zone] or 0) < PURGE_MIN_GAS then
				Notify.player(player, "This zone's air is still clean: purge where the gas is!", "info")
				return
			end
			purgedUntil[zone] = now + R.PurgeShield
			breathOf(player).Purged = true
			button.Color = Palette.NeonGreen
			button:SetAttribute("Done", true)
			task.delay(R.PurgeShield, function()
				if token == myToken then
					button.Color = Palette.NeonGold
					button:SetAttribute("Done", nil)
				end
			end)
			MissionEvents.record(player, "ZonePurged")
			Notify.all(string.format("🌀 %s purged the %s!", player.DisplayName, ZONE_NAMES[zone]), "success")
		end)
	end
end

local function buildStations(parent: Instance)
	for _, at in STATIONS do
		local model = Builder.model("OxygenStation", parent)
		local tank = Builder.part({
			Name = "OxygenTank",
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(5, 1.8, 1.8),
			CFrame = CFrame.new(at + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(80, 200, 255),
			Material = Enum.Material.Metal,
			Tags = { "OxygenStation" },
		})
		Builder.decor({
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 7, 7),
			CFrame = CFrame.new(at + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Palette.NeonCyan,
			Material = Enum.Material.Neon,
			Transparency = 0.6,
		})
		Builder.light("PointLight", tank, { Color = Palette.NeonCyan, Range = 12, Brightness = 1.2 })
		local prompt = Builder.prompt(tank, {
			ActionText = "Breathe",
			ObjectText = "Oxygen Tank",
			HoldDuration = 1,
			MaxActivationDistance = 8,
		})
		prompt.Triggered:Connect(function(player)
			if not token then
				return
			end
			local state = breathOf(player)
			local now = os.clock()
			if now < state.NextStation then
				Notify.player(
					player,
					string.format("😮‍💨 Catch your breath: %ds", math.ceil(state.NextStation - now)),
					"info"
				)
				return
			end
			state.NextStation = now + R.StationCooldown
			state.Meter = math.max(0, state.Meter - R.StationDrop)
			player:SetAttribute("Meter_Gas", state.Meter)
			Notify.effect(player, "Popup", { Text = "😮‍💨 FRESH AIR", Color = "Cyan", Y = 0.5 })
		end)
	end
end

local function zoneOf(position: Vector3): string?
	if position.Y > 20 or position.Y < -5 then
		return nil
	end
	return FoodCourtRules.zoneAt(position.X, position.Z)
end

local function bloaters(): number
	local count = 0
	for _, enemy in EnemyService.GetAll() do
		if enemy.Type == "SporeBloater" and not enemy.Dead then
			count += 1
		end
	end
	return count
end

local function spawnBloater()
	local open = {}
	for zone in sources do
		table.insert(open, zone)
	end
	if #open == 0 then
		return
	end
	-- out of a random open vent with nobody at it (else it waits for the next round)
	local spot = nil
	while #open > 0 and not spot do
		local zone = table.remove(open, rng:NextInteger(1, #open)) :: string
		local candidate = VENTS[zone] + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4))
		if not EnemyService.PlayerNear(candidate) then
			spot = candidate
		end
	end
	local enemy = spot and EnemyService.Spawn("SporeBloater", spot, R.Tier)
	if not enemy then
		return
	end
	enemy.Custom.OnGas = function(victims: { Player })
		for _, player in victims do
			dose(player, R.Exhale)
			Notify.effect(player, "Popup", { Text = "☣️ SPORES!", Color = "Green", Y = 0.5 })
		end
	end
	enemy.Custom.OnPop = function(position: Vector3)
		local where = zoneOf(position + Vector3.new(0, 1, 0))
		if where then
			levels[where] = math.min(1, (levels[where] or 0) + R.PopGas)
		end
		for _, player in Players:GetPlayers() do
			local root = livingRoot(player)
			if root and (root.Position - position).Magnitude <= R.PopRadius then
				dose(player, R.PopGas)
			end
		end
	end
end

local function step(dt: number)
	local now = os.clock()
	levels = FoodCourtRules.gasStep(levels, sources, purgedUntil, dt, now)
	for zone, emitter in fog do
		emitter.Rate = math.floor((levels[zone] or 0) * 14 + 0.5)
	end
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		local state = breathOf(player)
		if not root then
			continue
		end
		local zone = zoneOf(root.Position)
		local gas = if zone then levels[zone] or 0 else 0
		state.Meter = FoodCourtRules.gasMeterStep(state.Meter, gas, dt)
		player:SetAttribute("Meter_Gas", state.Meter)
		local choking = state.Meter >= 1
		player:SetAttribute("MoveScale", if choking then 0.8 else nil)
		if choking and now >= state.NextChoke then
			state.NextChoke = now + R.ChokeEvery
			if not state.EverChoked then
				state.EverChoked = true
				MissionEvents.record(player, "Choked")
			end
			EnemyService.HitPlayer(player, R.ChokeDamage, root.Position)
			Notify.effect(player, "Popup", { Text = "☣️ CHOKING! FIND CLEAN AIR!", Color = "Green", Y = 0.45 })
		end
	end
end

local function runNight(myToken: {})
	local started = os.clock()
	local opened = 0
	local nextSource = started
	local nextBloater = started + R.BloaterFirst
	local last = started
	while token == myToken do
		task.wait(0.25)
		local now = os.clock()
		if opened < R.MaxSources and now >= nextSource then
			opened += 1
			local zone = SOURCE_ORDER[opened]
			if folder then
				buildVent(folder, zone)
			end
			nextSource = now + (if opened < R.FirstSources then 0 else R.NewSourceEvery)
		end
		if now >= nextBloater then
			nextBloater = now + R.BloaterEvery
			if bloaters() < FoodCourtRules.bloaterCap(#Players:GetPlayers()) then
				spawnBloater()
			end
		end
		step(now - last)
		markGassySwitches()
		last = now
	end
end

local function clearNight()
	token = nil
	stage = nil
	if killedConnection then
		killedConnection:Disconnect()
		killedConnection = nil
	end
	for player in breath do
		if player.Parent then
			player:SetAttribute("Meter_Gas", nil)
			player:SetAttribute("MoveScale", nil)
		end
	end
	table.clear(breath)
	table.clear(levels)
	table.clear(switchButtons)
	table.clear(sources)
	table.clear(purgedUntil)
	table.clear(fog)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function Ventilation.StartNight()
	clearNight()
	local myToken = {}
	token = myToken
	stage = "Night"
	local newFolder = Instance.new("Folder")
	newFolder.Name = "ToxicBloomNight"
	newFolder.Parent = workspace
	folder = newFolder
	for _, model in fans() do
		if model:GetAttribute("Spinning") ~= true then
			setFan(model, true) -- the night needs them: emergency power kicks in
		end
	end
	buildFog(newFolder)
	buildSwitches(newFolder, myToken)
	buildStations(newFolder)
	killedConnection = EnemyService.Killed:Connect(function(enemy, contributors)
		if token ~= myToken or enemy.Type ~= "SporeBloater" then
			return
		end
		for player in contributors do
			if player.Parent then
				MissionEvents.record(player, "BloaterPopped")
			end
		end
	end)
	Notify.effectAll("Banner", {
		Title = "☣️ TOXIC BLOOM",
		Subtitle = "Purge the gas zone by zone. Breathe at the oxygen tanks. Burn bloaters from afar!",
		Color = "Green",
		Sound = "Warning",
	})
	task.spawn(runNight, myToken)
end

-- Dawn: players who never choked and helped purge get the clean-air bonus.
function Ventilation.BeforeNightEnd()
	if stage ~= "Night" then
		return
	end
	for player, state in breath do
		if player.Parent and not state.EverChoked and state.Purged then
			MissionEvents.record(player, "CleanAir")
		end
	end
end

function Ventilation.EndNight()
	clearNight()
	for _, model in fans() do
		setFan(model, false)
	end
end

return Ventilation
