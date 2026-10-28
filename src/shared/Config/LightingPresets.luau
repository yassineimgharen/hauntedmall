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

	-- Blackout (Night 2): the mall's own lights are dead. Near-black but not pitch black, so
	-- silhouettes still read; flashlights, emergency lamps, eyes and re-powered zones glow.
	Blackout = {
		Lighting = {
			ClockTime = 0.2,
			Brightness = 0.25,
			Ambient = rgb(16, 12, 30),
			OutdoorAmbient = rgb(24, 18, 46),
			ColorShift_Top = rgb(90, 90, 160),
			ColorShift_Bottom = rgb(10, 4, 20),
			EnvironmentDiffuseScale = 0.2,
			EnvironmentSpecularScale = 0.6,
			ExposureCompensation = 0,
		},
		Atmosphere = {
			Density = 0.48,
			Offset = 0.1,
			Color = rgb(26, 18, 52),
			Decay = rgb(8, 6, 20),
			Glare = 0,
			Haze = 2.6,
		},
		ColorCorrection = {
			TintColor = rgb(196, 196, 236),
			Saturation = -0.1,
			Contrast = 0.3,
			Brightness = -0.02,
		},
		Bloom = { Intensity = 1, Size = 24, Threshold = 0.9 },
		SunRays = { Intensity = 0, Spread = 0.55 },
	},

	-- Hunt (Night 5, the Stalker): red emergency lighting. Readable, but every shadow could
	-- be it.
	Hunt = {
		Lighting = {
			ClockTime = 0.2,
			Brightness = 0.5,
			Ambient = rgb(70, 18, 24),
			OutdoorAmbient = rgb(60, 20, 30),
			ColorShift_Top = rgb(255, 80, 80),
			ColorShift_Bottom = rgb(40, 0, 10),
			EnvironmentDiffuseScale = 0.3,
			EnvironmentSpecularScale = 0.8,
			ExposureCompensation = 0.1,
		},
		Atmosphere = {
			Density = 0.42,
			Offset = 0.15,
			Color = rgb(90, 20, 30),
			Decay = rgb(30, 4, 10),
			Glare = 0,
			Haze = 2.2,
		},
		ColorCorrection = {
			TintColor = rgb(255, 196, 196),
			Saturation = -0.05,
			Contrast = 0.28,
			Brightness = -0.01,
		},
		Bloom = { Intensity = 0.9, Size = 24, Threshold = 1 },
		SunRays = { Intensity = 0, Spread = 0.55 },
	},

	-- Queen (Night 7, boss): deep royal violet with a sickly green edge.
	Queen = {
		Lighting = {
			ClockTime = 0.2,
			Brightness = 0.8,
			Ambient = rgb(52, 22, 84),
			OutdoorAmbient = rgb(40, 60, 50),
			ColorShift_Top = rgb(190, 90, 255),
			ColorShift_Bottom = rgb(20, 60, 30),
			EnvironmentDiffuseScale = 0.4,
			EnvironmentSpecularScale = 1,
			ExposureCompensation = 0.2,
		},
		Atmosphere = {
			Density = 0.4,
			Offset = 0.2,
			Color = rgb(70, 30, 120),
			Decay = rgb(20, 50, 30),
			Glare = 0,
			Haze = 2,
		},
		ColorCorrection = {
			TintColor = rgb(220, 205, 255),
			Saturation = 0.2,
			Contrast = 0.25,
			Brightness = 0,
		},
		Bloom = { Intensity = 1, Size = 30, Threshold = 1 },
		SunRays = { Intensity = 0, Spread = 0.55 },
	},
}

return LightingPresets
