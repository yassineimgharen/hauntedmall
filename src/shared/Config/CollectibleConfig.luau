--!strict
-- Rare merchandise found after surviving a night. Earned through play only — never sold
-- as random paid boxes.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Legendary"

export type Collectible = {
	Id: string,
	Name: string,
	Rarity: Rarity,
	Icon: string,
}

local CollectibleConfig = {
	Rarities = {
		Common = { Weight = 60, Color = Color3.fromRGB(190, 200, 215) },
		Uncommon = { Weight = 28, Color = Color3.fromRGB(90, 230, 140) },
		Rare = { Weight = 10, Color = Color3.fromRGB(80, 170, 255) },
		Legendary = { Weight = 2, Color = Color3.fromRGB(255, 190, 60) },
	},

	Items = {
		{ Id = "GhostPlush", Name = "Ghost Plush", Rarity = "Common", Icon = "👻" },
		{ Id = "NeonCassette", Name = "Neon Cassette", Rarity = "Common", Icon = "📼" },
		{ Id = "CursedCoupon", Name = "Cursed Coupon", Rarity = "Uncommon", Icon = "🎟️" },
		{ Id = "MoonlitSneakers", Name = "Moonlit Sneakers", Rarity = "Uncommon", Icon = "👟" },
		{ Id = "WardensKeyring", Name = "Warden's Keyring", Rarity = "Rare", Icon = "🗝️" },
		{ Id = "GoldenRegister", Name = "Golden Register", Rarity = "Legendary", Icon = "💰" },
	} :: { Collectible },
}

function CollectibleConfig.DropChance(kills: number, fuses: number): number
	return math.min(0.35 + kills * 0.05 + fuses * 0.1, 0.9)
end

return CollectibleConfig
