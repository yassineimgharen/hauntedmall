-- Player settings, saved to the profile through a validated remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Components = require(script.Parent.Parent.Components)
local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer

local SettingsPanel = {}
SettingsPanel.__index = SettingsPanel

function SettingsPanel.new(root: Frame, onClose: () -> ())
	local self = setmetatable({}, SettingsPanel)
	local modal, body = Components.modal(root, "⚙️  SETTINGS", UDim2.fromOffset(480, 360), onClose)
	self.Modal = modal
	self.Values = {
		Music = player:GetAttribute("Set_Music") or 0.6,
		Sfx = player:GetAttribute("Set_Sfx") or 0.8,
		ReducedEffects = player:GetAttribute("Set_ReducedEffects") == true,
	}
	self.SaveToken = 0
	Create.list(nil, 14).Parent = body

	local function volumeRow(key: string, caption: string, order: number)
		local row = Components.panel({
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundColor3 = C.PanelLight,
			LayoutOrder = order,
			Parent = body,
		})
		Create.text({
			Size = UDim2.new(0.5, 0, 0, 24),
			Position = UDim2.fromOffset(16, 20),
			Text = caption,
			FontFace = Theme.Fonts.Heading,
			Parent = row,
		})
		local value = Create.text({
			Size = UDim2.fromOffset(60, 24),
			Position = UDim2.new(1, -78, 0, 20),
			AnchorPoint = Vector2.new(1, 0),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = row,
		})
		local function render()
			value.Text = string.format("%d%%", math.floor(self.Values[key] * 100 + 0.5))
		end
		local function step(delta: number)
			self.Values[key] = math.clamp(math.floor((self.Values[key] + delta) * 10 + 0.5) / 10, 0, 1)
			render()
			self:_save()
		end
		Components.button({
			Text = "−",
			Color = C.PanelLighter,
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.new(1, -146, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = row,
			OnClick = function()
				step(-0.1)
			end,
		})
		Components.button({
			Text = "+",
			Color = C.Pink,
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = row,
			OnClick = function()
				step(0.1)
			end,
		})
		render()
	end
	volumeRow("Music", "🎵 Music", 1)
	volumeRow("Sfx", "🔊 Sound effects", 2)

	local fxRow = Components.panel({
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = C.PanelLight,
		LayoutOrder = 3,
		Parent = body,
	})
	Create.text({
		Size = UDim2.new(0.6, 0, 0, 24),
		Position = UDim2.fromOffset(16, 12),
		Text = "✨ Reduced effects",
		FontFace = Theme.Fonts.Heading,
		Parent = fxRow,
	})
	Create.text({
		Size = UDim2.new(0.6, 0, 0, 14),
		Position = UDim2.fromOffset(16, 38),
		Text = "Less flicker — for comfort and low-end devices",
		TextColor3 = C.TextDim,
		FontFace = Theme.Fonts.Body,
		Parent = fxRow,
	})
	local toggle
	toggle = Components.button({
		Text = "",
		Color = C.PanelLighter,
		Size = UDim2.fromOffset(90, 44),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = fxRow,
		OnClick = function()
			self.Values.ReducedEffects = not self.Values.ReducedEffects
			self:_renderToggle(toggle)
			self:_save()
		end,
	})
	self:_renderToggle(toggle)
	return self
end

function SettingsPanel:_renderToggle(toggle: TextButton)
	local on = self.Values.ReducedEffects
	toggle.BackgroundColor3 = if on then C.Green else C.PanelLighter
	local label = toggle:FindFirstChild("Label") :: TextLabel
	label.Text = if on then "ON" else "OFF"
end

-- Debounced: one remote call after the player stops clicking.
function SettingsPanel:_save()
	self.SaveToken += 1
	local token = self.SaveToken
	task.delay(0.6, function()
		if token == self.SaveToken then
			Net.get("SaveSettings"):FireServer(table.clone(self.Values))
		end
	end)
end

function SettingsPanel:SetVisible(visible: boolean)
	Components.show(self.Modal, visible)
end

return SettingsPanel
