-- Low-level construction helpers for the procedural mall.
-- Everything built here is the "blockout+" layer: correct scale, materials and lighting.
-- Hero props can be replaced by real meshes through AssetRegistry without code changes.

local CollectionService = game:GetService("CollectionService")

local Builder = {}

local PART_DEFAULTS = {
	Anchored = true,
	CanTouch = false,
	TopSurface = Enum.SurfaceType.Smooth,
	BottomSurface = Enum.SurfaceType.Smooth,
	Material = Enum.Material.SmoothPlastic,
}

local SKIP = { Parent = true, Tags = true, Shape = true, Attributes = true }

-- Generic part factory. props may contain Tags = {...} and Attributes = {...}.
function Builder.part(props: { [string]: any }, className: string?): BasePart
	local part = Instance.new(className or "Part") :: any
	for key, value in PART_DEFAULTS do
		part[key] = value
	end
	if props.Shape then
		part.Shape = props.Shape
	end
	for key, value in props do
		if not SKIP[key] then
			part[key] = value
		end
	end
	if props.Tags then
		for _, tag in props.Tags do
			CollectionService:AddTag(part, tag)
		end
	end
	if props.Attributes then
		for name, value in props.Attributes do
			part:SetAttribute(name, value)
		end
	end
	part.Parent = props.Parent
	return part
end

-- Non-colliding, non-queryable decoration (cheaper for physics and raycasts).
function Builder.decor(props: { [string]: any }, className: string?): BasePart
	props.CanCollide = false
	props.CanQuery = false
	if props.CastShadow == nil then
		props.CastShadow = false
	end
	return Builder.part(props, className)
end

-- Vertical cylinder centred at `center`.
function Builder.cylinder(center: Vector3, radius: number, height: number, props: { [string]: any }): BasePart
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, radius * 2, radius * 2)
	props.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	return Builder.part(props)
end

-- Box spanning from a to b with a square cross-section.
function Builder.beam(a: Vector3, b: Vector3, thickness: number, props: { [string]: any }): BasePart
	local length = (b - a).Magnitude
	props.Size = Vector3.new(thickness, thickness, length)
	props.CFrame = CFrame.lookAt((a + b) / 2, b)
	return Builder.part(props)
end

function Builder.model(name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Builder.folder(name: string, parent: Instance?): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function Builder.light(className: string, parent: Instance, props: { [string]: any }, tags: { string }?): Light
	local light = Instance.new(className) :: any
	for key, value in props do
		light[key] = value
	end
	if tags then
		for _, tag in tags do
			CollectionService:AddTag(light, tag)
		end
	end
	light.Parent = parent
	return light
end

-- Text on a part face. Glowing (unlit) by default, like a backlit sign.
function Builder.label(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	options: { [string]: any }?
): (SurfaceGui, TextLabel)
	local opts = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = opts.GuiName or "Gui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.PixelsPerStud or 40
	gui.LightInfluence = if opts.Lit then 1 else 0
	gui.Brightness = opts.Brightness or 1.6
	gui.ZOffset = 1

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = opts.Color or Color3.new(1, 1, 1)
	label.FontFace = opts.Font or Font.new("rbxasset://fonts/families/FredokaOne.json")
	label.Parent = gui

	if opts.Stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Color = opts.Stroke
		stroke.Thickness = opts.StrokeThickness or 3
		stroke.Parent = label
	end

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = label

	gui.Parent = part
	return gui, label
end

function Builder.tag(instance: Instance, ...: string)
	for _, tag in { ... } do
		CollectionService:AddTag(instance, tag)
	end
end

function Builder.prompt(parent: Instance, props: { [string]: any }): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	for key, value in props do
		(prompt :: any)[key] = value
	end
	prompt.Parent = parent
	return prompt
end

-- Darken/lighten helpers for material variation.
function Builder.shade(color: Color3, amount: number): Color3
	if amount >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), amount)
	end
	return color:Lerp(Color3.new(0, 0, 0), -amount)
end

return Builder
