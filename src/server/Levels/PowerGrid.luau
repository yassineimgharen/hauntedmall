-- Level mechanic for Level 2 (Day "Power Failure" / Night "Total Blackout").
--
-- Day:   a maintenance depot hands out spare fuses and emergency lamps (one carried item
--        at a time). Players carry fuses to 4 sparking electrical panels around the mall
--        and lamps to 5 glowing floor rings. Day lights flicker until the panels are fixed.
-- Night: every lamp placed during the day switches on: a warm light pool that burns any
--        crawler stepping into it (safe spots in the blackout). Supplies patrol and guard
--        points for the crawlers. NightService runs the blackout and the breakers.
--
-- Everything is spawned at stage start and destroyed at stage end, so other levels and
-- Free Shift never see these props.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local Layout = require(script.Parent.Parent.World.Layout)
local Carry = require(script.Parent.Carry)

local PowerGrid = {}

local A = Layout.Atrium
local C = Layout.Corridor
local HALF = A.Half
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local LAMP_RADIUS = 13 -- crawlers inside a lit lamp's radius burn
local LAMP_DPS = EnemyConfig.Fuses.SafeDPS

local PANELS = {
	{ Name = "West Hall Panel", CFrame = CFrame.lookAt(Vector3.new(-HALF, 4.5, 8), Vector3.new(0, 4.5, 8)) },
	{ Name = "North Hall Panel", CFrame = CFrame.lookAt(Vector3.new(0, 4.5, HALF), Vector3.new(0, 4.5, 0)) },
	{
		Name = "Upper Level Panel",
		CFrame = CFrame.lookAt(Vector3.new(-HALF, A.BalconyY + 4.5, 0), Vector3.new(0, A.BalconyY + 4.5, 0)),
	},
	{ Name = "East Wing Panel", CFrame = CFrame.lookAt(Vector3.new(C.EndX, 4.5, -14.5), Vector3.new(0, 4.5, -14.5)) },
}

-- the first three sit beside tonight's breakers (fuse boxes), the last two are bonus spots
local LAMP_SPOTS = {
	Vector3.new(60, 0, -25),
	Vector3.new(-12, A.BalconyY, 61),
	Vector3.new(172, 0, 10),
	Vector3.new(109, 0, -12.5),
	Vector3.new(-44, 0, 44),
}

local DEPOT = CFrame.lookAt(Vector3.new(26, 0, -63), Vector3.new(26, 0, 0))

-- Crawler routes for the blackout: breaker fronts first (guards spawn there), then halls.
local PATROL = {
	Vector3.new(62, 0, -30),
	Vector3.new(-12, A.BalconyY, 63),
	Vector3.new(175, 0, 14),
	Vector3.new(126, 0, 0),
	Vector3.new(92, 0, -6),
	Vector3.new(-40, 0, 30),
	Vector3.new(40, 0, 40),
}

local dayFolder: Folder? = nil
local lampFolder: Folder? = nil
local panelsDone = 0
local nightToken: {}? = nil

-- ── carrying ────────────────────────────────────────────────────────────────

local function pickUp(player: Player, item: "Fuse" | "Lamp")
	if GameStateService.GetPhase() ~= "Day" or not Carry.pickUp(player, item) then
		return
	end
	Notify.player(
		player,
		if item == "Fuse"
			then "⚡ Spare fuse in hand: carry it to a sparking panel."
			else "💡 Emergency lamp in hand: place it on a glowing ring.",
		"info"
	)
end

local function consume(player: Player, item: string): boolean
	return GameStateService.GetPhase() == "Day" and Carry.consume(player, item)
end

-- ── day props ───────────────────────────────────────────────────────────────

local function carryPrompt(part: BasePart, props: { [string]: any }, requires: string): ProximityPrompt
	local prompt = Builder.prompt(part, props)
	prompt:SetAttribute("RequiresCarry", requires)
	Builder.tag(prompt, "CarryPrompt")
	return prompt
end

local function markDone(part: BasePart, prompt: ProximityPrompt)
	part:SetAttribute("Done", true)
	prompt:SetAttribute("Done", true)
	prompt.Enabled = false
end

local function buildDepot(parent: Instance)
	local model = Builder.model("MaintenanceDepot", parent)
	Builder.part({
		Parent = model,
		Size = Vector3.new(11, 1, 4),
		CFrame = DEPOT * CFrame.new(0, 0.5, 0),
		Color = Palette.DarkMetal,
		Material = Enum.Material.DiamondPlate,
	})
	local sign = Builder.decor({
		Parent = model,
		Size = Vector3.new(9, 1.8, 0.3),
		CFrame = DEPOT * CFrame.new(0, 6.4, 1.6),
		Color = Color3.fromRGB(240, 196, 40),
	})
	Builder.label(
		sign,
		Enum.NormalId.Front,
		"⚠ MAINTENANCE DEPOT",
		{ Color = Color3.fromRGB(30, 24, 20), Font = FONT }
	)
	for _, data in
		{
			{ "SupplyFuse", "Fuse", "Take Spare Fuse", "Spare Fuses", -2.6, Palette.NeonGold },
			{ "SupplyLamp", "Lamp", "Take Emergency Lamp", "Emergency Lamps", 2.6, Palette.WarmLight },
		}
	do
		local bin = Builder.part({
			Name = data[1],
			Parent = model,
			Size = Vector3.new(4, 3, 3),
			CFrame = DEPOT * CFrame.new(data[5], 2.5, 0),
			Color = Color3.fromRGB(60, 56, 70),
			Material = Enum.Material.Metal,
		})
		for i = 0, 2 do
			Builder.decor({
				Parent = model,
				Size = Vector3.new(0.8, 1.2, 0.8),
				CFrame = DEPOT * CFrame.new(data[5] - 1.1 + i * 1.1, 4.6, 0),
				Color = data[6],
				Material = Enum.Material.Neon,
			})
		end
		Builder.tag(bin, data[1])
		local prompt = Builder.prompt(bin, {
			Name = "TakePrompt",
			ActionText = data[3],
			ObjectText = data[4],
			MaxActivationDistance = 9,
		})
		local item = data[2]
		prompt.Triggered:Connect(function(player)
			pickUp(player, item)
		end)
	end
end

local function buildPanel(parent: Instance, info: { Name: string, CFrame: CFrame }, total: number)
	local model = Builder.model("PowerPanel", parent)
	local cf = info.CFrame
	local box = Builder.part({
		Name = "Box",
		Parent = model,
		Size = Vector3.new(4, 5, 1.2),
		CFrame = cf * CFrame.new(0, 0, -0.6),
		Color = Color3.fromRGB(150, 156, 166),
		Material = Enum.Material.Metal,
	})
	for i = 0, 3 do
		Builder.decor({
			Parent = model,
			Size = Vector3.new(4.05, 0.35, 0.1),
			CFrame = cf * CFrame.new(0, -2.2 + i * 0.12, -1.25) * CFrame.Angles(0, 0, if i % 2 == 0 then 0.5 else -0.5),
			Color = if i % 2 == 0 then Color3.fromRGB(240, 196, 40) else Color3.fromRGB(30, 30, 30),
		})
	end
	local status = Builder.decor({
		Name = "Status",
		Parent = model,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.6,
		CFrame = cf * CFrame.new(0, 2.9, -0.7),
		Color = Palette.NeonRed,
		Material = Enum.Material.Neon,
	})
	local light = Builder.light("PointLight", status, { Range = 10, Brightness = 2, Color = Palette.NeonRed })
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 1, -0.7)
	attachment.Parent = box
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 240, 180), Color3.fromRGB(255, 160, 60))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.25, 0)
	sparks.Speed = NumberRange.new(6, 14)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Acceleration = Vector3.new(0, -35, 0)
	sparks.Lifetime = NumberRange.new(0.25, 0.6)
	sparks.Rate = 26
	sparks.Parent = attachment

	box:SetAttribute("Done", false)
	Builder.tag(box, "PowerPanel")
	local prompt = carryPrompt(box, {
		Name = "RepairPrompt",
		ActionText = "Install Spare Fuse",
		ObjectText = info.Name,
		HoldDuration = 2.5,
		MaxActivationDistance = 9,
	}, "Fuse")
	prompt.Triggered:Connect(function(player)
		if box:GetAttribute("Done") or not consume(player, "Fuse") then
			return
		end
		markDone(box, prompt)
		sparks.Enabled = false
		status.Color = Palette.NeonGreen
		light.Color = Palette.NeonGreen
		panelsDone += 1
		MissionEvents.record(player, "PanelRepaired")
		Notify.all(
			string.format("🔧 %s fixed the %s (%d/%d)", player.DisplayName, info.Name, panelsDone, total),
			"success"
		)
		Notify.effect(player, "Purchase")
		if panelsDone >= total then
			ReplicatedStorage:SetAttribute("PowerFlicker", false)
			Notify.all("✅ Panels repaired: the flickering stops. Now get those emergency lamps in place!", "success")
		end
	end)
end

local function buildLamp(parent: Instance, position: Vector3): Model
	local model = Builder.model("EmergencyLamp", parent)
	Builder.part({
		Parent = model,
		Size = Vector3.new(1.6, 0.4, 1.6),
		CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Metal,
	})
	Builder.decor({
		Parent = model,
		Size = Vector3.new(0.3, 4, 0.3),
		CFrame = CFrame.new(position + Vector3.new(0, 2.3, 0)),
		Color = Color3.fromRGB(240, 196, 40),
		Material = Enum.Material.Metal,
	})
	local head = Builder.decor({
		Name = "Head",
		Parent = model,
		Size = Vector3.new(1.4, 1.2, 1.4),
		CFrame = CFrame.new(position + Vector3.new(0, 4.8, 0)),
		Color = Color3.fromRGB(120, 110, 90),
		Material = Enum.Material.Glass,
	})
	Builder.light(
		"PointLight",
		head,
		{ Name = "Glow", Range = 24, Brightness = 0, Color = Palette.WarmLight, Shadows = false }
	)
	model:SetAttribute("Position", position)
	return model
end

local function buildSpot(parent: Instance, lamps: Instance, position: Vector3)
	local ring = Builder.decor({
		Name = "LampSpot",
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 5, 5),
		CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.WarmLight,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
	})
	ring:SetAttribute("Done", false)
	Builder.tag(ring, "LampSpot")
	local prompt = carryPrompt(ring, {
		Name = "PlacePrompt",
		ActionText = "Place Emergency Lamp",
		ObjectText = "Lamp Spot",
		MaxActivationDistance = 8,
	}, "Lamp")
	prompt.Triggered:Connect(function(player)
		if ring:GetAttribute("Done") or not consume(player, "Lamp") then
			return
		end
		markDone(ring, prompt)
		ring.Transparency = 1
		buildLamp(lamps, position)
		MissionEvents.record(player, "LampPlaced")
		Notify.all(string.format("💡 %s set up an emergency lamp.", player.DisplayName), "success")
		Notify.effect(player, "Purchase")
	end)
end

-- ── level hooks (called by MissionService) ──────────────────────────────────

local function clearDay()
	Carry.clearAll()
	if dayFolder then
		dayFolder:Destroy()
		dayFolder = nil
	end
	ReplicatedStorage:SetAttribute("PowerFlicker", false)
end

local function clearLamps()
	nightToken = nil
	if lampFolder then
		lampFolder:Destroy()
		lampFolder = nil
	end
end

function PowerGrid.StartDay()
	clearDay()
	clearLamps()
	panelsDone = 0
	local folder = Instance.new("Folder")
	folder.Name = "PowerGridDay"
	folder.Parent = workspace
	dayFolder = folder
	local lamps = Instance.new("Folder")
	lamps.Name = "EmergencyLamps"
	lamps.Parent = workspace
	lampFolder = lamps

	buildDepot(folder)
	for _, info in PANELS do
		buildPanel(folder, info, #PANELS)
	end
	for _, position in LAMP_SPOTS do
		buildSpot(folder, lamps, position)
	end
	ReplicatedStorage:SetAttribute("PowerFlicker", true)
end

function PowerGrid.EndDay()
	clearDay()
end

function PowerGrid.StartNight()
	local lamps = lampFolder
	if not lamps then
		return
	end
	local centers = {}
	for _, lamp in lamps:GetChildren() do
		local head = lamp:FindFirstChild("Head") :: BasePart?
		local glow = head and head:FindFirstChild("Glow") :: PointLight?
		if head and glow then
			head.Material = Enum.Material.Neon
			head.Color = Palette.WarmLight
			glow.Brightness = 3
			table.insert(centers, lamp:GetAttribute("Position") :: Vector3)
		end
	end
	if #centers == 0 then
		return
	end
	local token = {}
	nightToken = token
	task.spawn(function()
		while nightToken == token do
			task.wait(0.5)
			for _, enemy in table.clone(EnemyService.GetAll()) do
				for _, center in centers do
					if (enemy.Root.Position - center).Magnitude < LAMP_RADIUS then
						EnemyService.Damage(enemy, LAMP_DPS * 0.5, nil)
						break
					end
				end
			end
		end
	end)
end

function PowerGrid.EndNight()
	clearLamps()
end

function PowerGrid.PatrolPoints(): { Vector3 }
	return PATROL
end

return PowerGrid
