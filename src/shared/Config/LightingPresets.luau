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

local LightingPresets: { [string]: Preset } = {
	Day = {
		Lighting = {
			ClockTime = 13.6,
			Brightness = 2.4,
			Ambient = rgb(108, 98, 92),
			OutdoorAmbient = rgb(150, 138, 128),
			ColorShift_Top = rgb(255, 236, 210),
			EnvironmentDiffuseScale = 0.7,
			EnvironmentSpecularScale = 0.8,
			ExposureCompensation = 0.15,
		},
		Atmosphere = {
			Density = 0.22,
			Offset = 0.1,
			Color = rgb(214, 190, 160),
			Decay = rgb(140, 110, 90),
			Glare = 0.35,
			Haze = 1,
		},
		ColorCorrection = {
			TintColor = rgb(255, 248, 238),
			Saturation = 0.15,
			Contrast = 0.08,
			Brightness = 0.02,
		},
		Bloom = { Intensity = 0.55, Size = 24, Threshold = 1.5 },
		SunRays = { Intensity = 0.06, Spread = 0.6 },
	},

	Night = {
		Lighting = {
			ClockTime = 0.3,
			Brightness = 0.7,
			Ambient = rgb(46, 30, 82),
			OutdoorAmbient = rgb(62, 42, 116),
			ColorShift_Top = rgb(150, 110, 255),
			EnvironmentDiffuseScale = 0.45,
			EnvironmentSpecularScale = 1,
			ExposureCompensation = 0.35,
		},
		Atmosphere = {
			Density = 0.42,
			Offset = 0,
			Color = rgb(92, 54, 168),
			Decay = rgb(36, 18, 84),
			Glare = 0,
			Haze = 2.4,
		},
		ColorCorrection = {
			TintColor = rgb(214, 196, 255),
			Saturation = 0.28,
			Contrast = 0.2,
			Brightness = 0,
		},
		Bloom = { Intensity = 1.1, Size = 30, Threshold = 0.95 },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
}

return LightingPresets
