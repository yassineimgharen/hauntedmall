-- Premium detail pass for the East Wing corridor (visual benchmark slice): marble runner,
-- coffered soffit beams with cove light troughs, hanging wayfinding, backlit ad panels on
-- the pilasters, night uplights, planted flower beds, skylight sun shafts and particles.
-- Keeps the customer lanes (z = ±Layout.Corridor.LaneZ) and shop doorways clear.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Builder = require(script.Parent.Builder)
local Layout = require(script.Parent.Layout)
local Props = require(script.Parent.Props)

local CorridorDetail = {}

local C = Layout.Corridor

local ADS = {
	{ "MOONBEAM CAFÉ", "Now brewing past midnight", Color3.fromRGB(170, 70, 140) },
	{ "STARLIGHT CINEMA", "Midnight double feature", Color3.fromRGB(60, 70, 170) },
	{ "VELVET ARCADE", "High scores never sleep", Color3.fromRGB(120, 50, 180) },
	{ "AURORA SWEETS", "Glow-in-the-dark candy!", Color3.fromRGB(40, 140, 150) },
	{ "ECHO RECORDS", "Vinyl that whispers back", Color3.fromRGB(150, 60, 70) },
	{ "COMET KICKS", "Run faster. Trust us.", Color3.fromRGB(200, 120, 40) },
	{ "PRISM OPTICS", "See what's really there", Color3.fromRGB(50, 120, 190) },
	{ "NIGHT SHIFT MALL", "Open late. Very late.", Color3.fromRGB(110, 40, 150) },
}

local function pilasterGaps(): { { number } }
	local fronts = {}
	for _, x in Layout.Shop.CentersX do
		table.insert(fronts, { x - Layout.Shop.Width / 2, x + Layout.Shop.Width / 2 })
	end
	local gaps = { { C.StartX, fronts[1][1] } }
	for i = 1, #fronts - 1 do
		table.insert(gaps, { fronts[i][2], fronts[i + 1][1] })
	end
	table.insert(gaps, { fronts[#fronts][2], C.EndX })
	return gaps
end

local function floorDetail(parent: Instance)
	local floor = parent:FindFirstChild("CorridorFloor", true)
	if floor then
		Builder.tag(floor, "ReflectiveFloor")
	end
	local length = C.EndX - C.StartX
	local midX = (C.StartX + C.EndX) / 2
	Builder.decor({
		Parent = parent,
		Size = Vector3.new(length, 0.03, 9),
		CFrame = CFrame.new(midX, 0.03, 0),
		Color = Palette.MarbleDark,
		Material = Enum.Material.Marble,
	})
	for _, z in { -4.6, 4.6 } do
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(length, 0.04, 0.25),
			CFrame = CFrame.new(midX, 0.035, z),
			Color = Palette.Gold,
			Material = Enum.Material.Metal,
		})
	end
end

local function ceilingDetail(parent: Instance)
	local length = C.EndX - C.StartX
	local midX = (C.StartX + C.EndX) / 2
	for x = C.StartX + 8, C.EndX - 4, 16 do
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(1.4, 1.2, C.HalfWidth * 2),
			CFrame = CFrame.new(x, C.Height - 0.6, 0),
			Color = Palette.Wall,
			CastShadow = true,
		})
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(1.45, 0.14, C.HalfWidth * 2),
			CFrame = CFrame.new(x, C.Height - 1.22, 0),
			Color = Palette.Gold,
			Material = Enum.Material.Metal,
		})
	end
	-- warm cove troughs along both sides of the skylight
	for _, z in { -11.5, 11.5 } do
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(length, 0.15, 0.5),
			CFrame = CFrame.new(midX, C.Height - 0.08, z),
			Color = Palette.WarmLight,
			Material = Enum.Material.Neon,
			Tags = { "DayNeon" },
		})
	end
end

local function signage(parent: Instance)
	local beamBottom = C.Height - 1.2
	Props.hangingSign(
		CFrame.lookAt(Vector3.new(C.StartX + 24, 19.4, 0), Vector3.new(C.StartX, 19.4, 0)), -- hangs from the x=94 soffit
		12,
		2.6,
		"★ EAST WING SHOPS ★",
		Palette.NeonPink,
		beamBottom,
		parent
	)
	Props.hangingSign(
		CFrame.lookAt(Vector3.new(C.EndX - 24, 19.4, 0), Vector3.new(C.StartX, 19.4, 0)), -- hangs from the x=158 soffit
		12,
		2.6,
		"FOOD COURT  ›  SOON",
		Palette.NeonCyan,
		beamBottom,
		parent
	)

	local index = 0
	for _, gap in pilasterGaps() do
		local width = math.min(gap[2] - gap[1] - 1, 5)
		local x = (gap[1] + gap[2]) / 2
		for _, sign in { -1, 1 } do
			index += 1
			local ad = ADS[(index - 1) % #ADS + 1]
			local face = Vector3.new(x, 4.3, sign * (C.HalfWidth - 1.15))
			Props.lightbox(CFrame.lookAt(face, face - Vector3.new(0, 0, sign)), width, 4.2, ad[1], ad[2], ad[3], parent)
			Props.uplight(
				Vector3.new(x, 0, sign * (C.HalfWidth - 2.4)),
				if index % 2 == 0 then Palette.NeonPurple else Palette.NeonCyan,
				parent,
				2.5
			)
		end
	end
end

local function flowerBeds(parent: Instance)
	local colors =
		{ Palette.NeonPink, Color3.fromRGB(255, 236, 120), Color3.fromRGB(255, 255, 255), Palette.NeonPurple }
	local rng = Random.new(77)
	local centers = Layout.Shop.CentersX
	for i = 1, #centers - 1 do
		local x = (centers[i] + centers[i + 1]) / 2
		for k = 0, 9 do
			local angle = k / 10 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
			local r = rng:NextNumber(1.2, 2.1)
			Builder.decor({
				Parent = parent,
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * rng:NextNumber(0.45, 0.7),
				CFrame = CFrame.new(x + math.cos(angle) * r, 2.75, math.sin(angle) * r),
				Color = colors[k % #colors + 1],
				Material = Enum.Material.SmoothPlastic,
			})
		end
	end
end

local function atmosphere(parent: Instance)
	local midX = (C.StartX + C.EndX) / 2
	local sun = Lighting:GetSunDirection()
	if sun.Y > 0.2 then
		local anchor = Builder.decor({
			Name = "ShaftAnchor",
			Parent = parent,
			Size = Vector3.one,
			CFrame = CFrame.new(midX, 1, 0),
			Transparency = 1,
		})
		local reach = (C.Height + 0.6) / sun.Y
		for x = C.StartX + 18, C.EndX - 14, 26 do
			for _, z in { -3, 3 } do
				local floor = Vector3.new(x, 0, z) - Vector3.new(sun.X, 0, sun.Z) * reach
				-- the ray must pass through the skylight strip (|z| < 8) to be physically plausible
				local through = floor + sun * reach
				if
					math.abs(through.Z) < 7
					and floor.X > C.StartX + 4
					and floor.X < C.EndX - 4
					and math.abs(floor.Z) < C.HalfWidth - 3
				then
					Props.sunShaft(anchor, floor, sun, reach + 20, 5)
				end
			end
		end
	end
	Props.ambientVolume(CFrame.new(midX, 10, 0), Vector3.new(C.EndX - C.StartX, 18, C.HalfWidth * 2 - 4), 10, parent)
end

function CorridorDetail.build(parent: Instance)
	local model = Builder.model("CorridorDetail", parent)
	floorDetail(parent)
	ceilingDetail(model)
	signage(model)
	flowerBeds(model)
	atmosphere(model)
	return model
end

return CorridorDetail
