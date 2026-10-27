--!strict
-- Central monetization catalog. The server, the store UI and the Studio test mode all read
-- from here; nothing else defines products.
--
-- SAFETY:
--   * Enabled = false → no real purchase prompts are ever shown. Turn it on only after every
--     product has been created in the Creator Dashboard, its Id pasted below, and approved.
--   * Id = 0 means "not created yet"; such items can never be prompted for real.
--   * DisplayPrice is a fallback label only. Once Ids exist, the store UI shows the live price
--     from MarketplaceService:GetProductInfo so players always see the real amount.
--   * TestMode only works inside Roblox Studio (enforced in MonetizationService). Simulated
--     purchases use a separate ledger (TestReceipts) and the Studio-only DataStore.
--
-- Design rules: paid items are cosmetics or convenience. Cash packs only accelerate what
-- free players earn by playing; no purchase grants anything free players cannot get.

export type Grant = {
	Cash: number?, -- more grant kinds (themes, cosmetics, emotes) arrive in later phases
}

export type Product = {
	Key: string,
	Id: number,
	DisplayPrice: number,
	Name: string,
	Description: string,
	Category: "Currency" | "Bundle" | "Seasonal",
	Grant: Grant,
}

export type GamePass = {
	Key: string,
	Id: number,
	DisplayPrice: number,
	Name: string,
	Description: string,
	Benefits: { string },
}

local Products: { [string]: Product } = {
	CashSmall = {
		Key = "CashSmall",
		Id = 0,
		DisplayPrice = 29,
		Name = "Small Cash Pack",
		Description = "$500 to spend on stock and upgrades.",
		Category = "Currency",
		Grant = { Cash = 500 },
	},
	CashMedium = {
		Key = "CashMedium",
		Id = 0,
		DisplayPrice = 79,
		Name = "Medium Cash Pack",
		Description = "$1,500 to spend on stock and upgrades.",
		Category = "Currency",
		Grant = { Cash = 1500 },
	},
	CashLarge = {
		Key = "CashLarge",
		Id = 0,
		DisplayPrice = 199,
		Name = "Large Cash Pack",
		Description = "$4,000 to spend on stock and upgrades.",
		Category = "Currency",
		Grant = { Cash = 4000 },
	},
	CashMega = {
		Key = "CashMega",
		Id = 0,
		DisplayPrice = 399,
		Name = "Mega Cash Pack",
		Description = "$9,000 to spend on stock and upgrades.",
		Category = "Currency",
		Grant = { Cash = 9000 },
	},
}

local GamePasses: { [string]: GamePass } = {
	VIP = {
		Key = "VIP",
		Id = 0,
		DisplayPrice = 199,
		Name = "VIP Membership",
		Description = "Permanent VIP status in every server.",
		Benefits = {
			"VIP name tag and chat tag",
			"Exclusive VIP aura effect",
			"Exclusive shop decorations",
			"VIP lounge access",
			"Special VIP emotes",
		},
	},
}

local MonetizationConfig = {
	Enabled = false,
	TestMode = true,

	Products = Products,
	GamePasses = GamePasses,

	-- Receipt ledger housekeeping. Roblox only re-delivers recent receipts, so very old ids
	-- can be pruned once the ledger grows; recent ones are always kept.
	Ledger = {
		MaxReceipts = 300,
		RetentionDays = 60,
		MaxHistory = 50,
	},
}

local productsById: { [number]: Product } = {}
for _, product in Products do
	if product.Id ~= 0 then
		productsById[product.Id] = product
	end
end

function MonetizationConfig.productById(id: number): Product?
	return productsById[id]
end

function MonetizationConfig.passById(id: number): GamePass?
	for _, pass in GamePasses do
		if pass.Id ~= 0 and pass.Id == id then
			return pass
		end
	end
	return nil
end

-- Catalog sanity checks, run by the server at startup. Returns a list of problems.
function MonetizationConfig.validate(): { string }
	local problems = {}
	local seen: { [number]: string } = {}
	local function checkId(kind: string, key: string, id: number)
		if id < 0 or id ~= math.floor(id) then
			table.insert(problems, string.format("%s %s has an invalid Id (%s)", kind, key, tostring(id)))
		elseif id ~= 0 then
			if seen[id] then
				table.insert(problems, string.format("%s %s reuses Id %d (also %s)", kind, key, id, seen[id]))
			end
			seen[id] = key
		end
	end
	for key, product in Products do
		if product.Key ~= key then
			table.insert(problems, "Product " .. key .. " has mismatched Key " .. product.Key)
		end
		checkId("Product", key, product.Id)
		local cash = product.Grant.Cash
		if cash ~= nil and (cash <= 0 or cash ~= math.floor(cash)) then
			table.insert(problems, "Product " .. key .. " grants invalid cash")
		end
	end
	for key, pass in GamePasses do
		if pass.Key ~= key then
			table.insert(problems, "GamePass " .. key .. " has mismatched Key " .. pass.Key)
		end
		checkId("GamePass", key, pass.Id)
	end
	return problems
end

return MonetizationConfig
