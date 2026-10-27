--!strict
-- Core tuning for the day/night loop. All durations are in seconds.

local GameConfig = {
	Phases = {
		Intermission = 12, -- first boot only, gives players time to load in
		Day = 150,
		Dusk = 9,
		Night = 120,
		Dawn = 12,
	},

	-- Shortened loop for Studio playtests. Enable with the Workspace attribute
	-- "FastPhases" = true before pressing Play (see docs/TESTING.md).
	FastPhases = {
		Intermission = 5,
		Day = 45,
		Dusk = 9,
		Night = 60,
		Dawn = 12,
	},

	PlayerMaxHealth = 100,
	AutosaveInterval = 60,
}

export type Phase = "Intermission" | "Day" | "Dusk" | "Night" | "Dawn"

return GameConfig
