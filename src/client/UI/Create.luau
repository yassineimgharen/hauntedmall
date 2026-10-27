-- Tiny declarative instance builder plus the shared visual primitives (corner, stroke,
-- gradient, padding, list) so every screen gets the same look.

local Theme = require(script.Parent.Theme)

local Create = {}

-- Create("Frame", { Size = ..., Parent = ... }, { children... })
local function new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className) :: any
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				instance[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

setmetatable(Create, {
	__call = function(_, className: string, props: { [string]: any }?, children: { Instance }?)
		return new(className, props, children)
	end,
})

function Create.corner(radius: number?): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius) })
end

function Create.round(): UICorner
	return new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Create.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return new("UIStroke", {
		Color = color or Theme.Colors.PanelLighter,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Create.gradient(a: Color3, b: Color3, rotation: number?): UIGradient
	return new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rotation or 0 })
end

function Create.padding(all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
	})
end

function Create.list(direction: Enum.FillDirection?, padding: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Create.text(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = Theme.Colors.Text,
		FontFace = Theme.Fonts.Bold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		defaults[key] = value
	end
	return new("TextLabel", defaults)
end

return Create
