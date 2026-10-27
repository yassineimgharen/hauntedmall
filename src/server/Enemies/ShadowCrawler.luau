-- Shadow Crawler: fast, weak, six-legged shadow with a glowing grin.
-- Built procedurally as a Humanoid rig. Legs and body hang on Motor6Ds named Hip*/Knee*/
-- BodyJoint so the client can animate them (EnemyVisualController). An authored model named
-- "ShadowCrawler" in ServerStorage.Assets replaces this if it has the same joint names.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local AssetRegistry = require(script.Parent.Parent.World.AssetRegistry)

local ShadowCrawler = {}

local CONFIG = EnemyConfig.Types.ShadowCrawler
local UPPER = 2.6
local LOWER = 4.4

local function part(model: Model, props: { [string]: any }, className: string?): BasePart
	local p = Instance.new(className or "Part") :: any
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Palette.ShadowBody
	for key, value in props do
		p[key] = value
	end
	p.Parent = model
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	part1.CFrame = part0.CFrame * c0 * c1:Inverse()
	m.Parent = part0
	return m
end

local function ellipsoid(model: Model, size: Vector3, cf: CFrame, color: Color3, name: string?): BasePart
	local p = part(model, { Name = name or "Part", Size = size, CFrame = cf, Color = color })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Pale, translucent re-colour for the Phantom Shopper (same rig and animation).
local function phantomize(model: Model)
	local eye = Color3.fromRGB(120, 240, 255)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			if descendant.Color == Palette.ShadowEye then
				descendant.Color = eye
			else
				descendant.Color = descendant.Color:Lerp(Color3.fromRGB(205, 215, 235), 0.85)
				descendant.Material = Enum.Material.Glass
				descendant.Transparency = math.max(descendant.Transparency, 0.3)
			end
		elseif descendant:IsA("Light") then
			descendant.Color = eye
		elseif descendant:IsA("Trail") then
			descendant.Color = ColorSequence.new(eye)
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Color = ColorSequence.new(Color3.fromRGB(220, 235, 255), Color3.fromRGB(120, 140, 180))
		end
	end
	model.Name = "PhantomShopper"
end

-- variant "Phantom" builds the Phantom Shopper's revealed form.
function ShadowCrawler.build(variant: string?): Model
	local authored = AssetRegistry.clone(if variant == "Phantom" then "PhantomShopper" else "ShadowCrawler")
	if authored then
		return authored
	end

	local model = Instance.new("Model")
	model.Name = "ShadowCrawler"
	local base = CFrame.new(0, CONFIG.HipHeight + 1, 0)

	local root = part(model, {
		Name = "HumanoidRootPart",
		Size = Vector3.new(3, 2, 4),
		CFrame = base,
		Transparency = 1,
		CanCollide = true,
		Massless = false,
	})
	model.PrimaryPart = root

	local body =
		ellipsoid(model, Vector3.new(3.4, 2.4, 4.4), base * CFrame.new(0, 0.4, 0.3), Palette.ShadowBody, "Body")
	motor("BodyJoint", root, body, CFrame.new(0, 0.4, 0.3), CFrame.new())

	local headCF = body.CFrame * CFrame.new(0, 0.45, -2.3)
	local head = ellipsoid(model, Vector3.new(2.7, 2.1, 2.3), headCF, Color3.fromRGB(26, 12, 42), "Skull")
	weld(body, head)

	for _, side in { -1, 1 } do
		local eye = part(model, {
			Name = "Eye",
			Size = Vector3.new(0.62, 0.42, 0.15),
			CFrame = headCF * CFrame.new(side * 0.58, 0.28, -1.08) * CFrame.Angles(0, side * 0.25, side * -0.3),
			Color = Palette.ShadowEye,
			Material = Enum.Material.Neon,
		})
		weld(head, eye)
		-- ghostly streak behind each eye as it skitters (cheap, very readable in the dark)
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, 0.14, 0)
		top.Parent = eye
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -0.14, 0)
		bottom.Parent = eye
		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Lifetime = 0.25
		trail.MinLength = 0.1
		trail.FaceCamera = true
		trail.LightEmission = 1
		trail.Color = ColorSequence.new(Palette.ShadowEye)
		trail.Transparency = NumberSequence.new(0.25, 1)
		trail.Parent = eye
		if side == 1 then
			local light = Instance.new("PointLight")
			light.Color = Palette.ShadowEye
			light.Range = 9
			light.Brightness = 2
			light.Parent = eye
		end
	end
	for i = -3, 3 do
		local tooth = part(model, {
			Name = "Tooth",
			Size = Vector3.new(0.24, 0.24, 0.08),
			CFrame = headCF
				* CFrame.new(i * 0.2, -0.35 + math.abs(i) * 0.06 + (i % 2) * 0.12, -1.12 + math.abs(i) * 0.03)
				* CFrame.Angles(0, 0, math.rad(45)),
			Color = Color3.fromRGB(255, 235, 255),
			Material = Enum.Material.Neon,
		})
		weld(head, tooth)
	end
	for i, z in { -0.8, 0.4, 1.5 } do
		local spike = part(model, {
			Name = "Spike",
			Size = Vector3.new(0.35, 1.1 - i * 0.15, 1.2),
			CFrame = body.CFrame * CFrame.new(0, 1.35, z) * CFrame.Angles(math.rad(-20), 0, 0),
			Color = Color3.fromRGB(34, 16, 56),
		}, "WedgePart")
		weld(body, spike)
	end

	local legIndex = 0
	for _, side in { 1, -1 } do
		for _, z in { -1.3, 0, 1.3 } do
			legIndex += 1
			local fan = math.rad(side * (-z / 1.3) * 30)
			local hipC0 = CFrame.new(side * 1.3, 0.5, z + 0.3)
				* CFrame.Angles(0, if side < 0 then math.pi else 0, 0)
				* CFrame.Angles(0, fan, 0)
				* CFrame.Angles(0, 0, math.rad(35))
			local upper = part(model, {
				Name = "UpperLeg" .. legIndex,
				Size = Vector3.new(UPPER, 0.38, 0.38),
				Color = Palette.ShadowBody,
			})
			local lower = part(model, {
				Name = "LowerLeg" .. legIndex,
				Size = Vector3.new(LOWER, 0.28, 0.28),
				Color = Color3.fromRGB(30, 14, 48),
			})
			local hip = motor("Hip" .. legIndex, root, upper, hipC0, CFrame.new(-UPPER / 2, 0, 0))
			hip:SetAttribute("Phase", if (legIndex % 2 == 0) == (side > 0) then 0 else math.pi)
			motor(
				"Knee" .. legIndex,
				upper,
				lower,
				CFrame.new(UPPER / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(-110)),
				CFrame.new(-LOWER / 2, 0, 0)
			)
		end
	end

	local smokePoint = Instance.new("Attachment")
	smokePoint.Parent = body
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 20, 120), Color3.fromRGB(20, 6, 36))
	smoke.Transparency = NumberSequence.new(0.45, 1)
	smoke.Size = NumberSequence.new(2.2, 4)
	smoke.Lifetime = NumberRange.new(0.8, 1.3)
	smoke.Rate = 12
	smoke.Speed = NumberRange.new(0.5, 1.5)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.LightEmission = 0.15
	smoke.Parent = smokePoint

	local aura = Instance.new("PointLight")
	aura.Color = Palette.NeonPurple
	aura.Range = 10
	aura.Brightness = 1
	aura.Parent = body

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = CONFIG.HipHeight
	humanoid.WalkSpeed = CONFIG.WalkSpeed
	humanoid.MaxHealth = 1e6 -- real HP is tracked by EnemyService; the Humanoid only moves
	humanoid.Health = 1e6
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model

	for _, state in
		{
			Enum.HumanoidStateType.Seated,
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Swimming,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Dead,
		}
	do
		humanoid:SetStateEnabled(state, false)
	end

	if variant == "Phantom" then
		phantomize(model)
	end
	return model
end

return ShadowCrawler
