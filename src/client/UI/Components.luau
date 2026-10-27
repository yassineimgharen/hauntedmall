-- Reusable UI widgets: glass panels, animated buttons, progress bars, modal shells.

local TweenService = game:GetService("TweenService")

local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)

local C = Theme.Colors

local Components = {}

function Components.panel(props: { [string]: any }): Frame
	local frame = Create("Frame", {
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	}, {
		Create.corner(),
		Create.stroke(C.Purple, 1.5, 0.25),
		-- soft top-lit sheen so panels read as glass rather than flat fills
		Create.gradient(Color3.new(1, 1, 1), Color3.fromRGB(165, 155, 195), 90),
	})
	for key, value in props do
		frame[key] = value
	end
	return frame
end

-- Pill-shaped neon button with hover/press feedback.
function Components.button(props: {
	Text: string,
	Color: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	LayoutOrder: number?,
	OnClick: () -> (),
}): TextButton
	local color = props.Color or C.Pink
	local button = Create("TextButton", {
		Size = props.Size or UDim2.fromOffset(160, 48),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		Selectable = true,
	}, {
		Create.round(),
		Create.gradient(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200), 90),
		Create.stroke(Color3.new(1, 1, 1), 2, 0.6),
		Create.text({
			Name = "Label",
			Size = UDim2.fromScale(1, 0.56),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = props.Text,
			FontFace = Theme.Fonts.Heading,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.new(1, 1, 1),
		}),
	})
	local scale = Create("UIScale", { Parent = button })
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, Theme.Tween, { Scale = 1.05 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, Theme.Tween, { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, Theme.Tween, { Scale = 0.95 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, Theme.Tween, { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		if button:GetAttribute("Disabled") then
			return
		end
		AudioController.Play("UIClick")
		props.OnClick()
	end)
	button.Parent = props.Parent
	return button
end

function Components.setButtonEnabled(button: TextButton, enabled: boolean, color: Color3?)
	button:SetAttribute("Disabled", not enabled)
	button.BackgroundColor3 = if enabled then color or C.Pink else C.PanelLighter
	local label = button:FindFirstChild("Label") :: TextLabel?
	if label then
		label.TextTransparency = if enabled then 0 else 0.35
	end
end

-- Horizontal bar. Returns frame and a setter(fraction, instant?).
function Components.bar(props: { [string]: any }, color: Color3): (Frame, (number, boolean?) -> ())
	local back = Create("Frame", {
		BackgroundColor3 = Color3.fromRGB(14, 8, 26),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}, { Create.round() })
	for key, value in props do
		back[key] = value
	end
	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = back,
	}, {
		Create.round(),
		Create.gradient(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190), 90),
	})
	local function set(fraction: number, instant: boolean?)
		local goal = { Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1) }
		if instant then
			fill.Size = goal.Size
		else
			TweenService:Create(fill, Theme.Tween, goal):Play()
		end
	end
	return back, set
end

-- Centered modal shell with title and close button. Returns (root, body).
function Components.modal(parent: Instance, title: string, size: UDim2, onClose: () -> ()): (Frame, Frame)
	local root = Components.panel({
		Name = title .. "Modal",
		Size = size,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = parent,
		ZIndex = 5,
	})
	Create("UIScale", { Name = "PopScale", Parent = root })
	Create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = C.PanelLight,
		BorderSizePixel = 0,
		Parent = root,
	}, {
		Create.corner(),
		Create.gradient(C.Purple, C.Pink, 0),
		Create.text({
			Size = UDim2.new(1, -90, 0, 34),
			Position = UDim2.fromOffset(22, 15),
			Text = title,
			FontFace = Theme.Fonts.Heading,
		}),
	})
	Components.button({
		Text = "✕",
		Color = C.PanelLighter,
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.new(1, -12, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		Parent = root,
		OnClick = onClose,
	})
	local body = Create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, -36, 1, -88),
		Position = UDim2.fromOffset(18, 76),
		BackgroundTransparency = 1,
		Parent = root,
	})
	return root, body
end

function Components.show(modal: Frame, visible: boolean)
	local scale = modal:FindFirstChild("PopScale") :: UIScale
	if visible then
		modal.Visible = true
		scale.Scale = 0.85
		TweenService:Create(scale, Theme.TweenSlow, { Scale = 1 }):Play()
	else
		modal.Visible = false
	end
end

return Components
