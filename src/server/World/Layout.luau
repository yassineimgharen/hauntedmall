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

	Escalators = {
		-- bottom/top centres of the walking surface
		{ Bottom = Vector3.new(-27, 0, -21), Top = Vector3.new(-27, 24, 20.7) },
		{ Bottom = Vector3.new(27, 0, 21), Top = Vector3.new(27, 24, -20.7) },
	},

	PlayerSpawn = CFrame.new(0, 0.6, -52),

	-- Customer route from outside the doors to the corridor mouth (y = 0 floor level).
	CustomerSpawn = Vector3.new(0, 3, -98),
	CustomerRoute = {
		Vector3.new(0, 0, -62),
		Vector3.new(40, 0, -40),
		Vector3.new(64, 0, 0),
	},
}

return Layout
