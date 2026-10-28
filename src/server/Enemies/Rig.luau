-- Shared helpers for procedural enemy rigs (Chapter 2 monsters). Same conventions as
-- ShadowCrawler: an invisible HumanoidRootPart moved by a Humanoid, visible parts hung
-- on Motor6Ds (BodyJoint, Hip*/Knee*, plus per-type joints the client animates) or
-- welded, parts named "Eye" glow (EnemyVisualController recolours them on wind-ups).

local Rig = {}

function Rig.part(model: Model, props: { [string]: any }, className: string?): BasePart
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
	for key, value in props do
		p[key] = value
	end
	p.Parent = model
	return p
end

function Rig.weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- Places part1 from part0 * c0 * c1⁻¹ and joins them (the client animates .Transform).
function Rig.motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame?): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1 or CFrame.new()
	part1.CFrame = part0.CFrame * c0 * m.C1:Inverse()
	m.Parent = part0
	return m
end

function Rig.ball(model: Model, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Rig.part(model, { Name = "Part", Size = size, CFrame = cf, Color = color })
	for key, value in (props or {}) :: { [string]: any } do
		(p :: any)[key] = value
	end
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- The collision box the Humanoid walks with; its bottom sits hipHeight above the floor.
function Rig.root(model: Model, size: Vector3, hipHeight: number): BasePart
	local root = Rig.part(model, {
		Name = "HumanoidRootPart",
		Size = size,
		CFrame = CFrame.new(0, hipHeight + size.Y / 2, 0),
		Transparency = 1,
		CanCollide = true,
		Massless = false,
	})
	model.PrimaryPart = root
	return root
end

function Rig.eye(model: Model, attachTo: BasePart, cf: CFrame, size: Vector3, color: Color3, light: boolean?): BasePart
	local eye =
		Rig.part(model, { Name = "Eye", Size = size, CFrame = cf, Color = color, Material = Enum.Material.Neon })
	Rig.weld(attachTo, eye)
	if light then
		local glow = Instance.new("PointLight")
		glow.Color = color
		glow.Range = 10
		glow.Brightness = 1.6
		glow.Parent = eye
	end
	return eye
end

function Rig.particles(part: BasePart, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.2
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = part
	return emitter
end

-- Humanoid used only for movement (real HP lives in EnemyService).
function Rig.humanoid(model: Model, hipHeight: number, walkSpeed: number): Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.WalkSpeed = walkSpeed
	humanoid.MaxHealth = 1e6
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
	return humanoid
end

-- A two-segment leg on Hip<i>/Knee<i> motors (animated by EnemyVisualController).
function Rig.leg(
	model: Model,
	root: BasePart,
	index: number,
	hipC0: CFrame,
	upper: number,
	lower: number,
	color: Color3,
	phase: number
)
	local upperPart =
		Rig.part(model, { Name = "UpperLeg" .. index, Size = Vector3.new(upper, 0.3, 0.3), Color = color })
	local lowerPart =
		Rig.part(model, { Name = "LowerLeg" .. index, Size = Vector3.new(lower, 0.22, 0.22), Color = color })
	local hip = Rig.motor("Hip" .. index, root, upperPart, hipC0, CFrame.new(-upper / 2, 0, 0))
	hip:SetAttribute("Phase", phase)
	Rig.motor(
		"Knee" .. index,
		upperPart,
		lowerPart,
		CFrame.new(upper / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(-110)),
		CFrame.new(-lower / 2, 0, 0)
	)
end

return Rig
