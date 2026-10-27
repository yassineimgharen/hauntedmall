--!strict
-- Persistent upgrades bought with in-game cash. Never sold for Robux (no pay-to-win).

export type Upgrade = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string,
	Category: "Shop" | "Gear",
	MaxLevel: number,
	BaseCost: number,
	CostGrowth: number,
	PerLevel: number,
}

local List: { Upgrade } = {
	{
		Id = "Shelves",
		Name = "Bigger Shelves",
		Description = "+10 max stock",
		Icon = "📦",
		Category = "Shop",
		MaxLevel = 5,
		BaseCost = 120,
		CostGrowth = 1.9,
		PerLevel = 10,
	},
	{
		Id = "Quality",
		Name = "Premium Products",
		Description = "+15% sale price",
		Icon = "⭐",
		Category = "Shop",
		MaxLevel = 5,
		BaseCost = 180,
		CostGrowth = 1.9,
		PerLevel = 0.15,
	},
	{
		Id = "Appeal",
		Name = "Window Displays",
		Description = "+12% customer traffic",
		Icon = "🪟",
		Category = "Shop",
		MaxLevel = 5,
		BaseCost = 150,
		CostGrowth = 1.9,
		PerLevel = 0.12,
	},
	{
		Id = "Lens",
		Name = "Focused Lens",
		Description = "+20% flashlight damage",
		Icon = "🔦",
		Category = "Gear",
		MaxLevel = 5,
		BaseCost = 140,
		CostGrowth = 1.9,
		PerLevel = 0.2,
	},
	{
		Id = "Battery",
		Name = "Battery Pack",
		Description = "+25% battery capacity",
		Icon = "🔋",
		Category = "Gear",
		MaxLevel = 5,
		BaseCost = 130,
		CostGrowth = 1.9,
		PerLevel = 0.25,
	},
}

local ById: { [string]: Upgrade } = {}
for _, upgrade in List do
	ById[upgrade.Id] = upgrade
end

local UpgradeConfig = {
	List = List,
	ById = ById,
}

function UpgradeConfig.Cost(id: string, currentLevel: number): number
	local upgrade = ById[id]
	return math.floor(upgrade.BaseCost * upgrade.CostGrowth ^ currentLevel)
end

return UpgradeConfig
