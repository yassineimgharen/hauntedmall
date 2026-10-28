-- Vault keypad (Level 5 day). Shows the colour order printed on the keypad and the card
-- digits found so far; submits the code through the validated SubmitCode remote.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Components = require(script.Parent.Parent.Components)
local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors
local ICONS = { Red = "🟥", Green = "🟩", Blue = "🟦" }

local KeypadPanel = {}
KeypadPanel.__index = KeypadPanel

function KeypadPanel.new(root: Frame, onClose: () -> ())
	local self = setmetatable({}, KeypadPanel)
	local modal, body = Components.modal(root, "🔢  VAULT KEYPAD", UDim2.fromOffset(380, 520), onClose)
	self.Modal = modal
	self.Code = ""
	self.Order = {} :: { string }
	self.OnClose = onClose

	self.Hint = Create.text({
		Size = UDim2.new(1, 0, 0, 44),
		Text = "",
		TextScaled = false,
		TextSize = 16,
		TextWrapped = true,
		FontFace = Theme.Fonts.Body,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = body,
	})
	self.Display = Create.text({
		Size = UDim2.new(1, 0, 0, 56),
		Position = UDim2.fromOffset(0, 48),
		Text = "_ _ _",
		FontFace = Theme.Fonts.Heading,
		TextColor3 = C.Cyan,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = body,
	})
	local grid = Create("Frame", {
		Size = UDim2.new(1, 0, 1, -116),
		Position = UDim2.fromOffset(0, 112),
		BackgroundTransparency = 1,
		Parent = body,
	}, {
		Create("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -8, 0, 62),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "ENTER" }
	for i, key in keys do
		Components.button({
			Text = key,
			Color = if key == "ENTER" then C.Green elseif key == "⌫" then C.Red else C.PanelLighter,
			LayoutOrder = i,
			Parent = grid,
			OnClick = function()
				self:_press(key)
			end,
		})
	end
	return self
end

function KeypadPanel:_render()
	local slots = {}
	for i = 1, 3 do
		slots[i] = string.sub(self.Code, i, i)
		if slots[i] == "" then
			slots[i] = "_"
		end
	end
	self.Display.Text = table.concat(slots, " ")
	local found = {}
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, ReplicatedStorage:GetAttribute("VaultCards") or "{}")
	if ok and type(decoded) == "table" then
		found = decoded
	end
	local order, known = {}, {}
	for _, color in self.Order do
		table.insert(order, ICONS[color] or "?")
		table.insert(
			known,
			(ICONS[color] or "?") .. " " .. (if found[color] ~= nil then tostring(found[color]) else "?")
		)
	end
	self.Hint.Text =
		string.format("Order: %s\nCards found: %s", table.concat(order, " → "), table.concat(known, "   "))
end

function KeypadPanel:_press(key: string)
	if key == "⌫" then
		self.Code = string.sub(self.Code, 1, -2)
	elseif key == "ENTER" then
		if #self.Code == 3 then
			Net.get("SubmitCode"):FireServer(self.Code)
			self.OnClose()
		end
		return
	elseif #self.Code < 3 then
		self.Code ..= key
	end
	self:_render()
end

function KeypadPanel:Open(order: { string })
	self.Order = order
	self.Code = ""
	self:_render()
end

function KeypadPanel:SetVisible(visible: boolean)
	if visible then
		self:_render()
	end
	Components.show(self.Modal, visible)
end

return KeypadPanel
