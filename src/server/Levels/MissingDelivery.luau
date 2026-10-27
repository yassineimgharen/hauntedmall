-- Level 3 day, "The Missing Delivery": an investigation.
--
--   1. A trail of 3 clues (only the current one exists) leads from the empty delivery van
--      through the atrium to the upper level. The last clue names the storage cage.
--   2. 4 storage cages can be searched (hold E). One, random each time, hides the stash.
--   3. The 4 stolen crates are unique carried items: carry each back to the van. Loading
--      one also gifts stock to the carrier's shop. A dropped crate returns to the stash.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
local ShopService = require(script.Parent.Parent.Services.ShopService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local Layout = require(script.Parent.Parent.World.Layout)
local Carry = require(script.Parent.Carry)

local MissingDelivery = {}

local A = Layout.Atrium
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local CARDBOARD = Color3.fromRGB(198, 152, 100)
local CRATES = 4
local STOCK_PER_CRATE = 6

-- Van in the plaza, cab facing east; its open rear faces the entrance (x = 28).
local VAN = CFrame.lookAt(Vector3.new(36, 0, -78), Vector3.new(60, 0, -78))
local DOCK = Vector3.new(25, 0, -78)

local CLUES = {
	{
		Position = Vector3.new(24, 0, -85),
		Text = '📄 A torn delivery manifest: "4 crates, signed by…" just claw marks. The tracks lead into the mall.',
	},
	{
		Position = Vector3.new(-48, 0, -24),
		Text = "🥜 Spilled packing peanuts and three-toed footprints, heading for the escalator.",
	},
	{
		Position = Vector3.new(40, A.BalconyY, 54),
		Text = "🧤 A chewed work glove. The scratches lead to STORAGE %s!",
	},
}

local CAGES = {
	{ Name = "A", Position = Vector3.new(-58, 0, 58) },
	{ Name = "B", Position = Vector3.new(58, 0, 60) },
	{ Name = "C", Position = Vector3.new(-55, A.BalconyY, -55) },
	{ Name = "D", Position = Vector3.new(170, 0, -12) },
}

local JUNK = {
	"just tangled tinsel and a headless mannequin.",
	"only broken shopping carts in here.",
	"boxes of last year's holiday decorations. Nothing stolen.",
}

local folder: Folder? = nil
local active = false
local stash = 1
local loaded = 0
local rng = Random.new()

local function isDay(): boolean
	return active and GameStateService.GetPhase() == "Day"
end

-- The cage door faces the atrium centre; the cage extends behind it (local +Z).
local function cageFront(cage: { Position: Vector3 }): CFrame
	local p = cage.Position
	return CFrame.lookAt(p, Vector3.new(0, p.Y, 0))
end

-- ── van ─────────────────────────────────────────────────────────────────────

local function buildVan(parent: Instance)
	local model = Builder.model("DeliveryVan", parent)
	local function solid(size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?)
		return Builder.part({
			Parent = model,
			Size = size,
			CFrame = VAN * CFrame.new(offset),
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
		})
	end
	local box = solid(Vector3.new(7, 7, 11), Vector3.new(0, 4.6, 2.5), Color3.fromRGB(236, 236, 240))
	solid(Vector3.new(7, 5, 5), Vector3.new(0, 3.6, -5.5), Palette.NeonPurple)
	Builder.decor({
		Parent = model,
		Size = Vector3.new(6.4, 2, 0.1),
		CFrame = VAN * CFrame.new(0, 4.7, -8.05),
		Color = Color3.fromRGB(40, 50, 70),
		Material = Enum.Material.Glass,
	})
	Builder.decor({ -- dark, empty cargo opening
		Parent = model,
		Size = Vector3.new(6, 6, 0.1),
		CFrame = VAN * CFrame.new(0, 4.6, 8.05),
		Color = Color3.fromRGB(14, 12, 20),
	})
	for _, side in { -1, 1 } do
		Builder.decor({ -- rear doors swung open
			Parent = model,
			Size = Vector3.new(0.2, 6, 3),
			CFrame = VAN * CFrame.new(side * 4.9, 4.6, 9.4),
			Color = Color3.fromRGB(220, 220, 228),
		})
		for _, z in { -5.5, 4.5 } do
			Builder.decor({
				Parent = model,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1, 2.4, 2.4),
				CFrame = VAN * CFrame.new(side * 3.4, 1.2, z),
				Color = Color3.fromRGB(26, 26, 30),
			})
		end
	end
	Builder.label(
		box,
		Enum.NormalId.Left,
		"NIGHT SHIFT\nDELIVERIES",
		{ Color = Palette.NeonPurple, Font = FONT, Lit = true }
	)
	Builder.label(
		box,
		Enum.NormalId.Right,
		"NIGHT SHIFT\nDELIVERIES",
		{ Color = Palette.NeonPurple, Font = FONT, Lit = true }
	)

	local dock = Builder.decor({
		Name = "ReturnDock",
		Parent = model,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 6, 6),
		CFrame = CFrame.new(DOCK + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.NeonGreen,
		Material = Enum.Material.Neon,
		Transparency = 0.5,
	})
	Builder.tag(dock, "ReturnDock")
	local prompt = Builder.prompt(dock, {
		Name = "LoadPrompt",
		ActionText = "Load Crate",
		ObjectText = "Delivery Van",
		MaxActivationDistance = 9,
	})
	prompt:SetAttribute("RequiresCarry", "Crate")
	Builder.tag(prompt, "CarryPrompt")
	prompt.Triggered:Connect(function(player)
		if not isDay() or not Carry.consume(player, "Crate") then
			return
		end
		loaded += 1
		Builder.decor({ -- stack the recovered crate in the van's doorway
			Parent = model,
			Size = Vector3.new(2.2, 2, 2.2),
			CFrame = VAN * CFrame.new(-1.3 + ((loaded - 1) % 2) * 2.6, 2.1 + math.floor((loaded - 1) / 2) * 2.1, 6.6),
			Color = CARDBOARD,
			Material = Enum.Material.Cardboard,
		})
		MissionEvents.record(player, "CrateRecovered")
		local stock = ShopService.AddStock(player, STOCK_PER_CRATE)
		Notify.all(string.format("🚚 %s loaded a crate (%d/%d)", player.DisplayName, loaded, CRATES), "success")
		if stock > 0 then
			Notify.player(
				player,
				string.format("📦 +%d stock for your shop from the recovered goods!", stock),
				"success"
			)
		end
		Notify.effect(player, "Purchase")
		if loaded >= CRATES then
			Notify.all("✅ The whole delivery is back in the van!", "success")
			dock:SetAttribute("Done", true)
			prompt:SetAttribute("Done", true)
			prompt.Enabled = false
		end
	end)
end

-- ── stash crates ────────────────────────────────────────────────────────────

local function spawnCrate(parent: Instance, cf: CFrame)
	if not isDay() then
		return
	end
	local crate = Builder.part({
		Name = "StashCrate",
		Parent = parent,
		Size = Vector3.new(2.2, 2, 2.2),
		CFrame = cf,
		Color = CARDBOARD,
		Material = Enum.Material.Cardboard,
	})
	Builder.tag(crate, "StashCrate")
	local glow = Builder.light("PointLight", crate, { Range = 8, Brightness = 1, Color = Palette.NeonGold })
	glow.Name = "Glow"
	local prompt = Builder.prompt(crate, {
		Name = "GrabPrompt",
		ActionText = "Grab Crate",
		ObjectText = "Stolen Stock",
		MaxActivationDistance = 8,
	})
	prompt.Triggered:Connect(function(player)
		if not isDay() or crate:GetAttribute("Done") then
			return
		end
		local taken = Carry.pickUp(player, "Crate", function()
			spawnCrate(parent, cf) -- dropped: it turns up back at the stash
		end)
		if taken then
			crate:SetAttribute("Done", true)
			crate:Destroy()
			Notify.player(player, "📦 Crate in hand: carry it to the delivery van outside the entrance.", "info")
		end
	end)
end

-- ── storage cages ───────────────────────────────────────────────────────────

local function buildCage(parent: Instance, index: number)
	local cage = CAGES[index]
	local model = Builder.model("Storage" .. cage.Name, parent)
	local cf = cageFront(cage)
	local metal = Color3.fromRGB(120, 124, 136)
	Builder.part({
		Parent = model,
		Size = Vector3.new(7, 0.3, 7),
		CFrame = cf * CFrame.new(0, 0.15, 4),
		Color = Palette.DarkMetal,
		Material = Enum.Material.DiamondPlate,
	})
	for _, x in { -3.4, 3.4 } do
		for _, z in { 0.6, 7.4 } do
			Builder.part({
				Parent = model,
				Size = Vector3.new(0.3, 7, 0.3),
				CFrame = cf * CFrame.new(x, 3.5, z),
				Color = metal,
				Material = Enum.Material.Metal,
			})
		end
	end
	for i = -2, 2 do -- mesh bars on the sides and back
		for _, data in
			{
				{ Vector3.new(0.12, 6.8, 0.12), Vector3.new(-3.4, 3.4, 4 + i * 1.3) },
				{ Vector3.new(0.12, 6.8, 0.12), Vector3.new(3.4, 3.4, 4 + i * 1.3) },
				{ Vector3.new(0.12, 6.8, 0.12), Vector3.new(i * 1.3, 3.4, 7.4) },
			}
		do
			Builder.decor({
				Parent = model,
				Size = data[1],
				CFrame = cf * CFrame.new(data[2]),
				Color = metal,
				Material = Enum.Material.Metal,
			})
		end
	end
	Builder.decor({
		Parent = model,
		Size = Vector3.new(7, 0.3, 7),
		CFrame = cf * CFrame.new(0, 7, 4),
		Color = metal,
		Material = Enum.Material.Metal,
	})
	for i = 1, 3 do
		Builder.decor({
			Parent = model,
			Size = Vector3.new(1.8, 1.6, 1.8),
			CFrame = cf * CFrame.new(-2 + (i - 1) * 2, 1.1, 6) * CFrame.Angles(0, i * 0.4, 0),
			Color = Builder.shade(CARDBOARD, -0.1 * i),
			Material = Enum.Material.Cardboard,
		})
	end
	local sign = Builder.decor({
		Parent = model,
		Size = Vector3.new(4, 1.4, 0.2),
		CFrame = cf * CFrame.new(0, 7.9, 0.6),
		Color = Color3.fromRGB(240, 196, 40),
	})
	Builder.label(
		sign,
		Enum.NormalId.Front,
		"STORAGE " .. cage.Name,
		{ Color = Color3.fromRGB(30, 24, 20), Font = FONT }
	)

	local door = Builder.part({
		Name = "Door",
		Parent = model,
		Size = Vector3.new(6.4, 6.6, 0.15),
		CFrame = cf * CFrame.new(0, 3.5, 0.6),
		Color = metal,
		Material = Enum.Material.Metal,
		Transparency = 0.55,
	})
	door:SetAttribute("Done", false)
	door:SetAttribute("Cage", cage.Name)
	Builder.tag(door, "StorageCage")
	local prompt = Builder.prompt(door, {
		Name = "SearchPrompt",
		ActionText = "Search Storage " .. cage.Name,
		ObjectText = "Storage Cage",
		HoldDuration = 3,
		MaxActivationDistance = 9,
	})
	prompt.Triggered:Connect(function(player)
		if not isDay() or door:GetAttribute("Done") then
			return
		end
		door:SetAttribute("Done", true)
		prompt.Enabled = false
		door.CanCollide = false
		door.Transparency = 0.9
		MissionEvents.record(player, "CageSearched")
		if index == stash then
			MissionEvents.record(player, "StashFound")
			Notify.all(
				string.format("📦 %s found the stolen crates in Storage %s!", player.DisplayName, cage.Name),
				"success"
			)
			for i = 1, CRATES do
				spawnCrate(model, cf * CFrame.new(-3.3 + (i - 1) * 2.2, 1.3, -2.2))
			end
		else
			Notify.player(player, string.format("Storage %s: %s", cage.Name, JUNK[rng:NextInteger(1, #JUNK)]), "info")
		end
	end)
end

-- ── clue trail ──────────────────────────────────────────────────────────────

local function spawnClue(parent: Instance, index: number)
	local clue = CLUES[index]
	if not clue or not isDay() then
		return
	end
	local part = Builder.decor({
		Name = "Clue",
		Parent = parent,
		Size = Vector3.new(1.4, 0.3, 1.4),
		CFrame = CFrame.new(clue.Position + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
		Color = Color3.fromRGB(240, 236, 220),
	})
	Builder.tag(part, "Clue")
	Builder.light("PointLight", part, { Range = 10, Brightness = 1.6, Color = Palette.NeonCyan })
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Palette.NeonCyan)
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(0.35, 0)
	sparkle.Lifetime = NumberRange.new(0.8, 1.2)
	sparkle.Speed = NumberRange.new(1, 2)
	sparkle.Rate = 8
	sparkle.Parent = attachment
	local prompt = Builder.prompt(part, {
		Name = "InspectPrompt",
		ActionText = "Inspect",
		ObjectText = string.format("Clue %d/%d", index, #CLUES),
		HoldDuration = 1.5,
		MaxActivationDistance = 8,
	})
	prompt.Triggered:Connect(function(player)
		if not isDay() or part:GetAttribute("Done") then
			return
		end
		part:SetAttribute("Done", true)
		part:Destroy()
		MissionEvents.record(player, "ClueFound")
		local text = if index == #CLUES then string.format(clue.Text, CAGES[stash].Name) else clue.Text
		Notify.all(string.format("🔍 %s: %s", player.DisplayName, text), "info")
		if index == #CLUES then
			for _, door in CollectionService:GetTagged("StorageCage") do
				if door:GetAttribute("Cage") == CAGES[stash].Name then
					door:SetAttribute("Hinted", true) -- the guide marker now prefers this cage
				end
			end
		else
			spawnClue(parent, index + 1)
		end
	end)
end

-- ── level hooks ─────────────────────────────────────────────────────────────

local function clear()
	active = false
	Carry.clearAll()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function MissingDelivery.StartDay()
	clear()
	active = true
	stash = rng:NextInteger(1, #CAGES)
	loaded = 0
	local newFolder = Instance.new("Folder")
	newFolder.Name = "MissingDelivery"
	newFolder.Parent = workspace
	folder = newFolder
	buildVan(newFolder)
	for index in CAGES do
		buildCage(newFolder, index)
	end
	spawnClue(newFolder, 1)
end

function MissingDelivery.EndDay()
	clear()
end

return MissingDelivery
