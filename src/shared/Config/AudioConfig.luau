--!strict
-- Sound asset references. "rbxasset://" paths ship with the Roblox client.
-- Entries set to "" are placeholders: pick properly licensed tracks from the Creator Store
-- (filter by Roblox-uploaded / free-to-use audio) and paste their rbxassetid:// here.
-- Empty entries are skipped silently, so the game runs without them.

local AudioConfig = {
	Music = {
		Day = "",
		Night = "",
	},
	Ambience = {
		MallDay = "",
		MallNight = "",
	},
	Sfx = {
		UIClick = "rbxasset://sounds/electronicpingshort.wav",
		Purchase = "rbxasset://sounds/electronicpingshort.wav",
		LevelUp = "rbxasset://sounds/electronicpingshort.wav",
		PowerDown = "",
		PowerUp = "",
		MonsterSpawn = "",
		MonsterHit = "",
		PlayerHurt = "",
	},
	Volumes = {
		Music = 0.35,
		Ambience = 0.4,
		Sfx = 0.6,
	},
}

return AudioConfig
