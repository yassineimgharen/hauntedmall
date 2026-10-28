-- Status meters for level hazards, driven by server-set player attributes (0..1):
--   Meter_Cold   🥶 frostbite (Level 11)       Meter_Gas  ☣️ toxic gas (Level 13)
--   Meter_Signal 📡 anomaly scanner (Level 12)
-- A missing attribute hides its bar. Cold and gas also tint the screen edges as they
-- rise. Purely visual: every effect of a meter is decided on the server.

local Players = game:GetService("Players")

local Components = require(script.Parent.Parent.UI.Components)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)

local MeterController = {}

local C = Theme.Colors
local METERS = {
	{
		Name = "Cold",
		Label = "🥶 COLD",
		Full = "❄️ FREEZING! Get to a heat lamp!",
		Color = C.Cyan,
		Tint = Color3.fromRGB(170, 220, 255),
	},
	{
		Name = "Gas",
		Label = "☣️ TOXIC GAS",
		Full = "☣️ CHOKING! Find clean air!",
		Color = C.Green,
		Tint = Color3.fromRGB(110, 255, 90),
	},
	{ Name = "Signal", Label = "📡 ANOMALY SIGNAL", Full = "📡 RIGHT HERE! Look around!", Color = C.Gold },
}

local player = Players.LocalPlayer

local function edgeTint(parent: Instance, rotation: number): Frame
	local frame = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = parent,
	})
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.22, 1),
		NumberSequenceKeypoint.new(0.78, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	gradient.Parent = frame
	return frame
end

function MeterController.Start()
	local gui = Create("ScreenGui", {
		Name = "Meters",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 2,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local tints = { edgeTint(gui, 0), edgeTint(gui, 90) }
	local stack = Create("Frame", {
		Size = UDim2.fromOffset(280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 0, 1, -178),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Create.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center).Parent = stack

	local rows = {}
	for order, meter in METERS do
		local panel = Components.panel({
			Size = UDim2.fromOffset(280, 52),
			LayoutOrder = order,
			Visible = false,
			Parent = stack,
		})
		local label = Create.text({
			Size = UDim2.new(1, -20, 0, 20),
			Position = UDim2.fromOffset(10, 5),
			Text = meter.Label,
			FontFace = Theme.Fonts.Heading,
			TextColor3 = meter.Color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = panel,
		})
		local _, setBar = Components.bar({
			Size = UDim2.new(1, -20, 0, 14),
			Position = UDim2.fromOffset(10, 30),
			Parent = panel,
		}, meter.Color)
		rows[meter.Name] = { Panel = panel, Label = label, Set = setBar, Meter = meter }
	end

	local function render()
		local tintColor, tintAmount = nil, 0
		for name, row in rows do
			local value = player:GetAttribute("Meter_" .. name)
			row.Panel.Visible = type(value) == "number"
			if type(value) == "number" then
				local v = math.clamp(value, 0, 1)
				row.Set(v, true)
				row.Label.Text = if v >= 0.99 then row.Meter.Full else row.Meter.Label
				if row.Meter.Tint and v > tintAmount then
					tintColor, tintAmount = row.Meter.Tint, v
				end
			end
		end
		for _, frame in tints do
			if tintColor then
				frame.BackgroundColor3 = tintColor
			end
			frame.BackgroundTransparency = 1 - tintAmount * 0.55
		end
	end
	for _, meter in METERS do
		player:GetAttributeChangedSignal("Meter_" .. meter.Name):Connect(render)
	end
	render()
end

return MeterController
