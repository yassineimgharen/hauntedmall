-- Shop ownership, stock and sales. Ownership lasts for the server session; stock and
-- upgrades persist in the owner's profile, so a player's shop follows them between servers.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)

export type Shop = {
	Id: string,
	Model: Model,
	Owner: Player?,
	Slots: { Model },
	LastAttackNotice: number,
	-- Optional absorber for raids (level mechanics, e.g. barricades). Returns true if it
	-- took the hit instead of the stock.
	Shield: ((amount: number) -> boolean)?,
}

local ShopService = {}
ShopService.ShopClaimed = Signal.new() -- (shop, player)
ShopService.ShopReleased = Signal.new() -- (shop)

local shops: { [string]: Shop } = {}
local shopByPlayer: { [Player]: Shop } = {}

local UNOWNED_TRIM = Color3.fromRGB(80, 80, 92)
local FONT_TITLE = Font.new("rbxasset://fonts/families/FredokaOne.json")

local function setTrim(shop: Shop, color: Color3)
	for _, part in (shop.Model:FindFirstChild("Trim") :: Folder):GetChildren() do
		(part :: BasePart).Color = color
		part:SetAttribute("BaseColor", color)
	end
end

local function setSign(shop: Shop, text: string, color: Color3)
	local sign = shop.Model:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("Gui")
	local label = gui and gui:FindFirstChild("Title") :: TextLabel?
	if label then
		label.Text = text
		label.TextColor3 = color
		label.FontFace = FONT_TITLE
	end
end

function ShopService.GetMaxStock(player: Player): number
	return EconomyConfig.BaseMaxStock + ProgressionService.UpgradeBonus(player, "Shelves")
end

local function refreshStock(shop: Shop)
	local stock, max = 0, 0
	if shop.Owner then
		local data = DataService.Get(shop.Owner)
		if data then
			max = ShopService.GetMaxStock(shop.Owner)
			data.Stock = math.clamp(data.Stock, 0, max)
			stock = data.Stock
		end
	end
	shop.Model:SetAttribute("Stock", stock)
	shop.Model:SetAttribute("MaxStock", max)
	if shop.Owner then
		shop.Owner:SetAttribute("ShopStock", stock)
		shop.Owner:SetAttribute("ShopMaxStock", max)
	end

	local visible = if max > 0 then math.ceil(stock / max * #shop.Slots) else 0
	for i, slot in shop.Slots do
		local transparency = if i <= visible then 0 else 1
		for _, part in slot:GetChildren() do
			(part :: BasePart).Transparency = transparency
		end
	end
end

local function claim(shop: Shop, player: Player)
	if shop.Owner then
		Notify.player(player, "This shop already has an owner.", "warning")
		return
	end
	if shopByPlayer[player] then
		Notify.player(player, "You already run a shop on this floor.", "warning")
		return
	end
	if not DataService.Get(player) then
		Notify.player(player, "Still loading your save — try again in a moment.", "warning")
		return
	end

	shop.Owner = player
	shopByPlayer[player] = shop
	local model = shop.Model
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
	player:SetAttribute("ShopId", shop.Id)

	local accent = model:GetAttribute("Accent") :: Color3
	setTrim(shop, accent)
	setSign(shop, string.format("%s's %s", player.DisplayName, model:GetAttribute("CategoryName")), accent)
	local stand = model:FindFirstChild("LeaseStand")
	if stand then
		for _, part in stand:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = 1
			elseif part:IsA("SurfaceGui") then
				part.Enabled = false
			end
		end
	end
	refreshStock(shop)

	Notify.player(
		player,
		"🛍️ The shop is yours! Next: order stock at the 📦 crates in the back corner.",
		"success"
	)
	ProgressionService.MarkTutorial(player, "Claimed")
	MissionEvents.record(player, "ShopClaimed")
	Notify.effect(player, "Purchase")
	ShopService.ShopClaimed:Fire(shop, player)
end

local function release(shop: Shop)
	local owner = shop.Owner
	if owner then
		shopByPlayer[owner] = nil
		if owner.Parent then
			owner:SetAttribute("ShopId", nil)
		end
	end
	shop.Owner = nil
	shop.Model:SetAttribute("OwnerUserId", 0)
	shop.Model:SetAttribute("OwnerName", "")
	setTrim(shop, UNOWNED_TRIM)
	setSign(shop, "FOR LEASE", Color3.fromRGB(200, 200, 210))
	local stand = shop.Model:FindFirstChild("LeaseStand")
	if stand then
		for _, part in stand:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = 0
			elseif part:IsA("SurfaceGui") then
				part.Enabled = true
			end
		end
	end
	refreshStock(shop)
	ShopService.ShopReleased:Fire(shop)
end

function ShopService.Restock(player: Player)
	local shop = shopByPlayer[player]
	local data = DataService.Get(player)
	if not shop or not data then
		Notify.player(player, "Claim a shop first!", "warning")
		return
	end
	local missing = ShopService.GetMaxStock(player) - data.Stock
	if missing <= 0 then
		Notify.player(player, "Your shelves are already full.", "info")
		return
	end
	local restock = EconomyConfig.Restock
	-- Buy a full order, or as many units as the player can afford (never a dead end).
	local units = math.min(restock.Units, missing, math.floor(data.Cash / restock.CostPerUnit))
	if units >= 1 then
		local cost = units * restock.CostPerUnit
		if not ProgressionService.TrySpend(player, cost) then
			return
		end
		data.Stock += units
		refreshStock(shop)
		Notify.player(player, string.format("📦 +%d stock delivered ($%d)", units, cost), "success")
		Notify.effect(player, "Purchase")
		ProgressionService.MarkTutorial(player, "Stocked")
		MissionEvents.record(player, "Restocked")
		return
	end

	-- Can't afford a single unit. If the shelves are also empty, the supplier fronts a free
	-- delivery so the player can never be locked out of earning (cooldown is persisted).
	local now = os.time()
	if data.Stock == 0 and now - (data.LastEmergencyStockAt or 0) >= restock.EmergencyCooldown then
		data.LastEmergencyStockAt = now
		data.Stock += math.min(restock.EmergencyUnits, missing)
		refreshStock(shop)
		Notify.player(
			player,
			"🚚 The supplier fronted you a free delivery — sell it to get back on your feet!",
			"success"
		)
		Notify.effect(player, "Purchase")
		ProgressionService.MarkTutorial(player, "Stocked")
		MissionEvents.record(player, "Restocked")
		return
	end
	Notify.player(
		player,
		string.format("Stock costs $%d per unit — sell what's on your shelves first.", restock.CostPerUnit),
		"warning"
	)
end

-- A customer bought one item. Returns the amount earned (0 if nothing to sell).
function ShopService.Sell(shop: Shop, served: boolean): number
	local owner = shop.Owner
	local data = owner and DataService.Get(owner)
	if not owner or not data or data.Stock <= 0 then
		return 0
	end
	data.Stock -= 1
	local price =
		math.floor(EconomyConfig.BaseSalePrice * (1 + ProgressionService.UpgradeBonus(owner, "Quality")) + 0.5)
	local tip = if served then math.floor(price * EconomyConfig.ServeTipFraction + 0.5) else 0
	ProgressionService.AddCash(owner, price + tip)
	ProgressionService.AddXP(owner, if served then EconomyConfig.XP.Serve else EconomyConfig.XP.Sale)
	ProgressionService.AddStat(owner, "Sales", 1)
	if served then
		ProgressionService.MarkTutorial(owner, "Served")
		MissionEvents.record(owner, "Served")
	end
	refreshStock(shop)
	Notify.effect(owner, "Sale", {
		Position = shop.Model:GetAttribute("P_Counter"),
		Amount = price + tip,
		Tip = tip,
	})
	if data.Stock == 0 then
		Notify.player(owner, "Your shelves are empty! Order more stock.", "warning")
	end
	return price + tip
end

-- Monsters stealing merchandise at night.
function ShopService.Drain(shop: Shop, amount: number)
	if shop.Shield and shop.Shield(amount) then
		return
	end
	local owner = shop.Owner
	local data = owner and DataService.Get(owner)
	if not owner or not data or data.Stock <= 0 then
		return
	end
	data.Stock = math.max(0, data.Stock - amount)
	refreshStock(shop)
	if os.clock() - shop.LastAttackNotice > 8 then
		shop.LastAttackNotice = os.clock()
		Notify.player(owner, "⚠️ Something is raiding your shop!", "danger")
	end
end

-- Free stock for the player's shop (level rewards), capped at shelf capacity.
-- Returns the units actually added (0 without a shop).
function ShopService.AddStock(player: Player, units: number): number
	local shop = ShopService.GetShopOf(player)
	local data = DataService.Get(player)
	if not shop or not data then
		return 0
	end
	local added = math.max(0, math.min(units, ShopService.GetMaxStock(player) - data.Stock))
	data.Stock += added
	refreshStock(shop)
	return added
end

function ShopService.SetShield(shop: Shop, shield: ((amount: number) -> boolean)?)
	shop.Shield = shield
end

function ShopService.GetStock(shop: Shop): number
	return (shop.Model:GetAttribute("Stock") :: number?) or 0
end

function ShopService.GetOwnedShops(): { Shop }
	local list = {}
	for _, shop in shops do
		if shop.Owner then
			table.insert(list, shop)
		end
	end
	return list
end

function ShopService.GetAllShops(): { Shop }
	local list = {}
	for _, shop in shops do
		table.insert(list, shop)
	end
	return list
end

function ShopService.GetShopOf(player: Player): Shop?
	return shopByPlayer[player]
end

function ShopService.Init() end

function ShopService.Start()
	for _, model in CollectionService:GetTagged("Shop") do
		local slots = {}
		for _, slot in (model:FindFirstChild("Products") :: Folder):GetChildren() do
			table.insert(slots, slot :: Model)
		end
		table.sort(slots, function(a, b)
			return (a:GetAttribute("Order") :: number) < (b:GetAttribute("Order") :: number)
		end)
		local shop: Shop = {
			Id = model:GetAttribute("ShopId"),
			Model = model,
			Owner = nil,
			Slots = slots,
			LastAttackNotice = 0,
		}
		shops[shop.Id] = shop
		setTrim(shop, UNOWNED_TRIM)

		local claimPrompt = model:FindFirstChild("ClaimPrompt", true) :: ProximityPrompt
		claimPrompt.Triggered:Connect(function(player)
			claim(shop, player)
		end)
		local restockPrompt = model:FindFirstChild("RestockPrompt", true) :: ProximityPrompt
		restockPrompt.Triggered:Connect(function(player)
			if shop.Owner ~= player then
				Notify.player(player, "This isn't your shop.", "warning")
				return
			end
			ShopService.Restock(player)
		end)
	end

	Net.handle("Restock", 2, 3, function(player)
		ShopService.Restock(player)
	end)

	ProgressionService.UpgradePurchased:Connect(function(player, id)
		local shop = shopByPlayer[player]
		if shop and id == "Shelves" then
			refreshStock(shop)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local shop = shopByPlayer[player]
		if shop then
			release(shop)
		end
	end)
end

return ShopService
