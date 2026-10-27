--!strict
-- Economy tuning. Values are first-pass and meant to be balanced from playtest data.
-- Target: a new player can afford their first upgrade after one day + one night.

local EconomyConfig = {
	StartingCash = 150,

	Restock = {
		Units = 10, -- units bought per order
		CostPerUnit = 3,
		-- Safety net: a shop with empty shelves whose owner can't afford even one unit gets a
		-- free delivery, at most once per cooldown (persisted, so rejoining doesn't reset it).
		EmergencyUnits = 10,
		EmergencyCooldown = 600,
	},

	TutorialBonus = 100, -- one-time cash for finishing the four day goals

	BaseMaxStock = 20,
	BaseSalePrice = 8,
	ServeTipFraction = 0.5, -- bonus fraction of the sale when the owner serves in person
	AutoCheckoutDelay = 7, -- seconds a customer waits at the register before self-checkout

	Customers = {
		BaseInterval = 9, -- seconds between customers for one shop, before Appeal upgrades
		FirstCustomerDelay = 3,
		MaxPerShop = 2,
		MaxTotal = 10,
		WalkSpeed = 13,
	},

	Night = {
		SurviveBonus = 80,
		PerKill = 10,
		PerFuse = 40,
		AllFusesBonus = 100,
		ScalingPerNight = 0.15, -- reward multiplier growth per night survived on this server
	},

	XP = {
		Sale = 2,
		Serve = 3,
		Kill = 6,
		Fuse = 15,
		Survive = 40,
	},

	MaxLevel = 100,

	Categories = {
		{ Id = "Toys", Name = "Toy Shop", Icon = "🧸" },
		{ Id = "Apparel", Name = "Boutique", Icon = "👕" },
		{ Id = "Gadgets", Name = "Gadget Hub", Icon = "🎮" },
	},
}

function EconomyConfig.XPForLevel(level: number): number
	return math.floor(100 * level ^ 1.35)
end

function EconomyConfig.LevelUpCash(level: number): number
	return 50 * level
end

return EconomyConfig
