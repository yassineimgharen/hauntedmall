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
	-- authored palm is modelled 16 studs tall; scale keeps per-site height variety
	local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	if AssetRegistry.place("PalmTree", CFrame.new(base) * yaw, parent, (height or 16) / 16) then
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
	-- Every decorative storefront is labelled so nobody mistakes it for a claimable shop.
	Builder.label(shutter, Enum.NormalId.Back, "COMING SOON\n🔒 future update", {
		Color = Color3.fromRGB(230, 230, 240),
		Font = FONT_BODY,
		Lit = true,
		GuiName = "Soon",
	})
	rng:NextNumber() -- keeps the seeded prop layout identical to earlier builds
	Props.infoPrompt(
		shutter,
		name,
		string.format(
			"🔒 %s is closed: it opens in a future mall expansion. Run your own store in the East Wing: follow the marker!",
			name
		)
	)

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

-- "What's this?" prompt on something non-interactive; the client shows InfoText locally.
function Props.infoPrompt(part: BasePart, title: string, text: string): ProximityPrompt
	local prompt = Builder.prompt(part, {
		Name = "InfoPrompt",
		ActionText = "What's this?",
		ObjectText = title,
		MaxActivationDistance = 12,
		KeyboardKeyCode = Enum.KeyCode.F, -- E stays free for gameplay prompts nearby
	})
	prompt:SetAttribute("InfoText", text)
	Builder.tag(prompt, "InfoPrompt")
	return prompt
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

-- ─── Atmosphere ────────────────────────────────────────────────────────────────

-- Soft volumetric-looking light shaft from a floor point toward the sun. Beams are cheap
-- (no lighting cost); clients show them by day only (tag SunShaft).
function Props.sunShaft(anchor: BasePart, floor: Vector3, sunDirection: Vector3, length: number, width: number)
	local bottom = Instance.new("Attachment")
	bottom.Parent = anchor
	bottom.WorldPosition = floor + Vector3.new(0, 0.2, 0)
	local top = Instance.new("Attachment")
	top.Parent = anchor
	top.WorldPosition = floor + sunDirection * length
	local beam = Instance.new("Beam")
	beam.Attachment0 = top
	beam.Attachment1 = bottom
	beam.Width0 = width * 0.75
	beam.Width1 = width
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 1
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 224, 176))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.97),
		NumberSequenceKeypoint.new(0.6, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = anchor
	Builder.tag(beam, "SunShaft")
	return beam
end

-- Invisible volume emitting drifting dust by day and glowing spores by night.
function Props.ambientVolume(cf: CFrame, size: Vector3, rate: number, parent: Instance): BasePart
	local volume =
		Builder.decor({ Name = "AmbientVolume", Parent = parent, Size = size, CFrame = cf, Transparency = 1 })
	local function emitter(tag: string, color: ColorSequence, particleSize: number, lift: number, emission: number)
		local e = Instance.new("ParticleEmitter")
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = color
		e.LightEmission = emission
		e.Size = NumberSequence.new(particleSize)
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Lifetime = NumberRange.new(8, 12)
		e.Speed = NumberRange.new(0.1, 0.4)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, lift, 0)
		e.Rate = rate
		e.Enabled = false
		e.Parent = volume
		Builder.tag(e, tag)
	end
	emitter("DayParticles", ColorSequence.new(Color3.fromRGB(255, 236, 200)), 0.12, -0.02, 0.6)
	emitter("NightParticles", ColorSequence.new(Palette.NeonPurple, Palette.NeonCyan), 0.16, 0.15, 1)
	return volume
end

-- Floor uplight that washes a surface with colour at night (lighting is the night look).
function Props.uplight(position: Vector3, color: Color3, parent: Instance, brightness: number?)
	local fixture = Builder.decor({
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, 1.1, 1.1),
		CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Metal,
	})
	local light = Builder.light("SpotLight", fixture, {
		Face = Enum.NormalId.Right, -- cylinder rotated 90°: local +X points up
		Angle = 45,
		Range = 26,
		Brightness = 0,
		Color = color,
	}, { "NightLight", "FxLight" })
	light:SetAttribute("NightBrightness", brightness or 3)
end

-- Double-sided hanging sign. cf = board centre, LookVector = one reading direction.
function Props.hangingSign(
	cf: CFrame,
	width: number,
	height: number,
	text: string,
	accent: Color3,
	ceilingY: number,
	parent: Instance
)
	local model = Builder.model("HangingSign", parent)
	for _, x in { -width * 0.38, width * 0.38 } do
		local top = (cf * CFrame.new(x, height / 2, 0)).Position
		Builder.beam(top, Vector3.new(top.X, ceilingY, top.Z), 0.12, {
			Parent = model,
			Color = Palette.DarkMetal,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
	end
	local board = Builder.decor({
		Parent = model,
		Size = Vector3.new(width, height, 0.35),
		CFrame = cf,
		Color = Color3.fromRGB(18, 13, 30),
		Material = Enum.Material.SmoothPlastic,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Builder.label(board, face, text, {
			Color = Color3.fromRGB(250, 246, 255),
			Font = FONT_TITLE,
			Stroke = accent,
			StrokeThickness = 2,
			GuiName = "Gui" .. face.Name,
		})
	end
	for _, y in { -height / 2 - 0.1, height / 2 + 0.1 } do
		Builder.decor({
			Parent = model,
			Size = Vector3.new(width + 0.2, 0.18, 0.42),
			CFrame = cf * CFrame.new(0, y, 0),
			Color = if y < 0 then accent else Palette.Gold,
			Material = if y < 0 then Enum.Material.Neon else Enum.Material.Metal,
			Tags = if y < 0 then { "NightNeon" } else nil,
		})
	end
	return model
end

-- Backlit advertising panel (unlit SurfaceGui so it glows). cf LookVector = viewer side.
function Props.lightbox(
	cf: CFrame,
	width: number,
	height: number,
	title: string,
	subtitle: string,
	color: Color3,
	parent: Instance
)
	local model = Builder.model("Lightbox", parent)
	Builder.decor({
		Parent = model,
		Size = Vector3.new(width + 0.4, height + 0.4, 0.3),
		CFrame = cf * CFrame.new(0, 0, 0.1),
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
	})
	local panel = Builder.decor({
		Parent = model,
		Size = Vector3.new(width, height, 0.2),
		CFrame = cf * CFrame.new(0, 0, -0.1) * CFrame.Angles(0, math.pi, 0),
		Color = color,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = color
	backdrop.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 110, 150))
	gradient.Rotation = 90
	gradient.Parent = backdrop
	for i, data in { { title, 0.08, 0.5, FONT_TITLE }, { subtitle, 0.62, 0.28, FONT_BODY } } do
		local label = Instance.new("TextLabel")
		label.Name = if i == 1 then "Title" else "Subtitle"
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.06, data[2])
		label.Size = UDim2.fromScale(0.88, data[3])
		label.Text = data[1]
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.FontFace = data[4]
		label.TextStrokeTransparency = 0.6
		label.Parent = gui
	end
	gui.Parent = panel
	return model
end

-- Circular seat wrapped around a planter (classic mall seating island).
function Props.ringBench(center: Vector3, innerRadius: number, outerRadius: number, parent: Instance)
	local model = Builder.model("RingBench", parent)
	local count = 16
	local step = math.pi * 2 / count
	local mid = (innerRadius + outerRadius) / 2
	local width = 2 * outerRadius * math.tan(step / 2) + 0.05
	for i = 0, count - 1 do
		local angle = i * step
		local p = center + Vector3.new(math.cos(angle) * mid, 0, math.sin(angle) * mid)
		local facing = CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z))
		Builder.part({
			Parent = model,
			Size = Vector3.new(width, 1.5, outerRadius - innerRadius),
			CFrame = facing * CFrame.new(0, 0.75, 0),
			Color = Palette.MarbleWarm,
			Material = Enum.Material.Marble,
		})
		Builder.part({
			Parent = model,
			Size = Vector3.new(width - 0.12, 0.3, outerRadius - innerRadius + 0.25),
			CFrame = facing * CFrame.new(0, 1.65, -0.12),
			Color = if i % 2 == 0 then Palette.Wood else Builder.shade(Palette.Wood, -0.08),
			Material = Enum.Material.Wood,
		})
	end
	return model
end

-- Mall kiosk cart with striped canopy. cf: floor centre, LookVector = customer side.
function Props.kioskCart(cf: CFrame, name: string, accent: Color3, parent: Instance)
	local model = Builder.model("Kiosk_" .. name, parent)
	Builder.part({
		Parent = model,
		Size = Vector3.new(6, 3, 3.2),
		CFrame = cf * CFrame.new(0, 1.9, 0),
		Color = Palette.WoodDark,
		Material = Enum.Material.Wood,
	})
	Builder.decor({
		Parent = model,
		Size = Vector3.new(5.2, 2.2, 0.1),
		CFrame = cf * CFrame.new(0, 1.9, -1.65),
		Color = Builder.shade(accent, -0.35),
	})
	Builder.decor({
		Parent = model,
		Size = Vector3.new(6.6, 0.3, 3.8),
		CFrame = cf * CFrame.new(0, 3.55, 0),
		Color = Palette.MarbleLight,
		Material = Enum.Material.Marble,
	})
	for _, x in { -2.4, 2.4 } do
		for _, z in { -1.2, 1.2 } do
			Builder.decor({
				Parent = model,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, 0.8, 0.8),
				CFrame = cf * CFrame.new(x, 0.4, z),
				Color = Color3.fromRGB(30, 30, 34),
			})
			Builder.decor({
				Parent = model,
				Size = Vector3.new(0.18, 4.6, 0.18),
				CFrame = cf * CFrame.new(x * 1.15, 5.9, z * 1.25),
				Color = Palette.Gold,
				Material = Enum.Material.Metal,
			})
		end
	end
	-- striped pitched canopy
	for i = 0, 7 do
		for _, side in { -1, 1 } do
			Builder.decor({
				Parent = model,
				Size = Vector3.new(0.92, 0.12, 2.6),
				CFrame = cf
					* CFrame.new(-3.2 + 0.92 * i + 0.46, 8.55, side * 1.15)
					* CFrame.Angles(side * math.rad(-18), 0, 0),
				Color = if i % 2 == 0 then accent else Color3.fromRGB(250, 246, 240),
				Material = Enum.Material.Fabric,
				CastShadow = true,
			})
		end
	end
	Builder.decor({
		Parent = model,
		Size = Vector3.new(7.4, 0.2, 0.2),
		CFrame = cf * CFrame.new(0, 8.05, -2.4),
		Color = accent,
		Material = Enum.Material.Neon,
		Tags = { "NightNeon" },
	})
	local menu = Builder.decor({
		Parent = model,
		Size = Vector3.new(4, 1.2, 0.15),
		CFrame = cf * CFrame.new(0, 7.35, -2.45),
		Color = Color3.fromRGB(20, 14, 32),
	})
	Builder.label(menu, Enum.NormalId.Front, name, { Color = Palette.NeonGold, Font = FONT_TITLE })
	for i = 0, 4 do
		Builder.decor({
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.7, 0.5, 0.5),
			CFrame = cf * CFrame.new(-1.6 + i * 0.8, 4.05, -0.6) * CFrame.Angles(0, 0, math.rad(90)),
			Color = if i % 2 == 0 then Color3.fromRGB(250, 246, 240) else accent,
		})
	end
	local bulb = Builder.decor({
		Parent = model,
		Size = Vector3.new(0.4, 0.2, 0.4),
		CFrame = cf * CFrame.new(0, 8.1, 0),
		Color = Palette.WarmLight,
		Material = Enum.Material.Neon,
		Tags = { "DayNeon" },
	})
	Builder.light("PointLight", bulb, { Range = 12, Brightness = 0.9, Color = Palette.WarmLight }, { "DayLight" })
	return model
end

-- Free-standing mall directory. cf: floor centre, LookVector = reading side.
function Props.directoryTotem(cf: CFrame, entries: { string }, parent: Instance)
	local model = Builder.model("DirectoryTotem", parent)
	Builder.part({
		Parent = model,
		Size = Vector3.new(4.6, 0.5, 1.6),
		CFrame = cf * CFrame.new(0, 0.25, 0),
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
	})
	local slab = Builder.part({
		Parent = model,
		Size = Vector3.new(4, 9, 0.9),
		CFrame = cf * CFrame.new(0, 5, 0) * CFrame.Angles(0, math.pi, 0),
		Color = Color3.fromRGB(18, 13, 30),
	})
	Builder.decor({
		Parent = model,
		Size = Vector3.new(4.1, 0.25, 1),
		CFrame = cf * CFrame.new(0, 9.6, 0),
		Color = Palette.NeonCyan,
		Material = Enum.Material.Neon,
		Tags = { "NightNeon" },
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.Parent = gui
	for i, text in entries do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(0.9, 0, 0, if i == 1 then 46 else 28)
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = if i == 1 then Palette.NeonCyan else Color3.fromRGB(235, 230, 250)
		label.FontFace = if i == 1 then FONT_TITLE else FONT_BODY
		label.TextXAlignment = if i == 1 then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
		label.LayoutOrder = i
		label.Parent = gui
	end
	gui.Parent = slab
	return model
end

return Props
