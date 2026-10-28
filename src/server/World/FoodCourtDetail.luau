-- Food court furnishing: six restaurants (storefront, sign, shutter, menu, appliances), the
-- dining hall (seating, centrepiece, lights), the grand kitchen's cooking lines, the walk-in
-- freezer, storage shelving, the loading dock and its truck, ventilation fans.
--
-- Level hooks (found with CollectionService, never by path):
--   FCRestaurant (Model)  attributes Index, RestaurantName; children Shutter, Sign, SignSwitch
--   FCAppliance  (Model)  attributes Kind, Restaurant (0 = grand kitchen); PrimaryPart Body
--   VentFan      (Model)  attribute FanIndex; child Blades (clients spin it while Spinning)
--   FoodCourtSpawn (Part) enemy spawn points for Chapter 2 nights
-- Everything decorative is CanCollide/CanQuery false (Builder.decor) to keep physics cheap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Builder = require(script.Parent.Builder)
local Layout = require(script.Parent.Layout)
local Props = require(script.Parent.Props)

local FoodCourtDetail = {}

local F = Layout.FoodCourt
local rgb = Color3.fromRGB
local FONT_TITLE = Font.new("rbxasset://fonts/families/Creepster.json")
local FONT_HEADING = Font.new("rbxasset://fonts/families/FredokaOne.json")
local STEEL = rgb(172, 178, 186)

FoodCourtDetail.Restaurants = {
	{ Name = "Moonlight Burgers", Accent = Palette.NeonGold, Menu = "SMASH BURGER · FRIES · SHAKES" },
	{ Name = "Lucky Wok", Accent = Palette.NeonRed, Menu = "NOODLES · DUMPLINGS · BAO" },
	{ Name = "Frost Bite Creamery", Accent = Palette.NeonCyan, Menu = "SOFT SERVE · SUNDAES · FLOATS" },
	{ Name = "Taco Eclipse", Accent = Palette.NeonGreen, Menu = "TACOS · NACHOS · CHURROS" },
	{ Name = "Slice of Night", Accent = Palette.NeonPink, Menu = "PIZZA BY THE SLICE · KNOTS" },
	{ Name = "Midnight Donuts", Accent = Palette.NeonPurple, Menu = "GLAZED · FILLED · COFFEE" },
}

-- ── small builders ──────────────────────────────────────────────────────────

local function box(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	solid: boolean?
)
	local props = {
		Parent = parent,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}
	return if solid then Builder.part(props) else Builder.decor(props)
end

local function neon(parent: Instance, size: Vector3, cf: CFrame, color: Color3, night: boolean?)
	return Builder.decor({
		Parent = parent,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = Enum.Material.Neon,
		Tags = if night then { "NightNeon" } else nil,
	})
end

-- An appliance the Level 8 night can possess. cf: floor centre, LookVector = its front.
local function appliance(parent: Instance, kind: string, cf: CFrame, restaurant: number): Model
	local model = Builder.model(kind, parent)
	local body: BasePart
	if kind == "Grill" then
		body = box(model, Vector3.new(5, 3.4, 3), cf * CFrame.new(0, 1.7, 0), STEEL, Enum.Material.Metal, true)
		box(model, Vector3.new(4.6, 0.2, 2.6), cf * CFrame.new(0, 3.5, 0), rgb(30, 28, 30), Enum.Material.DiamondPlate)
		neon(model, Vector3.new(4, 0.1, 0.2), cf * CFrame.new(0, 3.42, -0.6), rgb(255, 90, 40))
		neon(model, Vector3.new(4, 0.1, 0.2), cf * CFrame.new(0, 3.42, 0.6), rgb(255, 90, 40))
	elseif kind == "Fryer" then
		body = box(model, Vector3.new(3.2, 3.4, 3), cf * CFrame.new(0, 1.7, 0), STEEL, Enum.Material.Metal, true)
		box(model, Vector3.new(2.6, 0.1, 2.2), cf * CFrame.new(0, 3.3, 0), rgb(214, 160, 40), Enum.Material.Glass)
		for _, x in { -0.7, 0.7 } do
			box(
				model,
				Vector3.new(1.1, 0.8, 1.6),
				cf * CFrame.new(x, 3.6, 0),
				rgb(60, 60, 64),
				Enum.Material.DiamondPlate
			)
			box(model, Vector3.new(0.15, 0.15, 1.6), cf * CFrame.new(x, 4.1, -1.4), rgb(20, 20, 20))
		end
	elseif kind == "Fridge" then
		body = box(
			model,
			Vector3.new(3.6, 7, 3),
			cf * CFrame.new(0, 3.5, 0),
			rgb(214, 220, 226),
			Enum.Material.Metal,
			true
		)
		box(model, Vector3.new(0.2, 2.4, 0.2), cf * CFrame.new(1.3, 4.2, -1.6), rgb(60, 60, 64), Enum.Material.Metal)
		neon(model, Vector3.new(1, 0.4, 0.05), cf * CFrame.new(-0.8, 6.2, -1.52), Palette.NeonCyan)
	elseif kind == "Oven" then
		body = box(model, Vector3.new(5, 4, 4), cf * CFrame.new(0, 2, 0), rgb(150, 70, 52), Enum.Material.Brick, true)
		local dome = box(model, Vector3.new(5, 3, 4), cf * CFrame.new(0, 4.5, 0), rgb(150, 70, 52), Enum.Material.Brick)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = dome
		neon(model, Vector3.new(2.4, 1.4, 0.1), cf * CFrame.new(0, 2.6, -2.02), rgb(255, 120, 40))
	else -- Mixer: a big stand mixer on a steel table
		body = box(model, Vector3.new(4, 3, 3), cf * CFrame.new(0, 1.5, 0), STEEL, Enum.Material.Metal, true)
		box(
			model,
			Vector3.new(1.2, 2.6, 1.2),
			cf * CFrame.new(0.8, 4.3, 0.4),
			rgb(230, 230, 236),
			Enum.Material.SmoothPlastic
		)
		box(
			model,
			Vector3.new(2.2, 0.9, 1.2),
			cf * CFrame.new(0, 5.4, 0.2),
			rgb(230, 230, 236),
			Enum.Material.SmoothPlastic
		)
		box(model, Vector3.new(1.6, 1.2, 1.6), cf * CFrame.new(-0.4, 3.6, 0), rgb(200, 204, 210), Enum.Material.Metal)
	end
	body.Name = "Body"
	model.PrimaryPart = body
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Restaurant", restaurant)
	Builder.tag(model, "FCAppliance")
	return model
end

local function spawnPoint(parent: Instance, position: Vector3)
	Builder.part({
		Name = "FoodCourtSpawn",
		Parent = parent,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(position + Vector3.new(0, 3, 0)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Tags = { "FoodCourtSpawn" },
	})
end

-- ── restaurants ─────────────────────────────────────────────────────────────

local KITCHEN_KINDS = {
	{ "Grill", "Fryer", "Fridge" },
	{ "Grill", "Mixer", "Fridge" },
	{ "Fridge", "Mixer", "Fridge" },
	{ "Grill", "Fryer", "Fridge" },
	{ "Oven", "Mixer", "Fridge" },
	{ "Fryer", "Mixer", "Fridge" },
}

local function restaurant(parent: Instance, index: number, frontCenter: Vector3, inward: Vector3)
	local info = FoodCourtDetail.Restaurants[index]
	local accent = info.Accent
	local model = Builder.model("Restaurant" .. index, parent)
	model:SetAttribute("Index", index)
	model:SetAttribute("RestaurantName", info.Name)
	Builder.tag(model, "FCRestaurant")
	-- local frame: +depth = into the restaurant, x = across the front
	local frame = CFrame.lookAt(frontCenter, frontCenter + inward)
	local function at(x: number, y: number, depth: number): CFrame
		return frame * CFrame.new(x, y, -depth)
	end
	local depth = F.RowDepth

	-- counter with a glowing kick strip, register and menu stand
	box(model, Vector3.new(15, 3.6, 2.4), at(-2.5, 1.8, 4.5), rgb(46, 36, 60), Enum.Material.Wood, true)
	box(model, Vector3.new(15.4, 0.3, 2.8), at(-2.5, 3.75, 4.5), rgb(236, 232, 226), Enum.Material.Marble)
	neon(model, Vector3.new(15, 0.25, 0.1), at(-2.5, 0.5, 3.25), accent, true)
	box(model, Vector3.new(1.6, 1.2, 1.2), at(-7, 4.5, 4.6), rgb(30, 30, 36), Enum.Material.Metal)
	-- prep island
	box(model, Vector3.new(8, 3.4, 3), at(-3, 1.7, 15), STEEL, Enum.Material.Metal, true)
	box(model, Vector3.new(1.6, 0.6, 1), at(-5, 3.7, 15), rgb(220, 120, 80), Enum.Material.SmoothPlastic)
	box(model, Vector3.new(2, 0.2, 1.4), at(-1, 3.5, 15), rgb(150, 110, 70), Enum.Material.Wood)
	-- appliances along the back wall (facing the counter)
	for i, kind in KITCHEN_KINDS[index] do
		local x = -9 + (i - 1) * 6
		appliance(model, kind, at(x, 0, depth - 3) * CFrame.Angles(0, math.pi, 0), index)
	end
	-- menu board over the appliances
	Props.lightbox(
		at(0, 11.5, depth - 0.9) * CFrame.Angles(0, math.pi, 0),
		16,
		4,
		info.Name,
		info.Menu,
		accent:Lerp(rgb(20, 14, 30), 0.55),
		model
	)
	-- warm interior light
	local lampPart = neon(model, Vector3.new(12, 0.2, 0.6), at(0, F.RestaurantHeight - 0.4, 12), Palette.WarmLight)
	Builder.tag(lampPart, "DayNeon")
	Builder.light("PointLight", lampPart, { Color = Palette.WarmLight, Range = 20, Brightness = 1.1 }, { "DayLight" })
	local night = neon(model, Vector3.new(0.6, 0.6, 0.6), at(0, F.RestaurantHeight - 1, 20), accent)
	local nightLight = Builder.light(
		"PointLight",
		night,
		{ Color = accent, Range = 22, Brightness = 0 },
		{ "NightLight" }
	)
	nightLight:SetAttribute("NightBrightness", 1.4)

	-- sign over the storefront (faces the hall) and the roll-up shutter (open by default;
	-- Level 8's day closes them and players reopen the restaurants)
	local signCF = at(0, 16.4, -1.5) * CFrame.Angles(0, math.pi, 0)
	local sign = box(model, Vector3.new(24, 3.4, 0.5), signCF, rgb(16, 10, 26), Enum.Material.SmoothPlastic)
	sign.Name = "Sign"
	Builder.label(sign, Enum.NormalId.Front, info.Name, {
		Color = rgb(255, 250, 240),
		Font = FONT_TITLE,
		Stroke = accent,
		StrokeThickness = 2.5,
		Brightness = 2.2,
	})
	for _, y in { -1.85, 1.85 } do
		local strip = neon(model, Vector3.new(24.4, 0.2, 0.3), signCF * CFrame.new(0, y, -0.2), accent, true)
		strip.Name = "SignStrip"
	end
	local shutter = Builder.part({
		Name = "Shutter",
		Parent = model,
		Size = Vector3.new(22, 1.2, 1.2),
		CFrame = at(0, 13.4, 0.4),
		Color = rgb(120, 124, 132),
		Material = Enum.Material.CorrodedMetal,
		CanCollide = false,
		CanQuery = false,
	})
	shutter:SetAttribute("OpenCFrame", shutter.CFrame)
	shutter:SetAttribute("ClosedCFrame", at(0, 7, 0.4))
	-- the switch box on the pillar beside the storefront (Level 8 day reopening)
	local switch = box(
		model,
		Vector3.new(1.4, 2, 0.6),
		at(12.5, 4.5, -1.3) * CFrame.Angles(0, math.pi, 0),
		rgb(240, 196, 40),
		Enum.Material.Metal,
		true
	)
	switch.Name = "SignSwitch"
	spawnPoint(model, at(3, 0, depth - 7).Position)
	return model
end

-- ── dining hall ─────────────────────────────────────────────────────────────

local function tableSet(parent: Instance, center: Vector3, accent: Color3, rng: Random)
	local model = Builder.model("TableSet", parent)
	Builder.cylinder(
		center + Vector3.new(0, 1.6, 0),
		0.25,
		3.2,
		{ Parent = model, Color = Palette.DarkMetal, Material = Enum.Material.Metal }
	)
	Builder.cylinder(
		center + Vector3.new(0, 3.25, 0),
		2.6,
		0.3,
		{ Parent = model, Color = rgb(236, 230, 220), Material = Enum.Material.Marble }
	)
	Builder.cylinder(center + Vector3.new(0, 3.08, 0), 2.7, 0.08, {
		Parent = model,
		Color = accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Tags = { "NightNeon" },
	})
	for i = 0, 3 do
		local angle = i * math.pi / 2 + rng:NextNumber(-0.2, 0.2)
		local p = center + Vector3.new(math.cos(angle) * 3.8, 0, math.sin(angle) * 3.8)
		Builder.cylinder(
			p + Vector3.new(0, 1.1, 0),
			0.15,
			2.2,
			{ Parent = model, Color = Palette.DarkMetal, Material = Enum.Material.Metal }
		)
		Builder.cylinder(
			p + Vector3.new(0, 2.3, 0),
			1,
			0.35,
			{ Parent = model, Color = accent:Lerp(rgb(40, 30, 50), 0.35), Material = Enum.Material.Leather }
		)
	end
end

local function booth(parent: Instance, cf: CFrame, accent: Color3)
	local model = Builder.model("Booth", parent)
	box(
		model,
		Vector3.new(7, 1.6, 2.4),
		cf * CFrame.new(0, 0.8, 0),
		accent:Lerp(rgb(30, 20, 40), 0.4),
		Enum.Material.Leather,
		true
	)
	box(
		model,
		Vector3.new(7, 3.4, 0.8),
		cf * CFrame.new(0, 2.3, 1.4),
		accent:Lerp(rgb(30, 20, 40), 0.4),
		Enum.Material.Leather,
		true
	)
	box(model, Vector3.new(5, 0.3, 2.6), cf * CFrame.new(0, 2.9, -2.4), rgb(236, 230, 220), Enum.Material.Marble, true)
	box(model, Vector3.new(0.4, 2.8, 0.4), cf * CFrame.new(0, 1.4, -2.4), Palette.DarkMetal, Enum.Material.Metal)
	neon(model, Vector3.new(7, 0.15, 0.1), cf * CFrame.new(0, 4.05, 1.8), accent, true)
end

local function buildHall(parent: Instance, rng: Random)
	local H = F.Hall
	local model = Builder.model("DiningHall", parent)
	-- terrazzo bands and a neon logo inlay in the middle of the floor
	for _, z in { -30, 30 } do
		box(
			model,
			Vector3.new(H.MaxX - H.MinX - 4, 0.04, 1.2),
			CFrame.new((H.MinX + H.MaxX) / 2, 0.02, z),
			rgb(46, 36, 60),
			Enum.Material.Marble
		)
	end
	local center = Vector3.new(-141, 0, 0)
	Builder.cylinder(center + Vector3.new(0, 0.02, 0), 12, 0.04, {
		Parent = model,
		Color = rgb(40, 30, 56),
		Material = Enum.Material.Marble,
		CanCollide = false,
		CanQuery = false,
	})
	Builder.cylinder(center + Vector3.new(0, 0.04, 0), 11.4, 0.04, {
		Parent = model,
		Color = Palette.NeonPink,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Tags = { "NightNeon" },
	})
	Builder.cylinder(center + Vector3.new(0, 0.06, 0), 10.8, 0.04, {
		Parent = model,
		Color = rgb(232, 220, 196),
		Material = Enum.Material.CeramicTiles,
		CanCollide = false,
		CanQuery = false,
	})

	-- seating: four clusters of tables and the booths along the side walls
	local accents = { Palette.NeonPink, Palette.NeonCyan, Palette.NeonGold, Palette.NeonPurple, Palette.NeonGreen }
	local i = 0
	for _, x in { -112, -128, -154, -170 } do
		for _, z in { -24, -10, 10, 24 } do
			if math.abs(z) > 12 or (x ~= -128 and x ~= -154) then
				i += 1
				tableSet(
					model,
					Vector3.new(x + rng:NextNumber(-1, 1), 0, z + rng:NextNumber(-1, 1)),
					accents[i % #accents + 1],
					rng
				)
			end
		end
	end
	for k, z in { -40, -30, -20, 20, 30, 40 } do
		booth(model, CFrame.lookAt(Vector3.new(-101.5, 0, z), Vector3.new(-110, 0, z)), accents[k % #accents + 1])
	end

	-- centrepiece: a neon halo chandelier with the food court's name
	local haloY = 21
	local count = 20
	for k = 0, count - 1 do
		local a0, a1 = k / count * math.pi * 2, (k + 1) / count * math.pi * 2
		local p0 = center + Vector3.new(math.cos(a0) * 9, haloY, math.sin(a0) * 9)
		local p1 = center + Vector3.new(math.cos(a1) * 9, haloY, math.sin(a1) * 9)
		Builder.beam(p0, p1, 0.5, {
			Parent = model,
			Color = if k % 2 == 0 then Palette.NeonPink else Palette.NeonCyan,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Tags = { "NightNeon" },
		})
	end
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local p = center + Vector3.new(math.cos(a) * 9, haloY, math.sin(a) * 9)
		Builder.beam(
			p,
			Vector3.new(p.X, H.Height, p.Z),
			0.12,
			{ Parent = model, Color = Palette.DarkMetal, CanCollide = false, CanQuery = false }
		)
	end
	Props.hangingSign(
		CFrame.new(center + Vector3.new(0, haloY - 3, 0)),
		14,
		3.6,
		"NIGHT BITES",
		Palette.NeonPink,
		haloY,
		model
	)
	Props.hangingSign(
		CFrame.new(center + Vector3.new(0, haloY - 3, 0)) * CFrame.Angles(0, math.pi / 2, 0),
		14,
		3.6,
		"FOOD COURT",
		Palette.NeonCyan,
		haloY,
		model
	)
	local haloLight =
		neon(model, Vector3.one * 0.5, CFrame.new(center + Vector3.new(0, haloY - 3, 0)), Palette.NeonPink)
	local glow = Builder.light(
		"PointLight",
		haloLight,
		{ Color = Palette.NeonPink, Range = 30, Brightness = 0 },
		{ "NightLight" }
	)
	glow:SetAttribute("NightBrightness", 1.6)

	-- pendant lamps over the tables (day), coloured uplights on the walls (night)
	for _, x in { -112, -128, -154, -170 } do
		for _, z in { -24, 24 } do
			Props.pendantLamp(Vector3.new(x, 14, z), H.Height, model)
		end
	end
	for k, x in { -100.5, -127, -155, -181.5 } do
		Props.uplight(Vector3.new(x, 0, 46.6), accents[k], model, 2.4)
		Props.uplight(Vector3.new(x, 0, -46.6), accents[k + 1], model, 2.4)
	end
	-- planters by the kitchen doors and promenade
	for _, p in
		{ Vector3.new(-178, 0, -14), Vector3.new(-178, 0, 14), Vector3.new(-104, 0, -16), Vector3.new(-104, 0, 16) }
	do
		Props.pottedPlant(p, model, rng)
	end
	Props.ambientVolume(CFrame.new(-141, 12, 0), Vector3.new(80, 20, 90), 6, model)
	-- spilled trays and knocked chairs: the court was left in a hurry
	for _ = 1, 10 do
		local p = Vector3.new(rng:NextNumber(-178, -104), 0.1, rng:NextNumber(-36, 36))
		box(
			model,
			Vector3.new(1.6, 0.12, 1.1),
			CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			Palette.ShopAccents[rng:NextInteger(1, 6)],
			Enum.Material.SmoothPlastic
		)
	end
end

-- ── grand kitchen, freezer, storage, dock ───────────────────────────────────

local function cookingLine(parent: Instance, z: number, facing: number)
	local K = F.Kitchen
	local model = Builder.model("CookingLine", parent)
	local x0, x1 = K.MinX + 12, K.MaxX - 14
	box(model, Vector3.new(x1 - x0, 3.4, 4), CFrame.new((x0 + x1) / 2, 1.7, z), STEEL, Enum.Material.Metal, true)
	for x = x0 + 3, x1 - 3, 6 do
		Builder.cylinder(Vector3.new(x, 3.45, z), 0.9, 0.1, {
			Parent = model,
			Color = rgb(30, 30, 34),
			Material = Enum.Material.DiamondPlate,
			CanCollide = false,
			CanQuery = false,
		})
		Builder.cylinder(Vector3.new(x, 3.5, z), 0.6, 0.05, {
			Parent = model,
			Color = rgb(255, 110, 50),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			Tags = { "NightNeon" },
		})
	end
	-- extraction hood
	box(
		model,
		Vector3.new(x1 - x0 + 2, 1.2, 6),
		CFrame.new((x0 + x1) / 2, 12, z),
		rgb(150, 156, 164),
		Enum.Material.Metal
	)
	box(
		model,
		Vector3.new(x1 - x0 + 2, 3, 0.4),
		CFrame.new((x0 + x1) / 2, 10, z + facing * 3),
		rgb(150, 156, 164),
		Enum.Material.Metal
	)
	for x = x0 + 4, x1 - 4, 10 do
		local bulb = neon(model, Vector3.new(1.4, 0.2, 1.4), CFrame.new(x, 11.3, z), Palette.WarmLight)
		Builder.tag(bulb, "DayNeon")
		Builder.light(
			"SpotLight",
			bulb,
			{ Face = Enum.NormalId.Bottom, Angle = 90, Range = 16, Brightness = 1.3, Color = Palette.WarmLight },
			{ "DayLight" }
		)
	end
end

local function shelf(parent: Instance, cf: CFrame, length: number, rng: Random, palette: { Color3 })
	local model = Builder.model("Shelf", parent)
	for _, x in { -length / 2, length / 2 } do
		box(model, Vector3.new(0.3, 8, 0.3), cf * CFrame.new(x, 4, 0), Palette.DarkMetal, Enum.Material.Metal, true)
	end
	for y = 1, 7, 2 do
		box(model, Vector3.new(length, 0.2, 2.4), cf * CFrame.new(0, y, 0), STEEL, Enum.Material.Metal, true)
		local x = -length / 2 + 0.8
		while x < length / 2 - 0.8 do
			local w = rng:NextNumber(0.8, 1.8)
			local h = rng:NextNumber(0.6, 1.6)
			box(
				model,
				Vector3.new(w, h, rng:NextNumber(1.2, 2)),
				cf * CFrame.new(x + w / 2, y + 0.1 + h / 2, 0),
				palette[rng:NextInteger(1, #palette)],
				Enum.Material.Cardboard
			)
			x += w + rng:NextNumber(0.15, 0.6)
		end
	end
end

local function buildKitchen(parent: Instance, rng: Random)
	local K = F.Kitchen
	local model = Builder.model("GrandKitchen", parent)
	cookingLine(model, 31, 1)
	cookingLine(model, -31, -1)
	-- appliances on the end walls and prep stations
	local kinds = { "Oven", "Mixer", "Fryer", "Grill" }
	for i, z in { -24, -14, 14, 24 } do
		appliance(model, kinds[i], CFrame.lookAt(Vector3.new(K.MinX + 3, 0, z), Vector3.new(K.MaxX, 0, z)), 0)
	end
	for _, z in { -44, 44 } do
		shelf(
			model,
			CFrame.lookAt(Vector3.new(-238, 0, z), Vector3.new(-238, 0, 0)),
			16,
			rng,
			{ rgb(200, 190, 170), rgb(150, 110, 70), rgb(220, 70, 60) }
		)
	end
	-- red quarry tile border and drain grates
	for _, z in { -4, 4 } do
		box(
			model,
			Vector3.new(4, 0.05, 1.2),
			CFrame.new(-217, 0.03, z * 6),
			rgb(40, 40, 44),
			Enum.Material.DiamondPlate
		)
	end
	-- the double doors into the hall
	Props.hangingSign(
		CFrame.lookAt(Vector3.new(-181.5, 16.5, 0), Vector3.new(-170, 16.5, 0)),
		12,
		2.4,
		"KITCHEN · STAFF ONLY",
		Palette.NeonRed,
		F.Hall.Height,
		model
	)
	for _, z in { -22, 22 } do
		local light = neon(model, Vector3.one * 0.6, CFrame.new(-217, 22, z), rgb(255, 120, 60))
		local l = Builder.light(
			"PointLight",
			light,
			{ Color = rgb(255, 120, 60), Range = 30, Brightness = 0 },
			{ "NightLight" }
		)
		l:SetAttribute("NightBrightness", 1.2)
	end
	for _, p in { Vector3.new(-236, 0, 12), Vector3.new(-200, 0, -12), Vector3.new(-226, 0, 40) } do
		spawnPoint(model, p)
	end
end

local function buildFreezer(parent: Instance, rng: Random)
	local fr, hf = F.Freezer, F.HiddenFreezer
	local model = Builder.model("WalkInFreezer", parent)
	local frost = { rgb(220, 236, 246), rgb(180, 210, 232), rgb(240, 246, 250) }
	for k, x in { -240, -226, -200 } do
		shelf(
			model,
			CFrame.lookAt(Vector3.new(x, 0, 72), Vector3.new(x, 0, 60)) * CFrame.Angles(0, k * 0.01, 0),
			9,
			rng,
			frost
		)
	end
	-- hanging carcasses (pale, swaying shapes) and plastic strip curtain at the door
	for k = 0, 5 do
		local p = Vector3.new(-246 + k * 7, 0, 86 - (k % 2) * 3)
		Builder.beam(
			Vector3.new(p.X, fr.Height, p.Z),
			Vector3.new(p.X, 10, p.Z),
			0.15,
			{ Parent = model, Color = Palette.Chrome, CanCollide = false, CanQuery = false }
		)
		local meat = box(
			model,
			Vector3.new(1.8, 4, 1.2),
			CFrame.new(p.X, 7.8, p.Z) * CFrame.Angles(0, k, 0.1),
			rgb(196, 120, 130),
			Enum.Material.SmoothPlastic
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = meat
	end
	for x = -223.5, -212.5, 1.2 do
		box(model, Vector3.new(1, 9.6, 0.08), CFrame.new(x, 5.2, 48.6), rgb(210, 230, 240), Enum.Material.Glass).Transparency =
			0.55
	end
	-- cold blue light and drifting frost
	for _, p in { Vector3.new(-230, 0, 70), Vector3.new(-200, 0, 70), Vector3.new(-269, 0, 70) } do
		local lamp = neon(
			model,
			Vector3.new(4, 0.2, 0.8),
			CFrame.new(p.X, (if p.X < -250 then hf.Height else fr.Height) - 0.3, p.Z),
			Palette.CoolLight
		)
		Builder.light("PointLight", lamp, { Color = rgb(150, 200, 255), Range = 24, Brightness = 1 })
	end
	local fog = Builder.decor({
		Parent = model,
		Size = Vector3.new(60, 2, 40),
		CFrame = CFrame.new(-217, 1, 70),
		Transparency = 1,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Color = ColorSequence.new(rgb(220, 240, 255))
	emitter.Transparency = NumberSequence.new(0.8, 1)
	emitter.Size = NumberSequence.new(4, 7)
	emitter.Lifetime = NumberRange.new(4, 6)
	emitter.Rate = 3
	emitter.Speed = NumberRange.new(0.2, 0.6)
	emitter.Parent = fog
	-- the hidden freezer: icicles and frozen chains (Level 11 adds what's frozen in here)
	for k = 0, 7 do
		local p =
			Vector3.new(rng:NextNumber(hf.MinX + 3, hf.MaxX - 3), hf.Height, rng:NextNumber(hf.MinZ + 3, hf.MaxZ - 3))
		box(
			model,
			Vector3.new(0.6, 2 + k % 3, 0.6),
			CFrame.new(p - Vector3.new(0, 1 + (k % 3) / 2, 0)),
			rgb(200, 230, 250),
			Enum.Material.Glass
		).Transparency =
			0.3
	end
	spawnPoint(model, Vector3.new(-206, 0, 80))
end

local function buildStorage(parent: Instance, rng: Random)
	local st = F.Storage
	local model = Builder.model("Storage", parent)
	local goods = { rgb(196, 160, 110), rgb(150, 110, 70), rgb(214, 190, 150), rgb(120, 140, 90) }
	for _, spot in { Vector2.new(-246, -88), Vector2.new(-204, -72), Vector2.new(-192, -72) } do
		shelf(model, CFrame.lookAt(Vector3.new(spot.X, 0, spot.Y), Vector3.new(spot.X + 1, 0, spot.Y)), 14, rng, goods)
	end
	for k = 0, 5 do
		box(
			model,
			Vector3.new(3, 2.6, 3),
			CFrame.new(-214 + (k % 3) * 3.4, 1.3 + (k // 3) * 2.6, -92),
			goods[k % 4 + 1],
			Enum.Material.Cardboard,
			true
		)
	end
	local sign = box(
		model,
		Vector3.new(8, 1.4, 0.3),
		CFrame.lookAt(Vector3.new(-226, 6, -95), Vector3.new(-226, 6, -80)),
		rgb(20, 18, 24)
	)
	Builder.label(sign, Enum.NormalId.Front, "⬇ BASEMENT", { Color = Palette.NeonGold, Font = FONT_HEADING })
	local lamp = neon(model, Vector3.new(6, 0.2, 0.8), CFrame.new(-217, st.Height - 0.3, -72), Palette.WarmLight)
	Builder.light("PointLight", lamp, { Color = Palette.WarmLight, Range = 26, Brightness = 0.9 })
	spawnPoint(model, Vector3.new(-196, 0, -88))
end

local function buildDock(parent: Instance)
	local d = F.Dock
	local model = Builder.model("LoadingDock", parent)
	-- the delivery truck (box body, cab, wheels)
	local truck = Builder.model("DeliveryTruck", model)
	local base = CFrame.new(-142, 0, -114) * CFrame.Angles(0, math.pi, 0) -- cab faces the corridor
	box(truck, Vector3.new(9, 9, 18), base * CFrame.new(0, 6, 0), rgb(232, 232, 236), Enum.Material.SmoothPlastic, true)
	box(truck, Vector3.new(8.6, 6.4, 6), base * CFrame.new(0, 4.6, -12), rgb(70, 50, 120), Enum.Material.Metal, true)
	box(truck, Vector3.new(8, 2.6, 0.2), base * CFrame.new(0, 6.4, -15.05), rgb(40, 60, 80), Enum.Material.Glass)
	local logo = box(truck, Vector3.new(0.1, 4, 10), base * CFrame.new(4.55, 6.6, 0), rgb(232, 232, 236))
	Builder.label(
		logo,
		Enum.NormalId.Right,
		"NIGHT BITES\nSUPPLY CO.",
		{ Color = rgb(90, 60, 150), Font = FONT_HEADING, Lit = true }
	)
	for _, z in { -12, -3, 5 } do
		for _, x in { -4.4, 4.4 } do
			Builder.part({
				Parent = truck,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.2, 3, 3),
				CFrame = base * CFrame.new(x, 1.5, z),
				Color = rgb(24, 24, 26),
				Material = Enum.Material.Rubber,
			})
		end
	end
	-- pallets and a conveyor along the east wall
	for k = 0, 3 do
		local p = Vector3.new(-122 + (k % 2) * 7, 0, -102 - (k // 2) * 8)
		box(
			model,
			Vector3.new(5, 0.6, 5),
			CFrame.new(p + Vector3.new(0, 0.3, 0)),
			rgb(170, 130, 80),
			Enum.Material.WoodPlanks,
			true
		)
	end
	box(model, Vector3.new(4, 3, 30), CFrame.new(-102, 1.5, -110), Palette.DarkMetal, Enum.Material.Metal, true)
	box(model, Vector3.new(3.4, 0.1, 30), CFrame.new(-102, 3.05, -110), rgb(30, 30, 32), Enum.Material.Rubber)
	-- caution stripes at the roll-up door, sodium lamps
	for k = 0, 5 do
		neon(
			model,
			Vector3.new(1.4, 0.05, 2),
			CFrame.new(-136 + k * 2.8, 0.03, -126) * CFrame.Angles(0, 0.6, 0),
			if k % 2 == 0 then Palette.NeonGold else rgb(20, 20, 20)
		)
	end
	for _, x in { -150, -118 } do
		local lamp = neon(model, Vector3.new(1.2, 0.6, 1.2), CFrame.new(x, d.Height - 0.5, -110), rgb(255, 170, 80))
		Builder.light("PointLight", lamp, { Color = rgb(255, 170, 80), Range = 30, Brightness = 1.1 })
	end
	spawnPoint(model, Vector3.new(-152, 0, -100))
	spawnPoint(model, Vector3.new(-110, 0, -124))
end

local function buildCorridors(parent: Instance)
	local model = Builder.model("ServiceCorridors", parent)
	for _, z in { 90.4, -90.4 } do
		-- pipes along the ceiling, caution stripe at the floor edge
		for k, y in { 12.4, 11.4 } do
			Builder.beam(
				Vector3.new(-183, y, z - k * 0.8 * math.sign(z)),
				Vector3.new(-99, y, z - k * 0.8 * math.sign(z)),
				0.6,
				{
					Parent = model,
					Color = if k == 1 then rgb(150, 60, 50) else rgb(90, 110, 130),
					Material = Enum.Material.Metal,
					CanCollide = false,
					CanQuery = false,
				}
			)
		end
		for x = -176, -104, 18 do
			local lamp =
				neon(model, Vector3.new(3, 0.2, 0.6), CFrame.new(x, 13.6, z - 6 * math.sign(z)), rgb(220, 230, 255))
			Builder.light("PointLight", lamp, { Color = rgb(220, 230, 255), Range = 16, Brightness = 0.7 })
		end
	end
end

-- An atrium-side archway sign over the doorway into the food court.
local function buildEntranceSign(parent: Instance)
	local sign = Builder.decor({
		Parent = parent,
		Size = Vector3.new(0.6, 4, 22),
		CFrame = CFrame.new(-69.6, F.DoorHeight + 2.4, 0),
		Color = rgb(20, 14, 34),
	})
	Builder.label(
		sign,
		Enum.NormalId.Right,
		"🍔 FOOD COURT  ›",
		{ Color = Palette.NeonGold, Font = FONT_HEADING, Brightness = 2.2 }
	)
	neon(parent, Vector3.new(0.3, 0.3, 22.4), CFrame.new(-69.3, F.DoorHeight + 0.3, 0), Palette.NeonGold, true)
	neon(parent, Vector3.new(0.3, 0.3, 22.4), CFrame.new(-69.3, F.DoorHeight + 4.5, 0), Palette.NeonGold, true)
end

-- A ventilation fan unit inside a fan room (Level 13 repairs them).
function FoodCourtDetail.ventFan(room: Instance, center: Vector3, name: string, index: number)
	local model = Builder.model("VentFan", room)
	model:SetAttribute("FanIndex", index)
	model:SetAttribute("FanName", name)
	local cf = CFrame.new(center + Vector3.new(0, 6, 0))
	box(model, Vector3.new(9, 9, 2), cf * CFrame.new(0, 0, 0), rgb(70, 74, 82), Enum.Material.DiamondPlate, true)
	local hub = Builder.part({
		Name = "Blades",
		Parent = model,
		Size = Vector3.new(7.4, 1.2, 0.4),
		CFrame = cf * CFrame.new(0, 0, -1.2),
		Color = rgb(150, 156, 164),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CanQuery = false,
	})
	for _, angle in { math.pi / 3, -math.pi / 3 } do
		local blade = box(
			model,
			Vector3.new(7.4, 1.2, 0.4),
			hub.CFrame * CFrame.Angles(0, 0, angle),
			rgb(150, 156, 164),
			Enum.Material.Metal
		)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hub
		weld.Part1 = blade
		weld.Parent = blade
		blade.Anchored = false
	end
	local status = neon(model, Vector3.new(1, 1, 0.2), cf * CFrame.new(3.6, 3.6, -1.1), Palette.NeonRed)
	status.Name = "Status"
	local label = box(model, Vector3.new(6, 1.2, 0.2), cf * CFrame.new(0, 5.4, -1.1), rgb(20, 18, 24))
	Builder.label(
		label,
		Enum.NormalId.Front,
		"🌀 " .. string.upper(name),
		{ Color = Palette.NeonCyan, Font = FONT_HEADING }
	)
	Builder.tag(model, "VentFan")
	return model
end

function FoodCourtDetail.build(parent: Instance)
	local rng = Random.new(2024) -- fixed seed: identical furnishing on every server
	local H = F.Hall
	local row = Builder.model("Restaurants", parent)
	for i, cx in F.RestaurantCentersX do
		restaurant(row, i, Vector3.new(cx, 0, H.HalfZ), Vector3.new(0, 0, 1))
		restaurant(row, i + 3, Vector3.new(cx, 0, -H.HalfZ), Vector3.new(0, 0, -1))
	end
	buildHall(parent, rng)
	buildKitchen(parent, rng)
	buildFreezer(parent, rng)
	buildStorage(parent, rng)
	buildDock(parent)
	buildCorridors(parent)
	buildEntranceSign(parent)
end

return FoodCourtDetail
