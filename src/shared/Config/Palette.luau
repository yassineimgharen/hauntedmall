--!strict
-- Art-direction palette shared by the world builder and the UI so both stay consistent.

local rgb = Color3.fromRGB

local Palette = {
	-- Architecture
	MarbleLight = rgb(234, 228, 218),
	MarbleWarm = rgb(214, 196, 172),
	MarbleDark = rgb(44, 38, 66),
	Wall = rgb(242, 236, 228),
	WallTrim = rgb(200, 176, 146),
	Gold = rgb(216, 174, 96),
	Chrome = rgb(176, 180, 196),
	DarkMetal = rgb(36, 34, 46),
	Glass = rgb(176, 218, 236),
	Concrete = rgb(150, 146, 152),
	Asphalt = rgb(52, 50, 58),

	-- Neon (night identity: purple + electric blue + pink)
	NeonPink = rgb(255, 64, 200),
	NeonCyan = rgb(64, 220, 255),
	NeonPurple = rgb(152, 72, 255),
	NeonGold = rgb(255, 192, 84),
	NeonGreen = rgb(84, 255, 164),
	NeonRed = rgb(255, 70, 80),

	-- Nature & materials
	Leaf = rgb(58, 146, 72),
	LeafDark = rgb(34, 104, 56),
	Trunk = rgb(122, 90, 62),
	Soil = rgb(66, 48, 36),
	Wood = rgb(178, 124, 80),
	WoodDark = rgb(108, 70, 44),
	Water = rgb(64, 196, 226),
	Fabric = rgb(88, 52, 140),

	-- Creatures
	ShadowBody = rgb(18, 8, 30),
	ShadowEye = rgb(236, 84, 255),

	-- Warm interior light
	WarmLight = rgb(255, 214, 160),
	CoolLight = rgb(180, 210, 255),
}

Palette.ShopAccents = {
	Palette.NeonPink,
	Palette.NeonCyan,
	Palette.NeonGold,
	Palette.NeonPurple,
	Palette.NeonGreen,
	rgb(255, 120, 80),
}

return Palette
