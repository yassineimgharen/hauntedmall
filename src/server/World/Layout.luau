--!strict
-- Single source of truth for mall dimensions (studs). Builder, customers and enemies all
-- read from here so navigation points never drift from geometry.
--
--            N (+Z)
--     ┌───────────────────┐ ┌─────┬─────┬─────┐
--     │   balcony ring    │ │ S1  │ S3  │ S5  │  shops (north side)
--     │   ┌─────────┐     │ ├─────┴─────┴─────┤
--  W  │   │ fountain│     ═══  east corridor  ║ gate (locked wing)
--     │   └─────────┘     │ ├─────┬─────┬─────┤
--     │                   │ │ S2  │ S4  │ S6  │  shops (south side)
--     └──────┐ door ┌─────┘ └─────┴─────┴─────┘
--            plaza  (-Z)

local Layout = {
	Atrium = {
		Half = 70, -- interior half-width
		Height = 48, -- ceiling
		BalconyY = 24,
		BalconyInner = 34,
		DomeRadius = 46,
		ColumnRadius = 37,
	},

	Corridor = {
		StartX = 70,
		EndX = 182,
		HalfWidth = 18,
		Height = 24,
		LaneZ = 8, -- customers walk along z = ±LaneZ
	},

	Shop = {
		Width = 30,
		Depth = 34,
		Height = 20,
		CentersX = { 92, 126, 160 },
	},

	Entrance = {
		Z = -70,
		HalfWidth = 12,
		Height = 16,
	},

	Plaza = {
		MinZ = -118,
		HalfWidth = 64,
	},

	-- Bottom/top centres of the walking surface. Direction 1 carries riders up, -1 down;
	-- the collision ramp is a conveyor moving at EscalatorSpeed studs/s along the slope.
	Escalators = {
		{ Bottom = Vector3.new(-27, 0, -21), Top = Vector3.new(-27, 24, 20.7), Direction = 1 },
		{ Bottom = Vector3.new(27, 0, 21), Top = Vector3.new(27, 24, -20.7), Direction = -1 },
	},
	EscalatorSpeed = 7, -- players walk at 16, so riders can still walk with or against it

	-- faces north so the first view is the fountain, dome and the big neon sign
	PlayerSpawn = CFrame.new(0, 0.6, -52) * CFrame.Angles(0, math.pi, 0),

	-- Customer route from outside the doors to the corridor mouth (y = 0 floor level).
	CustomerSpawn = Vector3.new(0, 3, -98),
	CustomerRoute = {
		Vector3.new(0, 0, -62),
		Vector3.new(40, 0, -40),
		Vector3.new(64, 0, 0),
	},

	-- Chapter 2: the Haunted Food Court, west of the atrium through a doorway at z = 0.
	--
	--   N (+Z)      hidden   ┌ walk-in freezer ┐┌──── maintenance corridor ────┐ exit
	--               freezer ║                  │├ R1 ──┬─ R2 ──┬─ R3 ─┤ (north row)
	--                       │  GRAND KITCHEN   ║      DINING HALL      ═ promenade ═ atrium
	--               exit  ══│  (boss arena)    ║                       │
	--                       │                  │├ R4 ──┴─ R5 ──┴─ R6 ─┤ (south row)
	--                       └ storage (stairs) ┘└──── service corridor ──┘
	--                          ↓ basement maze          └ loading dock ┘ exit
	FoodCourt = {
		DoorHalfWidth = 12, -- the opening in the atrium's west wall
		DoorHeight = 18,
		Promenade = { MinX = -98, MaxX = -72, HalfZ = 12, Height = 20 },
		Hall = { MinX = -184, MaxX = -98, HalfZ = 48, Height = 30 },
		RowDepth = 30, -- restaurants: z 48..78 (north) and -78..-48 (south)
		RestaurantWidth = 28,
		RestaurantCentersX = { -113, -141, -169 },
		RestaurantHeight = 18,
		Kitchen = { MinX = -250, MaxX = -184, HalfZ = 48, Height = 26 },
		Freezer = { MinX = -250, MaxX = -184, MinZ = 48, MaxZ = 92, Height = 16 },
		HiddenFreezer = { MinX = -288, MaxX = -250, MinZ = 52, MaxZ = 88, Height = 14 },
		FalseWallZ = 64, -- centre of the secret door in the freezer's west wall
		Storage = { MinX = -250, MaxX = -184, MinZ = -96, MaxZ = -48, Height = 16 },
		NorthHall = { MinX = -184, MaxX = -98, MinZ = 78, MaxZ = 92, Height = 14 },
		SouthHall = { MinX = -184, MaxX = -98, MinZ = -92, MaxZ = -78, Height = 14 },
		Dock = { MinX = -160, MaxX = -98, MinZ = -128, MaxZ = -92, Height = 18 },
		-- 8 × 8 cells of 12 studs under the kitchen and hall; reached by a ramp in storage
		Basement = { MinX = -244, MaxX = -148, MinZ = -48, MaxZ = 48, FloorY = -30, Height = 12, Cell = 12 },
		Ramp = { X = -226, HalfWidth = 5, TopZ = -86, BottomZ = -48 },
		-- emergency exits: the doorway centre (floor level) and the safe landing outside it
		Exits = {
			North = { Door = Vector3.new(-98, 0, 85), Outside = Vector3.new(-90, 0, 85) },
			Dock = { Door = Vector3.new(-129, 0, -128), Outside = Vector3.new(-129, 0, -136) },
			West = { Door = Vector3.new(-250, 0, 0), Outside = Vector3.new(-258, 0, 0) },
		},
		-- crawl ducts (hidden maintenance passages) to the three ventilation fan rooms
		FanRooms = {
			{
				Name = "North Fan",
				Center = Vector3.new(-140, 0, 117),
				Duct = { Vector3.new(-140, 0, 92), Vector3.new(-140, 0, 110) },
			},
			{
				Name = "West Fan",
				Center = Vector3.new(-277, 0, -70),
				Duct = { Vector3.new(-250, 0, -70), Vector3.new(-270, 0, -70) },
			},
			{
				Name = "Dock Fan",
				Center = Vector3.new(-183, 0, -110),
				Duct = { Vector3.new(-160, 0, -110), Vector3.new(-176, 0, -110) },
			},
		},
	},
}

return Layout
