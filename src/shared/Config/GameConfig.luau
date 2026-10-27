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

	-- Studio playtests read/write a separate DataStore so testing can never touch real
	-- player saves, even when "Studio Access to API Services" is on in the live experience.
	StudioDataStoreSuffix = "_Studio",
}

export type Phase = "Intermission" | "Day" | "Dusk" | "Night" | "Dawn"

return GameConfig
