--!strict
-- UI design tokens. Night-neon identity: deep violet glass panels, pink/cyan accents.

local rgb = Color3.fromRGB

local Theme = {
	Colors = {
		Backdrop = rgb(8, 4, 18),
		Panel = rgb(24, 16, 44),
		PanelLight = rgb(38, 28, 66),
		PanelLighter = rgb(54, 42, 90),
		Text = rgb(246, 242, 255),
		TextDim = rgb(176, 166, 210),
		Pink = rgb(255, 72, 200),
		Cyan = rgb(70, 220, 255),
		Purple = rgb(150, 80, 255),
		Gold = rgb(255, 200, 70),
		Green = rgb(90, 232, 150),
		Red = rgb(255, 80, 96),
		Day = rgb(255, 196, 90),
		Night = rgb(150, 90, 255),
	},
	Fonts = {
		Title = Font.new("rbxasset://fonts/families/Creepster.json"),
		Heading = Font.new("rbxasset://fonts/families/FredokaOne.json"),
		Body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
		Bold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	},
	Radius = 14,
	Tween = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	TweenSlow = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

return Theme
