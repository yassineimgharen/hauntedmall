-- The east shopping corridor with six ownable shops, skylight, and the locked wing gate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Builder = require(script.Parent.Builder)
local CorridorDetail = require(script.Parent.CorridorDetail)
local Layout = require(script.Parent.Layout)
local Props = require(script.Parent.Props)
local ShopUnit = require(script.Parent.ShopUnit)

local Corridor = {}

local C = Layout.Corridor
local FONT_HEADING = Font.new("rbxasset://fonts/families/FredokaOne.json")
local FONT_TITLE = Font.new("rbxasset://fonts/families/Creepster.json")

local function buildShell(parent: Instance)
	local length = C.EndX - C.StartX
	local midX = (C.StartX + C.EndX) / 2
	local shellZ = Layout.Shop.Depth + C.HalfWidth + 4

	-- floor: marble with dark transverse inlays and gold lane lines
	Builder.part({
		Name = "CorridorFloor",
		Parent = parent,
		Size = Vector3.new(length, 1, C.HalfWidth * 2),
		CFrame = CFrame.new(midX, -0.5, 0),
		Color = Palette.MarbleLight,
		Material = Enum.Material.Marble,
		Reflectance = 0.06,
	})
	for x = C.StartX + 8, C.EndX - 4, 8 do
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(1.2, 0.02, C.HalfWidth * 2 - 4),
			CFrame = CFrame.new(x, 0.01, 0),
			Color = Palette.MarbleDark,
			Material = Enum.Material.Marble,
		})
	end
	for _, z in { -C.HalfWidth + 2, C.HalfWidth - 2 } do
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(length, 0.03, 0.4),
			CFrame = CFrame.new(midX, 0.015, z),
			Color = Palette.Gold,
			Material = Enum.Material.Metal,
		})
	end

	-- pilasters between shopfronts and the bulkhead above them
	local fronts = {}
	for _, x in Layout.Shop.CentersX do
		table.insert(fronts, { x - Layout.Shop.Width / 2, x + Layout.Shop.Width / 2 })
	end
	local gaps = { { C.StartX, fronts[1][1] } }
	for i = 1, #fronts - 1 do
		table.insert(gaps, { fronts[i][2], fronts[i + 1][1] })
	end
	table.insert(gaps, { fronts[#fronts][2], C.EndX })
	for _, sign in { -1, 1 } do
		for _, gap in gaps do
			local width = gap[2] - gap[1]
			Builder.part({
				Parent = parent,
				Size = Vector3.new(width, C.Height, 3),
				CFrame = CFrame.new((gap[1] + gap[2]) / 2, C.Height / 2, sign * (C.HalfWidth + 0.5)),
				Color = Palette.MarbleWarm,
				Material = Enum.Material.Marble,
			})
			-- wall sconce
			local sconce = Builder.decor({
				Parent = parent,
				Size = Vector3.new(0.8, 1.6, 0.4),
				CFrame = CFrame.new((gap[1] + gap[2]) / 2, 9, sign * (C.HalfWidth - 1.2)),
				Color = Palette.WarmLight,
				Material = Enum.Material.Neon,
				Tags = { "DayNeon" },
			})
			Builder.light(
				"PointLight",
				sconce,
				{ Range = 12, Brightness = 0.8, Color = Palette.WarmLight },
				{ "DayLight" }
			)
		end
		Builder.part({
			Parent = parent,
			Size = Vector3.new(length, C.Height - 20, 3),
			CFrame = CFrame.new(midX, 20 + (C.Height - 20) / 2, sign * (C.HalfWidth + 0.5)),
			Color = Palette.Wall,
		})
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(length, 0.3, 0.3),
			CFrame = CFrame.new(midX, 20.6, sign * (C.HalfWidth - 1.1)),
			Color = if sign > 0 then Palette.NeonPink else Palette.NeonCyan,
			Material = Enum.Material.Neon,
			Tags = { "NightNeon" },
		})
	end

	-- ceiling with a central skylight
	local skylight = 8
	for _, sign in { -1, 1 } do
		local width = C.HalfWidth - skylight
		Builder.part({
			Parent = parent,
			Size = Vector3.new(length, 1, width + 1),
			CFrame = CFrame.new(midX, C.Height + 0.5, sign * (skylight + width / 2 + 0.5)),
			Color = Palette.Wall,
		})
	end
	Builder.decor({
		Parent = parent,
		Size = Vector3.new(length, 0.3, skylight * 2),
		CFrame = CFrame.new(midX, C.Height + 0.6, 0),
		Color = Palette.Glass,
		Material = Enum.Material.Glass,
		Transparency = 0.55,
	})
	for x = C.StartX + 4, C.EndX - 2, 8 do
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(0.5, 0.8, skylight * 2),
			CFrame = CFrame.new(x, C.Height + 0.2, 0),
			Color = Palette.DarkMetal,
			Material = Enum.Material.Metal,
		})
	end

	-- outer shell & roof over the shops
	local roofProps = { Parent = parent, Color = Palette.Wall }
	for _, sign in { -1, 1 } do
		local roof = table.clone(roofProps)
		roof.Size = Vector3.new(length + 2, 1, shellZ - C.HalfWidth - 2)
		roof.CFrame = CFrame.new(midX + 1, C.Height + 0.5, sign * (C.HalfWidth + 2 + (shellZ - C.HalfWidth - 2) / 2))
		Builder.part(roof)
		local side = table.clone(roofProps)
		side.Size = Vector3.new(length + 2, C.Height + 2, 2)
		side.CFrame = CFrame.new(midX + 1, (C.Height + 2) / 2, sign * shellZ)
		Builder.part(side)
	end
	Builder.part({
		Parent = parent,
		Size = Vector3.new(2, C.Height + 2, shellZ * 2),
		CFrame = CFrame.new(C.EndX + 1, (C.Height + 2) / 2, 0),
		Color = Palette.Wall,
	})
end

local function buildGate(parent: Instance)
	local x = C.EndX - 0.2
	local gate = Builder.part({
		Name = "WingGate",
		Parent = parent,
		Size = Vector3.new(0.3, 16, 22),
		CFrame = CFrame.new(x, 9.4, 0),
		Color = Builder.shade(Palette.Chrome, -0.3),
		Material = Enum.Material.DiamondPlate,
	})
	Props.infoPrompt(
		gate,
		"Food Court",
		"🍔 The Food Court is closed for renovation: it opens in a future update. Until then, the six East Wing shops are open for lease!"
	)
	Builder.label(gate, Enum.NormalId.Left, "FOOD COURT\nCOMING SOON", {
		Color = Color3.fromRGB(235, 235, 245),
		Font = FONT_HEADING,
		Lit = true,
	})
	Builder.decor({
		Parent = parent,
		Size = Vector3.new(0.2, 1.4, 22),
		CFrame = CFrame.new(x - 0.1, 0.7, 0),
		Color = Color3.new(0, 0, 0),
	})
	for _, data in
		{
			{ Vector3.new(0.3, 0.3, 22.6), Vector3.new(x - 0.3, 17.6, 0) },
			{ Vector3.new(0.3, 17, 0.3), Vector3.new(x - 0.3, 9, 11.3) },
			{ Vector3.new(0.3, 17, 0.3), Vector3.new(x - 0.3, 9, -11.3) },
		}
	do
		Builder.decor({
			Parent = parent,
			Size = data[1],
			CFrame = CFrame.new(data[2]),
			Color = Palette.NeonRed,
			Material = Enum.Material.Neon,
			Tags = { "NightNeon" },
		})
	end
	for _, z in { -5, 3 } do
		Props.lurkerEyes(CFrame.lookAt(Vector3.new(x - 0.4, 0.7, z), Vector3.new(0, 0.7, z)), parent, 1.2)
	end
	local warning = Builder.part({
		Parent = parent,
		Size = Vector3.new(0.3, 2.6, 12),
		CFrame = CFrame.new(x - 0.4, 20.5, 0),
		Color = Color3.fromRGB(16, 12, 26),
	})
	Builder.label(warning, Enum.NormalId.Left, "DO NOT ENTER AFTER DARK", {
		Color = Palette.NeonRed,
		Font = FONT_TITLE,
	})
end

local function buildDressing(parent: Instance, rng: Random)
	local centers = Layout.Shop.CentersX
	for i = 1, #centers - 1 do
		local x = (centers[i] + centers[i + 1]) / 2
		Props.planter(Vector3.new(x, 0, 0), 2.6, parent)
		Props.palm(Vector3.new(x, 2.5, 0), parent, rng, 11)
		for _, sign in { -1, 1 } do
			Props.bench(CFrame.lookAt(Vector3.new(x, 0, sign * 4.6), Vector3.new(x, 0, sign * 20)), parent)
		end
	end
	for x = C.StartX + 14, C.EndX - 8, 22 do
		for _, sign in { -1, 1 } do
			Props.pendantLamp(Vector3.new(x, 18, sign * 12.5), C.Height, parent, false)
		end
	end

	-- info kiosk near the corridor mouth
	local kiosk = Builder.model("InfoKiosk", parent)
	Builder.cylinder(Vector3.new(80, 1.8, 0), 2.6, 3.6, {
		Parent = kiosk,
		Color = Palette.MarbleLight,
		Material = Enum.Material.Marble,
	})
	Builder.cylinder(Vector3.new(80, 3.75, 0), 2.9, 0.3, {
		Parent = kiosk,
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
	})
	local screen = Builder.decor({
		Parent = kiosk,
		Size = Vector3.new(0.3, 4, 6),
		CFrame = CFrame.new(80, 6.4, 0),
		Color = Color3.fromRGB(18, 14, 30),
	})
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		Builder.label(screen, face, "MALL GUIDE\n🛍️ Claim a shop\n🌙 Survive the night", {
			Color = Palette.NeonCyan,
			Font = FONT_HEADING,
			GuiName = "Gui" .. face.Name,
		})
	end
end

function Corridor.build(parent: Instance)
	local model = Builder.model("EastCorridor", parent)
	local shops = Builder.folder("Shops", parent)
	local rng = Random.new(4242)

	buildShell(model)
	buildGate(model)
	buildDressing(model, rng)
	CorridorDetail.build(model)

	local index = 0
	for _, x in Layout.Shop.CentersX do
		for _, side in { 1, -1 } do
			index += 1
			local origin = CFrame.new(x, 0, side * C.HalfWidth)
			if side < 0 then
				origin *= CFrame.Angles(0, math.pi, 0)
			end
			local accent = Palette.ShopAccents[(index - 1) % #Palette.ShopAccents + 1]
			local category = EconomyConfig.Categories[(index - 1) % #EconomyConfig.Categories + 1]
			ShopUnit.build(shops, "S" .. index, origin, accent, category)
		end
	end

	Props.fuseBox(
		CFrame.lookAt(Vector3.new(C.EndX, 4.5, 14.5), Vector3.new(0, 4.5, 14.5)),
		"Corridor",
		"East Wing Power",
		model
	)
	for _, z in { -6, 6 } do
		Builder.part({
			Name = "EnemySpawn",
			Parent = model,
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(C.EndX - 6, 3, z),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Tags = { "EnemySpawn" },
		})
	end
	return model
end

return Corridor
