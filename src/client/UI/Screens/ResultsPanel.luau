-- Dawn summary: what you did, what you earned, and any rare find.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CollectibleConfig = require(ReplicatedStorage.Shared.Config.CollectibleConfig)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Components = require(script.Parent.Parent.Components)
local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors

local ResultsPanel = {}
ResultsPanel.__index = ResultsPanel

function ResultsPanel.new(root: Frame, onClose: () -> ())
	local self = setmetatable({}, ResultsPanel)
	local modal, body = Components.modal(root, "🌅  SHIFT REPORT", UDim2.fromOffset(520, 520), onClose)
	self.Modal = modal

	self.Title = Create.text({
		Size = UDim2.new(1, 0, 0, 56),
		Text = "NIGHT 1 SURVIVED",
		FontFace = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Gold,
		Parent = body,
	})
	local rows = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 170),
		Position = UDim2.fromOffset(0, 66),
		BackgroundTransparency = 1,
		Parent = body,
	}, { Create.list(nil, 6) })
	self.Rows = {}
	for i, key in { "Kills", "Fuses", "Deaths", "Power" } do
		local row = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = C.PanelLight,
			LayoutOrder = i,
			Parent = rows,
		}, { Create.corner(10) })
		local label = Create.text({
			Size = UDim2.new(0.7, 0, 0, 20),
			Position = UDim2.fromOffset(14, 8),
			Text = "",
			FontFace = Theme.Fonts.Body,
			Parent = row,
		})
		local value = Create.text({
			Size = UDim2.new(0.3, -14, 0, 20),
			Position = UDim2.new(1, -14, 0, 8),
			AnchorPoint = Vector2.new(1, 0),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
		self.Rows[key] = { Label = label, Value = value }
	end

	self.Earned = Create.text({
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 246),
		Text = "",
		TextColor3 = C.Green,
		FontFace = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = body,
	})

	self.Find = Components.panel({
		Size = UDim2.new(1, 0, 0, 84),
		Position = UDim2.fromOffset(0, 290),
		BackgroundColor3 = C.PanelLight,
		Parent = body,
	})
	self.FindIcon = Create.text({
		Size = UDim2.fromOffset(60, 60),
		Position = UDim2.fromOffset(12, 12),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = self.Find,
	})
	self.FindName = Create.text({
		Size = UDim2.new(1, -96, 0, 26),
		Position = UDim2.fromOffset(84, 14),
		Text = "",
		FontFace = Theme.Fonts.Heading,
		Parent = self.Find,
	})
	self.FindRarity = Create.text({
		Size = UDim2.new(1, -96, 0, 18),
		Position = UDim2.fromOffset(84, 46),
		Text = "",
		Parent = self.Find,
	})

	Components.button({
		Text = "BACK TO WORK",
		Color = C.Pink,
		Size = UDim2.fromOffset(220, 50),
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = body,
		OnClick = onClose,
	})
	return self
end

function ResultsPanel:Show(data: { [string]: any })
	self.Title.Text = string.format("NIGHT %d SURVIVED", data.Night or 1)
	local rows = {
		Kills = { "👾 Shadows burned", tostring(data.Kills or 0) },
		Fuses = { "⚡ Fuse boxes repaired", tostring(data.Fuses or 0) },
		Deaths = { "💀 Times knocked out", tostring(data.Deaths or 0) },
		Power = { "💡 Emergency power restored", if data.AllFuses then "YES" else "no" },
	}
	for key, row in rows do
		self.Rows[key].Label.Text = row[1]
		self.Rows[key].Value.Text = row[2]
	end
	self.Earned.Text = string.format("+%s   ·   +%s XP", Format.cash(data.Cash or 0), Format.number(data.XP or 0))

	local item = data.Collectible
	if item then
		local rarity = CollectibleConfig.Rarities[item.Rarity]
		self.FindIcon.Text = item.Icon
		self.FindName.Text = "Rare find: " .. item.Name
		self.FindRarity.Text = string.upper(item.Rarity)
		self.FindRarity.TextColor3 = if rarity then rarity.Color else C.Text
		local stroke = self.Find:FindFirstChildOfClass("UIStroke")
		if stroke and rarity then
			stroke.Color = rarity.Color
			stroke.Transparency = 0
		end
	else
		self.FindIcon.Text = "🔦"
		self.FindName.Text = "No rare find this time"
		self.FindRarity.Text = "Burn more shadows and fix fuses to improve your odds"
		self.FindRarity.TextColor3 = C.TextDim
	end

	Components.show(self.Modal, true)
	self.Earned.TextTransparency = 1
	TweenService:Create(self.Earned, Theme.TweenSlow, { TextTransparency = 0 }):Play()
end

function ResultsPanel:SetVisible(visible: boolean)
	Components.show(self.Modal, visible)
end

return ResultsPanel
