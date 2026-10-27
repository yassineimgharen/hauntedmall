-- Reusable set-dressing props. Each checks AssetRegistry first so authored meshes
-- replace the procedural version automatically.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local AssetRegistry = require(script.Parent.AssetRegistry)
local Builder = require(script.Parent.Builder)

local Props = {}

local FONT_TITLE = Font.new("rbxasset://fonts/families/FredokaOne.json")
local FONT_BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

-- Cylinder spanning a → b (Roblox cylinders run along local X).
function Props.rod(a: Vector3, b: Vector3, radius: number, props: { [string]: any }): BasePart
	local length = (b - a).Magnitude
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(length, radius * 2, radius * 2)
	props.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	return Builder.part(props)
end

-- Flat leaf blade from a to b.
local function blade(a: Vector3, b: Vector3, width: number, color: Color3, parent: Instance)
	Builder.decor({
		Parent = parent,
		Size = Vector3.new(width, 0.12, (b - a).Magnitude),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = color,
		CastShadow = true,
	})
end

function Props.palm(base: Vector3, parent: Instance, rng: Random, height: number?)
	if
		AssetRegistry.place("PalmTree", CFrame.new(base) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), parent)
	then
		return
	end
	local model = Builder.model("PalmTree", parent)
	local h = height or rng:NextNumber(14, 18)
	local leanAngle = rng:NextNumber(0, math.pi * 2)
	local lean = Vector3.new(math.cos(leanAngle), 0, math.sin(leanAngle)) * rng:NextNumber(1.5, 3)

	local segments = 7
	local previous = base
	for i = 1, segments do
		local t = i / segments
		local point = base + Vector3.new(0, h * t, 0) + lean * (t * t)
		Props.rod(previous, point, 0.95 - 0.4 * t, {
			Parent = model,
			Color = if i % 2 == 0 then Palette.Trunk else Builder.shade(Palette.Trunk, -0.15),
			Material = Enum.Material.Wood,
			CanCollide = i <= 2,
		})
		previous = point
	end

	local top = previous
	Builder.decor({
		Parent = model,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.8,
		CFrame = CFrame.new(top),
		Color = Builder.shade(Palette.Trunk, -0.3),
	})
	for i = 1, 3 do
		local angle = i * 2.1
		Builder.decor({
			Parent = model,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.9,
			CFrame = CFrame.new(top + Vector3.new(math.cos(angle) * 0.8, -0.7, math.sin(angle) * 0.8)),
			Color = Palette.WoodDark,
		})
	end

	local fronds = 9
	for f = 1, fronds do
		local yaw = (f / fronds) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
		local droop = rng:NextNumber(1.2, 2.2)
		local mid = top + dir * 3.4 + Vector3.new(0, 0.9, 0)
		local tip = top + dir * 7.2 - Vector3.new(0, droop, 0)
		local color = if f % 2 == 0 then Palette.Leaf else Palette.LeafDark
		blade(top, mid, 1.7, color, model)
		blade(mid, tip, 1.2, Builder.shade(color, 0.08), model)
	end
end

function Props.planter(center: Vector3, radius: number, parent: Instance): Model
	local model = Builder.model("Planter", parent)
	Builder.cylinder(center + Vector3.new(0, 1.2, 0), radius, 2.4, {
		Parent = model,
		Color = Palette.MarbleWarm,
		Material = Enum.Material.Marble,
	})
	Builder.cylinder(center + Vector3.new(0, 2.45, 0), radius + 0.15, 0.3, {
		Parent = model,
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
		Reflectance = 0.1,
	})
	Builder.cylinder(center + Vector3.new(0, 2.5, 0), radius - 0.3, 0.3, {
		Parent = model,
		Color = Palette.Soil,
		Material = Enum.Material.Ground,
		CanCollide = false,
	})
	return model
end

function Props.pottedPlant(base: Vector3, parent: Instance, rng: Random)
	if AssetRegistry.place("PottedPlant", CFrame.new(base), parent) then
		return
	end
	local model = Builder.model("PottedPlant", parent)
	Builder.cylinder(base + Vector3.new(0, 0.9, 0), 0.9, 1.8, {
		Parent = model,
		Color = Palette.Wall,
		Material = Enum.Material.Marble,
	})
	local top = base + Vector3.new(0, 1.8, 0)
	for i = 1, 7 do
		local yaw = i / 7 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
		local tip = top + dir * rng:NextNumber(1.2, 1.9) + Vector3.new(0, rng:NextNumber(2, 3.4), 0)
		blade(top, tip, 0.7, if i % 2 == 0 then Palette.Leaf else Palette.LeafDark, model)
	end
end

-- cf: seat centre on the floor; the sitter faces cf.LookVector.
function Props.bench(cf: CFrame, parent: Instance)
	if AssetRegistry.place("Bench", cf, parent) then
		return
	end
	local model = Builder.model("Bench", parent)
	Builder.part({
		Parent = model,
		Size = Vector3.new(6, 0.45, 2),
		CFrame = cf * CFrame.new(0, 1.9, 0),
		Color = Palette.Wood,
		Material = Enum.Material.Wood,
	}, "Seat")
	Builder.decor({
		Parent = model,
		Size = Vector3.new(6, 1.5, 0.3),
		CFrame = cf * CFrame.new(0, 3.2, 0.95) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = Palette.Wood,
		Material = Enum.Material.Wood,
		CastShadow = true,
	})
	for _, x in { -2.7, 2.7 } do
		Builder.part({
			Parent = model,
			Size = Vector3.new(0.35, 1.9, 1.8),
			CFrame = cf * CFrame.new(x, 0.95, 0),
			Color = Palette.DarkMetal,
			Material = Enum.Material.Metal,
		})
		Builder.decor({
			Parent = model,
			Size = Vector3.new(0.4, 0.25, 2.1),
			CFrame = cf * CFrame.new(x, 2.75, 0),
			Color = Palette.Gold,
			Material = Enum.Material.Metal,
		})
	end
end

-- Hanging lamp. Light is tagged DayLight so clients switch it off at night.
function Props.pendantLamp(position: Vector3, ceilingY: number, parent: Instance, shadows: boolean?)
	local model = Builder.model("PendantLamp", parent)
	Builder.decor({
		Parent = model,
		Size = Vector3.new(0.12, ceilingY - position.Y, 0.12),
		CFrame = CFrame.new(position.X, (ceilingY + position.Y) / 2, position.Z),
		Color = Palette.DarkMetal,
	})
	Builder.decor({
		Parent = model,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 2.4, 2.4),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Metal,
	})
	local bulb = Builder.decor({
		Parent = model,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.8,
		CFrame = CFrame.new(position - Vector3.new(0, 0.55, 0)),
		Color = Palette.WarmLight,
		Material = Enum.Material.Neon,
		Tags = { "DayNeon" },
	})
	Builder.light("PointLight", bulb, {
		Color = Palette.WarmLight,
		Range = 22,
		Brightness = 1.3,
		Shadows = shadows == true,
	}, { "DayLight" })
end

-- Recessed ceiling downlight (face pointing down).
function Props.downlight(position: Vector3, parent: Instance, range: number?)
	local disc = Builder.decor({
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 1.6, 1.6),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.WarmLight,
		Material = Enum.Material.Neon,
		Tags = { "DayNeon" },
	})
	Builder.light("SpotLight", disc, {
		Face = Enum.NormalId.Left, -- cylinder rotated 90° → local -X points down
		Angle = 100,
		Range = range or 26,
		Brightness = 1.6,
		Color = Palette.WarmLight,
	}, { "DayLight" })
end

function Props.lurkerEyes(cf: CFrame, parent: Instance, scale: number?)
	local s = scale or 1
	local model = Builder.model("LurkerEyes", parent)
	for _, x in { -0.4, 0.4 } do
		Builder.decor({
			Parent = model,
			Size = Vector3.new(0.38, 0.22, 0.05) * s,
			CFrame = cf * CFrame.new(x * s, 0, 0) * CFrame.Angles(0, 0, math.rad(if x < 0 then -12 else 12)),
			Color = Palette.ShadowEye,
			Material = Enum.Material.Neon,
			Transparency = 1,
		})
	end
	Builder.tag(model, "LurkerEyes")
	return model
end

-- Decorative closed storefront. cf: floor centre of the front face, LookVector = outward.
function Props.facade(
	cf: CFrame,
	width: number,
	height: number,
	name: string,
	accent: Color3,
	parent: Instance,
	rng: Random
)
	local model = Builder.model("Facade_" .. name, parent)
	local inward = CFrame.Angles(0, math.pi, 0) -- local -Z of parts faces the viewer

	for _, x in { -width / 2, width / 2 } do
		Builder.part({
			Parent = model,
			Size = Vector3.new(1.4, height, 1.4),
			CFrame = cf * CFrame.new(x, height / 2, 0),
			Color = Palette.MarbleWarm,
			Material = Enum.Material.Marble,
		})
	end

	local header = Builder.part({
		Parent = model,
		Size = Vector3.new(width, 3.2, 1.2),
		CFrame = cf * CFrame.new(0, height - 1.6, 0) * inward,
		Color = Palette.DarkMetal,
		Material = Enum.Material.Metal,
	})
	Builder.label(header, Enum.NormalId.Back, name, { Color = accent, Font = FONT_TITLE, Brightness = 2 })

	Builder.decor({
		Parent = model,
		Size = Vector3.new(width - 3, 0.25, 0.25),
		CFrame = cf * CFrame.new(0, height - 3.45, -0.75),
		Color = accent,
		Material = Enum.Material.Neon,
		Tags = { "NightNeon" },
	})

	local shutterHeight = height - 3.2 - 1.4
	local shutter = Builder.part({
		Parent = model,
		Size = Vector3.new(width - 1.4, shutterHeight, 0.3),
		CFrame = cf * CFrame.new(0, 1.4 + shutterHeight / 2, 0.3) * inward,
		Color = Builder.shade(Palette.Chrome, -0.25),
		Material = Enum.Material.DiamondPlate,
	})
	for i = 1, 6 do
		Builder.decor({
			Parent = model,
			Size = Vector3.new(width - 1.6, 0.12, 0.1),
			CFrame = cf * CFrame.new(0, 1.4 + i * shutterHeight / 7, 0.1),
			Color = Palette.DarkMetal,
		})
	end
	Builder.label(shutter, Enum.NormalId.Back, "OPENING SOON", {
		Color = Color3.fromRGB(230, 230, 240),
		Font = FONT_BODY,
		Lit = true,
		GuiName = "Soon",
	}).Enabled = rng:NextNumber()
		< 0.5

	-- dark gap under a half-closed shutter, sometimes with something watching
	Builder.decor({
		Parent = model,
		Size = Vector3.new(width - 1.4, 1.4, 0.2),
		CFrame = cf * CFrame.new(0, 0.7, 0.45),
		Color = Color3.new(0, 0, 0),
	})
	if rng:NextNumber() < 0.6 then
		Props.lurkerEyes(cf * CFrame.new(rng:NextNumber(-width / 3, width / 3), 0.7, 0.3), model, 1)
	end
	return model
end

function Props.fuseBox(cf: CFrame, id: string, zone: string, parent: Instance): Model
	local model = Builder.model("FuseBox_" .. id, parent)
	model:SetAttribute("FuseId", id)
	model:SetAttribute("Zone", zone)
	model:SetAttribute("Repaired", false)

	local box = Builder.part({
		Name = "Box",
		Parent = model,
		Size = Vector3.new(3, 4, 1),
		CFrame = cf * CFrame.new(0, 0, -0.5),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Metal,
	})
	local door = Builder.decor({
		Parent = model,
		Size = Vector3.new(2.6, 3.4, 0.1),
		CFrame = cf * CFrame.new(0, -0.15, -1.05),
		Color = Color3.fromRGB(240, 196, 40),
	})
	Builder.label(door, Enum.NormalId.Front, "⚡", { Color = Color3.fromRGB(30, 30, 30), Lit = true })

	local indicator = Builder.decor({
		Name = "Indicator",
		Parent = model,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.55,
		CFrame = cf * CFrame.new(0, 2.35, -0.6),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Neon,
	})
	Builder.light("PointLight", indicator, { Name = "Status", Range = 12, Brightness = 0, Color = Palette.NeonRed })

	local sparkPoint = Instance.new("Attachment")
	sparkPoint.Name = "SparkPoint"
	sparkPoint.Position = Vector3.new(0, 1, -0.6)
	sparkPoint.Parent = box
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Enabled = false
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 240, 180), Color3.fromRGB(255, 160, 60))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.25, 0)
	sparks.Speed = NumberRange.new(6, 14)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Acceleration = Vector3.new(0, -35, 0)
	sparks.Lifetime = NumberRange.new(0.25, 0.6)
	sparks.Rate = 22
	sparks.Parent = sparkPoint

	Builder.prompt(box, {
		Name = "RepairPrompt",
		ActionText = "Repair Fuse Box",
		ObjectText = zone,
		HoldDuration = 3,
		Enabled = false,
		MaxActivationDistance = 9,
	})

	Builder.tag(model, "FuseBox")
	return model
end

function Props.streetLamp(base: Vector3, parent: Instance)
	local model = Builder.model("StreetLamp", parent)
	Builder.cylinder(base + Vector3.new(0, 7, 0), 0.35, 14, {
		Parent = model,
		Color = Palette.DarkMetal,
		Material = Enum.Material.Metal,
	})
	local head = Builder.decor({
		Parent = model,
		Size = Vector3.new(1.6, 0.9, 1.6),
		CFrame = CFrame.new(base + Vector3.new(0, 14.2, 0)),
		Color = Palette.WarmLight,
		Material = Enum.Material.Neon,
		Tags = { "NightNeon" },
	})
	Builder.light("SpotLight", head, {
		Face = Enum.NormalId.Bottom,
		Angle = 110,
		Range = 30,
		Brightness = 0,
		Color = Palette.CoolLight,
	}, { "NightLight" })
end

function Props.banner(top: Vector3, facing: Vector3, text: string, parent: Instance)
	local model = Builder.model("Banner", parent)
	local cf = CFrame.lookAt(top, top + facing)
	Builder.decor({
		Parent = model,
		Size = Vector3.new(7, 0.3, 0.3),
		CFrame = cf * CFrame.new(0, 0, 0),
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
	})
	local cloth = Builder.decor({
		Parent = model,
		Size = Vector3.new(6, 13, 0.15),
		CFrame = cf * CFrame.new(0, -6.7, 0),
		Color = Palette.Fabric,
		Material = Enum.Material.Fabric,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local _, label = Builder.label(cloth, face, text, {
			Color = Color3.fromRGB(255, 220, 250),
			Font = FONT_TITLE,
			Lit = true,
			GuiName = "Gui" .. face.Name,
		})
		label.LineHeight = 0.9
	end
	Builder.decor({
		Parent = model,
		Size = Vector3.new(6, 0.25, 0.25),
		CFrame = cf * CFrame.new(0, -13.1, 0),
		Color = Palette.NeonPink,
		Material = Enum.Material.Neon,
		Tags = { "NightNeon" },
	})
end

return Props
