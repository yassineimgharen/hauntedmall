-- Level 6 day, "Final Preparations" (+ its floodlights at night).
--
--   * Scrap piles (random each day) are collected just by walking over them; they fill a
--     shared team pool.
--   * The workbench crafts a floodlight kit from SCRAP_PER_KIT scrap; carry it to one of
--     the tower spots by the entrance.
--   * Three markings on the walls are invisible until held in a flashlight beam; each one
--     reveals a clue about the boss.
--   * Night: built floodlights switch on and burn crawlers near the evac point.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local CombatService = require(script.Parent.Parent.Services.CombatService)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local Layout = require(script.Parent.Parent.World.Layout)
local Carry = require(script.Parent.Carry)

local Preparations = {}

local A = Layout.Atrium
local FONT = Font.new("rbxasset://fonts/families/Creepster.json")
local PILES = 14
local SCRAP_PER_KIT = 3
local PICKUP_RANGE = 4.5
local REVEAL_SECONDS = 2
local FLOOD_RADIUS = 14

local SCRAP_SPOTS = {
	Vector3.new(-40, 0, -30),
	Vector3.new(38, 0, -28),
	Vector3.new(-30, 0, 40),
	Vector3.new(30, 0, 44),
	Vector3.new(-55, 0, 0),
	Vector3.new(55, 0, 10),
	Vector3.new(-20, 0, 55),
	Vector3.new(20, 0, 55),
	Vector3.new(-45, A.BalconyY, 45),
	Vector3.new(45, A.BalconyY, -45),
	Vector3.new(0, A.BalconyY, 55),
	Vector3.new(0, A.BalconyY, -55),
	Vector3.new(55, A.BalconyY, 30),
	Vector3.new(85, 0, -12),
	Vector3.new(100, 0, 12),
	Vector3.new(118, 0, -12),
	Vector3.new(135, 0, 12),
	Vector3.new(150, 0, -12),
	Vector3.new(170, 0, 8),
	Vector3.new(-30, 0, -85),
	Vector3.new(35, 0, -110),
}
local WORKBENCH = CFrame.lookAt(Vector3.new(-26, 0, -63), Vector3.new(-26, 0, 0))
local TOWER_SPOTS = { Vector3.new(-14, 0, -58), Vector3.new(14, 0, -58), Vector3.new(0, 0, -42) }
local MARKINGS = {
	{
		CFrame = CFrame.lookAt(Vector3.new(-69.6, 6, -20), Vector3.new(0, 6, -20)),
		Text = "SHE WAKES ON\nTHE SEVENTH NIGHT",
	},
	{
		CFrame = CFrame.lookAt(Vector3.new(69.6, 6, 24), Vector3.new(0, 6, 24)),
		Text = "HER SHIELD BREAKS\nIN FOCUSED LIGHT",
	},
	{
		CFrame = CFrame.lookAt(Vector3.new(181.6, 6, -10), Vector3.new(0, 6, -10)),
		Text = "THE BROOD\nSERVES THE QUEEN",
	},
}

local folder: Folder? = nil
local towerFolder: Folder? = nil
local token: {}? = nil
local nightToken: {}? = nil
local piles: { BasePart } = {}
local pool = 0
local benchPrompt: ProximityPrompt? = nil
local rng = Random.new()

local function isDay(): boolean
	return token ~= nil and GameStateService.GetPhase() == "Day"
end

local function updateBench()
	if benchPrompt then
		benchPrompt.ObjectText = string.format("Workbench · scrap %d (kit costs %d)", pool, SCRAP_PER_KIT)
	end
end

-- ── scrap ───────────────────────────────────────────────────────────────────

local function buildPile(parent: Instance, position: Vector3)
	local pile = Builder.decor({
		Name = "ScrapPile",
		Parent = parent,
		Size = Vector3.new(2.4, 0.6, 2.4),
		CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)),
		Color = Color3.fromRGB(120, 124, 132),
		Material = Enum.Material.CorrodedMetal,
	})
	for i = 1, 3 do
		Builder.decor({
			Parent = pile,
			Size = Vector3.new(rng:NextNumber(0.6, 1.4), 0.3, rng:NextNumber(0.3, 0.8)),
			CFrame = CFrame.new(
				position + Vector3.new(rng:NextNumber(-0.8, 0.8), 0.7 + i * 0.12, rng:NextNumber(-0.8, 0.8))
			) * CFrame.Angles(0, rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)),
			Color = Color3.fromRGB(160, 150, 130),
			Material = Enum.Material.Metal,
		})
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = pile
	local glint = Instance.new("ParticleEmitter")
	glint.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glint.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200))
	glint.LightEmission = 1
	glint.Size = NumberSequence.new(0.3, 0)
	glint.Lifetime = NumberRange.new(0.4, 0.7)
	glint.Rate = 3
	glint.Speed = NumberRange.new(0.5, 1)
	glint.Parent = attachment
	Builder.tag(pile, "ScrapPile")
	table.insert(piles, pile)
end

local function runScrap(myToken: {})
	while token == myToken do
		task.wait(0.25)
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				for i = #piles, 1, -1 do
					local pile = piles[i]
					local offset = pile.Position - root.Position
					if Vector3.new(offset.X, 0, offset.Z).Magnitude < PICKUP_RANGE and math.abs(offset.Y) < 6 then
						table.remove(piles, i)
						pile:Destroy()
						pool += 1
						updateBench()
						MissionEvents.record(player, "ScrapCollected")
						Notify.effect(player, "Purchase")
						Notify.player(player, string.format("🔩 +1 scrap (team pool: %d)", pool), "info")
					end
				end
			end
		end
	end
end

-- ── workbench & towers ──────────────────────────────────────────────────────

local function buildWorkbench(parent: Instance)
	local model = Builder.model("Workbench", parent)
	local bench = Builder.part({
		Name = "Workbench",
		Parent = model,
		Size = Vector3.new(7, 3.2, 3),
		CFrame = WORKBENCH * CFrame.new(0, 1.6, 0),
		Color = Palette.WoodDark,
		Material = Enum.Material.Wood,
	})
	Builder.decor({
		Parent = model,
		Size = Vector3.new(7.2, 0.3, 3.2),
		CFrame = WORKBENCH * CFrame.new(0, 3.35, 0),
		Color = Palette.DarkMetal,
		Material = Enum.Material.DiamondPlate,
	})
	Builder.decor({
		Parent = model,
		Size = Vector3.new(6, 4, 0.3),
		CFrame = WORKBENCH * CFrame.new(0, 5.4, 1.4),
		Color = Color3.fromRGB(60, 56, 70),
		Material = Enum.Material.Metal,
	})
	Builder.light("PointLight", bench, { Range = 12, Brightness = 1.4, Color = Palette.WarmLight })
	Builder.tag(bench, "Workbench")
	local prompt = Builder.prompt(bench, {
		Name = "CraftPrompt",
		ActionText = "Craft Floodlight Kit",
		ObjectText = "Workbench",
		HoldDuration = 2,
		MaxActivationDistance = 9,
	})
	benchPrompt = prompt
	updateBench()
	prompt.Triggered:Connect(function(player)
		if not isDay() then
			return
		end
		if pool < SCRAP_PER_KIT then
			Notify.player(
				player,
				string.format("Need %d scrap in the team pool (have %d).", SCRAP_PER_KIT, pool),
				"warning"
			)
			return
		end
		if Carry.pickUp(player, "Floodlight") then
			pool -= SCRAP_PER_KIT
			updateBench()
			Notify.player(player, "💡 Floodlight kit crafted: carry it to a tower spot by the entrance.", "info")
		end
	end)
end

local function buildTower(parent: Instance, position: Vector3): BasePart
	local model = Builder.model("FloodlightTower", parent)
	Builder.part({
		Parent = model,
		Size = Vector3.new(2.4, 0.6, 2.4),
		CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Metal,
	})
	Builder.part({
		Parent = model,
		Size = Vector3.new(0.5, 10, 0.5),
		CFrame = CFrame.new(position + Vector3.new(0, 5.4, 0)),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Metal,
	})
	local head = Builder.decor({
		Name = "Head",
		Parent = model,
		Size = Vector3.new(3, 1.6, 1.2),
		CFrame = CFrame.new(position + Vector3.new(0, 10.6, 0)),
		Color = Color3.fromRGB(110, 114, 130),
		Material = Enum.Material.Glass,
	})
	Builder.light(
		"PointLight",
		head,
		{ Name = "Glow", Range = 30, Brightness = 0, Color = Color3.fromRGB(235, 240, 255) }
	)
	return head
end

local function buildSpot(parent: Instance, position: Vector3)
	local ring = Builder.decor({
		Name = "FloodlightSpot",
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 5, 5),
		CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(235, 240, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.5,
	})
	ring:SetAttribute("Done", false)
	Builder.tag(ring, "FloodlightSpot")
	local prompt = Builder.prompt(ring, {
		Name = "BuildPrompt",
		ActionText = "Build Floodlight Tower",
		ObjectText = "Tower Spot",
		HoldDuration = 2,
		MaxActivationDistance = 8,
	})
	prompt:SetAttribute("RequiresCarry", "Floodlight")
	Builder.tag(prompt, "CarryPrompt")
	prompt.Triggered:Connect(function(player)
		local towers = towerFolder
		if not isDay() or ring:GetAttribute("Done") or not towers or not Carry.consume(player, "Floodlight") then
			return
		end
		ring:SetAttribute("Done", true)
		prompt:SetAttribute("Done", true)
		prompt.Enabled = false
		ring.Transparency = 1
		buildTower(towers, position)
		MissionEvents.record(player, "FloodlightBuilt")
		Notify.all(string.format("💡 %s raised a floodlight tower.", player.DisplayName), "success")
	end)
end

-- ── markings ────────────────────────────────────────────────────────────────

local function buildMarking(parent: Instance, info: { CFrame: CFrame, Text: string })
	local model = Instance.new("Model")
	model.Name = "Marking"
	local plate = Builder.decor({
		Name = "Marking",
		Parent = model,
		Size = Vector3.new(7, 4.5, 0.1),
		CFrame = info.CFrame,
		Color = Palette.Wall,
		Transparency = 1,
	})
	model.PrimaryPart = plate
	model.Parent = parent
	local _, label = Builder.label(plate, Enum.NormalId.Front, info.Text, { Color = Palette.NeonPurple, Font = FONT })
	label.TextTransparency = 0.94 -- barely visible until lit
	plate:SetAttribute("Done", false)
	Builder.tag(plate, "Marking")

	local lit = 0
	CombatService.RegisterLightTarget(model, function(player, dt)
		if not isDay() or plate:GetAttribute("Done") then
			return
		end
		lit += dt
		label.TextTransparency = math.max(0, 0.94 - lit / REVEAL_SECONDS)
		if lit >= REVEAL_SECONDS then
			plate:SetAttribute("Done", true)
			CombatService.UnregisterLightTarget(model)
			label.TextTransparency = 0
			Builder.light("PointLight", plate, { Range = 12, Brightness = 2, Color = Palette.NeonPurple })
			MissionEvents.record(player, "MarkingRevealed")
			Notify.all(
				string.format('🔦 %s revealed a marking: "%s"', player.DisplayName, (info.Text:gsub("\n", " "))),
				"warning"
			)
		end
	end)
end

-- ── level hooks ─────────────────────────────────────────────────────────────

local function clearDay()
	token = nil
	Carry.clearAll()
	table.clear(piles)
	benchPrompt = nil
	if folder then
		for _, descendant in folder:GetDescendants() do
			if descendant:IsA("Model") then
				CombatService.UnregisterLightTarget(descendant)
			end
		end
		folder:Destroy()
		folder = nil
	end
end

local function clearTowers()
	nightToken = nil
	if towerFolder then
		towerFolder:Destroy()
		towerFolder = nil
	end
end

function Preparations.StartDay()
	clearDay()
	clearTowers()
	local myToken = {}
	token = myToken
	pool = 0
	local newFolder = Instance.new("Folder")
	newFolder.Name = "Preparations"
	newFolder.Parent = workspace
	folder = newFolder
	local towers = Instance.new("Folder")
	towers.Name = "FloodlightTowers"
	towers.Parent = workspace
	towerFolder = towers

	local spots = table.clone(SCRAP_SPOTS)
	for _ = 1, math.min(PILES, #spots) do
		buildPile(newFolder, table.remove(spots, rng:NextInteger(1, #spots)) :: Vector3)
	end
	buildWorkbench(newFolder)
	for _, position in TOWER_SPOTS do
		buildSpot(newFolder, position)
	end
	for _, info in MARKINGS do
		buildMarking(newFolder, info)
	end
	task.spawn(runScrap, myToken)
end

function Preparations.EndDay()
	clearDay()
end

function Preparations.StartNight()
	local towers = towerFolder
	if not towers then
		return
	end
	local centers = {}
	for _, tower in towers:GetChildren() do
		local head = tower:FindFirstChild("Head") :: BasePart?
		local glow = head and head:FindFirstChild("Glow") :: PointLight?
		if head and glow then
			head.Material = Enum.Material.Neon
			head.Color = Color3.fromRGB(235, 240, 255)
			glow.Brightness = 3
			table.insert(centers, Vector3.new(head.Position.X, 0, head.Position.Z))
		end
	end
	if #centers == 0 then
		return
	end
	local myToken = {}
	nightToken = myToken
	task.spawn(function()
		while nightToken == myToken do
			task.wait(0.5)
			for _, enemy in table.clone(EnemyService.GetAll()) do
				for _, center in centers do
					local offset = enemy.Root.Position - center
					if Vector3.new(offset.X, 0, offset.Z).Magnitude < FLOOD_RADIUS then
						EnemyService.Damage(enemy, EnemyConfig.Fuses.SafeDPS * 0.5, nil)
						break
					end
				end
			end
		end
	end)
end

function Preparations.EndNight()
	clearTowers()
end

return Preparations
