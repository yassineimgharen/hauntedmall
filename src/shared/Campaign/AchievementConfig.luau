--!strict
-- Achievements: one-time rewards for feats in the campaign. Pure data; CampaignLogic
-- decides which are earned (unlockAchievements) and MissionService pays them, once per
-- player, saved in data.Campaign.Achievements. Rules read saved campaign progress only:
--   Level    = "L08"       that level has been cleared
--   Optional = "L08/mine"  that optional objective was completed (OptionalDone key)
--   Chapter  = 2           that chapter's finale was cleared

export type Rule = { Level: string?, Optional: string?, Chapter: number? }
export type Achievement = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string,
	Cash: number,
	XP: number,
	Rule: Rule,
}

local AchievementConfig = {}

AchievementConfig.List = {
	{
		Id = "QueenSlayer",
		Name = "Queen Slayer",
		Description = "Defeat the Shadow Queen and finish Chapter 1.",
		Icon = "👑",
		Cash = 300,
		XP = 300,
		Rule = { Chapter = 1 },
	},
	{
		Id = "KitchenExorcist",
		Name = "Kitchen Exorcist",
		Description = "Exorcise 2 possessed appliances yourself (Level 8).",
		Icon = "🍳",
		Cash = 150,
		XP = 150,
		Rule = { Optional = "L08/myexorcisms" },
	},
	{
		Id = "Firefighter",
		Name = "Firefighter",
		Description = "Put out 12 fires in one night (Level 9).",
		Icon = "🧯",
		Cash = 150,
		XP = 150,
		Rule = { Optional = "L09/fires" },
	},
	{
		Id = "SharpEye",
		Name = "Return to Sender",
		Description = "Sort every delivery without a single wrong call (Level 10).",
		Icon = "📦",
		Cash = 150,
		XP = 150,
		Rule = { Optional = "L10/nowrong" },
	},
	{
		Id = "ColdFeet",
		Name = "Cold Feet",
		Description = "Escape the Frost Wraith without ever freezing solid (Level 11).",
		Icon = "❄️",
		Cash = 200,
		XP = 200,
		Rule = { Optional = "L11/nofreeze" },
	},
	{
		Id = "MazeRunner",
		Name = "Maze Runner",
		Description = "Escape the shifting maze with a minute to spare (Level 12).",
		Icon = "🧭",
		Cash = 150,
		XP = 150,
		Rule = { Optional = "L12/escaped" },
	},
	{
		Id = "CleanLungs",
		Name = "Clean Lungs",
		Description = "Survive the gas outbreak without ever choking (Level 13).",
		Icon = "😷",
		Cash = 200,
		XP = 200,
		Rule = { Optional = "L13/nochoke" },
	},
	{
		Id = "ChefsKiss",
		Name = "Chef's Kiss",
		Description = "Serve the Gorging Chef 2 laced dishes yourself (Level 14).",
		Icon = "🧪",
		Cash = 250,
		XP = 250,
		Rule = { Optional = "L14/feeder" },
	},
	{
		Id = "FoodCourtHero",
		Name = "Food Court Hero",
		Description = "Defeat the Gorging Chef and finish Chapter 2.",
		Icon = "👨‍🍳",
		Cash = 500,
		XP = 500,
		Rule = { Chapter = 2 },
	},
} :: { Achievement }

AchievementConfig.ById = {} :: { [string]: Achievement }
for _, achievement in AchievementConfig.List do
	AchievementConfig.ById[achievement.Id] = achievement
end

return AchievementConfig
