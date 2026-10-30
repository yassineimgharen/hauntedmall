-- Procedural animation and feedback for enemies. The server moves the root; each client
-- animates legs/body through Motor6D.Transform, shows health bars, burn sparks, the
-- emerge-from-the-floor spawn, attack lunges, stuns and the death dissolve.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local MonsterAnimations = require(script.Parent.MonsterAnimations)

local EnemyVisualController = {}

type Leg = { Hip: Motor6D, Knee: Motor6D?, Phase: number }
type Visual = {
	Model: Model,
	Root: BasePart,
	Body: Motor6D?,
	Legs: { Leg },
	Eyes: { BasePart },
	Sparks: ParticleEmitter,
	Flash: Highlight,
	Bar: Frame,
	BarGui: BillboardGui,
	Gait: number,
	Dying: boolean,
	Joints: { [string]: Motor6D }, -- every Motor6D by name (per-type animations)
	Custom: { [string]: any }, -- per-type animation state
}

local camera = workspace.CurrentCamera
local visuals: { [Model]: Visual } = {}
local EYE_COLOR = Palette.ShadowEye
local BURN_COLOR = Color3.fromRGB(255, 250, 230)
local WARN_COLOR = Color3.fromRGB(255, 60, 40) -- eyes flare red while winding up an attack

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function makeHealthBar(root: BasePart): (BillboardGui, Frame)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(4, 0.35)
	gui.StudsOffset = Vector3.new(0, 4.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.Enabled = false
	gui.Adornee = root
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 10, 30)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Palette.NeonPink
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner:Clone().Parent = fill
	gui.Parent = root
	return gui, fill
end

local function makeSparks(root: BasePart): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 0.8, 0)
	attachment.Parent = root
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 150, 240))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.5, 0)
	sparks.Speed = NumberRange.new(3, 7)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Rate = 40
	sparks.Enabled = false
	sparks.Parent = attachment
	return sparks
end

-- White hit-flash while the flashlight burns the enemy (max 14 enemies, well under the
-- 31-Highlight engine limit).
local function makeFlash(model: Model): Highlight
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 245, 255)
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = Color3.fromRGB(255, 170, 255)
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Adornee = model
	highlight.Parent = model
	return highlight
end

-- Per-type death puffs (default: a big purple one).
local DEATH_BURSTS: { [string]: { Color: Color3, Count: number } } = {
	ParcelMimic = { Color = Color3.fromRGB(196, 154, 104), Count = 24 },
	ParcelMite = { Color = Color3.fromRGB(120, 60, 200), Count = 10 },
}

local function burst(root: BasePart, color: Color3, count: number)
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(color)
	smoke.Transparency = NumberSequence.new(0.2, 1)
	smoke.Size = NumberSequence.new(3, 7)
	smoke.Speed = NumberRange.new(4, 9)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Lifetime = NumberRange.new(0.6, 1.1)
	smoke.Rate = 0
	smoke.LightEmission = 0.3
	smoke.Parent = attachment
	smoke:Emit(count)
	task.delay(1.5, function()
		attachment:Destroy()
	end)
end

local function dissolve(visual: Visual)
	if visual.Dying then
		return
	end
	visual.Dying = true
	visual.BarGui.Enabled = false
	visual.Flash.Enabled = false
	local death = DEATH_BURSTS[(visual.Model:GetAttribute("EnemyType") or "") :: string]
	burst(visual.Root, if death then death.Color else Color3.fromRGB(120, 60, 200), if death then death.Count else 30)
	for _, part in visual.Model:GetDescendants() do
		if part:IsA("BasePart") and part ~= visual.Root then
			TweenService:Create(part, TweenInfo.new(0.9), { Transparency = 1 }):Play()
		elseif part:IsA("Light") then
			TweenService:Create(part, TweenInfo.new(0.6), { Brightness = 0 }):Play()
		elseif part:IsA("ParticleEmitter") then
			part.Enabled = false
		end
	end
end

local function register(model: Instance)
	if not model:IsA("Model") or visuals[model] then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not root then
		return
	end
	local legs = {}
	local body: Motor6D? = nil
	local joints = {}
	for _, joint in model:GetDescendants() do
		if joint:IsA("Motor6D") then
			joints[joint.Name] = joint
			if joint.Name == "BodyJoint" then
				body = joint
			elseif joint.Name:sub(1, 3) == "Hip" then
				local index = joint.Name:sub(4)
				table.insert(legs, {
					Hip = joint,
					Knee = model:FindFirstChild("Knee" .. index, true) :: Motor6D?,
					Phase = (joint:GetAttribute("Phase") :: number?) or 0,
				})
			end
		end
	end
	local eyes = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name == "Eye" then
			table.insert(eyes, part)
		end
	end

	local gui, bar = makeHealthBar(root)
	local visual: Visual = {
		Model = model,
		Root = root,
		Body = body,
		Legs = legs,
		Eyes = eyes,
		Sparks = makeSparks(root),
		Flash = makeFlash(model),
		Bar = bar,
		BarGui = gui,
		Gait = math.random() * 10,
		Dying = false,
		Joints = joints,
		Custom = {},
	}
	visuals[model] = visual
	if not model:GetAttribute("Disguised") then
		burst(root, Color3.fromRGB(60, 10, 100), 25) -- a disguised parcel just sits there
	end

	local function onHealth()
		local hp = model:GetAttribute("HP") or 0
		local max = model:GetAttribute("MaxHP") or 1
		gui.Enabled = hp < max and hp > 0
		bar.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
	end
	model:GetAttributeChangedSignal("HP"):Connect(onHealth)
	model:GetAttributeChangedSignal("Dead"):Connect(function()
		dissolve(visual)
	end)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			visuals[model] = nil
		end
	end)
	onHealth()
end

local function animate(visual: Visual, dt: number, now: number)
	local model = visual.Model
	if model:GetAttribute("Disguised") then
		-- a parcel on the floor: no walk cycle, bob or spawn animation to compute
		local still = MonsterAnimations[model:GetAttribute("EnemyType") or ""]
		if still then
			still(visual, dt, now)
		end
		return
	end
	local velocity = visual.Root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = math.clamp(speed / 10, 0, 1)
	visual.Gait += dt * (2 + speed * 0.9)
	local g = visual.Gait

	for _, leg in visual.Legs do
		local swing = math.sin(g + leg.Phase) * 0.5 * moving
		local lift = math.max(0, math.cos(g + leg.Phase)) * 0.4 * moving + math.sin(now * 2 + leg.Phase) * 0.04
		leg.Hip.Transform = CFrame.Angles(0, swing, 0) * CFrame.Angles(0, 0, lift)
		if leg.Knee then
			leg.Knee.Transform = CFrame.Angles(0, 0, -lift * 0.7)
		end
	end

	if visual.Body then
		local offset = CFrame.new(0, math.sin(g * 2) * 0.12 * moving + math.sin(now * 2.2) * 0.06, 0)
		local spawnedAt = model:GetAttribute("SpawnedAt") or 0
		local age = serverNow() - spawnedAt
		if age < 0.9 then
			offset *= CFrame.new(0, -3.2 * (1 - age / 0.9), 0)
		end
		local attackAt = model:GetAttribute("AttackAt") or 0
		local sinceAttack = serverNow() - attackAt
		if sinceAttack < 0.35 then
			local k = math.sin(sinceAttack / 0.35 * math.pi)
			offset *= CFrame.new(0, -0.3 * k, -1.1 * k) * CFrame.Angles(-0.35 * k, 0, 0)
		end
		local stunnedUntil = model:GetAttribute("StunnedUntil") or 0
		if serverNow() < stunnedUntil then
			offset *= CFrame.Angles(0, 0, math.sin(now * 30) * 0.08)
		end
		-- lean into the chase; shiver while being burned
		offset *= CFrame.Angles(-0.14 * moving, 0, 0)
		-- attack telegraph: rear up, head raised, before the bite lands
		local windup = model:GetAttribute("Windup") or 0.6
		local sinceWindup = serverNow() - (model:GetAttribute("WindupAt") or 0)
		if sinceWindup >= 0 and sinceWindup < windup then
			local k = math.sin(math.min(sinceWindup / windup, 1) * math.pi * 0.5)
			offset *= CFrame.new(0, 0.9 * k, 0.5 * k) * CFrame.Angles(0.55 * k, 0, 0)
		end
		if serverNow() < (model:GetAttribute("LitUntil") or 0) then
			offset *= CFrame.new((math.random() - 0.5) * 0.15, 0, (math.random() - 0.5) * 0.15)
		end
		visual.Body.Transform = offset
	end

	local lit = serverNow() < (model:GetAttribute("LitUntil") or 0)
	visual.Sparks.Enabled = lit
	visual.Flash.Enabled = lit
	local windingUp = serverNow() - (model:GetAttribute("WindupAt") or 0) < (model:GetAttribute("Windup") or 0.6)
	local eyeColor = if windingUp
		then WARN_COLOR
		elseif lit and math.floor(now * 20) % 2 == 0 then BURN_COLOR
		else EYE_COLOR
	for _, eye in visual.Eyes do
		eye.Color = eyeColor
	end

	local extra = MonsterAnimations[model:GetAttribute("EnemyType") or ""]
	if extra then
		extra(visual, dt, now)
	end
end

function EnemyVisualController.Start()
	for _, model in CollectionService:GetTagged("Enemy") do
		task.spawn(register, model)
	end
	CollectionService:GetInstanceAddedSignal("Enemy"):Connect(function(model)
		task.spawn(register, model)
	end)

	RunService.PreSimulation:Connect(function(dt)
		local now = os.clock()
		local cameraPosition = camera.CFrame.Position
		for _, visual in visuals do
			if not visual.Dying and (visual.Root.Position - cameraPosition).Magnitude < 170 then
				animate(visual, dt, now)
			end
		end
	end)
end

return EnemyVisualController
