-- Shop management: stock status, ordering, and the persistent upgrade tree.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CollectibleConfig = require(ReplicatedStorage.Shared.Config.CollectibleConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Components = require(script.Parent.Parent.Components)
local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer

local ShopPanel = {}
ShopPanel.__index = ShopPanel

function ShopPanel.new(root: Frame, onClose: () -> ())
	local self = setmetatable({}, ShopPanel)
	local modal, body = Components.modal(root, "🏪  MY SHOP", UDim2.fromOffset(680, 540), onClose)
	self.Modal = modal

	-- status strip
	local status = Components.panel({
		Size = UDim2.new(1, 0, 0, 92),
		BackgroundColor3 = C.PanelLight,
		Parent = body,
	})
	self.StatusTitle = Create.text({
		Size = UDim2.new(0.6, 0, 0, 26),
		Position = UDim2.fromOffset(16, 12),
		Text = "",
		FontFace = Theme.Fonts.Heading,
		Parent = status,
	})
	self.StockLabel = Create.text({
		Size = UDim2.new(0.6, 0, 0, 18),
		Position = UDim2.fromOffset(16, 42),
		Text = "",
		TextColor3 = C.TextDim,
		Parent = status,
	})
	local stockBar, setStock = Components.bar({
		Size = UDim2.new(0.6, -16, 0, 10),
		Position = UDim2.fromOffset(16, 68),
		Parent = status,
	}, C.Green)
	self.StockBar = stockBar
	self.SetStock = setStock
	local restock = EconomyConfig.Restock
	self.RestockButton = Components.button({
		Text = string.format("📦 ORDER %d · $%d", restock.Units, restock.Units * restock.CostPerUnit),
		Color = C.Green,
		Size = UDim2.fromOffset(220, 52),
		Position = UDim2.new(1, -16, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = status,
		OnClick = function()
			Net.get("Restock"):FireServer()
		end,
	})

	self.CollectionLabel = Create.text({
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 102),
		Text = "",
		TextColor3 = C.Gold,
		Parent = body,
	})

	local scroll = Create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -134),
		Position = UDim2.fromOffset(0, 132),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Purple,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, {
		Create("UIGridLayout", {
			CellSize = UDim2.new(0.5, -8, 0, 120),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Create.padding(2, 2),
	})

	self.Cards = {}
	for i, upgrade in UpgradeConfig.List do
		local card = Components.panel({
			BackgroundColor3 = C.PanelLight,
			LayoutOrder = i,
			Parent = scroll,
		})
		Create.text({
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.fromOffset(12, 12),
			Text = upgrade.Icon,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card,
		})
		Create.text({
			Size = UDim2.new(1, -80, 0, 22),
			Position = UDim2.fromOffset(66, 12),
			Text = upgrade.Name,
			FontFace = Theme.Fonts.Heading,
			Parent = card,
		})
		local level = Create.text({
			Size = UDim2.new(1, -80, 0, 16),
			Position = UDim2.fromOffset(66, 38),
			Text = "",
			TextColor3 = C.Pink,
			Parent = card,
		})
		Create.text({
			Size = UDim2.new(1, -150, 0, 16),
			Position = UDim2.new(0, 14, 1, -28),
			Text = upgrade.Description .. (if upgrade.Category == "Gear" then "  · gear" else ""),
			TextColor3 = C.TextDim,
			FontFace = Theme.Fonts.Body,
			Parent = card,
		})
		local buy = Components.button({
			Text = "",
			Color = C.Pink,
			Size = UDim2.fromOffset(118, 40),
			Position = UDim2.new(1, -12, 1, -12),
			AnchorPoint = Vector2.new(1, 1),
			Parent = card,
			OnClick = function()
				Net.get("PurchaseUpgrade"):FireServer(upgrade.Id)
			end,
		})
		self.Cards[upgrade.Id] = { Level = level, Buy = buy, Upgrade = upgrade }
	end

	for _, attribute in { "Cash", "ShopId", "ShopStock", "ShopMaxStock", "CollectiblesFound" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			self:Refresh()
		end)
	end
	for _, upgrade in UpgradeConfig.List do
		player:GetAttributeChangedSignal("Upg_" .. upgrade.Id):Connect(function()
			self:Refresh()
		end)
	end
	self:Refresh()
	return self
end

function ShopPanel:Refresh()
	local cash = player:GetAttribute("Cash") or 0
	local hasShop = player:GetAttribute("ShopId") ~= nil
	local stock = player:GetAttribute("ShopStock") or 0
	local max = player:GetAttribute("ShopMaxStock") or 0

	if hasShop then
		self.StatusTitle.Text = "Your store is open"
		self.StockLabel.Text = string.format("Stock %d / %d  ·  customers buy 1 item each", stock, max)
		self.SetStock(if max > 0 then stock / max else 0)
		self.StockBar.Visible = true
		self.RestockButton.Visible = true
		-- The server buys a partial order when cash is short (or a free emergency delivery
		-- when the shelves are empty), so the button only needs free shelf space.
		Components.setButtonEnabled(self.RestockButton, stock < max, C.Green)
	else
		self.StatusTitle.Text = "No shop yet"
		self.StockLabel.Text = "Walk into the East Wing and claim an empty store — it's free!"
		self.StockBar.Visible = false
		self.RestockButton.Visible = false
	end

	self.CollectionLabel.Text = string.format(
		"🏆 Rare finds collected: %d / %d   (survive nights to discover more)",
		player:GetAttribute("CollectiblesFound") or 0,
		#CollectibleConfig.Items
	)

	for id, card in self.Cards do
		local level = player:GetAttribute("Upg_" .. id) or 0
		local upgrade = card.Upgrade
		card.Level.Text = string.rep("●", level) .. string.rep("○", upgrade.MaxLevel - level)
		local label = card.Buy:FindFirstChild("Label") :: TextLabel
		if level >= upgrade.MaxLevel then
			label.Text = "MAX"
			Components.setButtonEnabled(card.Buy, false)
		else
			local cost = UpgradeConfig.Cost(id, level)
			label.Text = Format.cash(cost)
			Components.setButtonEnabled(card.Buy, cash >= cost, if upgrade.Category == "Gear" then C.Cyan else C.Pink)
		end
	end
end

function ShopPanel:SetVisible(visible: boolean)
	if visible then
		self:Refresh()
	end
	Components.show(self.Modal, visible)
end

return ShopPanel
