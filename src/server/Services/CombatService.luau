-- Flashlight combat. Light burns shadows: holding the beam on an enemy damages it.
--
-- Server-authoritative: the client only says "beam on/off" and where it is aiming. The
-- server validates the aim against the character's facing, drains the battery, and runs
-- the cone + line-of-sight test itself at 10 Hz. Clients never report hits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPack = game:GetService("StarterPack")

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Net = require(ReplicatedStorage.Shared.Net)
local LightCone = require(ReplicatedStorage.Shared.Util.LightCone)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
local CollisionGroups = require(script.Parent.Parent.Util.CollisionGroups)
local Notify = require(script.Parent.Parent.Util.Notify)
local EnemyService = require(script.Parent.EnemyService)
local ProgressionService = require(script.Parent.ProgressionService)

type BeamState = {
	On: boolean,
	Aim: Vector3,
	Battery: number, -- seconds remaining
	OffAt: number,
	SentBattery: number,
}

local CombatService = {}

local FL = EnemyConfig.Flashlight
local TICK = 0.1
local BEAM_OFFSET = Vector3.new(1.1, 1.0, -1.6)
local BEAM_ON_BRIGHTNESS = 6

-- Non-enemy things the beam can reveal or burn (level mechanics, bosses).
export type LightOptions = {
	-- Spheres to test (centre = part position). Default: the model's PrimaryPart as a point.
	Parts: { BasePart }?,
	Radius: { number }?, -- per part, matching Parts (default 0)
}

type LightTarget = {
	OnLit: (player: Player, dt: number, part: BasePart) -> (),
	Parts: { BasePart }?,
	Radius: { number },
}

local states: { [Player]: BeamState } = {}
local lightTargets: { [Model]: LightTarget } = {}
local rayParams = CollisionGroups.worldRaycastParams()
local coneHalf = math.rad(FL.ConeHalfAngle)
local cosDeviation = math.cos(math.rad(FL.MaxAimDeviation))

local function capacity(player: Player): number
	return FL.BatterySeconds * (1 + ProgressionService.UpgradeBonus(player, "Battery"))
end

local function buildTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Flashlight"
	tool.ToolTip = "Hold to burn shadows"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, -0.1, 0.2)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.45, 0.45, 1.9)
	handle.Color = Palette.DarkMetal
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Parent = tool

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Cylinder
	head.Size = Vector3.new(0.5, 0.75, 0.75)
	head.CFrame = handle.CFrame * CFrame.new(0, 0, -1.1) * CFrame.Angles(0, math.rad(90), 0)
	head.Color = Color3.fromRGB(240, 196, 40)
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.Massless = true
	head.Parent = tool

	local lens = Instance.new("Part")
	lens.Name = "Lens"
	lens.Shape = Enum.PartType.Cylinder
	lens.Size = Vector3.new(0.06, 0.6, 0.6)
	lens.CFrame = handle.CFrame * CFrame.new(0, 0, -1.37) * CFrame.Angles(0, math.rad(90), 0)
	lens.Color = Palette.WarmLight
	lens.Material = Enum.Material.Neon
	lens.CanCollide = false
	lens.Massless = true
	lens.Parent = tool

	for _, part in { head, lens } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
	end
	return tool
end

-- Light cone rig on the HumanoidRootPart, pointed by the server from the validated aim.
local function buildBeamRig(root: BasePart)
	local origin = Instance.new("Attachment")
	origin.Name = "BeamOrigin"
	origin.Position = BEAM_OFFSET
	origin.Parent = root

	local tip = Instance.new("Attachment")
	tip.Name = "BeamTip"
	tip.Position = BEAM_OFFSET + Vector3.new(0, 0, -FL.Range * 0.75)
	tip.Parent = root

	local light = Instance.new("SpotLight")
	light.Name = "FlashlightLight"
	light.Face = Enum.NormalId.Front
	light.Angle = FL.ConeHalfAngle * 2.4
	light.Range = FL.Range
	light.Brightness = 0
	light.Color = Palette.WarmLight
	light.Parent = origin

	local beam = Instance.new("Beam")
	beam.Name = "FlashlightBeam"
	beam.Attachment0 = origin
	beam.Attachment1 = tip
	beam.Width0 = 0.6
	beam.Width1 = math.tan(math.rad(FL.ConeHalfAngle)) * FL.Range * 1.5
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 1
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 236, 190))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Enabled = false
	beam.Parent = root
end

local function rigOf(player: Player): (BasePart?, Attachment?, Attachment?, SpotLight?, Beam?)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local origin = root:FindFirstChild("BeamOrigin") :: Attachment?
	return root,
		origin,
		root:FindFirstChild("BeamTip") :: Attachment?,
		origin and origin:FindFirstChild("FlashlightLight") :: SpotLight?,
		root:FindFirstChild("FlashlightBeam") :: Beam?
end

local function setVisual(player: Player, on: boolean)
	local _, _, _, light, beam = rigOf(player)
	if light then
		light.Brightness = if on then BEAM_ON_BRIGHTNESS else 0
	end
	if beam then
		beam.Enabled = on
	end
end

local function pointRig(player: Player, aim: Vector3)
	local root, origin, tip = rigOf(player)
	if not (root and origin and tip) then
		return
	end
	local localAim = root.CFrame:VectorToObjectSpace(aim)
	origin.CFrame = CFrame.lookAt(BEAM_OFFSET, BEAM_OFFSET + localAim)
	tip.Position = BEAM_OFFSET + localAim * FL.Range * 0.75
end

local function equipped(player: Player): boolean
	return player.Character ~= nil and player.Character:FindFirstChild("Flashlight") ~= nil
end

-- Clamp a client aim to what the character could plausibly be pointing at.
local function sanitizeAim(player: Player, aim: any): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local facing = root.CFrame.LookVector
	if not Validate.unitVector(aim) then
		return facing
	end
	local flatAim = Vector3.new(aim.X, 0, aim.Z)
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	if flatAim.Magnitude < 0.05 or math.abs(aim.Y) > FL.MaxAimPitch then
		return facing
	end
	if flatAim.Unit:Dot(flatFacing.Unit) < cosDeviation then
		return facing
	end
	return aim.Unit
end

local function setBeam(player: Player, on: boolean)
	local state = states[player]
	if not state then
		return
	end
	if on and (state.Battery <= 0 or not equipped(player)) then
		on = false
	end
	if state.On and not on then
		state.OffAt = os.clock()
	end
	state.On = on
	setVisual(player, on)
end

-- onLit(player, dt, part) runs every beam tick while `model` is in a player's lit cone
-- (at most once per tick per player; `part` is the body part that was lit).
function CombatService.RegisterLightTarget(
	model: Model,
	onLit: (player: Player, dt: number, part: BasePart) -> (),
	options: LightOptions?
)
	lightTargets[model] = {
		OnLit = onLit,
		Parts = options and options.Parts,
		Radius = options and options.Radius or {},
	}
end

function CombatService.UnregisterLightTarget(model: Model)
	lightTargets[model] = nil
end

-- A clear line from the lens to the sphere: try the point of the sphere nearest the aim
-- line first (what the player is pointing at), then its centre. World geometry blocks it
-- (e.g. the fountain), the target's own parts don't.
local function canSee(model: Model, origin: Vector3, aim: Vector3, center: Vector3, radius: number): boolean
	local offset = center - origin
	local targets = { center }
	if radius > 0 then
		local along = origin + aim * math.max(0, offset:Dot(aim))
		local fromCenter = along - center
		if fromCenter.Magnitude > 0.05 then
			table.insert(targets, 1, center + fromCenter.Unit * math.min(fromCenter.Magnitude, radius * 0.8))
		end
	end
	for _, point in targets do
		local hit = workspace:Raycast(origin, point - origin, rayParams)
		if hit == nil or hit.Instance:IsDescendantOf(model) then
			return true
		end
	end
	return false
end

local function revealTargets(player: Player, origin: Vector3, aim: Vector3, dt: number)
	for model, target in lightTargets do
		if not model.Parent then
			continue
		end
		local parts = target.Parts
		if not parts then
			local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart?
			parts = if root then { root } else {}
		end
		for i, part in parts :: { BasePart } do
			local radius = target.Radius[i] or 0
			local offset = part.Position - origin
			local distance = offset.Magnitude
			local alignment = if distance > 0.01 then aim:Dot(offset / distance) else 1
			if
				LightCone.hits(alignment, distance, radius, coneHalf, FL.Range)
				and canSee(model, origin, aim, part.Position, radius)
			then
				task.spawn(target.OnLit, player, dt, part)
				break
			end
		end
	end
end

-- Refills a player's flashlight (e.g. a light cannon's blast).
function CombatService.Recharge(player: Player)
	local state = states[player]
	if state then
		state.Battery = capacity(player)
		state.OffAt = 0
	end
end

local function burn(player: Player, origin: Vector3, aim: Vector3, dt: number)
	local damage = FL.DPS * dt * (1 + ProgressionService.UpgradeBonus(player, "Lens"))
	for _, enemy in EnemyService.GetAll() do
		if not enemy.Dead then
			local offset = enemy.Root.Position - origin
			local distance = offset.Magnitude
			if distance <= FL.Range and distance > 0.1 then
				local inCone = LightCone.hits(aim:Dot(offset / distance), distance, 0, coneHalf, FL.Range)
				if inCone and workspace:Raycast(origin, offset, rayParams) == nil then
					EnemyService.Burn(enemy, damage, player, dt)
				end
			end
		end
	end
end

local function tick(dt: number)
	for player, state in states do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local alive = humanoid ~= nil and humanoid.Health > 0 and head ~= nil
		local cap = capacity(player)

		if state.On and not (alive and equipped(player)) then
			setBeam(player, false)
		end

		if state.On and head then
			state.Battery = math.max(0, state.Battery - dt)
			burn(player, head.Position, state.Aim, dt)
			revealTargets(player, head.Position, state.Aim, dt)
			if state.Battery <= 0 then
				setBeam(player, false)
				Notify.player(player, "🔋 Battery drained — release to recharge.", "warning")
			end
		elseif os.clock() - state.OffAt >= FL.RechargeDelay then
			state.Battery = math.min(cap, state.Battery + cap * FL.RechargePerSecond * dt)
		end

		local fraction = math.floor(state.Battery / cap * 100 + 0.5) / 100
		if fraction ~= state.SentBattery then
			state.SentBattery = fraction
			player:SetAttribute("Battery", fraction)
		end
	end
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	humanoid.MaxHealth = GameConfig.PlayerMaxHealth
	humanoid.Health = GameConfig.PlayerMaxHealth
	CollisionGroups.assign(character, CollisionGroups.Players)
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CollisionGroups.Players
		end
	end)
	buildBeamRig(root)
	local state = states[player]
	if state then
		state.On = false
		state.Battery = capacity(player)
	end
end

function CombatService.Init()
	buildTool().Parent = StarterPack
end

function CombatService.Start()
	local function onPlayer(player: Player)
		states[player] = {
			On = false,
			Aim = Vector3.new(0, 0, -1),
			Battery = FL.BatterySeconds,
			OffAt = 0,
			SentBattery = -1,
		}
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	Net.handle("SetBeam", 12, 12, function(player, on, aim)
		if type(on) ~= "boolean" then
			return
		end
		local state = states[player]
		local clean = sanitizeAim(player, aim)
		if state and clean then
			state.Aim = clean
			pointRig(player, clean)
		end
		setBeam(player, on)
	end)

	Net.handle("AimUpdate", 20, 20, function(player, aim)
		local state = states[player]
		if not state or not state.On then
			return
		end
		local clean = sanitizeAim(player, aim)
		if clean then
			state.Aim = clean
			pointRig(player, clean)
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= TICK then
			tick(accumulator)
			accumulator = 0
		end
	end)
end

return CombatService
