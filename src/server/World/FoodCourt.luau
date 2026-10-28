-- Chapter 2's Haunted Food Court: the building shell west of the atrium (floors, walls,
-- ceilings, doorways, emergency exits, crawl ducts, the basement under the kitchen).
-- Furniture, restaurants and equipment are in FoodCourtDetail. Coordinates: Layout.FoodCourt.
--
-- Walls are built once along shared centre lines (no doubled faces), with openings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Builder = require(script.Parent.Builder)
local FoodCourtDetail = require(script.Parent.FoodCourtDetail)
local Layout = require(script.Parent.Layout)

local FoodCourt = {}

local F = Layout.FoodCourt
local WALL = 2
local rgb = Color3.fromRGB

local LOOK = {
	Wall = { Color = rgb(56, 44, 70), Material = Enum.Material.Plaster },
	HallWall = { Color = rgb(238, 226, 206), Material = Enum.Material.Plaster },
	KitchenWall = { Color = rgb(220, 226, 228), Material = Enum.Material.CeramicTiles },
	FreezerWall = { Color = rgb(196, 222, 236), Material = Enum.Material.DiamondPlate },
	Service = { Color = rgb(84, 86, 96), Material = Enum.Material.Concrete },
	Ceiling = { Color = rgb(34, 30, 44), Material = Enum.Material.SmoothPlastic },
	HallFloor = { Color = rgb(232, 220, 196), Material = Enum.Material.CeramicTiles },
	KitchenFloor = { Color = rgb(120, 46, 44), Material = Enum.Material.CeramicTiles },
	FreezerFloor = { Color = rgb(188, 214, 228), Material = Enum.Material.Slate },
	ServiceFloor = { Color = rgb(96, 98, 104), Material = Enum.Material.Concrete },
	DockFloor = { Color = rgb(70, 72, 80), Material = Enum.Material.DiamondPlate },
	Basement = { Color = rgb(58, 52, 50), Material = Enum.Material.Brick },
	BasementFloor = { Color = rgb(48, 46, 44), Material = Enum.Material.Concrete },
	Outside = { Color = Palette.Asphalt, Material = Enum.Material.Asphalt },
}

type Look = { Color: Color3, Material: Enum.Material }
type Opening = { number } -- { from, to, height }

local function slab(
	parent: Instance,
	name: string,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	y: number,
	look: Look
)
	return Builder.part({
		Name = name,
		Parent = parent,
		Size = Vector3.new(maxX - minX, 1, maxZ - minZ),
		CFrame = CFrame.new((minX + maxX) / 2, y, (minZ + maxZ) / 2),
		Color = look.Color,
		Material = look.Material,
	})
end

local function floor(parent: Instance, minX: number, maxX: number, minZ: number, maxZ: number, look: Look, y: number?)
	return slab(parent, "Floor", minX, maxX, minZ, maxZ, (y or 0) - 0.5, look)
end

local function ceiling(
	parent: Instance,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	height: number,
	y0: number?
)
	return slab(parent, "Ceiling", minX, maxX, minZ, maxZ, (y0 or 0) + height + 0.5, LOOK.Ceiling)
end

-- A wall along `axis` ("X": runs along X at z = fixed; "Z": along Z at x = fixed) from a to b,
-- with openings { from, to, height } (sorted) cut out of it.
local function wallRun(
	parent: Instance,
	axis: "X" | "Z",
	fixed: number,
	a: number,
	b: number,
	height: number,
	look: Look,
	openings: { Opening }?,
	y0: number?
)
	local base = y0 or 0
	local function segment(s: number, e: number, bottom: number, top: number)
		if e - s < 0.05 or top - bottom < 0.05 then
			return
		end
		local mid, y = (s + e) / 2, base + (bottom + top) / 2
		Builder.part({
			Name = "Wall",
			Parent = parent,
			Size = if axis == "X"
				then Vector3.new(e - s, top - bottom, WALL)
				else Vector3.new(WALL, top - bottom, e - s),
			CFrame = if axis == "X" then CFrame.new(mid, y, fixed) else CFrame.new(fixed, y, mid),
			Color = look.Color,
			Material = look.Material,
		})
	end
	local cursor = a
	for _, opening in (openings or {}) :: { Opening } do
		segment(cursor, opening[1], 0, height)
		segment(opening[1], opening[2], opening[3], height)
		cursor = opening[2]
	end
	segment(cursor, b, 0, height)
end

-- A free-standing box room (fan rooms, ducts, landings): floor, walls with openings, ceiling.
local function room(
	parent: Instance,
	name: string,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	height: number,
	look: Look,
	floorLook: Look,
	openings: { [string]: { Opening } }
): Model
	local model = Builder.model(name, parent)
	floor(model, minX, maxX, minZ, maxZ, floorLook)
	ceiling(model, minX, maxX, minZ, maxZ, height)
	wallRun(model, "X", minZ, minX, maxX, height, look, openings.South)
	wallRun(model, "X", maxZ, minX, maxX, height, look, openings.North)
	wallRun(model, "Z", minX, minZ, maxZ, height, look, openings.West)
	wallRun(model, "Z", maxX, minZ, maxZ, height, look, openings.East)
	return model
end

local function railing(parent: Instance, a: Vector3, b: Vector3)
	Builder.beam(a + Vector3.new(0, 3.2, 0), b + Vector3.new(0, 3.2, 0), 0.3, {
		Parent = parent,
		Color = Palette.Chrome,
		Material = Enum.Material.Metal,
	})
	local length = (b - a).Magnitude
	for i = 0, math.floor(length / 4) do
		local p = a:Lerp(b, math.min(i * 4 / length, 1))
		Builder.part({
			Parent = parent,
			Size = Vector3.new(0.25, 3.2, 0.25),
			CFrame = CFrame.new(p + Vector3.new(0, 1.6, 0)),
			Color = Palette.Chrome,
			Material = Enum.Material.Metal,
		})
	end
end

-- ── the main building ───────────────────────────────────────────────────────

local function buildShell(parent: Instance)
	local P, H, K = F.Promenade, F.Hall, F.Kitchen
	local fr, st, hf = F.Freezer, F.Storage, F.HiddenFreezer
	local nh, sh, dock = F.NorthHall, F.SouthHall, F.Dock
	local rowTop = H.HalfZ + F.RowDepth -- 78

	-- floors
	-- runs under the atrium wall's doorway (x -72..-70) to meet the atrium floor: no gap
	floor(parent, P.MinX, P.MaxX + 2, -P.HalfZ, P.HalfZ, LOOK.HallFloor)
	floor(parent, H.MinX, H.MaxX, -rowTop, rowTop, LOOK.HallFloor) -- hall + both restaurant rows
	floor(parent, K.MinX, K.MaxX, -K.HalfZ, K.HalfZ, LOOK.KitchenFloor)
	floor(parent, fr.MinX, fr.MaxX, fr.MinZ, fr.MaxZ, LOOK.FreezerFloor)
	floor(parent, nh.MinX, nh.MaxX, nh.MinZ, nh.MaxZ, LOOK.ServiceFloor)
	floor(parent, sh.MinX, sh.MaxX, sh.MinZ, sh.MaxZ, LOOK.ServiceFloor)
	floor(parent, dock.MinX, dock.MaxX, dock.MinZ, dock.MaxZ, LOOK.DockFloor)
	-- storage floor around the ramp hole
	local r = F.Ramp
	local holeMinX, holeMaxX, holeMinZ, holeMaxZ = r.X - r.HalfWidth, r.X + r.HalfWidth, r.TopZ, r.TopZ + 12
	floor(parent, st.MinX, holeMinX, st.MinZ, st.MaxZ, LOOK.ServiceFloor)
	floor(parent, holeMaxX, st.MaxX, st.MinZ, st.MaxZ, LOOK.ServiceFloor)
	floor(parent, holeMinX, holeMaxX, st.MinZ, holeMinZ, LOOK.ServiceFloor)
	floor(parent, holeMinX, holeMaxX, holeMaxZ, st.MaxZ, LOOK.ServiceFloor)
	for _, x in { holeMinX, holeMaxX } do
		railing(parent, Vector3.new(x, 0, holeMinZ), Vector3.new(x, 0, holeMaxZ))
	end
	railing(parent, Vector3.new(holeMinX, 0, holeMaxZ), Vector3.new(holeMaxX, 0, holeMaxZ))

	-- ceilings (the hall has a long skylight down the middle)
	ceiling(parent, P.MinX, P.MaxX, -P.HalfZ - 1, P.HalfZ + 1, P.Height)
	local sky = { MinX = -172, MaxX = -110, HalfZ = 10 }
	ceiling(parent, H.MinX, H.MaxX, -H.HalfZ, -sky.HalfZ, H.Height)
	ceiling(parent, H.MinX, H.MaxX, sky.HalfZ, H.HalfZ, H.Height)
	ceiling(parent, H.MinX, sky.MinX, -sky.HalfZ, sky.HalfZ, H.Height)
	ceiling(parent, sky.MaxX, H.MaxX, -sky.HalfZ, sky.HalfZ, H.Height)
	Builder.part({
		Name = "Skylight",
		Parent = parent,
		Size = Vector3.new(sky.MaxX - sky.MinX, 0.4, sky.HalfZ * 2),
		CFrame = CFrame.new((sky.MinX + sky.MaxX) / 2, H.Height + 0.6, 0),
		Color = Palette.Glass,
		Material = Enum.Material.Glass,
		Transparency = 0.6,
		CastShadow = false,
	})
	for x = sky.MinX, sky.MaxX, 6.2 do
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(0.5, 0.8, sky.HalfZ * 2),
			CFrame = CFrame.new(x, H.Height + 0.4, 0),
			Color = Palette.DarkMetal,
			Material = Enum.Material.Metal,
		})
	end
	ceiling(parent, H.MinX, H.MaxX, H.HalfZ, rowTop, F.RestaurantHeight)
	ceiling(parent, H.MinX, H.MaxX, -rowTop, -H.HalfZ, F.RestaurantHeight)
	ceiling(parent, K.MinX, K.MaxX, -K.HalfZ, K.HalfZ, K.Height)
	ceiling(parent, fr.MinX, fr.MaxX, fr.MinZ, fr.MaxZ, fr.Height)
	ceiling(parent, st.MinX, st.MaxX, st.MinZ, st.MaxZ, st.Height)
	ceiling(parent, nh.MinX, nh.MaxX, nh.MinZ, nh.MaxZ, nh.Height)
	ceiling(parent, sh.MinX, sh.MaxX, sh.MinZ, sh.MaxZ, sh.Height)
	ceiling(parent, dock.MinX, dock.MaxX, dock.MinZ, dock.MaxZ, dock.Height)

	-- promenade side walls
	for _, z in { -P.HalfZ - 1, P.HalfZ + 1 } do
		wallRun(parent, "X", z, P.MinX, P.MaxX, P.Height, LOOK.HallWall)
	end

	-- east facade (x = -98): promenade mouth and the north emergency exit
	local north = F.Exits.North.Door
	wallRun(parent, "Z", H.MaxX, dock.MinZ, nh.MaxZ, H.Height, LOOK.HallWall, {
		{ -P.HalfZ, P.HalfZ, P.Height },
		{ north.Z - 4, north.Z + 4, 9 },
	})

	-- the kitchen line (x = -184): storage↔service corridor, three kitchen doors, freezer↔corridor
	wallRun(parent, "Z", H.MinX, st.MinZ, fr.MaxZ, H.Height, LOOK.Wall, {
		{ -90, -80, 10 },
		{ -30, -20, 12 },
		{ -6, 6, 14 },
		{ 20, 30, 12 },
		{ 80, 90, 10 },
	})

	-- restaurant fronts (z = ±48): one wide opening per restaurant
	local fronts = {}
	for _, cx in F.RestaurantCentersX do
		table.insert(fronts, 1, { cx - 11, cx + 11, 14 })
	end
	for _, z in { H.HalfZ, -H.HalfZ } do
		wallRun(parent, "X", z, H.MinX, H.MaxX, H.Height, LOOK.HallWall, fronts)
	end
	-- restaurant dividers and back walls (z = ±78) with a staff door each
	-- (mirrored so the door is on the same side of every restaurant's own floor plan)
	for _, sign in { 1, -1 } do
		local backs = {}
		for _, cx in F.RestaurantCentersX do
			table.insert(backs, 1, if sign > 0 then { cx - 11, cx - 6, 9 } else { cx + 6, cx + 11, 9 })
		end
		for _, x in { -127, -155 } do
			local a, b = H.HalfZ * sign, rowTop * sign
			wallRun(parent, "Z", x, math.min(a, b), math.max(a, b), F.RestaurantHeight, LOOK.Wall)
		end
		wallRun(parent, "X", rowTop * sign, H.MinX, H.MaxX, F.RestaurantHeight, LOOK.Service, backs)
	end

	-- maintenance corridor (north) with the crawl duct to the North Fan, service corridor
	-- (south) opening onto the loading dock
	local northDuct = F.FanRooms[1].Duct[1]
	wallRun(parent, "X", nh.MaxZ, H.MinX, H.MaxX, nh.Height, LOOK.Service, {
		{ northDuct.X - 3, northDuct.X + 3, 7 },
	})
	wallRun(parent, "X", sh.MinZ, H.MinX, H.MaxX, sh.Height, LOOK.Service, { { -140, -118, 12 } })

	-- loading dock: west wall (duct to the Dock Fan), south wall (roll-up exit)
	local dockDuct = F.FanRooms[3].Duct[1]
	wallRun(parent, "Z", dock.MinX, dock.MinZ, dock.MaxZ, dock.Height, LOOK.Service, {
		{ dockDuct.Z - 3, dockDuct.Z + 3, 7 },
	})
	local dockExit = F.Exits.Dock.Door
	wallRun(parent, "X", dock.MinZ, dock.MinX, dock.MaxX, dock.Height, LOOK.Service, {
		{ dockExit.X - 6, dockExit.X + 6, 12 },
	})

	-- kitchen: north (freezer door), south (storage door); the far west wall (x = -250)
	-- holds the West exit, the freezer's false wall and the West Fan duct
	wallRun(parent, "X", K.HalfZ, K.MinX, K.MaxX, K.Height, LOOK.KitchenWall, { { -224, -212, 10 } })
	wallRun(parent, "X", -K.HalfZ, K.MinX, K.MaxX, K.Height, LOOK.KitchenWall, { { -212, -200, 10 } })
	local westDuct = F.FanRooms[2].Duct[1]
	wallRun(parent, "Z", K.MinX, st.MinZ, fr.MaxZ, K.Height, LOOK.Wall, {
		{ westDuct.Z - 3, westDuct.Z + 3, 7 },
		{ -5, 5, 10 },
		{ F.FalseWallZ - 4, F.FalseWallZ + 4, 9 },
	})
	wallRun(parent, "X", fr.MaxZ, fr.MinX, fr.MaxX, fr.Height, LOOK.FreezerWall)
	wallRun(parent, "X", st.MinZ, st.MinX, st.MaxX, st.Height, LOOK.Service)

	-- the secret door: looks like the freezer wall; Level 11 slides it aside
	Builder.part({
		Name = "FalseWall",
		Parent = parent,
		Size = Vector3.new(WALL - 0.2, 9, 8),
		CFrame = CFrame.new(K.MinX, 4.5, F.FalseWallZ),
		Color = LOOK.FreezerWall.Color,
		Material = LOOK.FreezerWall.Material,
		Tags = { "FalseWall" },
	})

	-- hidden freezer behind it (east side open onto the false wall)
	local hidden = room(parent, "HiddenFreezer", hf.MinX, hf.MaxX, hf.MinZ, hf.MaxZ, hf.Height, LOOK.FreezerWall, {
		Color = rgb(150, 190, 214),
		Material = Enum.Material.Glacier,
	}, { East = { { hf.MinZ, hf.MaxZ, hf.Height } } })
	hidden:SetAttribute("Zone", "HiddenFreezer")
end

-- ── exits, ducts, fan rooms ─────────────────────────────────────────────────

local function exitSign(parent: Instance, cf: CFrame)
	local sign = Builder.decor({
		Parent = parent,
		Size = Vector3.new(4, 1.2, 0.3),
		CFrame = cf,
		Color = rgb(10, 40, 20),
		Tags = { "NightNeon" },
	})
	Builder.label(sign, Enum.NormalId.Front, "🏃 EXIT", { Color = Palette.NeonGreen, Brightness = 2.4 })
	Builder.light("PointLight", sign, { Color = Palette.NeonGreen, Range = 10, Brightness = 0.8 })
end

local function buildExits(parent: Instance)
	local model = Builder.model("EmergencyExits", parent)
	for name, exit in F.Exits do
		local door, outside = exit.Door, exit.Outside
		local outward = Vector3.new(outside.X - door.X, 0, outside.Z - door.Z).Unit
		local side = Vector3.new(-outward.Z, 0, outward.X)
		-- landing outside with railings
		local center = door + outward * 8
		local size = if math.abs(outward.X) > 0.5 then Vector3.new(16, 1, 18) else Vector3.new(18, 1, 16)
		Builder.part({
			Name = "ExitLanding",
			Parent = model,
			Size = size,
			CFrame = CFrame.new(center - Vector3.new(0, 0.5, 0)),
			Color = LOOK.Outside.Color,
			Material = LOOK.Outside.Material,
			Attributes = { Exit = name },
		})
		for _, s in { -1, 1 } do
			railing(model, door + side * 8.5 * s, door + outward * 15.5 + side * 8.5 * s)
		end
		railing(model, door + outward * 15.5 - side * 8.5, door + outward * 15.5 + side * 8.5)
		local inside = door - outward * 1.4
		exitSign(model, CFrame.lookAt(inside + Vector3.new(0, 10.5, 0), inside + Vector3.new(0, 10.5, 0) - outward))
		-- green floor arrow just inside
		Builder.decor({
			Parent = model,
			Size = Vector3.new(3, 0.05, 3),
			CFrame = CFrame.lookAt(
				door - outward * 4 + Vector3.new(0, 0.03, 0),
				door - outward * 2 + Vector3.new(0, 0.03, 0)
			),
			Color = Palette.NeonGreen,
			Material = Enum.Material.Neon,
			Transparency = 0.5,
			Tags = { "NightNeon" },
		})
	end
end

local function buildDucts(parent: Instance)
	for i, fan in F.FanRooms do
		local a, b = fan.Duct[1], fan.Duct[2]
		local alongX = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
		local minX, maxX = math.min(a.X, b.X), math.max(a.X, b.X)
		local minZ, maxZ = math.min(a.Z, b.Z), math.max(a.Z, b.Z)
		if alongX then
			minZ, maxZ = a.Z - 3, a.Z + 3
		else
			minX, maxX = a.X - 3, a.X + 3
		end
		-- the duct: a low steel tunnel open at both ends
		local duct = Builder.model("CrawlDuct" .. i, parent)
		floor(duct, minX, maxX, minZ, maxZ, LOOK.DockFloor)
		ceiling(duct, minX, maxX, minZ, maxZ, 7)
		if alongX then
			wallRun(duct, "X", minZ, minX, maxX, 7, LOOK.FreezerWall)
			wallRun(duct, "X", maxZ, minX, maxX, 7, LOOK.FreezerWall)
		else
			wallRun(duct, "Z", minX, minZ, maxZ, 7, LOOK.FreezerWall)
			wallRun(duct, "Z", maxX, minZ, maxZ, 7, LOOK.FreezerWall)
		end
		local glow = Builder.decor({
			Parent = duct,
			Size = if alongX then Vector3.new(maxX - minX, 0.2, 0.3) else Vector3.new(0.3, 0.2, maxZ - minZ),
			CFrame = CFrame.new((minX + maxX) / 2, 6.3, (minZ + maxZ) / 2),
			Color = Palette.NeonCyan,
			Material = Enum.Material.Neon,
			Tags = { "NightNeon" },
		})
		Builder.light("PointLight", glow, { Color = Palette.NeonCyan, Range = 12, Brightness = 0.6 })

		-- the fan room at the far end (opening on the duct side)
		local c = fan.Center
		local half = 8
		local openings: { [string]: { Opening } } = {}
		if alongX then
			local side = if b.X < a.X then "East" else "West"
			openings[side] = { { a.Z - 3, a.Z + 3, 7 } }
		else
			local side = if b.Z > a.Z then "South" else "North"
			openings[side] = { { a.X - 3, a.X + 3, 7 } }
		end
		local fanRoom = room(
			parent,
			"FanRoom" .. i,
			c.X - half,
			c.X + half,
			c.Z - half,
			c.Z + half,
			12,
			LOOK.Service,
			LOOK.ServiceFloor,
			openings
		)
		fanRoom:SetAttribute("FanIndex", i)
		FoodCourtDetail.ventFan(fanRoom, c, fan.Name, i)
	end
end

-- ── basement (Level 12): an empty brick cellar; the maze walls are a level prop ─────

local function buildBasement(parent: Instance)
	local B, r = F.Basement, F.Ramp
	local model = Builder.model("Basement", parent)
	local y0 = B.FloorY
	floor(model, B.MinX, B.MaxX, B.MinZ, B.MaxZ, LOOK.BasementFloor, y0)
	slab(model, "Ceiling", B.MinX, B.MaxX, B.MinZ, B.MaxZ, y0 + B.Height + 0.5, LOOK.Ceiling)
	wallRun(model, "X", B.MinZ, B.MinX, B.MaxX, B.Height, LOOK.Basement, {
		{ r.X - r.HalfWidth - 1, r.X + r.HalfWidth + 1, B.Height },
	}, y0)
	wallRun(model, "X", B.MaxZ, B.MinX, B.MaxX, B.Height, LOOK.Basement, nil, y0)
	wallRun(model, "Z", B.MinX, B.MinZ, B.MaxZ, B.Height, LOOK.Basement, nil, y0)
	wallRun(model, "Z", B.MaxX, B.MinZ, B.MaxZ, B.Height, LOOK.Basement, nil, y0)

	-- the ramp down from the storage room: a tilted slab, walls each side, a cap below the top
	local top = Vector3.new(r.X, 0, r.TopZ)
	local bottom = Vector3.new(r.X, y0, r.BottomZ)
	local length = (bottom - top).Magnitude
	local frame = CFrame.lookAt((top + bottom) / 2, bottom)
	Builder.part({
		Name = "BasementRamp",
		Parent = model,
		Size = Vector3.new(r.HalfWidth * 2, 1, length + 1),
		CFrame = frame * CFrame.new(0, -0.5, 0),
		Color = LOOK.Service.Color,
		Material = Enum.Material.DiamondPlate,
	})
	for _, x in { r.X - r.HalfWidth - 1, r.X + r.HalfWidth + 1 } do
		Builder.part({
			Parent = model,
			Size = Vector3.new(WALL, -y0, r.BottomZ - r.TopZ),
			CFrame = CFrame.new(x, y0 / 2 - 1, (r.TopZ + r.BottomZ) / 2),
			Color = LOOK.Basement.Color,
			Material = LOOK.Basement.Material,
		})
	end
	Builder.part({
		Parent = model,
		Size = Vector3.new(r.HalfWidth * 2 + 4, -y0, WALL),
		CFrame = CFrame.new(r.X, y0 / 2 - 1, r.TopZ - 1),
		Color = LOOK.Basement.Color,
		Material = LOOK.Basement.Material,
	})
	-- caged work lights along the ramp
	for i = 1, 3 do
		local p = top:Lerp(bottom, i / 4) + Vector3.new(r.HalfWidth - 0.2, 4, 0)
		local lamp = Builder.decor({
			Parent = model,
			Size = Vector3.new(0.4, 0.8, 0.8),
			CFrame = CFrame.new(p),
			Color = Palette.WarmLight,
			Material = Enum.Material.Neon,
		})
		Builder.light("PointLight", lamp, { Color = Palette.WarmLight, Range = 14, Brightness = 0.7 })
	end
	-- old pillars and a few dim bulbs (the maze is built on top of this at Level 12)
	for x = B.MinX + B.Cell * 2, B.MaxX - 1, B.Cell * 2 do
		for z = B.MinZ + B.Cell * 2, B.MaxZ - 1, B.Cell * 2 do
			Builder.part({
				Name = "Pillar",
				Parent = model,
				Size = Vector3.new(1.6, B.Height, 1.6),
				CFrame = CFrame.new(x, y0 + B.Height / 2, z),
				Color = rgb(70, 60, 56),
				Material = Enum.Material.Brick,
			})
		end
	end
	for _, p in
		{ Vector3.new(-220, 0, -30), Vector3.new(-172, 0, 10), Vector3.new(-226, 0, 30), Vector3.new(-190, 0, -6) }
	do
		local bulb = Builder.decor({
			Parent = model,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.7,
			CFrame = CFrame.new(p.X, y0 + B.Height - 1, p.Z),
			Color = Palette.WarmLight,
			Material = Enum.Material.Neon,
		})
		Builder.light("PointLight", bulb, { Color = rgb(255, 190, 120), Range = 16, Brightness = 0.5 })
	end
	model:SetAttribute("Zone", "Basement")
end

function FoodCourt.build(parent: Instance): Model
	local model = Builder.model("FoodCourt", parent)
	buildShell(model)
	buildExits(model)
	buildDucts(model)
	buildBasement(model)
	FoodCourtDetail.build(model)
	return model
end

return FoodCourt
