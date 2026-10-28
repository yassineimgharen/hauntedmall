-- Level 7, "The Warning" (day) / "The Shadow Queen" (night, Chapter 1 boss).
--
-- Day:   3 light cannons around the fountain charge while players stand in their rings
--        (zone capture, faster with more people). North of the fountain, a mirror puzzle
--        (MirrorGrid) steers a beam to a crystal; solving it grants every player present
--        the Prism Lens (persisted equipment: +50% light damage against bosses).
-- Night: the Shadow Queen hovers over the atrium. Her shield only drops for SHIELD_DOWN
--        seconds when a cannon fires at her (uncharged cannons must be charged first; fired
--        ones recharge on their own). Then flashlights hurt her.
--          Phase 1 (>66%)  telegraphed slams, brood summons
--          Phase 2 (>33%)  + double slams, darkness pulses (cannons can't fire)
--          Phase 3         + a sweeping floor beam you must jump over

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local ShadowCrawler = require(script.Parent.Parent.Enemies.ShadowCrawler)
local CombatService = require(script.Parent.Parent.Services.CombatService)
local DataService = require(script.Parent.Parent.Services.DataService)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
local ProgressionService = require(script.Parent.Parent.Services.ProgressionService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local MirrorGrid = require(script.Parent.MirrorGrid)

local ShadowQueen = {}

local FL = EnemyConfig.Flashlight
local CHARGE_SECONDS = 20 -- one person standing in the ring
local RECHARGE_SECONDS = 25 -- automatic, after a cannon has fired at night
local RING_RADIUS = 6
local SHIELD_DOWN = 8
local PRISM_BONUS = 0.5
local BASE_HP = 700
local HP_PER_PLAYER = 350
local SLAM_RADIUS = 9
local SLAM_DAMAGE = 30
local SWEEP_LENGTH = 40
local SWEEP_DAMAGE = 25
local BROOD_TIER = 6
local HOVER_Y = 8
local SPEED = 7

local CANNONS = { Vector3.new(14.5, 0, 25.1), Vector3.new(-14.5, 0, 25.1), Vector3.new(0, 0, -30) }
local ARENA = {
	Vector3.new(0, 0, 0),
	Vector3.new(-25, 0, -20),
	Vector3.new(25, 0, -15),
	Vector3.new(-20, 0, 20),
	Vector3.new(22, 0, 18),
	Vector3.new(0, 0, -40),
}

type Cannon = {
	Position: Vector3,
	Ring: BasePart,
	Tip: Vector3,
	Label: TextLabel,
	FirePrompt: ProximityPrompt,
	Progress: number,
	Charged: boolean,
	Fired: boolean,
	Helpers: { [Player]: boolean },
}

local folder: Folder? = nil
local beamFolder: Folder? = nil
local dayToken: {}? = nil
local nightToken: {}? = nil
local cannons: { Cannon } = {}
local mirrorStates: { string } = {}
local mirrorParts: { BasePart } = {}
local solved = false
local queen: Model? = nil
local queenRoot: BasePart? = nil
local hp, maxHp = 0, 1
local shieldUntil = 0
local darkUntil = 0
local phase = 1
local rng = Random.new()

local function stage(): string
	return GameStateService.GetPhase()
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

local function strike(player: Player, damage: number, from: Vector3)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(player)
	if not humanoid or not root then
		return
	end
	humanoid:TakeDamage(damage)
	local flat = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
	Notify.effect(player, "Hit", { Damage = damage, Direction = if flat.Magnitude > 0.01 then flat.Unit else nil })
end

-- ── cannons ─────────────────────────────────────────────────────────────────

local function setCannonLabel(cannon: Cannon)
	cannon.Label.Text = if cannon.Charged
		then "🔆 CHARGED"
		else string.format("🔆 %d%%", math.floor(cannon.Progress * 100))
	cannon.Label.TextColor3 = if cannon.Charged then Palette.NeonGold else Color3.new(1, 1, 1)
	cannon.Ring.Color = if cannon.Charged then Palette.NeonGold else Palette.NeonCyan
end

local function fireBeam(from: Vector3, to: Vector3)
	local parent = folder
	if not parent then
		return
	end
	local length = (to - from).Magnitude
	local beam = Builder.decor({
		Parent = parent,
		Size = Vector3.new(1.2, 1.2, length),
		CFrame = CFrame.lookAt((from + to) / 2, to),
		Color = Palette.NeonGold,
		Material = Enum.Material.Neon,
	})
	TweenService:Create(beam, TweenInfo.new(0.7), { Transparency = 1, Size = Vector3.new(0.2, 0.2, length) }):Play()
	task.delay(0.8, function()
		beam:Destroy()
	end)
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
	Builder.part({
		Parent = model,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 1.6, 1.6),
		CFrame = facing
			* CFrame.new(0, 3.4, -1)
			* CFrame.Angles(0, math.rad(90), 0)
			* CFrame.Angles(0, 0, math.rad(-25)),
		Color = Color3.fromRGB(230, 232, 240),
		Material = Enum.Material.Metal,
	})
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
	billboard.Size = UDim2.fromOffset(130, 32)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 150
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard
	billboard.Parent = base
	local prompt = Builder.prompt(base, {
		Name = "FirePrompt",
		ActionText = "Fire Light Cannon",
		ObjectText = "Light Cannon",
		HoldDuration = 1.5,
		MaxActivationDistance = 9,
		Enabled = false,
	})
	local cannon: Cannon = {
		Position = position,
		Ring = ring,
		Tip = (facing * CFrame.new(0, 4.6, -3.2)).Position,
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
		local target = queenRoot
		if stage() ~= "Night" or not cannon.Charged or not target or hp <= 0 or os.clock() < darkUntil then
			return
		end
		cannon.Charged = false
		cannon.Fired = true
		cannon.Progress = 0
		prompt.Enabled = false
		setCannonLabel(cannon)
		fireBeam(cannon.Tip, target.Position)
		shieldUntil = os.clock() + SHIELD_DOWN
		ReplicatedStorage:SetAttribute("BossShielded", false)
		MissionEvents.record(player, "CannonFired")
		Notify.all(
			string.format("💥 %s fired a light cannon! Her shield is DOWN: burn her!", player.DisplayName),
			"success"
		)
	end)
end

-- Day: stand in the ring. Night: charge if never charged; fired cannons recharge alone.
local function runCannons(myToken: {}, isNight: boolean)
	while (if isNight then nightToken else dayToken) == myToken do
		local dt = 0.25
		for _, cannon in cannons do
			if not cannon.Charged then
				local inside = {}
				for _, player in Players:GetPlayers() do
					local root = rootOf(player)
					if root then
						local offset = root.Position - cannon.Position
						if Vector3.new(offset.X, 0, offset.Z).Magnitude < RING_RADIUS and math.abs(offset.Y) < 6 then
							table.insert(inside, player)
							cannon.Helpers[player] = true
						end
					end
				end
				local rate = math.min(#inside, 3) / CHARGE_SECONDS
				if isNight and cannon.Fired then
					rate = math.max(rate, 1 / RECHARGE_SECONDS)
				end
				if rate > 0 then
					cannon.Progress = math.min(1, cannon.Progress + rate * dt)
					if cannon.Progress >= 1 then
						cannon.Charged = true
						if not isNight then
							cannon.Ring:SetAttribute("Done", true)
							MissionEvents.record(nil, "CannonCharged")
							for helper in cannon.Helpers do
								if helper.Parent then
									MissionEvents.record(helper, "CannonHelped")
								end
							end
							Notify.all("🔆 A light cannon is fully charged!", "success")
						else
							Notify.all("🔆 A light cannon is ready to fire!", "info")
						end
					end
					setCannonLabel(cannon)
				end
			end
			if isNight then
				cannon.FirePrompt.Enabled = cannon.Charged and hp > 0 and os.clock() >= darkUntil
			end
		end
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

-- ── the Queen ───────────────────────────────────────────────────────────────

local function publishBoss()
	ReplicatedStorage:SetAttribute("BossHP", math.max(0, math.ceil(hp)))
	ReplicatedStorage:SetAttribute("BossMaxHP", maxHp)
	ReplicatedStorage:SetAttribute("BossPhase", phase)
	ReplicatedStorage:SetAttribute("BossShielded", os.clock() >= shieldUntil)
end

local function buildQueen(parent: Instance): (Model, BasePart)
	local model = ShadowCrawler.build()
	model.Name = "ShadowQueen"
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	model.PrimaryPart = root
	model:ScaleTo(3.2)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	root.Anchored = true
	local skull = model:FindFirstChild("Skull") :: BasePart?
	if skull then
		for i = -2, 2 do
			local spike = Builder.decor({
				Name = "Crown",
				Parent = model,
				Size = Vector3.new(0.8, 2.4 - math.abs(i) * 0.4, 0.8),
				CFrame = skull.CFrame * CFrame.new(i * 1.4, skull.Size.Y / 2 + 0.9, 0) * CFrame.Angles(0, 0, -i * 0.15),
				Color = Palette.Gold,
				Material = Enum.Material.Neon,
				Anchored = false,
			})
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = skull
			weld.Part1 = spike
			weld.Parent = spike
		end
	end
	local hitbox = Builder.decor({
		Name = "Hitbox",
		Parent = model,
		Size = Vector3.new(8, 6, 10),
		CFrame = root.CFrame * CFrame.new(0, -2, 0),
		Transparency = 1,
		Anchored = false,
	})
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = hitbox
	weld.Parent = hitbox
	model.PrimaryPart = hitbox
	local shield = Instance.new("Highlight")
	shield.Name = "Shield"
	shield.FillColor = Palette.NeonPurple
	shield.FillTransparency = 0.7
	shield.OutlineColor = Palette.NeonPurple
	shield.Parent = model
	root.CFrame = CFrame.new(0, HOVER_Y, 0)
	model.Parent = parent
	return model, root
end

local function telegraph(position: Vector3, radius: number, seconds: number): BasePart?
	local parent = folder
	if not parent then
		return nil
	end
	local circle = Builder.decor({
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		CFrame = CFrame.new(position.X, position.Y + 0.15, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.NeonRed,
		Material = Enum.Material.Neon,
		Transparency = 0.75,
	})
	TweenService:Create(circle, TweenInfo.new(seconds), { Transparency = 0.25 }):Play()
	return circle
end

local function slam(myToken: {}, telegraphSeconds: number)
	local victims = {}
	for _, player in Players:GetPlayers() do
		if rootOf(player) then
			table.insert(victims, player)
		end
	end
	if #victims == 0 then
		return
	end
	local target = rootOf(victims[rng:NextInteger(1, #victims)])
	if not target then
		return
	end
	local center = Vector3.new(target.Position.X, target.Position.Y - 3, target.Position.Z)
	local circle = telegraph(center, SLAM_RADIUS, telegraphSeconds)
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and (root.Position - center).Magnitude < SLAM_RADIUS + 6 then
			Notify.effect(player, "Danger", { Windup = telegraphSeconds })
		end
	end
	task.wait(telegraphSeconds)
	if circle then
		circle:Destroy()
	end
	if nightToken ~= myToken or hp <= 0 then
		return
	end
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			local offset = root.Position - center
			if Vector3.new(offset.X, 0, offset.Z).Magnitude < SLAM_RADIUS and math.abs(offset.Y) < 8 then
				strike(player, SLAM_DAMAGE, center)
			end
		end
	end
	Notify.effectAll("Shake", { Position = center })
end

local function brood()
	local root = queenRoot
	if not root then
		return
	end
	Notify.all("👑 The Queen calls her brood!", "danger")
	for i = 1, 3 do
		if EnemyService.AliveCount() >= 10 then
			break
		end
		local angle = i / 3 * math.pi * 2 + rng:NextNumber(0, 1)
		EnemyService.Spawn(
			"ShadowCrawler",
			Vector3.new(root.Position.X + math.cos(angle) * 10, 0, root.Position.Z + math.sin(angle) * 10),
			BROOD_TIER
		)
	end
end

local function darkness(myToken: {})
	Notify.all("🌑 She swallows the light! The cannons can't fire!", "danger")
	darkUntil = os.clock() + 6
	ReplicatedStorage:SetAttribute("BossDarkness", true)
	task.wait(6)
	if nightToken == myToken then
		ReplicatedStorage:SetAttribute("BossDarkness", false)
	end
end

local function sweep(myToken: {})
	local root = queenRoot
	local parent = folder
	if not root or not parent then
		return
	end
	local center = Vector3.new(root.Position.X, 0, root.Position.Z)
	local start = rng:NextNumber(0, math.pi * 2)
	local function armCFrame(angle: number): CFrame
		return CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(SWEEP_LENGTH / 2, 1.5, 0)
	end
	local arm = Builder.decor({
		Parent = parent,
		Size = Vector3.new(SWEEP_LENGTH, 1.5, 1.2),
		CFrame = armCFrame(start),
		Color = Palette.NeonPurple,
		Material = Enum.Material.Neon,
		Transparency = 0.7,
	})
	Notify.all("⚠️ Sweeping beam! JUMP over it!", "danger")
	task.wait(1.5)
	arm.Transparency = 0
	local hitPlayers: { [Player]: boolean } = {}
	local duration = 6
	local elapsed = 0
	while elapsed < duration and nightToken == myToken and hp > 0 do
		local angle = start + elapsed / duration * math.pi * 2
		arm.CFrame = armCFrame(angle)
		local frame = CFrame.new(center) * CFrame.Angles(0, angle, 0)
		for _, player in Players:GetPlayers() do
			local playerRoot = rootOf(player)
			if playerRoot and not hitPlayers[player] then
				local p = frame:PointToObjectSpace(playerRoot.Position)
				if p.X > 0 and p.X < SWEEP_LENGTH and math.abs(p.Z) < 1.6 and p.Y < 4.6 then
					hitPlayers[player] = true
					strike(player, SWEEP_DAMAGE, center)
				end
			end
		end
		task.wait(0.05)
		elapsed += 0.05
	end
	arm:Destroy()
end

local function setPhase(newPhase: number)
	if newPhase == phase then
		return
	end
	phase = newPhase
	publishBoss()
	Notify.effectAll("BossPhase", { Phase = newPhase })
	Notify.all(
		if newPhase == 2
			then "👑 PHASE 2: She's furious! Darkness and double slams!"
			else "👑 FINAL PHASE: sweeping beams! Jump!",
		"danger"
	)
end

local function defeat()
	local model = queen
	MissionEvents.record(nil, "QueenDefeated")
	CombatService.UnregisterLightTarget(model :: Model)
	EnemyService.ClearAll()
	ReplicatedStorage:SetAttribute("BossDarkness", false)
	Notify.all("👑 THE SHADOW QUEEN HAS FALLEN! Chapter 1 complete at dawn!", "levelup")
	Notify.effectAll("BossDefeated")
	if model then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				TweenService:Create(part, TweenInfo.new(2.5), { Transparency = 1 }):Play()
			end
		end
		task.delay(2.6, function()
			model:Destroy()
		end)
	end
	queen, queenRoot = nil, nil
	task.delay(3, function()
		ReplicatedStorage:SetAttribute("BossActive", false)
	end)
end

local function onLit(player: Player, dt: number)
	if hp <= 0 or os.clock() >= shieldUntil then
		return
	end
	local data = DataService.Get(player)
	local prism = if data and data.Equipment.PrismLens then 1 + PRISM_BONUS else 1
	hp -= FL.DPS * dt * (1 + ProgressionService.UpgradeBonus(player, "Lens")) * prism
	if hp <= 0 then
		hp = 0
		publishBoss()
		defeat()
		return
	end
	local fraction = hp / maxHp
	setPhase(if fraction > 0.66 then 1 elseif fraction > 0.33 then 2 else 3)
end

local function runQueen(myToken: {})
	task.wait(6)
	local parent = folder
	if nightToken ~= myToken or not parent then
		return
	end
	local model, root = buildQueen(parent)
	queen, queenRoot = model, root
	local alive = 0
	for _, player in Players:GetPlayers() do
		if player.Character then
			alive += 1
		end
	end
	maxHp = BASE_HP + HP_PER_PLAYER * math.max(alive, 1)
	hp = maxHp
	phase = 1
	shieldUntil = 0
	publishBoss()
	ReplicatedStorage:SetAttribute("BossName", "THE SHADOW QUEEN")
	ReplicatedStorage:SetAttribute("BossActive", true)
	CombatService.RegisterLightTarget(model, onLit)
	Notify.effectAll("BossIntro")

	-- movement
	task.spawn(function()
		local goal = ARENA[1]
		local t = 0
		while nightToken == myToken and queen == model do
			t += 0.05
			local position = root.Position
			local flat = Vector3.new(position.X, 0, position.Z)
			if (flat - goal).Magnitude < 1 then
				goal = ARENA[rng:NextInteger(1, #ARENA)]
			end
			local step = (goal - flat)
			if step.Magnitude > 0 then
				flat += step.Unit * math.min(step.Magnitude, SPEED * 0.05)
			end
			local nearest, nearestDistance = nil, math.huge
			for _, player in Players:GetPlayers() do
				local playerRoot = rootOf(player)
				if playerRoot and (playerRoot.Position - position).Magnitude < nearestDistance then
					nearest, nearestDistance = playerRoot, (playerRoot.Position - position).Magnitude
				end
			end
			local at = Vector3.new(flat.X, HOVER_Y + math.sin(t * 1.5) * 0.6, flat.Z)
			local look = if nearest
				then Vector3.new(nearest.Position.X, at.Y, nearest.Position.Z)
				else at + Vector3.new(0, 0, -1)
			root.CFrame = if (look - at).Magnitude > 0.1 then CFrame.lookAt(at, look) else CFrame.new(at)
			local shieldUp = os.clock() >= shieldUntil
			local highlight = model:FindFirstChild("Shield") :: Highlight?
			if highlight then
				highlight.Enabled = shieldUp
			end
			if shieldUp ~= ReplicatedStorage:GetAttribute("BossShielded") then
				ReplicatedStorage:SetAttribute("BossShielded", shieldUp)
				if shieldUp then
					Notify.all("🛡️ Her shield is back up. Fire another cannon!", "warning")
				end
			end
			ReplicatedStorage:SetAttribute("BossHP", math.max(0, math.ceil(hp)))
			task.wait(0.05)
		end
	end)

	-- attacks
	while nightToken == myToken and queen == model and hp > 0 do
		local roll = rng:NextNumber()
		if phase >= 3 and roll < 0.3 then
			sweep(myToken)
		elseif phase >= 2 and roll < 0.45 then
			task.spawn(darkness, myToken)
			slam(myToken, 2)
		elseif roll < 0.7 then
			if phase >= 2 then
				task.spawn(slam, myToken, 2)
			end
			slam(myToken, if phase == 1 then 2.4 else 2)
		else
			brood()
		end
		task.wait(if phase == 1 then 5 elseif phase == 2 then 4 else 3.2)
	end
end

-- ── level hooks ─────────────────────────────────────────────────────────────

local function clearAll()
	dayToken, nightToken = nil, nil
	if queen then
		CombatService.UnregisterLightTarget(queen)
	end
	queen, queenRoot = nil, nil
	hp = 0
	table.clear(cannons)
	table.clear(mirrorStates)
	table.clear(mirrorParts)
	solved = false
	ReplicatedStorage:SetAttribute("BossActive", false)
	ReplicatedStorage:SetAttribute("BossDarkness", false)
	for _, f in { folder, beamFolder } do
		if f then
			f:Destroy()
		end
	end
	folder, beamFolder = nil, nil
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
	for _, position in CANNONS do
		buildCannon(newFolder, position)
	end
	buildPuzzle(newFolder)
	task.spawn(runCannons, myToken, false)
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
	darkUntil = 0
	for _, cannon in cannons do
		cannon.Helpers = {}
		setCannonLabel(cannon)
	end
	task.spawn(runCannons, myToken, true)
	task.spawn(runQueen, myToken)
end

function ShadowQueen.EndNight()
	if queen and hp > 0 then
		Notify.all("👑 The Queen retreats into the dark… she'll be back next shift.", "danger")
	end
	clearAll()
end

return ShadowQueen
