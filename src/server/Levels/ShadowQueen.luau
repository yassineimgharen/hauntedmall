-- Level 7, "The Warning" (day) / "The Shadow Queen" (night, Chapter 1 boss).
--
-- Day:   3 light cannons around the fountain charge while players stand in their rings
--        (zone capture, faster with more people). North of the fountain, a mirror puzzle
--        (MirrorGrid) steers a beam to a crystal; solving it grants every player present
--        the Prism Lens (persisted equipment: +50% light damage against bosses).
-- Night: the Shadow Queen circles the fountain. Her shield blocks all light until a charged
--        cannon fires at her: then it is down for QueenLogic.Tuning.ShieldDown seconds,
--        every flashlight is refilled and her brood is stunned. Cannons recharge on their
--        own (faster with people in the ring), and their lit rings burn crawlers.
--          Phase 1 (>66%)  slow, telegraphed slams; a small brood
--          Phase 2 (>33%)  + double slams, darkness pulses (cannons can't fire)
--          Phase 3         + a sweeping floor beam you must jump over
-- The rules (health, shield, phases, brood sizes, spawn spots) live in QueenLogic and are
-- unit-tested; this file is the world side: models, effects, timing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local CombatService = require(script.Parent.Parent.Services.CombatService)
local DataService = require(script.Parent.Parent.Services.DataService)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
local ProgressionService = require(script.Parent.Parent.Services.ProgressionService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local MirrorGrid = require(script.Parent.MirrorGrid)
local BossScaling = require(script.Parent.BossScaling)
local QueenLogic = require(script.Parent.QueenLogic)

local ShadowQueen = {}

local FL = EnemyConfig.Flashlight
local T = QueenLogic.Tuning
local RING_RADIUS = 6
local WARD_DPS = 15 -- a cannon's lit ring burns crawlers inside it
local HOVER_Y = 11
local ORBIT_RADIUS = 17 -- between the fountain basin (11) and the palms (22)
local ANGULAR_SPEED = 0.22 -- rad/s along the orbit (~4 studs/s)
local SWEEP_LENGTH = 40
local SWEEP_SECONDS = 8
local SWEEP_WARNING = 2.5
local DEFEAT_DAWN_SECONDS = 12 -- after she falls, dawn (and the rewards) come this soon

local CANNONS = { Vector3.new(14.5, 0, 25.1), Vector3.new(-14.5, 0, 25.1), Vector3.new(0, 0, -30) }
-- Brood portals around the atrium floor: clear of the fountain, escalators, puzzle and
-- the player spawn. QueenLogic.pickSpawn keeps them away from players and cannons.
local BROOD_POINTS = {
	Vector3.new(-50, 0, 30),
	Vector3.new(-50, 0, -30),
	Vector3.new(50, 0, 30),
	Vector3.new(50, 0, -30),
	Vector3.new(-30, 0, 55),
	Vector3.new(30, 0, 55),
	Vector3.new(-58, 0, 0),
	Vector3.new(58, 0, 0),
	Vector3.new(-32, 0, -52),
	Vector3.new(32, 0, -52),
}
local EYE_COLORS = { Palette.NeonPink, Palette.NeonRed, Color3.fromRGB(255, 245, 210) }
local REFUSAL_TEXT = {
	NotCharged = "🔆 This cannon is still charging. Stand in its ring to speed it up.",
	ShieldDown = "⚡ Her shield is ALREADY down: burn her with your flashlight! Save this cannon.",
	Dark = "🌑 Her darkness smothers the cannons. Fire again when it lifts.",
	Defeated = "👑 She's already beaten!",
}

type Cannon = {
	Position: Vector3,
	Ring: BasePart,
	Tip: Vector3,
	Lens: BasePart,
	Glow: PointLight,
	Label: TextLabel,
	FirePrompt: ProximityPrompt,
	Progress: number,
	Charged: boolean,
	Fired: boolean,
	Helpers: { [Player]: boolean },
}

type Pose = { RearUntil: number, RearLength: number, DropUntil: number, RecoilUntil: number, RoarUntil: number }

local folder: Folder? = nil
local beamFolder: Folder? = nil
local hazards: Folder? = nil -- telegraphs, beams and portals: cleared the moment she falls
local dayToken: {}? = nil
local nightToken: {}? = nil
local cannons: { Cannon } = {}
local mirrorStates: { string } = {}
local mirrorParts: { BasePart } = {}
local solved = false
local queen: Model? = nil
local queenRoot: BasePart? = nil
local fight: QueenLogic.Fight? = nil
local dying = false
local motion: RBXScriptConnection? = nil
local sweepAngle: number? = nil -- while the floor beam sweeps, she turns with it
local pose: Pose = { RearUntil = 0, RearLength = 1, DropUntil = 0, RecoilUntil = 0, RoarUntil = 0 }
local pendingDamage: { [Player]: { Amount: number, Position: Vector3 } } = {}
local blockedAt: { [Player]: number } = {}
local toldBlocked: { [Player]: boolean } = {}
local lastHitPublish = 0
local rng = Random.new()

local function stage(): string
	return GameStateService.GetPhase()
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function cellPosition(x: number, z: number, y: number?): Vector3
	return Vector3.new(-10 + x * 5, y or 2.5, 38 + z * 5)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function activePlayers(): number
	local count = 0
	for _, player in Players:GetPlayers() do
		if rootOf(player) then
			count += 1
		end
	end
	return math.max(count, 1)
end

local function nightAlive(myToken: {}): boolean
	local f = fight
	return nightToken == myToken and f ~= nil and not f.Defeated and not dying
end

-- Short-lived neon effect part that tweens to `goal` and is removed.
local function flash(props: { [string]: any }, seconds: number, goal: { [string]: any }): BasePart?
	local parent = hazards or folder
	if not parent then
		return nil
	end
	props.Parent = parent
	props.Material = props.Material or Enum.Material.Neon
	local part = Builder.decor(props)
	goal.Transparency = goal.Transparency or 1
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	task.delay(seconds + 0.05, function()
		part:Destroy()
	end)
	return part
end

local function burst(center: Vector3, color: Color3, count: number, distance: number)
	for i = 1, count do
		local direction = CFrame.Angles(0, i / count * math.pi * 2, 0) * CFrame.Angles(rng:NextNumber(-0.6, 0.9), 0, 0)
		local start = CFrame.lookAt(center, center + direction.LookVector)
		flash({
			Size = Vector3.new(0.5, 0.5, 1.8),
			CFrame = start,
			Color = color,
		}, 0.7, { CFrame = start + direction.LookVector * distance, Size = Vector3.new(0.1, 0.1, 0.6) })
	end
end

-- ── cannons ─────────────────────────────────────────────────────────────────

local function readyToFire(cannon: Cannon): boolean
	local f = fight
	return f ~= nil and (QueenLogic.canFire(f, cannon, os.clock()))
end

local function setCannonLabel(cannon: Cannon)
	local f = fight
	local now = os.clock()
	local night = f ~= nil
	local dark = f ~= nil and now < f.DarkUntil
	local text, color
	if dark then
		text, color = "⛔ DARK", Color3.fromRGB(170, 150, 200)
	elseif cannon.Charged and night and f and now < f.ShieldUntil then
		text, color = "🔆 READY (shield is down)", Palette.NeonGold
	elseif cannon.Charged then
		text, color = if night then "🔆 READY: HOLD E" else "🔆 CHARGED", Palette.NeonGold
	else
		text, color = string.format("🔆 CHARGING %d%%", math.floor(cannon.Progress * 100)), Color3.new(1, 1, 1)
	end
	cannon.Label.Text = text
	cannon.Label.TextColor3 = color
	local lit = cannon.Charged and not dark
	cannon.Ring.Color = if dark then Palette.DarkMetal elseif lit then Palette.NeonGold else Palette.NeonCyan
	cannon.Lens.Color = if lit then Palette.NeonGold else Palette.DarkMetal
	cannon.Glow.Enabled = lit
end

local function buildCannon(parent: Instance, position: Vector3)
	local facing = CFrame.lookAt(position, Vector3.new(0, 0, 0))
	local model = Builder.model("LightCannon", parent)
	local base = Builder.part({
		Parent = model,
		Size = Vector3.new(3.4, 2, 3.4),
		CFrame = facing * CFrame.new(0, 1, 0),
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
	})
	local barrelCFrame = facing
		* CFrame.new(0, 3.4, -1)
		* CFrame.Angles(0, math.rad(90), 0)
		* CFrame.Angles(0, 0, math.rad(-25))
	Builder.part({
		Parent = model,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 1.6, 1.6),
		CFrame = barrelCFrame,
		Color = Color3.fromRGB(230, 232, 240),
		Material = Enum.Material.Metal,
	})
	local lens = Builder.decor({
		Name = "Lens",
		Parent = model,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 1.3, 1.3),
		CFrame = barrelCFrame * CFrame.new(-2.55, 0, 0),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Neon,
	})
	local glow = Builder.light("PointLight", lens, { Range = 12, Brightness = 2, Color = Palette.NeonGold })
	local ring = Builder.decor({
		Name = "CannonRing",
		Parent = model,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, RING_RADIUS * 2, RING_RADIUS * 2),
		CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.NeonCyan,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
	})
	ring:SetAttribute("Done", false)
	Builder.tag(ring, "LightCannon")
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(190, 36)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 160
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard
	billboard.Parent = base
	-- E / gamepad X / tap, held for a second (keyboard, controller and touch alike)
	local prompt = Builder.prompt(base, {
		Name = "FirePrompt",
		ActionText = "Fire at the Queen",
		ObjectText = "Light Cannon",
		HoldDuration = 1,
		MaxActivationDistance = 10,
		Enabled = false,
	})
	local cannon: Cannon = {
		Position = position,
		Ring = ring,
		Tip = (facing * CFrame.new(0, 4.6, -3.2)).Position,
		Lens = lens,
		Glow = glow,
		Label = label,
		FirePrompt = prompt,
		Progress = 0,
		Charged = false,
		Fired = false,
		Helpers = {},
	}
	table.insert(cannons, cannon)
	setCannonLabel(cannon)
	prompt.Triggered:Connect(function(player)
		ShadowQueen.FireCannon(cannon, player)
	end)
end

local function cannonBeam(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local cf = CFrame.lookAt((from + to) / 2, to)
	flash({ Size = Vector3.new(2.4, 2.4, length), CFrame = cf, Color = Palette.NeonGold }, 0.9, {
		Size = Vector3.new(0.2, 0.2, length),
	})
	flash({ Size = Vector3.new(0.9, 0.9, length), CFrame = cf, Color = Color3.new(1, 1, 1) }, 0.6, {
		Size = Vector3.new(0.1, 0.1, length),
	})
	flash(
		{ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = CFrame.new(from), Color = Palette.NeonGold },
		0.4,
		{
			Size = Vector3.one * 7,
		}
	)
end

-- Day: stand in the ring to charge (more people, faster).
local function runDayCannons(myToken: {})
	while dayToken == myToken do
		local dt = 0.25
		for _, cannon in cannons do
			if not cannon.Charged then
				local inside = 0
				for _, player in Players:GetPlayers() do
					local root = rootOf(player)
					if root then
						local offset = root.Position - cannon.Position
						if Vector3.new(offset.X, 0, offset.Z).Magnitude < RING_RADIUS and math.abs(offset.Y) < 6 then
							inside += 1
							cannon.Helpers[player] = true
						end
					end
				end
				local rate = math.min(inside, 3) / T.ChargeDay
				if rate > 0 then
					cannon.Progress = math.min(1, cannon.Progress + rate * dt)
					if cannon.Progress >= 1 then
						cannon.Charged = true
						cannon.Ring:SetAttribute("Done", true)
						MissionEvents.record(nil, "CannonCharged")
						for helper in cannon.Helpers do
							if helper.Parent then
								MissionEvents.record(helper, "CannonHelped")
							end
						end
						Notify.all("🔆 A light cannon is fully charged!", "success")
					end
					setCannonLabel(cannon)
				end
			end
		end
		task.wait(dt)
	end
end

-- Night: every cannon recharges by itself (faster with people in the ring), the lit ring
-- stuns and burns crawlers, and the guide marker points at cannons that can fire now.
local function runNightCannons(myToken: {})
	local dt = 0.25
	while nightToken == myToken do
		local ready = 0
		for _, cannon in cannons do
			local inside = 0
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root then
					local offset = root.Position - cannon.Position
					if Vector3.new(offset.X, 0, offset.Z).Magnitude < RING_RADIUS and math.abs(offset.Y) < 6 then
						inside += 1
					end
				end
			end
			if not cannon.Charged and fight and not fight.Defeated then
				cannon.Progress = math.min(1, cannon.Progress + QueenLogic.nightChargeRate(inside) * dt)
				if cannon.Progress >= 1 then
					cannon.Charged = true
					Notify.all("🔆 A light cannon is ready to fire!", "info")
				end
			end
			for _, enemy in table.clone(EnemyService.GetAll()) do
				local offset = enemy.Root.Position - cannon.Position
				if not enemy.Dead and Vector3.new(offset.X, 0, offset.Z).Magnitude < RING_RADIUS + 1.5 then
					EnemyService.Stun(enemy, 0.5)
					EnemyService.Damage(enemy, WARD_DPS * dt)
				end
			end
			local canFire = readyToFire(cannon)
			cannon.FirePrompt.Enabled = canFire
			cannon.Ring:SetAttribute("Done", not canFire)
			if canFire then
				ready += 1
			end
			setCannonLabel(cannon)
		end
		ReplicatedStorage:SetAttribute("BossCannonsReady", ready)
		task.wait(dt)
	end
end

-- ── mirror puzzle ───────────────────────────────────────────────────────────

local function drawBeam()
	local parent = beamFolder
	if not parent then
		return
	end
	parent:ClearAllChildren()
	local cells, dir, hit = MirrorGrid.trace(mirrorStates)
	local points = { cellPosition(MirrorGrid.SourceCell[1] - 1, MirrorGrid.SourceCell[2]) }
	for _, cell in cells do
		table.insert(points, cellPosition(cell[1], cell[2]))
	end
	local last = cells[#cells]
	if last then
		local exit = cellPosition(last[1], last[2]) + Vector3.new(dir[1], 0, dir[2]) * (if hit then 5 else 2.5)
		table.insert(points, exit)
	end
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		if length > 0.05 then
			Builder.decor({
				Parent = parent,
				Size = Vector3.new(0.35, 0.35, length),
				CFrame = CFrame.lookAt((a + b) / 2, b),
				Color = if hit then Palette.NeonCyan else Palette.WarmLight,
				Material = Enum.Material.Neon,
			})
		end
	end
end

local function mirrorYaw(state: string): CFrame
	-- the pane's long axis runs SW–NE for "/" and NW–SE for "\"
	return CFrame.Angles(0, if state == "/" then math.rad(-45) else math.rad(45), 0)
end

local function onSolved(player: Player)
	solved = true
	for _, pedestal in mirrorParts do
		pedestal:SetAttribute("Done", true)
		local prompt = pedestal:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end
	end
	MissionEvents.record(player, "LightPuzzleSolved")
	for _, member in Players:GetPlayers() do
		local data = DataService.Get(member)
		if data then
			data.Equipment.PrismLens = true
			member:SetAttribute("Equip_PrismLens", true)
		end
	end
	Notify.all(
		"🔷 The crystal blazes and shows HER: the Shadow Queen. Everyone here earned the PRISM LENS (+50% light damage vs bosses)!",
		"levelup"
	)
end

local function buildPuzzle(parent: Instance)
	Builder.part({
		Parent = parent,
		Size = Vector3.new(25, 0.2, 25),
		CFrame = CFrame.new(0, 0.1, 48),
		Color = Color3.fromRGB(26, 22, 40),
		Material = Enum.Material.Marble,
	})
	for i = 0, 5 do
		local offset = -12.5 + i * 5
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(0.15, 0.05, 25),
			CFrame = CFrame.new(offset, 0.22, 48),
			Color = Palette.NeonPurple,
			Material = Enum.Material.Neon,
		})
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(25, 0.05, 0.15),
			CFrame = CFrame.new(0, 0.22, 35.5 + i * 5),
			Color = Palette.NeonPurple,
			Material = Enum.Material.Neon,
		})
	end
	local source = Builder.part({
		Parent = parent,
		Size = Vector3.new(2, 3, 2),
		CFrame = CFrame.new(cellPosition(-1, MirrorGrid.SourceCell[2], 1.5)),
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
	})
	Builder.light("PointLight", source, { Range = 10, Brightness = 2, Color = Palette.WarmLight })
	local crystal = Builder.decor({
		Name = "Crystal",
		Parent = parent,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.4,
		CFrame = CFrame.new(cellPosition(MirrorGrid.ReceiverCell[1], MirrorGrid.ReceiverCell[2] + 1)),
		Color = Color3.fromRGB(120, 130, 160),
		Material = Enum.Material.Glass,
	})
	Builder.part({
		Parent = parent,
		Size = Vector3.new(2, 1.3, 2),
		CFrame = CFrame.new(cellPosition(MirrorGrid.ReceiverCell[1], MirrorGrid.ReceiverCell[2] + 1, 0.65)),
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
	})

	repeat -- start unsolved
		for i = 1, #MirrorGrid.Mirrors do
			mirrorStates[i] = if rng:NextNumber() < 0.5 then "/" else "\\"
		end
	until not MirrorGrid.solved(mirrorStates)

	for i, cell in MirrorGrid.Mirrors do
		local center = cellPosition(cell[1], cell[2], 0)
		local pedestal = Builder.part({
			Name = "Mirror",
			Parent = parent,
			Size = Vector3.new(1.6, 1, 1.6),
			CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)),
			Color = Palette.DarkMetal,
			Material = Enum.Material.Metal,
		})
		local pane = Builder.decor({
			Parent = parent,
			Size = Vector3.new(4, 3, 0.25),
			CFrame = CFrame.new(center + Vector3.new(0, 2.5, 0)) * mirrorYaw(mirrorStates[i]),
			Color = Color3.fromRGB(200, 220, 240),
			Material = Enum.Material.Glass,
			Reflectance = 0.5,
			Transparency = 0.2,
		})
		pedestal:SetAttribute("Done", false)
		Builder.tag(pedestal, "Mirror")
		table.insert(mirrorParts, pedestal)
		local prompt = Builder.prompt(pedestal, {
			Name = "RotatePrompt",
			ActionText = "Rotate Mirror",
			ObjectText = "Mirror",
			MaxActivationDistance = 7,
		})
		prompt.Triggered:Connect(function(player)
			if stage() ~= "Day" or solved or dayToken == nil then
				return
			end
			mirrorStates[i] = if mirrorStates[i] == "/" then "\\" else "/"
			pane.CFrame = CFrame.new(center + Vector3.new(0, 2.5, 0)) * mirrorYaw(mirrorStates[i])
			drawBeam()
			if MirrorGrid.solved(mirrorStates) then
				crystal.Material = Enum.Material.Neon
				crystal.Color = Palette.NeonCyan
				Builder.light("PointLight", crystal, { Range = 24, Brightness = 4, Color = Palette.NeonCyan })
				onSolved(player)
			end
		end)
	end
	drawBeam()
end

-- ── the Queen: model ────────────────────────────────────────────────────────

local function publishBoss()
	local f = fight
	if not f then
		return
	end
	local state = QueenLogic.shieldState(f, os.clock())
	ReplicatedStorage:SetAttribute("BossHP", math.max(0, math.ceil(f.Hp)))
	ReplicatedStorage:SetAttribute("BossMaxHP", f.MaxHp)
	ReplicatedStorage:SetAttribute("BossPhase", f.Phase)
	ReplicatedStorage:SetAttribute("BossShield", state)
	ReplicatedStorage:SetAttribute("BossShielded", state == "Shielded")
end

-- Body part welded to the anchored root; `offset` is in her local space (-Z forward).
local function body(
	model: Model,
	root: BasePart,
	offset: CFrame,
	props: { [string]: any },
	className: string?
): BasePart
	props.Parent = model
	props.Anchored = false
	props.Massless = true
	props.CanTouch = false
	props.CFrame = root.CFrame * offset
	local part = Builder.decor(props, className)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function ellipsoid(
	model: Model,
	root: BasePart,
	offset: CFrame,
	size: Vector3,
	color: Color3,
	props: { [string]: any }?
)
	local all = props or {}
	all.Size = size
	all.Color = color
	local part = body(model, root, offset, all)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function limb(model: Model, root: BasePart, a: Vector3, b: Vector3, thickness: number, color: Color3)
	local length = (b - a).Magnitude
	return body(model, root, CFrame.lookAt((a + b) / 2, b), {
		Size = Vector3.new(thickness, thickness, length),
		Color = color,
	})
end

-- A procedural queen (no external mesh): bloated abdomen with glowing bands, armoured
-- thorax, crowned head with six eyes, mandibles, translucent veil-wings and six long
-- legs that dangle as she hovers. Invisible "Weakpoint" spheres (QueenLogic.Body) are
-- the only queryable parts: the mouse lands on them and the server tests light on them.
local function buildQueen(parent: Instance): (Model, BasePart, { BasePart }, { number })
	local model = Instance.new("Model")
	model.Name = "ShadowQueen"
	local root = Builder.decor({
		Name = "Root",
		Parent = model,
		Size = Vector3.one,
		CFrame = CFrame.new(),
		Transparency = 1,
	})
	model.PrimaryPart = root
	local shell = Color3.fromRGB(34, 12, 56)
	local dark = Color3.fromRGB(20, 8, 34)

	ellipsoid(model, root, CFrame.new(0, 1.5, 0), Vector3.new(7, 6, 7), shell, { Name = "Thorax" })
	local abdomenCFrame = CFrame.new(0, 0.5, 6) * CFrame.Angles(math.rad(-12), 0, 0)
	local abdomen = ellipsoid(model, root, abdomenCFrame, Vector3.new(9, 7.5, 12), dark, { Name = "Abdomen" })
	for _, z in { -2.6, 0, 2.6 } do
		ellipsoid(
			model,
			root,
			abdomenCFrame * CFrame.new(0, 0, z),
			Vector3.new(9.3 - math.abs(z) * 0.5, 7.8 - math.abs(z) * 0.5, 0.45),
			Palette.NeonPurple,
			{ Name = "Band", Material = Enum.Material.Neon }
		)
	end
	local head = ellipsoid(model, root, CFrame.new(0, 3.6, -4.6), Vector3.new(5.5, 4.6, 5), dark, { Name = "Head" })

	-- eyes: two large, four small, all one colour that changes with the phase
	local eyeSpots = {
		{ CFrame.new(-1.2, 4.1, -6.95) * CFrame.Angles(0, -0.3, 0.25), Vector3.new(1.5, 0.75, 0.3) },
		{ CFrame.new(1.2, 4.1, -6.95) * CFrame.Angles(0, 0.3, -0.25), Vector3.new(1.5, 0.75, 0.3) },
		{ CFrame.new(-2.1, 4.9, -6.3) * CFrame.Angles(0, -0.6, 0), Vector3.new(0.55, 0.45, 0.25) },
		{ CFrame.new(2.1, 4.9, -6.3) * CFrame.Angles(0, 0.6, 0), Vector3.new(0.55, 0.45, 0.25) },
		{ CFrame.new(-0.6, 5.1, -6.85), Vector3.new(0.45, 0.4, 0.25) },
		{ CFrame.new(0.6, 5.1, -6.85), Vector3.new(0.45, 0.4, 0.25) },
	}
	for _, spot in eyeSpots do
		body(model, root, spot[1], {
			Name = "Eye",
			Size = spot[2],
			Color = EYE_COLORS[1],
			Material = Enum.Material.Neon,
		})
	end
	Builder.light("PointLight", head, { Name = "EyeGlow", Range = 18, Brightness = 2.5, Color = EYE_COLORS[1] })

	for _, side in { -1, 1 } do
		body(model, root, CFrame.new(side * 1.1, 2.1, -7) * CFrame.Angles(math.rad(25), side * 0.35, 0), {
			Name = "Mandible",
			Size = Vector3.new(0.6, 1.1, 2.6),
			Color = Palette.NeonPink,
			Material = Enum.Material.Neon,
		}, "WedgePart")
	end

	-- crown: gold band, seven neon spikes (tallest in the middle) and a jewel
	body(model, root, CFrame.new(0, 5.75, -4.5), {
		Name = "CrownBand",
		Size = Vector3.new(5.2, 0.55, 4.4),
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
	})
	for i = -3, 3 do
		local height = 3.6 - math.abs(i) * 0.65
		body(
			model,
			root,
			CFrame.new(i * 0.75, 6 + height / 2, -4.5 - math.abs(i) * 0.1) * CFrame.Angles(0, 0, -i * 0.12),
			{
				Name = "Crown",
				Size = Vector3.new(0.45, height, 0.45),
				Color = Palette.NeonGold,
				Material = Enum.Material.Neon,
			}
		)
	end
	body(model, root, CFrame.new(0, 6.1, -6.75), {
		Name = "Jewel",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.9,
		Color = Palette.NeonCyan,
		Material = Enum.Material.Neon,
	})

	-- veil-wings: translucent membranes with neon edges (the silhouette from below)
	for _, side in { -1, 1 } do
		local wing = CFrame.new(side * 4.8, 5.4, 2.5) * CFrame.Angles(0, side * math.rad(-18), side * math.rad(-38))
		body(model, root, wing, {
			Name = "Veil",
			Size = Vector3.new(0.2, 9, 12),
			Color = Palette.NeonPurple,
			Material = Enum.Material.Glass,
			Transparency = 0.55,
		})
		body(model, root, wing * CFrame.new(0, 4.5, 0), {
			Name = "VeilEdge",
			Size = Vector3.new(0.3, 0.3, 12),
			Color = Palette.NeonPurple,
			Material = Enum.Material.Neon,
		})
	end

	-- six legs: up and out from the thorax, then down to neon claws below her
	for _, side in { -1, 1 } do
		for _, z in { -1.8, 0, 1.8 } do
			local hip = Vector3.new(side * 3, 2, z)
			local knee = hip + Vector3.new(side * 5.5, 4, z * 0.6)
			local tip = knee + Vector3.new(side * 3, -10, z * 0.4)
			limb(model, root, hip, knee, 0.75, shell)
			limb(model, root, knee, tip, 0.5, dark)
			body(model, root, CFrame.lookAt(tip, tip + Vector3.new(0, -1, 0)), {
				Name = "Claw",
				Size = Vector3.new(0.4, 0.4, 1.4),
				Color = Palette.NeonPurple,
				Material = Enum.Material.Neon,
			})
		end
	end

	local mist = Instance.new("ParticleEmitter")
	mist.Rate = 5
	mist.Lifetime = NumberRange.new(1.6, 2.4)
	mist.Speed = NumberRange.new(1, 2)
	mist.SpreadAngle = Vector2.new(180, 180)
	mist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(0.5, 5),
		NumberSequenceKeypoint.new(1, 0),
	})
	mist.Transparency = NumberSequence.new(0.55, 1)
	mist.Color = ColorSequence.new(Color3.fromRGB(70, 20, 110))
	mist.LightEmission = 0.3
	mist.Parent = abdomen

	local shield = body(model, root, CFrame.new(0, 1.5, 0.5), {
		Name = "ShieldBubble",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 26,
		Color = Palette.NeonPurple,
		Material = Enum.Material.ForceField,
	})
	shield.Transparency = 0

	local weakpoints, radii = {}, {}
	for _, spot in QueenLogic.Body do
		local part = body(model, root, CFrame.new(spot.Offset[1], spot.Offset[2], spot.Offset[3]), {
			Name = "Weakpoint" .. spot.Name,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * spot.Radius * 2,
			Transparency = 1,
		})
		part.CanQuery = true -- the mouse cursor lands on her, so aiming feels right
		table.insert(weakpoints, part)
		table.insert(radii, spot.Radius)
	end

	-- PivotTo moves every part explicitly, so the welds are created with the right offsets
	model:PivotTo(CFrame.new(ORBIT_RADIUS, HOVER_Y, 0))
	model.Parent = parent
	return model, root, weakpoints, radii
end

local function setEyes(model: Model, color: Color3)
	for _, part in model:GetDescendants() do
		if (part:IsA("BasePart") and part.Name == "Eye") or (part:IsA("PointLight") and part.Name == "EyeGlow") then
			(part :: any).Color = color
		end
	end
end

local function nearestRoot(position: Vector3): BasePart?
	local best, bestDistance = nil, math.huge
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and (root.Position - position).Magnitude < bestDistance then
			best, bestDistance = root, (root.Position - position).Magnitude
		end
	end
	return best
end

local function flushDamage()
	for player, entry in pendingDamage do
		if player.Parent then
			Notify.effect(player, "BossHit", { Amount = math.floor(entry.Amount + 0.5), Position = entry.Position })
		end
	end
	table.clear(pendingDamage)
end

local function onShieldState(model: Model, state: QueenLogic.ShieldState, previous: QueenLogic.ShieldState?)
	publishBoss()
	local bubble = model:FindFirstChild("ShieldBubble") :: BasePart?
	if bubble then
		bubble.Transparency = if state == "Shielded" then 0 else 1
	end
	if state == "Shielded" and previous ~= nil then
		Notify.all("🛡️ Her shield is back up. Fire another 🔆 cannon!", "warning")
	end
end

-- Hovering orbit around the fountain, facing the nearest player, plus the "animations":
-- rearing up before a slam, the slam drop, recoiling from light, the phase roar, and a
-- flickering bubble while the shield returns. Runs every server frame (one CFrame).
local function startMotion(myToken: {}, model: Model, root: BasePart)
	local angle = 0
	local targetAngle = 0
	local retargetAt = 0
	local t = 0
	local lastState: QueenLogic.ShieldState? = nil
	local flushAt = 0
	local bubble = model:FindFirstChild("ShieldBubble") :: BasePart?
	motion = RunService.Heartbeat:Connect(function(dt)
		local f = fight
		if nightToken ~= myToken or not f or dying then
			return
		end
		local now = os.clock()
		t += dt
		if now >= retargetAt then
			retargetAt = now + rng:NextNumber(3, 5)
			local target = nearestRoot(root.Position)
			local base = if target then math.atan2(target.Position.Z, target.Position.X) else angle
			targetAngle = base + rng:NextNumber(-0.7, 0.7)
		end
		if not sweepAngle then -- she holds still while the floor beam turns around her
			local diff = (targetAngle - angle + math.pi) % (math.pi * 2) - math.pi
			angle += math.clamp(diff, -ANGULAR_SPEED * dt, ANGULAR_SPEED * dt)
		end

		local lift, pitch, jitter = 0, 0, Vector3.zero
		if now < pose.RearUntil then
			local k = math.clamp(1 - (pose.RearUntil - now) / pose.RearLength, 0, 1)
			lift += 3 * k
			pitch += math.rad(20) * k
		elseif now < pose.DropUntil then
			lift -= 1.5
			pitch -= math.rad(10)
		end
		if now < pose.RoarUntil then
			lift += 2
			pitch += math.rad(24)
			jitter += Vector3.new(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.25, 0.25))
		end
		if now < pose.RecoilUntil then
			pitch += math.rad(7)
			jitter += Vector3.new(rng:NextNumber(-0.15, 0.15), rng:NextNumber(-0.15, 0.15), 0)
		end

		local at = Vector3.new(
			math.cos(angle) * ORBIT_RADIUS,
			HOVER_Y + math.sin(t * 1.5) * 0.6 + lift,
			math.sin(angle) * ORBIT_RADIUS
		)
		local look
		if sweepAngle then
			look = at + Vector3.new(math.cos(sweepAngle), 0, -math.sin(sweepAngle))
		else
			local target = nearestRoot(at)
			look = if target then Vector3.new(target.Position.X, at.Y, target.Position.Z) else Vector3.new(0, at.Y, 0)
		end
		local facing = if (look - at).Magnitude > 0.1 then CFrame.lookAt(at, look) else CFrame.new(at)
		root.CFrame = (facing + jitter) * CFrame.Angles(pitch, 0, 0)

		local state = QueenLogic.shieldState(f, now)
		if state ~= lastState then
			onShieldState(model, state, lastState)
			lastState = state
		end
		if bubble and state == "Returning" then
			bubble.Transparency = if math.floor(now * 5) % 2 == 0 then 0.15 else 0.85
		end
		if now >= flushAt then
			flushAt = now + 0.3
			flushDamage()
		end
	end)
end

-- ── the Queen: attacks ──────────────────────────────────────────────────────

-- Red circle on the floor that fills in as the slam approaches.
local function telegraph(position: Vector3, radius: number, seconds: number): { BasePart }
	local parent = hazards
	if not parent then
		return {}
	end
	local cf = CFrame.new(position.X, position.Y + 0.15, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	local outline = Builder.decor({
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		CFrame = cf,
		Color = Palette.NeonRed,
		Material = Enum.Material.Neon,
		Transparency = 0.7,
	})
	local fill = Builder.decor({
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, 0.5, 0.5),
		CFrame = cf,
		Color = Palette.NeonRed,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
	})
	TweenService:Create(outline, TweenInfo.new(seconds), { Transparency = 0.45 }):Play()
	TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.25, radius * 2, radius * 2),
	}):Play()
	return { outline, fill }
end

local function slam(myToken: {}, target: Player?, telegraphSeconds: number, damage: number)
	local f = fight
	if not target or not f then
		return
	end
	local targetRoot = rootOf(target)
	if not targetRoot then
		return
	end
	local center = targetRoot.Position - Vector3.new(0, 3, 0)
	local parts = telegraph(center, T.SlamRadius, telegraphSeconds)
	pose.RearUntil, pose.RearLength = os.clock() + telegraphSeconds, telegraphSeconds
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and (root.Position - center).Magnitude < T.SlamRadius + 6 then
			Notify.effect(player, "Danger", { Windup = telegraphSeconds })
		end
	end
	task.wait(telegraphSeconds)
	for _, part in parts do
		part:Destroy()
	end
	if not nightAlive(myToken) then
		return
	end
	pose.DropUntil = os.clock() + 0.3
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			local offset = root.Position - center
			if Vector3.new(offset.X, 0, offset.Z).Magnitude < T.SlamRadius and math.abs(offset.Y) < 8 then
				EnemyService.HitPlayer(player, damage, center)
			end
		end
	end
	local ring = CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	flash(
		{ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2, 2), CFrame = ring, Color = Palette.NeonPurple },
		0.45,
		{
			Size = Vector3.new(0.3, T.SlamRadius * 2.6, T.SlamRadius * 2.6),
		}
	)
	Notify.effectAll("Shake", { Position = center, Strength = 1 })
end

local function randomTarget(except: Player?): Player?
	local choices = {}
	for _, player in Players:GetPlayers() do
		if player ~= except and rootOf(player) then
			table.insert(choices, player)
		end
	end
	return if #choices > 0 then choices[rng:NextInteger(1, #choices)] else except
end

local function darkness(myToken: {})
	local f = fight
	if not f then
		return
	end
	Notify.all("🌑 She's gathering darkness: fire a cannon NOW or wait it out!", "danger")
	Notify.effectAll("DarkWarn", { Seconds = T.DarkWarning })
	task.wait(T.DarkWarning)
	if not nightAlive(myToken) then
		return
	end
	f.DarkUntil = os.clock() + T.DarkSeconds
	ReplicatedStorage:SetAttribute("BossDarkUntil", serverNow() + T.DarkSeconds)
	ReplicatedStorage:SetAttribute("BossDarkness", true)
	task.wait(T.DarkSeconds)
	if nightToken == myToken then
		ReplicatedStorage:SetAttribute("BossDarkness", false)
	end
end

local function sweep(myToken: {})
	local root = queenRoot
	local parent = hazards
	if not root or not parent then
		return
	end
	local center = Vector3.new(root.Position.X, 0, root.Position.Z)
	local start = rng:NextNumber(0, math.pi * 2)
	local function armCFrame(a: number): CFrame
		return CFrame.new(center) * CFrame.Angles(0, a, 0) * CFrame.new(SWEEP_LENGTH / 2, 1.5, 0)
	end
	local arm = Builder.decor({
		Name = "SweepBeam",
		Parent = parent,
		Size = Vector3.new(SWEEP_LENGTH, 1.5, 1.2),
		CFrame = armCFrame(start),
		Color = Palette.NeonPurple,
		Material = Enum.Material.Neon,
		Transparency = 0.75,
	})
	local zone = Builder.decor({
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, SWEEP_LENGTH * 2, SWEEP_LENGTH * 2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.NeonPurple,
		Material = Enum.Material.Neon,
		Transparency = 0.9,
	})
	sweepAngle = start
	Notify.all("⚠️ SWEEPING BEAM: JUMP when it reaches you!", "danger")
	pose.RearUntil, pose.RearLength = os.clock() + SWEEP_WARNING, SWEEP_WARNING
	task.wait(SWEEP_WARNING)
	arm.Transparency = 0
	local hitPlayers: { [Player]: boolean } = {}
	local warned: { [Player]: boolean } = {}
	local elapsed = 0
	local speed = math.pi * 2 / SWEEP_SECONDS
	while elapsed < SWEEP_SECONDS and nightAlive(myToken) do
		local a = start + elapsed * speed
		arm.CFrame = armCFrame(a)
		sweepAngle = a
		local frame = CFrame.new(center) * CFrame.Angles(0, a, 0)
		for _, player in Players:GetPlayers() do
			local playerRoot = rootOf(player)
			if playerRoot and not hitPlayers[player] then
				local p = frame:PointToObjectSpace(playerRoot.Position)
				local radial = math.sqrt(p.X * p.X + p.Z * p.Z)
				if radial < SWEEP_LENGTH + 2 and p.Y < 8 then
					-- in the arm's frame the world turns toward +Z, so the arm reaches points
					-- at negative angles first: radians left before it gets here
					local ahead = (-math.atan2(p.Z, p.X)) % (math.pi * 2)
					if not warned[player] and ahead / speed < 0.7 then
						warned[player] = true
						Notify.effect(player, "Jump")
					end
				end
				if p.X > 0 and p.X < SWEEP_LENGTH and math.abs(p.Z) < 1.6 and p.Y < 4.6 then
					hitPlayers[player] = true
					EnemyService.HitPlayer(player, T.SweepDamage, center)
				end
			end
		end
		task.wait(0.05)
		elapsed += 0.05
	end
	sweepAngle = nil
	arm:Destroy()
	zone:Destroy()
end

local function runAttacks(myToken: {})
	task.wait(T.FirstAttackDelay)
	local nextDark = 0
	while nightAlive(myToken) do
		local f = fight :: QueenLogic.Fight
		local phase = f.Phase
		local now = os.clock()
		local roll = rng:NextNumber()
		if phase >= 3 and roll < 0.35 then
			sweep(myToken)
		elseif phase >= 2 and roll < 0.55 and now >= nextDark and now >= f.ShieldUntil then
			-- never during a vulnerable window, and not twice in a row
			nextDark = now + T.DarkCooldown
			task.spawn(darkness, myToken)
			slam(myToken, randomTarget(), T.SlamTelegraph[phase], T.SlamDamage[phase])
		elseif phase >= 2 and roll < 0.8 then
			-- a second circle on someone else, or (solo) a follow-up where you dodged to
			local first = randomTarget()
			local second = randomTarget(first)
			local delay = if second == first then 1.2 else 0
			task.delay(delay, slam, myToken, second, T.SlamTelegraph[phase], T.SlamDamage[phase])
			slam(myToken, first, T.SlamTelegraph[phase], T.SlamDamage[phase])
		else
			slam(myToken, randomTarget(), T.SlamTelegraph[phase], T.SlamDamage[phase])
		end
		task.wait(T.AttackGap[f.Phase])
	end
end

-- Crawlers come late, few and slower than players, out of portals that open (with a
-- warning flare) away from every player and cannon. Sizes adapt to who is still alive.
local function runBrood(myToken: {})
	task.wait(T.BroodFirstDelay)
	while nightAlive(myToken) do
		local f = fight :: QueenLogic.Fight
		local count = QueenLogic.broodToSpawn(f.Phase, activePlayers(), EnemyService.AliveCount())
		if count > 0 then
			local playerSpots, cannonSpots, candidates = {}, {}, {}
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root then
					table.insert(playerSpots, { root.Position.X, root.Position.Z })
				end
			end
			for _, cannon in cannons do
				table.insert(cannonSpots, { cannon.Position.X, cannon.Position.Z })
			end
			for _, point in BROOD_POINTS do
				table.insert(candidates, { point.X, point.Z })
			end
			local spots = {}
			for _ = 1, count do
				local index = QueenLogic.pickSpawn(candidates, playerSpots, cannonSpots)
				if not index then
					break
				end
				local spot = table.remove(candidates, index) :: { number }
				table.insert(spots, Vector3.new(spot[1], 0, spot[2]))
			end
			if #spots > 0 then
				Notify.all("👑 The Queen calls her brood! Burn them, or lure them into a lit cannon ring.", "danger")
				local tier = T.BroodTier[f.Phase]
				for _, spot in spots do
					local disc = CFrame.new(spot + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
					flash(
						{
							Shape = Enum.PartType.Cylinder,
							Size = Vector3.new(0.2, 1, 1),
							CFrame = disc,
							Color = Palette.NeonPurple,
						},
						1.5,
						{
							Size = Vector3.new(0.2, 7, 7),
							Transparency = 0.2,
						}
					)
				end
				task.wait(1.5)
				for _, spot in spots do
					if
						nightAlive(myToken)
						and EnemyService.AliveCount() < QueenLogic.maxBrood(f.Phase, activePlayers())
					then
						EnemyService.Spawn("ShadowCrawler", spot, tier)
					end
				end
			end
		end
		task.wait(T.BroodInterval[f.Phase])
	end
end

-- ── the Queen: damage, phases, defeat ───────────────────────────────────────

local PHASE_TEXT = {
	"",
	"👑 PHASE 2: she can swallow the light. During DARKNESS cannons can't fire: dodge and wait. Double slams!",
	"👑 FINAL PHASE: a beam sweeps the floor around her. JUMP when it reaches you!",
}

local function onPhase(model: Model, newPhase: number)
	pose.RoarUntil = os.clock() + 1.6
	setEyes(model, EYE_COLORS[newPhase] or EYE_COLORS[3])
	publishBoss()
	Notify.effectAll("BossPhase", { Phase = newPhase })
	Notify.all(PHASE_TEXT[newPhase] or PHASE_TEXT[3], "danger")
	local root = queenRoot
	if root then
		local ring = CFrame.new(root.Position.X, 0.4, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		flash(
			{
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.3, 4, 4),
				CFrame = ring,
				Color = EYE_COLORS[newPhase],
			},
			0.8,
			{
				Size = Vector3.new(0.3, 60, 60),
			}
		)
		Notify.effectAll("Shake", { Position = root.Position, Strength = 1.5 })
	end
end

local function deathSequence(model: Model, root: BasePart)
	local start = os.clock()
	local base = root.CFrame
	while os.clock() - start < 1.6 and model.Parent do
		local shake = Vector3.new(rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.6, 0.6))
		root.CFrame = (base + shake)
			* CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), 0, math.rad(rng:NextNumber(-8, 8)))
		task.wait(0.05)
	end
	if not model.Parent then
		return
	end
	burst(root.Position, Palette.NeonPurple, 14, 18)
	burst(root.Position, Palette.NeonGold, 8, 12)
	Notify.effectAll("Shake", { Position = root.Position, Strength = 2 })
	TweenService:Create(root, TweenInfo.new(2.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = base * CFrame.new(0, -7, 0) * CFrame.Angles(math.rad(35), 0, math.rad(15)),
	}):Play()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			TweenService:Create(part, TweenInfo.new(2.4), { Transparency = 1 }):Play()
		elseif part:IsA("ParticleEmitter") then
			part.Enabled = false
		end
	end
	task.wait(2.5)
	model:Destroy()
end

local function defeat(model: Model)
	local root = queenRoot
	dying = true
	if motion then
		motion:Disconnect()
		motion = nil
	end
	flushDamage()
	CombatService.UnregisterLightTarget(model)
	EnemyService.ClearAll() -- remaining brood dissolve; no more spawns (loops check `dying`)
	if hazards then
		hazards:ClearAllChildren()
	end
	sweepAngle = nil
	ReplicatedStorage:SetAttribute("BossDarkness", false)
	for _, cannon in cannons do
		cannon.FirePrompt.Enabled = false
		cannon.Ring:SetAttribute("Done", true)
	end
	publishBoss()
	MissionEvents.record(nil, "QueenDefeated")
	Notify.all("👑 THE SHADOW QUEEN HAS FALLEN! Dawn breaks in a few seconds…", "levelup")
	Notify.effectAll("BossDefeated", { Position = if root then root.Position else nil })
	if root then
		task.spawn(deathSequence, model, root)
	end
	GameStateService.ShortenPhase(DEFEAT_DAWN_SECONDS)
	task.delay(6, function()
		if dying then
			ReplicatedStorage:SetAttribute("BossActive", false)
		end
	end)
end

-- Her health follows who's still here (BossScaling keeps the fraction: nothing to gain by leaving).
local function runHpScaling(myToken: {}, players: number)
	local tracker = BossScaling.new(players)
	while nightToken == myToken do
		task.wait(1)
		local f = fight
		local count = BossScaling.decide(tracker, #Players:GetPlayers(), os.clock())
		if f and count and BossScaling.rescale(f, QueenLogic.maxHp(count)) then
			publishBoss()
		end
	end
end

-- Every beam tick from CombatService while a player's light touches one of her weak
-- points (it already checked the cone and line of sight). Server-authoritative.
local function onLit(player: Player, dt: number, part: BasePart)
	local f, model = fight, queen
	if not f or not model or dying then
		return
	end
	local now = os.clock()
	local data = DataService.Get(player)
	local amount = QueenLogic.lightDamage(
		FL.DPS,
		dt,
		ProgressionService.UpgradeBonus(player, "Lens"),
		data ~= nil and data.Equipment.PrismLens == true
	)
	local result = QueenLogic.applyLight(f, now, amount)
	if result.Blocked then
		if now - (blockedAt[player] or 0) > 1.2 then
			blockedAt[player] = now
			Notify.effect(player, "BossBlocked", { Position = part.Position })
			if not toldBlocked[player] then
				toldBlocked[player] = true
				Notify.player(
					player,
					"🛡️ Her shield blocks your light. Fire a 🔆 cannon first, THEN burn her!",
					"warning"
				)
			end
		end
		return
	end
	if result.Dealt > 0 then
		local entry = pendingDamage[player]
		if entry then
			entry.Amount += result.Dealt
			entry.Position = part.Position
		else
			pendingDamage[player] = { Amount = result.Dealt, Position = part.Position }
		end
		pose.RecoilUntil = now + 0.2
		if now - lastHitPublish > 0.1 or result.Defeated then
			lastHitPublish = now
			ReplicatedStorage:SetAttribute("BossHitAt", serverNow())
			publishBoss()
		end
	end
	if result.Defeated then
		defeat(model)
	elseif result.PhaseChanged then
		onPhase(model, result.PhaseChanged)
	end
end

-- A player held the prompt on `cannon`. Validated here, not by the client: night, boss
-- alive, player beside it, and QueenLogic.fire (charged, shield up, no darkness).
function ShadowQueen.FireCannon(cannon: Cannon, player: Player)
	local f, target = fight, queenRoot
	local root = rootOf(player)
	if stage() ~= "Night" or not f or not target or dying or not root then
		return
	end
	if (root.Position - cannon.Position).Magnitude > RING_RADIUS + 8 then
		return
	end
	local ok, reason = QueenLogic.fire(f, cannon, os.clock())
	if not ok then
		Notify.player(player, REFUSAL_TEXT[reason :: string] or "The cannon can't fire right now.", "warning")
		return
	end
	cannon.FirePrompt.Enabled = false
	setCannonLabel(cannon)
	cannonBeam(cannon.Tip, target.Position)
	burst(target.Position + Vector3.new(0, 1.5, 0), Palette.NeonPurple, 12, 14)
	ReplicatedStorage:SetAttribute("BossShieldUntil", serverNow() + T.ShieldDown)
	publishBoss()
	-- the blast refills every flashlight and stuns her brood: the window is for burning her
	for _, member in Players:GetPlayers() do
		CombatService.Recharge(member)
	end
	EnemyService.StunAll(3)
	MissionEvents.record(player, "CannonFired")
	Notify.effectAll("ShieldBreak", { Position = target.Position })
	Notify.all(
		string.format(
			"💥 %s fired a light cannon! SHIELD DOWN for %d s: hold your flashlights on her!",
			player.DisplayName,
			T.ShieldDown
		),
		"success"
	)
end

local function runQueen(myToken: {})
	task.wait(6)
	local parent = folder
	if nightToken ~= myToken or not parent then
		return
	end
	local model, root, weakpoints, radii = buildQueen(parent)
	queen, queenRoot = model, root
	local players = activePlayers()
	local f = QueenLogic.new(players)
	if RunService:IsStudio() then
		-- Studio helper: Workspace.QueenTest_Phase = 2 or 3 starts her just past that threshold
		local testPhase = workspace:GetAttribute("QueenTest_Phase")
		if testPhase == 2 or testPhase == 3 then
			f.Hp = math.floor(f.MaxHp * T.PhaseAt[testPhase - 1]) - 1
			f.Phase = testPhase
			setEyes(model, EYE_COLORS[testPhase])
		end
	end
	fight = f
	dying = false
	pose = { RearUntil = 0, RearLength = 1, DropUntil = 0, RecoilUntil = 0, RoarUntil = os.clock() + 2 }
	publishBoss()
	ReplicatedStorage:SetAttribute("BossName", "THE SHADOW QUEEN")
	ReplicatedStorage:SetAttribute("BossActive", true)
	CombatService.RegisterLightTarget(model, onLit, { Parts = weakpoints, Radius = radii })
	Notify.effectAll("BossIntro")
	Notify.all(
		"👑 Her purple shield blocks all light. Hold E at a glowing 🔆 cannon to break it, then burn her with your flashlight!",
		"info"
	)
	startMotion(myToken, model, root)
	task.spawn(runBrood, myToken)
	task.spawn(runHpScaling, myToken, players)
	runAttacks(myToken)
end

-- ── level hooks ─────────────────────────────────────────────────────────────

local function resetBossAttributes()
	for _, name in { "BossActive", "BossDarkness" } do
		ReplicatedStorage:SetAttribute(name, false)
	end
	ReplicatedStorage:SetAttribute("BossCannonsReady", 0)
	ReplicatedStorage:SetAttribute("BossShield", nil)
	ReplicatedStorage:SetAttribute("BossShieldUntil", 0)
	ReplicatedStorage:SetAttribute("BossDarkUntil", 0)
end

local function clearAll()
	dayToken, nightToken = nil, nil
	if motion then
		motion:Disconnect()
		motion = nil
	end
	if queen then
		CombatService.UnregisterLightTarget(queen)
	end
	queen, queenRoot, fight = nil, nil, nil
	dying = false
	sweepAngle = nil
	table.clear(cannons)
	table.clear(mirrorStates)
	table.clear(mirrorParts)
	table.clear(pendingDamage)
	table.clear(blockedAt)
	table.clear(toldBlocked)
	solved = false
	resetBossAttributes()
	for _, f in { folder, beamFolder } do
		if f then
			f:Destroy()
		end
	end
	folder, beamFolder, hazards = nil, nil, nil
end

function ShadowQueen.StartDay()
	clearAll()
	local myToken = {}
	dayToken = myToken
	local newFolder = Instance.new("Folder")
	newFolder.Name = "QueenArena"
	newFolder.Parent = workspace
	folder = newFolder
	local beams = Instance.new("Folder")
	beams.Name = "LightBeam"
	beams.Parent = newFolder
	beamFolder = beams
	local hazardFolder = Instance.new("Folder")
	hazardFolder.Name = "Hazards"
	hazardFolder.Parent = newFolder
	hazards = hazardFolder
	for _, position in CANNONS do
		buildCannon(newFolder, position)
	end
	buildPuzzle(newFolder)
	task.spawn(runDayCannons, myToken)
end

function ShadowQueen.EndDay()
	dayToken = nil
	for _, pedestal in mirrorParts do
		local prompt = pedestal:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end
	end
end

function ShadowQueen.StartNight()
	if not folder then
		return
	end
	local myToken = {}
	nightToken = myToken
	resetBossAttributes()
	for _, cannon in cannons do
		cannon.Helpers = {}
		setCannonLabel(cannon)
	end
	task.spawn(runNightCannons, myToken)
	task.spawn(runQueen, myToken)
end

function ShadowQueen.EndNight()
	local f = fight
	if queen and f and not f.Defeated then
		Notify.all("👑 The Queen retreats into the dark… she'll be back next shift.", "danger")
	end
	clearAll()
end

return ShadowQueen
