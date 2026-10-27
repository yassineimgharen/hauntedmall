-- Studio-only test store. Appears only when the server reports StoreMode "Test" (which
-- MonetizationService allows solely inside Roblox Studio). Buttons go through the same
-- RequestPurchase remote the real store UI will use; the server simulates the receipt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Components = require(script.Parent.Parent.Components)
local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer

local DevStorePanel = {}

function DevStorePanel.mount(root: Frame)
	if ReplicatedStorage:GetAttribute("StoreMode") ~= "Test" then
		return
	end
	local request = Net.get("RequestPurchase")

	local products = {}
	for _, product in MonetizationConfig.Products do
		table.insert(products, product)
	end
	table.sort(products, function(a, b)
		return a.DisplayPrice < b.DisplayPrice
	end)
	local passes = {}
	for _, pass in MonetizationConfig.GamePasses do
		table.insert(passes, pass)
	end

	local rows = #products + #passes
	local panel = Components.panel({
		Name = "DevStore",
		Size = UDim2.fromOffset(330, 92 + rows * 46),
		Position = UDim2.new(0, 16, 1, -78),
		AnchorPoint = Vector2.new(0, 1),
		Visible = false,
		ZIndex = 8,
		Parent = root,
	})
	Create.text({
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 10),
		Text = "🧪 STUDIO TEST STORE",
		TextColor3 = C.Gold,
		FontFace = Theme.Fonts.Heading,
		Parent = panel,
	})
	Create.text({
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.fromOffset(12, 34),
		Text = "Simulated — no Robux. Scenarios: Workspace StoreTest_*",
		TextColor3 = C.TextDim,
		FontFace = Theme.Fonts.Body,
		Parent = panel,
	})
	local list = Create("Frame", {
		Size = UDim2.new(1, -24, 1, -64),
		Position = UDim2.fromOffset(12, 58),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { Create.list(nil, 6) })

	for i, product in products do
		Components.button({
			Text = string.format(
				"%s · +%s  (R$%d)",
				product.Name,
				Format.cash(product.Grant.Cash or 0),
				product.DisplayPrice
			),
			Color = C.Green,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = i,
			Parent = list,
			OnClick = function()
				request:FireServer("Product", product.Key)
			end,
		})
	end
	for i, pass in passes do
		local button = Components.button({
			Text = "",
			Color = C.Purple,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = #products + i,
			Parent = list,
			OnClick = function()
				request:FireServer("GamePass", pass.Key)
			end,
		})
		local function render()
			local owned = player:GetAttribute("Pass_" .. pass.Key) == true
			local label = button:FindFirstChild("Label") :: TextLabel
			label.Text =
				string.format("%s  (R$%d) — %s", pass.Name, pass.DisplayPrice, if owned then "OWNED" else "not owned")
		end
		player:GetAttributeChangedSignal("Pass_" .. pass.Key):Connect(render)
		render()
	end

	Components.button({
		Text = "🧪 TEST STORE",
		Color = C.Gold,
		Size = UDim2.fromOffset(150, 36),
		Position = UDim2.new(0, 16, 1, -34),
		AnchorPoint = Vector2.new(0, 1),
		Parent = root,
		OnClick = function()
			panel.Visible = not panel.Visible
		end,
	})
end

return DevStorePanel
