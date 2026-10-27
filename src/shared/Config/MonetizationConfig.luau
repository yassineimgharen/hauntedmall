--!strict
-- Monetization plan (Phase 5). NOTHING here is live: Enabled is false and every Id is 0.
-- Fill in real IDs from the Creator Dashboard only after the owner reviews and approves them.
-- Rule: paid items add convenience, customization or cosmetics — never power over free players.

local MonetizationConfig = {
	Enabled = false,

	GamePasses = {
		VIP = { Id = 0, Price = 99, Description = "VIP name tag, exclusive shop decorations, +1 daily mission reroll" },
		ShopThemes = {
			Id = 0,
			Price = 149,
			Description = "Premium shop themes (Neon Noir, Moonlit Boutique, Retro Arcade)",
		},
		DecorSlots = { Id = 0, Price = 199, Description = "Extra decoration slots in your shop" },
		CharacterEffects = { Id = 0, Price = 249, Description = "Premium character trails and night-survival effects" },
		EmotePack = { Id = 0, Price = 79, Description = "Additional emote pack" },
		FlashlightSkins = { Id = 0, Price = 99, Description = "Cosmetic flashlight skins (no stat changes)" },
	},

	DeveloperProducts = {
		CashSmall = { Id = 0, Price = 29, Grant = { Cash = 250 } },
		CashMedium = { Id = 0, Price = 99, Grant = { Cash = 1000 } },
		CashLarge = { Id = 0, Price = 299, Grant = { Cash = 3500 } },
		CustomerRush = { Id = 0, Price = 49, Grant = { BoostMinutes = 15 } },
	},
}

return MonetizationConfig
