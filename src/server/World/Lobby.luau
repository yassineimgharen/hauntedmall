-- The central atrium: two floors around a glass dome, fountain, palms, escalators,
-- decorative storefronts and the entrance plaza.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local AssetRegistry = require(script.Parent.AssetRegistry)
local Builder = require(script.Parent.Builder)
local Layout = require(script.Parent.Layout)
local LobbyDetail = require(script.Parent.LobbyDetail)
local Props = require(script.Parent.Props)

local Lobby = {}

local A = Layout.Atrium
local HALF = A.Half
local WALL = 2
local FONT_TITLE = Font.new("rbxasset://fonts/families/Creepster.json")
local FONT_HEADING = Font.new("rbxasset://fonts/families/FredokaOne.json")

local function ringPoint(radius: number, angle: number, y: number): Vector3
	return Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
end

-- Rectangular segments approximating an annulus between rInner and rOuter.
local function ring(
	parent: Instance,
	count: number,
	rInner: number,
	rOuter: number,
	yBottom: number,
	yTop: number,
	props: { [string]: any }
)
	local step = math.pi * 2 / count
	local width = 2 * rOuter * math.tan(step / 2) + 0.05
	local mid = (rInner + rOuter) / 2
	for i = 0, count - 1 do
		local angle = i * step
		local center = ringPoint(mid, angle, (yBottom + yTop) / 2)
		local segment = table.clone(props)
		segment.Parent = parent
		segment.Size = Vector3.new(width, yTop - yBottom, rOuter - rInner)
		segment.CFrame = CFrame.lookAt(center, Vector3.new(0, center.Y, 0))
		Builder.part(segment)
	end
end

local function buildFloor(parent: Instance)
	Builder.part({
		Name = "AtriumFloor",
		Parent = parent,
		Size = Vector3.new(HALF * 2, 1, HALF * 2),
		CFrame = CFrame.new(0, -0.5, 0),
		Color = Palette.MarbleLight,
		Material = Enum.Material.Marble,
		Reflectance = 0.06,
	})

	-- Inlaid compass rose around the fountain: stacked discs, each a hair higher.
	local discs = {
		{ 27, Palette.Gold, Enum.Material.Metal },
		{ 26.2, Palette.MarbleDark, Enum.Material.Marble },
		{ 18, Palette.MarbleWarm, Enum.Material.Marble },
		{ 17.4, Palette.MarbleLight, Enum.Material.Marble },
	}
	for i, disc in discs do
		Builder.cylinder(Vector3.new(0, 0.01 * i, 0), disc[1], 0.02, {
			Parent = parent,
			Color = disc[2],
			Material = disc[3],
			CanCollide = false,
			CastShadow = false,
		})
	end
	for i = 0, 7 do
		local angle = i * math.pi / 4
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(if i % 2 == 0 then 1.2 else 0.6, 0.02, 8.6),
			CFrame = CFrame.new(ringPoint(22.1, angle, 0.045)) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			Color = Palette.Gold,
			Material = Enum.Material.Metal,
		})
	end
end

local function buildWalls(parent: Instance)
	local h = A.Height + 2
	local wallProps = { Parent = parent, Color = Palette.Wall, Material = Enum.Material.SmoothPlastic }
	local function wall(size: Vector3, position: Vector3)
		local props = table.clone(wallProps)
		props.Size = size
		props.CFrame = CFrame.new(position)
		Builder.part(props)
	end

	local outer = HALF + WALL / 2
	local span = HALF * 2 + WALL * 2
	-- north: solid; west: the doorway into the food court (Chapter 2)
	wall(Vector3.new(span, h, WALL), Vector3.new(0, h / 2, outer))
	local f = Layout.FoodCourt
	local westSide = HALF + WALL - f.DoorHalfWidth
	for _, sign in { -1, 1 } do
		wall(Vector3.new(WALL, h, westSide), Vector3.new(-outer, h / 2, sign * (f.DoorHalfWidth + westSide / 2)))
	end
	wall(
		Vector3.new(WALL, h - f.DoorHeight, f.DoorHalfWidth * 2),
		Vector3.new(-outer, f.DoorHeight + (h - f.DoorHeight) / 2, 0)
	)

	-- south: entrance gap
	local e = Layout.Entrance
	local sideWidth = HALF + WALL - e.HalfWidth
	for _, sign in { -1, 1 } do
		wall(Vector3.new(sideWidth, h, WALL), Vector3.new(sign * (e.HalfWidth + sideWidth / 2), h / 2, -outer))
	end
	wall(Vector3.new(e.HalfWidth * 2, h - e.Height, WALL), Vector3.new(0, e.Height + (h - e.Height) / 2, -outer))

	-- east: corridor mouth
	local c = Layout.Corridor
	local sideDepth = HALF + WALL - c.HalfWidth
	for _, sign in { -1, 1 } do
		wall(Vector3.new(WALL, h, sideDepth), Vector3.new(outer, h / 2, sign * (c.HalfWidth + sideDepth / 2)))
	end
	wall(Vector3.new(WALL, h - c.Height, c.HalfWidth * 2), Vector3.new(outer, c.Height + (h - c.Height) / 2, 0))

	-- marble wainscot + gold cornice on the inner faces (decor only)
	for _, data in
		{
			{ Vector3.new(span - 4, 3, 0.3), Vector3.new(0, 1.5, HALF - 0.15) },
			{ Vector3.new(0.3, 3, HALF - 2 - 12), Vector3.new(-HALF + 0.15, 1.5, -(HALF - 2 + 12) / 2) },
			{ Vector3.new(0.3, 3, HALF - 2 - 12), Vector3.new(-HALF + 0.15, 1.5, (HALF - 2 + 12) / 2) },
		}
	do
		Builder.decor({
			Parent = parent,
			Size = data[1],
			CFrame = CFrame.new(data[2]),
			Color = Palette.MarbleWarm,
			Material = Enum.Material.Marble,
		})
	end
	for _, data in
		{
			{ Vector3.new(span - 4, 0.5, 0.4), Vector3.new(0, A.Height - 0.6, HALF - 0.2) },
			{ Vector3.new(span - 4, 0.5, 0.4), Vector3.new(0, A.Height - 0.6, -HALF + 0.2) },
			{ Vector3.new(0.4, 0.5, span - 4), Vector3.new(HALF - 0.2, A.Height - 0.6, 0) },
			{ Vector3.new(0.4, 0.5, span - 4), Vector3.new(-HALF + 0.2, A.Height - 0.6, 0) },
		}
	do
		Builder.decor({
			Parent = parent,
			Size = data[1],
			CFrame = CFrame.new(data[2]),
			Color = Palette.Gold,
			Material = Enum.Material.Metal,
		})
	end
end

local function buildBalcony(parent: Instance)
	local y = A.BalconyY
	local inner = A.BalconyInner
	local slab = { Parent = parent, Color = Palette.MarbleLight, Material = Enum.Material.Marble }
	local band = HALF - inner
	local function addSlab(size: Vector3, position: Vector3)
		local props = table.clone(slab)
		props.Size = size
		props.CFrame = CFrame.new(position)
		Builder.part(props)
	end
	addSlab(Vector3.new(HALF * 2, 1.5, band), Vector3.new(0, y - 0.75, inner + band / 2))
	addSlab(Vector3.new(HALF * 2, 1.5, band), Vector3.new(0, y - 0.75, -(inner + band / 2)))
	addSlab(Vector3.new(band, 1.5, inner * 2), Vector3.new(inner + band / 2, y - 0.75, 0))
	addSlab(Vector3.new(band, 1.5, inner * 2), Vector3.new(-(inner + band / 2), y - 0.75, 0))

	-- circular inner edge
	ring(parent, 32, inner, inner * math.sqrt(2) + 0.2, y - 1.53, y + 0.03, {
		Color = Palette.MarbleLight,
		Material = Enum.Material.Marble,
	})

	-- fascia lip and the signature neon underglow
	local count = 32
	local step = math.pi * 2 / count
	local chord = 2 * inner * math.tan(step / 2) + 0.1
	for i = 0, count - 1 do
		local angle = i * step
		local fascia = ringPoint(inner + 0.3, angle, y - 2.2)
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(chord, 1.6, 0.6),
			CFrame = CFrame.lookAt(fascia, Vector3.new(0, fascia.Y, 0)),
			Color = Palette.Wall,
		})
		local neon = ringPoint(inner + 0.25, angle, y - 3.1)
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(chord, 0.3, 0.3),
			CFrame = CFrame.lookAt(neon, Vector3.new(0, neon.Y, 0)),
			Color = if i % 2 == 0 then Palette.NeonPink else Palette.NeonPurple,
			Material = Enum.Material.Neon,
			Tags = { "NightNeon" },
		})
	end

	-- glass railing with a gold top rail; gaps where the escalators land
	local railRadius = inner + 0.5
	local railChord = 2 * railRadius * math.tan(step / 2)
	for i = 0, count - 1 do
		local angle = (i + 0.5) * step
		local base = ringPoint(railRadius, angle, y)
		local blocked = false
		for _, escalator in Layout.Escalators do
			local top = escalator.Top
			if (Vector3.new(base.X, 0, base.Z) - Vector3.new(top.X, 0, top.Z)).Magnitude < 6.5 then
				blocked = true
			end
		end
		if not blocked then
			local look = Vector3.new(0, y, 0)
			Builder.part({
				Parent = parent,
				Size = Vector3.new(railChord, 3.2, 0.25),
				CFrame = CFrame.lookAt(base + Vector3.new(0, 1.6, 0), look + Vector3.new(0, 1.6, 0)),
				Color = Palette.Glass,
				Material = Enum.Material.Glass,
				Transparency = 0.6,
				CastShadow = false,
			})
			Builder.decor({
				Parent = parent,
				Size = Vector3.new(railChord, 0.35, 0.45),
				CFrame = CFrame.lookAt(base + Vector3.new(0, 3.35, 0), look + Vector3.new(0, 3.35, 0)),
				Color = Palette.Gold,
				Material = Enum.Material.Metal,
			})
		end
	end

	-- downlights under the balcony
	for i = 0, 15 do
		Props.downlight(ringPoint(inner + 10, (i + 0.5) * math.pi / 8, y - 1.6), parent, 24)
	end
end

local function buildColumns(parent: Instance)
	for i = 0, 7 do
		local angle = (i + 0.5) * math.pi / 4
		local p = ringPoint(A.ColumnRadius, angle, 0)
		if AssetRegistry.place("Column", CFrame.new(p), parent) then
			continue
		end
		Builder.cylinder(p + Vector3.new(0, A.Height / 2, 0), 1.5, A.Height, {
			Parent = parent,
			Color = Palette.MarbleLight,
			Material = Enum.Material.Marble,
		})
		for _, ringY in { 0.5, A.BalconyY - 2.5, A.BalconyY + 0.4, A.Height - 0.5 } do
			Builder.cylinder(p + Vector3.new(0, ringY, 0), 2, 0.8, {
				Parent = parent,
				Color = if ringY < 1 then Palette.MarbleWarm else Palette.Gold,
				Material = if ringY < 1 then Enum.Material.Marble else Enum.Material.Metal,
				CanCollide = false,
			})
		end
	end
end

local function buildCeilingAndDome(parent: Instance)
	local y = A.Height
	local hole = A.DomeRadius
	local band = HALF + WALL - hole
	local slab = { Parent = parent, Color = Palette.Wall, Material = Enum.Material.SmoothPlastic }
	local function addSlab(size: Vector3, position: Vector3)
		local props = table.clone(slab)
		props.Size = size
		props.CFrame = CFrame.new(position)
		Builder.part(props)
	end
	local full = (HALF + WALL) * 2
	addSlab(Vector3.new(full, 1.5, band), Vector3.new(0, y + 0.75, hole + band / 2))
	addSlab(Vector3.new(full, 1.5, band), Vector3.new(0, y + 0.75, -(hole + band / 2)))
	addSlab(Vector3.new(band, 1.5, hole * 2), Vector3.new(hole + band / 2, y + 0.75, 0))
	addSlab(Vector3.new(band, 1.5, hole * 2), Vector3.new(-(hole + band / 2), y + 0.75, 0))
	ring(parent, 32, hole, hole * math.sqrt(2) + 0.2, y - 0.1, y + 1.55, {
		Color = Palette.Wall,
		Material = Enum.Material.SmoothPlastic,
	})
	-- neon halo at the dome's base
	ring(parent, 48, hole - 0.4, hole, y - 0.4, y - 0.1, {
		Color = Palette.NeonCyan,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Tags = { "NightNeon" },
	})

	if AssetRegistry.place("GlassDome", CFrame.new(0, y + 1.5, 0), parent) then
		return
	end

	-- Geodesic-style glass dome: glass panels between steel ribs.
	local center = Vector3.new(0, y + 1.5, 0)
	local R = hole
	local bands = { 0, 18, 36, 54, 72 }
	local segments = 16
	local db = math.pi * 2 / segments
	local function sphere(elevation: number, azimuth: number, radius: number): Vector3
		local e = math.rad(elevation)
		return center
			+ Vector3.new(math.cos(e) * math.cos(azimuth), math.sin(e), math.cos(e) * math.sin(azimuth)) * radius
	end

	for k = 1, #bands - 1 do
		local a0, a1 = bands[k], bands[k + 1]
		local am = (a0 + a1) / 2
		local width = 2 * R * math.cos(math.rad(a0)) * math.sin(db / 2) + 0.3
		local height = 2 * R * math.sin(math.rad(a1 - a0) / 2) + 0.3
		for j = 0, segments - 1 do
			local bm = (j + 0.5) * db
			local pos = sphere(am, bm, R)
			Builder.decor({
				Parent = parent,
				Size = Vector3.new(width, height, 0.3),
				CFrame = CFrame.lookAt(pos, pos + (pos - center).Unit),
				Color = Palette.Glass,
				Material = Enum.Material.Glass,
				Transparency = 0.55,
			})
			-- ribs
			local frame =
				{ Parent = parent, Color = Palette.DarkMetal, Material = Enum.Material.Metal, CanCollide = false }
			local f1 = table.clone(frame)
			Builder.beam(sphere(a0, j * db, R - 0.3), sphere(a1, j * db, R - 0.3), 0.6, f1)
			local f2 = table.clone(frame)
			Builder.beam(sphere(a0, j * db, R - 0.3), sphere(a0, (j + 1) * db, R - 0.3), 0.6, f2)
		end
	end

	local capY = center.Y + R * math.sin(math.rad(72))
	local capRadius = R * math.cos(math.rad(72))
	Builder.cylinder(Vector3.new(0, capY, 0), capRadius + 0.4, 0.5, {
		Parent = parent,
		Color = Palette.Glass,
		Material = Enum.Material.Glass,
		Transparency = 0.5,
		CanCollide = false,
		CastShadow = false,
	})
	Builder.cylinder(Vector3.new(0, capY + 0.4, 0), capRadius * 0.4, 0.6, {
		Parent = parent,
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
end

-- Suspended neon "moon ring" sculpture under the dome.
local function buildCenterpiece(parent: Instance)
	local model = Builder.model("MoonRing", parent)
	for _, data in { { 10, 38, Palette.NeonCyan, 28 }, { 6.5, 35.5, Palette.NeonPurple, 20 } } do
		local radius, y, color, count = data[1], data[2], data[3], data[4]
		local step = math.pi * 2 / count
		for i = 0, count - 1 do
			local p = ringPoint(radius, i * step, y)
			Builder.decor({
				Parent = model,
				Size = Vector3.new(2 * radius * math.tan(step / 2) + 0.05, 0.45, 0.45),
				CFrame = CFrame.lookAt(p, Vector3.new(0, y, 0)),
				Color = color,
				Material = Enum.Material.Neon,
				Tags = { "NightNeon" },
			})
		end
	end
	for i = 0, 3 do
		local p = ringPoint(10, i * math.pi / 2, 38)
		Builder.beam(p, p + Vector3.new(0, 28, 0), 0.1, {
			Parent = model,
			Color = Palette.DarkMetal,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
	end
	local orb = Builder.decor({
		Parent = model,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 3,
		CFrame = CFrame.new(0, 36.5, 0),
		Color = Color3.fromRGB(235, 235, 255),
		Material = Enum.Material.Neon,
		Tags = { "NightNeon" },
	})
	Builder.light("PointLight", orb, { Range = 40, Brightness = 0.8, Color = Palette.NeonPurple }, { "NightLight" })
end

-- Central water plume. `at` must be unrotated so its Top face points up.
local function addSprays(at: BasePart)
	local function spray(offset: Vector3, rate: number, speed: NumberRange, spread: number)
		local attachment = Instance.new("Attachment")
		attachment.Position = offset
		attachment.Parent = at
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255), Color3.fromRGB(120, 210, 240))
		emitter.LightEmission = 0.35
		emitter.Transparency = NumberSequence.new(0.15, 1)
		emitter.Size = NumberSequence.new(0.45, 0.15)
		emitter.Speed = speed
		emitter.SpreadAngle = Vector2.new(spread, spread)
		emitter.Acceleration = Vector3.new(0, -34, 0)
		emitter.Lifetime = NumberRange.new(0.8, 1.15)
		emitter.Rate = rate
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Parent = attachment
	end
	spray(Vector3.new(0, 0.5, 0), 90, NumberRange.new(11, 14), 10)
	spray(Vector3.new(0, 0.2, 0), 40, NumberRange.new(4, 6), 60)
end

local function buildFountain(parent: Instance)
	if AssetRegistry.place("Fountain", CFrame.new(0, 0, 0), parent) then
		-- authored basin: keep the procedural water plume at the spout height
		addSprays(Builder.decor({
			Name = "FountainSpout",
			Parent = parent,
			Size = Vector3.one,
			CFrame = CFrame.new(0, 11, 0),
			Transparency = 1,
		}))
		return
	end
	local model = Builder.model("Fountain", parent)
	local function cyl(
		y: number,
		r: number,
		h: number,
		color: Color3,
		material: Enum.Material,
		extra: { [string]: any }?
	)
		local props = { Parent = model, Color = color, Material = material }
		if extra then
			for k, v in extra do
				props[k] = v
			end
		end
		return Builder.cylinder(Vector3.new(0, y, 0), r, h, props)
	end

	cyl(0.9, 11, 1.8, Palette.MarbleWarm, Enum.Material.Marble)
	cyl(1.95, 11.3, 0.3, Palette.MarbleLight, Enum.Material.Marble)
	cyl(0.15, 11.4, 0.2, Palette.NeonCyan, Enum.Material.Neon, { CanCollide = false, Tags = { "NightNeon" } })
	local water = cyl(1.6, 10.4, 0.3, Palette.Water, Enum.Material.Glass, {
		Transparency = 0.25,
		CanCollide = false,
		CastShadow = false,
		Reflectance = 0.15,
	})
	Builder.light("PointLight", water, { Range = 18, Brightness = 1.2, Color = Palette.NeonCyan })

	cyl(4.5, 1.6, 6, Palette.MarbleLight, Enum.Material.Marble)
	cyl(7.2, 5, 0.8, Palette.MarbleWarm, Enum.Material.Marble)
	cyl(7.65, 4.6, 0.2, Palette.Water, Enum.Material.Glass, { Transparency = 0.25, CanCollide = false })
	cyl(9, 0.9, 3, Palette.MarbleLight, Enum.Material.Marble)
	cyl(10.4, 2.6, 0.6, Palette.Gold, Enum.Material.Metal)
	local spout = Builder.decor({
		Parent = model,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.2,
		CFrame = CFrame.new(0, 11, 0),
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
	})

	addSprays(spout)
end

local function escalatorSign(position: Vector3, facing: Vector3, text: string, color: Color3, parent: Instance)
	Builder.decor({
		Parent = parent,
		Size = Vector3.new(0.2, 3, 0.2),
		CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0)),
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
	})
	local plate = Builder.decor({
		Parent = parent,
		Size = Vector3.new(2.8, 1.1, 0.15),
		CFrame = CFrame.lookAt(position + Vector3.new(0, 3.5, 0), position + Vector3.new(0, 3.5, 0) + facing),
		Color = Color3.fromRGB(18, 13, 30),
	})
	Builder.label(plate, Enum.NormalId.Front, text, { Color = color, Font = FONT_HEADING })
end

local function buildEscalator(bottom: Vector3, top: Vector3, parent: Instance, index: number, direction: number)
	local model = Builder.model("Escalator" .. index, parent)
	local dir = top - bottom
	local length = dir.Magnitude
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local cf = CFrame.lookAt((bottom + top) / 2, top)

	-- Walking ramp (top surface passes through bottom & top). It is anchored, and its
	-- AssemblyLinearVelocity makes it a conveyor: the physics engine carries anything
	-- standing on it, for every player at once, with no scripts or teleporting.
	local ramp = Builder.part({
		Name = "Ramp",
		Parent = model,
		Size = Vector3.new(6, 0.6, length + 1),
		CFrame = cf * CFrame.new(0, -0.3, 0),
		Transparency = 1,
	})
	ramp.AssemblyLinearVelocity = dir.Unit * Layout.EscalatorSpeed * direction
	model:SetAttribute("Direction", direction)
	model:SetAttribute("Speed", Layout.EscalatorSpeed)

	local right = cf.RightVector
	local along = flat.Unit
	local up = direction > 0
	escalatorSign(
		bottom - along * 1.6 + right * 4.2,
		-along,
		if up then "▲ UP" else "⛔ DOWN ONLY",
		if up then Palette.NeonGreen else Palette.NeonRed,
		model
	)
	escalatorSign(
		Vector3.new(top.X, top.Y, top.Z) + along * 1 + right * 4.2,
		along,
		if up then "⛔ UP ONLY" else "▼ DOWN",
		if up then Palette.NeonRed else Palette.NeonGreen,
		model
	)
	Builder.part({
		Parent = model,
		Size = Vector3.new(7.4, 2.6, length),
		CFrame = cf * CFrame.new(0, -1.9, 0),
		Color = Palette.Chrome,
		Material = Enum.Material.Metal,
	})
	for _, side in { -1, 1 } do
		Builder.decor({
			Parent = model,
			Size = Vector3.new(0.3, 0.3, length),
			CFrame = cf * CFrame.new(side * 3.75, -3.2, 0),
			Color = Palette.NeonCyan,
			Material = Enum.Material.Neon,
			Tags = { "NightNeon" },
		})
		Builder.part({
			Parent = model,
			Size = Vector3.new(0.25, 3, length),
			CFrame = cf * CFrame.new(side * 3.3, 1.6, 0),
			Color = Palette.Glass,
			Material = Enum.Material.Glass,
			Transparency = 0.55,
			CastShadow = false,
		})
		Builder.decor({
			Parent = model,
			Size = Vector3.new(0.5, 0.35, length + 1.2),
			CFrame = cf * CFrame.new(side * 3.3, 3.25, 0),
			Color = Color3.fromRGB(20, 20, 24),
			Material = Enum.Material.Rubber,
		})
		Builder.decor({
			Parent = model,
			Size = Vector3.new(0.25, 0.7, length),
			CFrame = cf * CFrame.new(side * 3.05, 0.2, 0),
			Color = Palette.Chrome,
			Material = Enum.Material.Metal,
		})
	end

	-- animated treads (moved client-side by WorldFxController)
	local count = 18
	model:SetAttribute("Bottom", bottom)
	model:SetAttribute("Top", top)
	model:SetAttribute("StepCount", count)
	local tread = flat.Magnitude / count
	for i = 1, count do
		local f = (i - 1) / count
		local position = bottom:Lerp(top, f) + Vector3.new(0, -0.5, 0)
		Builder.decor({
			Name = "Step",
			Parent = model,
			Size = Vector3.new(5.7, 1, tread),
			CFrame = CFrame.lookAt(position, position + flat),
			Color = Builder.shade(Palette.DarkMetal, if i % 2 == 0 then 0.1 else 0),
			Material = Enum.Material.DiamondPlate,
			Attributes = { Index = i },
		})
	end
	Builder.tag(model, "Escalator")

	-- landing at the top joining the balcony
	local landing = top + flat.Unit * 4
	Builder.part({
		Parent = model,
		Size = Vector3.new(6.6, 1.5, 8),
		CFrame = CFrame.lookAt(landing - Vector3.new(0, 0.72, 0), landing - Vector3.new(0, 0.72, 0) + flat),
		Color = Palette.Chrome,
		Material = Enum.Material.DiamondPlate,
	})
	Builder.decor({
		Parent = model,
		Size = Vector3.new(6.6, 0.1, 3),
		CFrame = CFrame.lookAt(bottom - flat.Unit * 1.5, bottom - flat.Unit * 1.5 + flat) * CFrame.new(0, 0.05, 0),
		Color = Palette.Chrome,
		Material = Enum.Material.DiamondPlate,
	})
end

local function buildEntranceAndPlaza(parent: Instance, rng: Random)
	local e = Layout.Entrance
	local z = -HALF - WALL / 2
	local p = Layout.Plaza

	-- ground
	Builder.part({
		Name = "Ground",
		Parent = parent,
		Size = Vector3.new(700, 2, 700),
		CFrame = CFrame.new(0, -1.15, 0),
		Color = Color3.fromRGB(44, 74, 52),
		Material = Enum.Material.Grass,
	})
	local plazaDepth = math.abs(p.MinZ - z)
	Builder.part({
		Parent = parent,
		Size = Vector3.new(p.HalfWidth * 2, 1, plazaDepth),
		CFrame = CFrame.new(0, -0.5, z - plazaDepth / 2),
		Color = Palette.Concrete,
		Material = Enum.Material.Pavement,
	})
	for i = -2, 2 do
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(1, 0.02, plazaDepth),
			CFrame = CFrame.new(i * 14, 0.01, z - plazaDepth / 2),
			Color = Palette.MarbleWarm,
			Material = Enum.Material.Pavement,
		})
	end

	-- invisible boundary
	for _, data in
		{
			{ Vector3.new(p.HalfWidth * 2, 40, 1), Vector3.new(0, 20, p.MinZ) },
			{ Vector3.new(1, 40, plazaDepth), Vector3.new(p.HalfWidth, 20, z - plazaDepth / 2) },
			{ Vector3.new(1, 40, plazaDepth), Vector3.new(-p.HalfWidth, 20, z - plazaDepth / 2) },
		}
	do
		Builder.part({
			Name = "Boundary",
			Parent = parent,
			Size = data[1],
			CFrame = CFrame.new(data[2]),
			Transparency = 1,
		})
	end

	-- door frame and opened sliding glass doors
	for _, side in { -1, 1 } do
		Builder.part({
			Parent = parent,
			Size = Vector3.new(1, e.Height, 2.6),
			CFrame = CFrame.new(side * (e.HalfWidth - 0.5), e.Height / 2, z),
			Color = Palette.Gold,
			Material = Enum.Material.Metal,
		})
		Builder.part({
			Parent = parent,
			Size = Vector3.new(6, e.Height - 1, 0.2),
			CFrame = CFrame.new(side * (e.HalfWidth + 3), (e.Height - 1) / 2, z + WALL / 2 + 0.2),
			Color = Palette.Glass,
			Material = Enum.Material.Glass,
			Transparency = 0.5,
			CastShadow = false,
		})
	end
	Builder.decor({
		Parent = parent,
		Size = Vector3.new(e.HalfWidth * 2, 1, 2.6),
		CFrame = CFrame.new(0, e.Height - 0.5, z),
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
	})

	-- canopy
	local canopy = Builder.part({
		Parent = parent,
		Size = Vector3.new(36, 1, 12),
		CFrame = CFrame.new(0, e.Height + 1.5, z - 6),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Metal,
	})
	Builder.decor({
		Parent = parent,
		Size = Vector3.new(36.2, 0.3, 0.3),
		CFrame = CFrame.new(0, e.Height + 0.95, z - 12),
		Color = Palette.NeonPink,
		Material = Enum.Material.Neon,
		Tags = { "NightNeon" },
	})
	Builder.light("SurfaceLight", canopy, {
		Face = Enum.NormalId.Bottom,
		Range = 18,
		Brightness = 1.2,
		Color = Palette.WarmLight,
		Angle = 80,
	}, { "DayLight" })
	for _, side in { -1, 1 } do
		Builder.cylinder(Vector3.new(side * 16, (e.Height + 1) / 2, z - 11), 0.6, e.Height + 1, {
			Parent = parent,
			Color = Palette.Gold,
			Material = Enum.Material.Metal,
		})
	end

	-- exterior marquee
	local marquee = Builder.part({
		Parent = parent,
		Size = Vector3.new(64, 12, 1),
		CFrame = CFrame.new(0, 33, z - 1.5) * CFrame.Angles(0, math.pi, 0),
		Color = Color3.fromRGB(16, 12, 28),
		Material = Enum.Material.SmoothPlastic,
	})
	local _, title = Builder.label(marquee, Enum.NormalId.Front, "NIGHT SHIFT MALL", {
		Color = Color3.fromRGB(240, 250, 255),
		Font = FONT_TITLE,
		Stroke = Palette.NeonPurple,
		StrokeThickness = 6,
		Brightness = 3,
		PixelsPerStud = 24,
	})
	title.Name = "Marquee"
	Builder.decor({
		Parent = parent,
		Size = Vector3.new(64.4, 0.4, 0.4),
		CFrame = CFrame.new(0, 26.8, z - 2.2),
		Color = Palette.NeonCyan,
		Material = Enum.Material.Neon,
		Tags = { "NightNeon" },
	})

	-- interior welcome sign above the doors
	local welcome = Builder.part({
		Parent = parent,
		Size = Vector3.new(26, 4.2, 0.5),
		CFrame = CFrame.new(0, e.Height + 3.2, z + WALL / 2 + 0.3) * CFrame.Angles(0, math.pi, 0),
		Color = Color3.fromRGB(20, 14, 34),
	})
	Builder.label(welcome, Enum.NormalId.Back, "WELCOME TO NIGHT SHIFT MALL", {
		Color = Palette.NeonGold,
		Font = FONT_HEADING,
		Brightness = 2.2,
	})

	-- plaza dressing
	for _, x in { -44, -24, 24, 44 } do
		local base = Vector3.new(x, 0, -92)
		Props.planter(base, 3.4, parent)
		Props.palm(base + Vector3.new(0, 2.5, 0), parent, rng)
	end
	for _, pos in
		{ Vector3.new(-56, 0, -80), Vector3.new(56, 0, -80), Vector3.new(-56, 0, -108), Vector3.new(56, 0, -108) }
	do
		Props.streetLamp(pos, parent)
	end
	for _, x in { -34, 34 } do
		Props.bench(CFrame.lookAt(Vector3.new(x, 0, -104), Vector3.new(x, 0, -90)), parent)
	end
end

local FACADE_NAMES = {
	"Moonbeam Café",
	"Velvet Arcade",
	"Pixel Plaza",
	"Glow Gear",
	"Starlight Cinema",
	"Candy Comet",
	"Echo Records",
	"Lumen Lanes",
	"Prism Optics",
	"Neon Noodle",
	"Orbit Outfitters",
	"Hush Books",
	"Comet Kicks",
	"Aurora Sweets",
	"Static TV",
	"Cosmo Toys",
}

local function buildFacades(parent: Instance, rng: Random)
	local inner = HALF - 0.05
	local slots = {
		-- ground floor (south & east sides keep the doors/corridor clear)
		{ Vector3.new(-36, 0, inner), Vector3.new(0, 0, -1) },
		{ Vector3.new(36, 0, inner), Vector3.new(0, 0, -1) },
		{ Vector3.new(-inner, 0, -36), Vector3.new(1, 0, 0) },
		{ Vector3.new(-inner, 0, 36), Vector3.new(1, 0, 0) },
		{ Vector3.new(-46, 0, -inner), Vector3.new(0, 0, 1) },
		{ Vector3.new(46, 0, -inner), Vector3.new(0, 0, 1) },
		{ Vector3.new(inner, 0, -46), Vector3.new(-1, 0, 0) },
		{ Vector3.new(inner, 0, 46), Vector3.new(-1, 0, 0) },
	}
	local y = A.BalconyY
	for _, offset in { -30, 30 } do
		table.insert(slots, { Vector3.new(offset, y, inner), Vector3.new(0, 0, -1) })
		table.insert(slots, { Vector3.new(offset, y, -inner), Vector3.new(0, 0, 1) })
		table.insert(slots, { Vector3.new(inner, y, offset), Vector3.new(-1, 0, 0) })
		table.insert(slots, { Vector3.new(-inner, y, offset), Vector3.new(1, 0, 0) })
	end

	for i, slot in slots do
		local cf = CFrame.lookAt(slot[1], slot[1] + slot[2])
		local accent = Palette.ShopAccents[(i - 1) % #Palette.ShopAccents + 1]
		Props.facade(cf, 22, 15, FACADE_NAMES[(i - 1) % #FACADE_NAMES + 1], accent, parent, rng)
	end
end

local function buildDressing(parent: Instance, rng: Random)
	-- palms in planters around the fountain
	for i = 0, 5 do
		local base = ringPoint(22, math.rad(30 + i * 60), 0)
		if not AssetRegistry.place("PlanterBench", CFrame.new(base), parent) then
			Props.planter(base, 3, parent)
		end
		Props.palm(base + Vector3.new(0, 2.5, 0), parent, rng)
	end
	-- benches facing the fountain
	for i = 0, 7 do
		local p = ringPoint(15.5, i * math.pi / 4, 0)
		Props.bench(CFrame.lookAt(p, Vector3.new(0, 0, 0)), parent)
	end
	-- potted plants along the balcony
	for i = 0, 11 do
		local p = ringPoint(A.BalconyInner + 3, (i + 0.25) * math.pi / 6, A.BalconyY)
		local nearLanding = false
		for _, escalator in Layout.Escalators do
			if (Vector3.new(p.X, 0, p.Z) - Vector3.new(escalator.Top.X, 0, escalator.Top.Z)).Magnitude < 10 then
				nearLanding = true
			end
		end
		if not nearLanding then
			Props.pottedPlant(p, parent, rng)
		end
	end
	-- banners hanging from the upper ceiling
	for i = 0, 3 do
		local angle = math.rad(45 + i * 90)
		local top = ringPoint(A.BalconyInner + 6, angle, A.Height - 0.2)
		Props.banner(top, Vector3.new(-math.cos(angle), 0, -math.sin(angle)), "🌴\nNIGHT\nSHIFT", parent)
	end
	-- corridor mouth sign
	local arch = Builder.part({
		Parent = parent,
		Size = Vector3.new(0.6, 3.6, 22),
		CFrame = CFrame.new(HALF - 0.4, Layout.Corridor.Height - 2.6, 0),
		Color = Color3.fromRGB(20, 14, 34),
	})
	Builder.label(arch, Enum.NormalId.Left, "EAST WING  ›  SHOPS", {
		Color = Palette.NeonCyan,
		Font = FONT_HEADING,
		Brightness = 2.2,
	})
	-- things that watch from high corners at night
	for _, cf in
		{
			CFrame.lookAt(Vector3.new(-66, 28, 66), Vector3.new(0, 28, 0)),
			CFrame.lookAt(Vector3.new(66, 30, 66), Vector3.new(0, 30, 0)),
			CFrame.lookAt(Vector3.new(-66, 4, -66), Vector3.new(0, 4, 0)),
			CFrame.lookAt(Vector3.new(-69.5, 9, 56), Vector3.new(0, 9, 56)),
		}
	do
		Props.lurkerEyes(cf, parent, 1.6)
	end
end

local function buildGameplayMarkers(parent: Instance)
	local spawn = Builder.part({
		Name = "PlayerSpawn",
		Parent = parent,
		Size = Vector3.new(8, 1, 8),
		CFrame = Layout.PlayerSpawn,
		Transparency = 1,
		CanCollide = false,
	}, "SpawnLocation") :: SpawnLocation
	spawn.Neutral = true
	spawn.Duration = 3 -- brief ForceField after (re)spawning, so nobody is bitten on arrival

	Props.fuseBox(
		CFrame.lookAt(Vector3.new(HALF, 4.5, -30), Vector3.new(0, 4.5, -30)),
		"Atrium",
		"Atrium Power",
		parent
	)
	Props.fuseBox(
		CFrame.lookAt(Vector3.new(-12, A.BalconyY + 4.5, HALF), Vector3.new(-12, A.BalconyY + 4.5, 0)),
		"Balcony",
		"Upper Level Power",
		parent
	)

	for _, position in
		{
			Vector3.new(-60, 3, 60),
			Vector3.new(60, 3, 62),
			Vector3.new(-58, A.BalconyY + 3, -58),
			Vector3.new(0, 3, -90),
		}
	do
		Builder.part({
			Name = "EnemySpawn",
			Parent = parent,
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(position),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Tags = { "EnemySpawn" },
		})
	end
end

function Lobby.build(parent: Instance)
	local model = Builder.model("Atrium", parent)
	local rng = Random.new(1337) -- fixed seed: identical layout every server
	buildFloor(model)
	buildWalls(model)
	buildBalcony(model)
	buildColumns(model)
	buildCeilingAndDome(model)
	buildCenterpiece(model)
	buildFountain(model)
	for i, escalator in Layout.Escalators do
		buildEscalator(escalator.Bottom, escalator.Top, model, i, escalator.Direction)
	end
	buildEntranceAndPlaza(model, rng)
	buildFacades(model, rng)
	buildDressing(model, rng)
	buildGameplayMarkers(model)
	LobbyDetail.build(model)
	return model
end

return Lobby
