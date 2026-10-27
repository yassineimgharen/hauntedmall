-- Toast notifications, top-right, newest on top, auto-dismiss.

local TweenService = game:GetService("TweenService")

local AudioController = require(script.Parent.Parent.Parent.Controllers.AudioController)
local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors
local KIND_COLORS = {
	info = C.Cyan,
	success = C.Green,
	warning = C.Gold,
	danger = C.Red,
	levelup = C.Pink,
}
local MAX_TOASTS = 5
local LIFETIME = 4

local Notifications = {}
Notifications.__index = Notifications

function Notifications.new(root: Frame)
	local self = setmetatable({}, Notifications)
	self.Container = Create("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(340, 400),
		Position = UDim2.new(1, -16, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = root,
	}, { Create.list(nil, 8, Enum.HorizontalAlignment.Right) })
	self.Order = 0
	return self
end

function Notifications:Push(text: string, kind: string?)
	local color = KIND_COLORS[kind or "info"] or C.Cyan
	self.Order -= 1
	local toast = Create("Frame", {
		Size = UDim2.fromOffset(340, 52),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.06,
		LayoutOrder = self.Order,
		ZIndex = 20,
		Parent = self.Container,
	}, {
		Create.corner(12),
		Create.stroke(color, 1.5, 0.2),
		Create("Frame", {
			Size = UDim2.new(0, 6, 1, -16),
			Position = UDim2.fromOffset(8, 8),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 21,
		}, { Create.round() }),
		Create.text({
			Name = "Text",
			Size = UDim2.new(1, -34, 1, -12),
			Position = UDim2.fromOffset(24, 6),
			Text = text,
			TextScaled = false,
			TextSize = 17,
			TextWrapped = true,
			FontFace = Theme.Fonts.Bold,
			ZIndex = 21,
		}),
	})
	local scale = Create("UIScale", { Scale = 0.6, Parent = toast })
	TweenService:Create(scale, Theme.TweenSlow, { Scale = 1 }):Play()
	if kind == "levelup" then
		AudioController.Play("LevelUp")
	end

	local toasts = {}
	for _, child in self.Container:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > MAX_TOASTS then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end

	task.delay(LIFETIME, function()
		if toast.Parent then
			TweenService:Create(scale, Theme.Tween, { Scale = 0 }):Play()
			task.wait(0.25)
			toast:Destroy()
		end
	end)
end

return Notifications
