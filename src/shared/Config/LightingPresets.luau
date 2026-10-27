--!strict
-- Lighting looks for each phase. The server applies "Day" once at boot; clients tween
-- between presets locally so transitions are smooth and cost no network traffic.

local rgb = Color3.fromRGB

export type Preset = {
	Lighting: { [string]: any },
	Atmosphere: { [string]: any },
	ColorCorrection: { [string]: any },
	Bloom: { [string]: any },
	SunRays: { [string]: any },
}

-- Day: warm early-afternoon sun (golden colour shift) so dome ribs cast long shadows and the
-- marble picks up warm highlights. Lower ambient than before = more depth and contrast.
-- Night: moonlit violet base kept readable; colour comes from tagged neon and coloured
-- uplights (NightLight) rather than from heavy fog or bloom.
local LightingPresets: { [string]: Preset } = {
	Day = {
		Lighting = {
			ClockTime = 13.8, -- ~52° sun: light falls through the dome opening onto the fountain
			Brightness = 3,
			Ambient = rgb(92, 82, 78),
			OutdoorAmbient = rgb(132, 116, 104),
			ColorShift_Top = rgb(255, 214, 168),
			ColorShift_Bottom = rgb(60, 40, 30),
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 1,
			ExposureCompensation = 0.1,
		},
		Atmosphere = {
			Density = 0.26,
			Offset = 0.15,
			Color = rgb(232, 198, 156),
			Decay = rgb(150, 112, 86),
			Glare = 0.4,
			Haze = 1.4,
		},
		ColorCorrection = {
			TintColor = rgb(255, 244, 230),
			Saturation = 0.12,
			Contrast = 0.12,
			Brightness = 0,
		},
		Bloom = { Intensity = 0.4, Size = 24, Threshold = 1.8 },
		SunRays = { Intensity = 0.08, Spread = 0.55 },
	},

	Night = {
		Lighting = {
			ClockTime = 0.2,
			Brightness = 1,
			Ambient = rgb(44, 30, 86),
			OutdoorAmbient = rgb(66, 46, 128),
			ColorShift_Top = rgb(140, 120, 255),
			ColorShift_Bottom = rgb(40, 10, 60),
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 1,
			ExposureCompensation = 0.3,
		},
		Atmosphere = {
			Density = 0.36,
			Offset = 0.2,
			Color = rgb(84, 52, 172),
			Decay = rgb(30, 18, 84),
			Glare = 0,
			Haze = 1.8,
		},
		ColorCorrection = {
			TintColor = rgb(208, 198, 255),
			Saturation = 0.18,
			Contrast = 0.22,
			Brightness = 0,
		},
		Bloom = { Intensity = 0.85, Size = 28, Threshold = 1.1 },
		SunRays = { Intensity = 0, Spread = 0.55 },
	},
}

return LightingPresets
