-- Level 5 night, "The Stalker": a blind hunter that tracks sound. It can't be fought.
--
--   Noise   computed on the server from each player's real movement: normal walking is
--           loud (heard from NOISE_LOUD studs), sneaking (WalkSpeed 7, client toggle) is
--           quiet (NOISE_QUIET), standing still is silent, jumping/falling is loud.
--           Mirrored to the player as attribute Noise (0..1) and StalkerNear (heartbeat).
--   Stalker wanders between the playing music boxes; investigates anything it hears;
--           hunts a player it hears within HUNT_RANGE; a catch is telegraphed (wind-up)
--           and dodgeable. After a catch it backs off for a few seconds.
--   Counter sneak, hide in a locker (silent; max HIDE_SECONDS), switch on a radio to lure
--           it away. Silencing all 4 music boxes confuses it (slower).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
local CollisionGroups = require(script.Parent.Parent.Util.CollisionGroups)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)
local Layout = require(script.Parent.Parent.World.Layout)
local NpcMover = require(script.Parent.NpcMover)

local Stalker = {}

local A = Layout.Atrium
local NOISE_LOUD = 45
local NOISE_JUMP = 30
local NOISE_QUIET = 10
local HUNT_RANGE = 18
local CATCH_RANGE = 5
local CATCH_WINDUP = 0.9
local CATCH_DAMAGE = 45
local LOSE_TRACK = 2.5
local RECOVER = 6
local HIDE_SECONDS = 25
local RADIO_SECONDS = 8
local RADIO_COOLDOWN = 30
local RADIO_RANGE = 120
local SPEEDS = { Wander = 8, Investigate = 13, Hunt = 19 }

local MUSIC_BOXES = {
	Vector3.new(0, 0, 45),
	Vector3.new(52, A.BalconyY, 0),
	Vector3.new(135, 0, -10),
	Vector3.new(-20, 0, -108),
}
local LOCKERS = {
	CFrame.lookAt(Vector3.new(-68.5, 0, -10), Vector3.new(0, 0, -10)),
	CFrame.lookAt(Vector3.new(68.5, 0, -64), Vector3.new(0, 0, -64)),
	CFrame.lookAt(Vector3.new(-68.5, A.BalconyY, -10), Vector3.new(0, A.BalconyY, -10)),
	CFrame.lookAt(Vector3.new(10, A.BalconyY, 68.5), Vector3.new(10, A.BalconyY, 0)),
	CFrame.lookAt(Vector3.new(180.5, 0, -4), Vector3.new(0, 0, -4)),
	CFrame.lookAt(Vector3.new(-62.5, 0, -95), Vector3.new(0, 0, -95)),
}
local RADIOS = {
	Vector3.new(40, 0, 45),
	Vector3.new(100, 0, -12),
	Vector3.new(-50, A.BalconyY, -40),
}
local PATROL = {
	Vector3.new(0, 0, -30),
	Vector3.new(-45, 0, 20),
	Vector3.new(45, 0, -40),
	Vector3.new(110, 0, 6),
	Vector3.new(160, 0, -6),
	Vector3.new(-40, A.BalconyY, 45),
}
local SPAWN = Vector3.new(170, 0, 0)

type Box = { Position: Vector3, Playing: boolean }
type Radio = { Position: Vector3, ActiveUntil: number }
type Locker = { CFrame: CFrame, Prompt: ProximityPrompt, Occupant: Player? }

local folder: Folder? = nil
local token: {}? = nil
local boxes: { Box } = {}
local radios: { Radio } = {}
local lockers: { Locker } = {}
local hidden: { [Player]: { Locker: Locker, Since: number } } = {}
local rng = Random.new()

local function isNight(): boolean
	return token ~= nil and GameStateService.GetPhase() == "Night"
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- ── noise ───────────────────────────────────────────────────────────────────

local function noiseRadius(player: Player): number
	if hidden[player] then
		return 0
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return 0
	end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
		return NOISE_JUMP
	end
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if speed > 11 then
		return NOISE_LOUD
	elseif speed > 2.5 then
		return NOISE_QUIET
	end
	return 0
end

-- ── lockers ─────────────────────────────────────────────────────────────────

local function leaveLocker(player: Player)
	local entry = hidden[player]
	if not entry then
		return
	end
	hidden[player] = nil
	local locker = entry.Locker
	locker.Occupant = nil
	locker.Prompt:SetAttribute("Occupant", 0)
	locker.Prompt.ActionText = "Hide"
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = false
		root.CFrame = locker.CFrame * CFrame.new(0, 3, -3)
	end
	if player.Parent then
		player:SetAttribute("Hidden", false)
	end
end

local function enterLocker(player: Player, locker: Locker)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or locker.Occupant then
		return
	end
	locker.Occupant = player
	locker.Prompt:SetAttribute("Occupant", player.UserId)
	locker.Prompt.ActionText = "Leave Locker"
	hidden[player] = { Locker = locker, Since = os.clock() }
	root.Anchored = true
	root.CFrame = locker.CFrame * CFrame.new(0, 3, 0.2)
	player:SetAttribute("Hidden", true)
	MissionEvents.record(player, "HidInLocker")
	Notify.player(player, "🚪 Hidden. It can't hear you in here, but the door won't hold for long.", "info")
end

local function buildLocker(parent: Instance, cf: CFrame)
	local body = Builder.part({
		Name = "Locker",
		Parent = parent,
		Size = Vector3.new(3.2, 7.5, 2.6),
		CFrame = cf * CFrame.new(0, 3.75, 0.3),
		Color = Color3.fromRGB(70, 90, 110),
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	for i = 0, 3 do
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(2, 0.12, 0.05),
			CFrame = cf * CFrame.new(0, 5.6 + i * 0.3, -1.02),
			Color = Color3.fromRGB(30, 34, 44),
		})
	end
	local prompt = Builder.prompt(body, {
		Name = "LockerPrompt",
		ActionText = "Hide",
		ObjectText = "Locker",
		MaxActivationDistance = 7,
	})
	prompt:SetAttribute("Occupant", 0)
	Builder.tag(prompt, "LockerPrompt")
	local locker: Locker = { CFrame = cf, Prompt = prompt, Occupant = nil }
	table.insert(lockers, locker)
	prompt.Triggered:Connect(function(player)
		if not isNight() then
			return
		end
		if locker.Occupant == player then
			leaveLocker(player)
		elseif not locker.Occupant and not hidden[player] then
			enterLocker(player, locker)
		end
	end)
end

-- ── music boxes & radios ────────────────────────────────────────────────────

local function buildBox(parent: Instance, position: Vector3, total: number)
	local box: Box = { Position = position, Playing = true }
	table.insert(boxes, box)
	local base = Builder.part({
		Name = "MusicBox",
		Parent = parent,
		Size = Vector3.new(2.6, 2.2, 2.6),
		CFrame = CFrame.new(position + Vector3.new(0, 1.1, 0)),
		Color = Color3.fromRGB(150, 40, 80),
		Material = Enum.Material.Wood,
	})
	local dancer = Builder.decor({
		Parent = parent,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1,
		CFrame = CFrame.new(position + Vector3.new(0, 2.8, 0)),
		Color = Color3.fromRGB(255, 220, 240),
		Material = Enum.Material.Neon,
	})
	local glow = Builder.light("PointLight", dancer, { Range = 14, Brightness = 1.6, Color = Palette.NeonPink })
	local attachment = Instance.new("Attachment")
	attachment.Parent = dancer
	local notes = Instance.new("ParticleEmitter")
	notes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	notes.Color = ColorSequence.new(Palette.NeonPink, Palette.NeonPurple)
	notes.LightEmission = 1
	notes.Size = NumberSequence.new(0.4, 0)
	notes.Speed = NumberRange.new(2, 4)
	notes.SpreadAngle = Vector2.new(40, 40)
	notes.Lifetime = NumberRange.new(1, 1.6)
	notes.Rate = 6
	notes.Parent = attachment
	base:SetAttribute("Done", false)
	Builder.tag(base, "MusicBox")
	local prompt = Builder.prompt(base, {
		Name = "SilencePrompt",
		ActionText = "Silence Music Box",
		ObjectText = "Music Box",
		HoldDuration = 3,
		MaxActivationDistance = 7,
	})
	prompt.Triggered:Connect(function(player)
		if not isNight() or not box.Playing then
			return
		end
		box.Playing = false
		base:SetAttribute("Done", true)
		prompt.Enabled = false
		notes.Enabled = false
		glow.Brightness = 0
		dancer.Material = Enum.Material.SmoothPlastic
		MissionEvents.record(player, "MusicBoxSilenced")
		local left = 0
		for _, other in boxes do
			if other.Playing then
				left += 1
			end
		end
		Notify.all(
			string.format("🎵 %s silenced a music box (%d/%d)", player.DisplayName, total - left, total),
			"success"
		)
		if left == 0 then
			Notify.all("🤫 The music stops. The Stalker sways, confused…", "success")
		end
	end)
end

local function buildRadio(parent: Instance, position: Vector3)
	local radio: Radio = { Position = position, ActiveUntil = 0 }
	table.insert(radios, radio)
	Builder.part({
		Parent = parent,
		Size = Vector3.new(3, 2.6, 2),
		CFrame = CFrame.new(position + Vector3.new(0, 1.3, 0)),
		Color = Palette.WoodDark,
		Material = Enum.Material.Wood,
	})
	local set = Builder.part({
		Name = "Radio",
		Parent = parent,
		Size = Vector3.new(2.2, 1.3, 0.9),
		CFrame = CFrame.new(position + Vector3.new(0, 3.25, 0)),
		Color = Color3.fromRGB(200, 160, 90),
		Material = Enum.Material.SmoothPlastic,
	})
	Builder.label(set, Enum.NormalId.Front, "📻", { Color = Color3.new(1, 1, 1) })
	local light = Builder.light("PointLight", set, { Range = 18, Brightness = 0, Color = Palette.NeonCyan })
	local prompt = Builder.prompt(set, {
		Name = "RadioPrompt",
		ActionText = "Turn On Radio (lure)",
		ObjectText = "Radio",
		MaxActivationDistance = 7,
	})
	prompt.Triggered:Connect(function(player)
		if not isNight() or os.clock() < radio.ActiveUntil + RADIO_COOLDOWN - RADIO_SECONDS then
			return
		end
		radio.ActiveUntil = os.clock() + RADIO_SECONDS
		prompt.Enabled = false
		MissionEvents.record(player, "DecoyUsed")
		Notify.all(string.format("📻 %s switched on a radio. Loud static!", player.DisplayName), "info")
		local myToken = token
		task.spawn(function()
			while os.clock() < radio.ActiveUntil and token == myToken do
				light.Brightness = if light.Brightness > 0 then 0 else 3
				task.wait(0.2)
			end
			light.Brightness = 0
			task.wait(RADIO_COOLDOWN - RADIO_SECONDS)
			if token == myToken then
				prompt.Enabled = true
			end
		end)
	end)
end

-- ── the Stalker ─────────────────────────────────────────────────────────────

local function buildStalker(parent: Instance): (Model, Humanoid, BasePart, PointLight)
	local model = Instance.new("Model")
	model.Name = "Stalker"
	local cf = CFrame.new(SPAWN + Vector3.new(0, 6, 0))
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cf * offset
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = true
		part.Parent = model
		return part
	end
	local root = piece("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(), Color3.new(), nil)
	root.Transparency = 1
	root.CanCollide = true
	root.Massless = false
	model.PrimaryPart = root
	local skin = Color3.fromRGB(16, 12, 22)
	local parts = {
		piece("Torso", Vector3.new(2.2, 4.4, 1.4), CFrame.new(0, 1.6, 0) * CFrame.Angles(0.15, 0, 0), skin),
		piece("Head", Vector3.new(1.5, 2.6, 1.6), CFrame.new(0, 5, -0.5) * CFrame.Angles(0.35, 0, 0), skin),
		piece("ArmL", Vector3.new(0.45, 6.8, 0.45), CFrame.new(-1.5, 0.2, -0.3) * CFrame.Angles(0.2, 0, 0.12), skin),
		piece("ArmR", Vector3.new(0.45, 6.8, 0.45), CFrame.new(1.5, 0.2, -0.3) * CFrame.Angles(0.2, 0, -0.12), skin),
		piece("LegL", Vector3.new(0.6, 6, 0.6), CFrame.new(-0.6, -3, 0), skin),
		piece("LegR", Vector3.new(0.6, 6, 0.6), CFrame.new(0.6, -3, 0), skin),
	}
	local mouth = piece(
		"Mouth",
		Vector3.new(1.1, 0.18, 0.1),
		CFrame.new(0, 4.6, -1.35) * CFrame.Angles(0.35, 0, 0),
		Palette.NeonRed,
		Enum.Material.Neon
	)
	table.insert(parts, mouth)
	for _, part in parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	local glow = Instance.new("PointLight")
	glow.Color = Palette.NeonRed
	glow.Range = 12
	glow.Brightness = 1
	glow.Parent = mouth
	local smokePoint = Instance.new("Attachment")
	smokePoint.Parent = root
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(40, 10, 20), Color3.fromRGB(10, 4, 10))
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.Size = NumberSequence.new(2, 4)
	smoke.Lifetime = NumberRange.new(1, 1.5)
	smoke.Rate = 10
	smoke.Speed = NumberRange.new(0.5, 1)
	smoke.Parent = smokePoint

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 5
	humanoid.WalkSpeed = SPEEDS.Wander
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model
	CollisionGroups.assign(model, CollisionGroups.Enemies)
	model.Parent = parent
	root:SetNetworkOwner(nil)
	return model, humanoid, root, glow
end

local function caught(player: Player, from: Vector3)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	humanoid:TakeDamage(CATCH_DAMAGE)
	local flat = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
	Notify.effect(player, "Hit", {
		Damage = CATCH_DAMAGE,
		Direction = if flat.Magnitude > 0.01 then flat.Unit else nil,
	})
	MissionEvents.record(player, "Caught")
	Notify.all(string.format("😱 The Stalker caught %s!", player.DisplayName), "danger")
end

local function runStalker(myToken: {})
	task.wait(8)
	local currentFolder = folder
	if token ~= myToken or not currentFolder then
		return
	end
	local model, humanoid, root, glow = buildStalker(currentFolder)
	local mover = NpcMover.new(humanoid, root, 2.5, 11)
	Notify.all("👂 You hear something tall moving in the East Wing…", "danger")

	local state = "Wander"
	local target: Player? = nil
	local targetPosition: Vector3? = nil
	local lastHeard = 0
	local lingerUntil = 0
	local recoverUntil = 0
	local windupUntil = 0
	local wanderGoal: Vector3? = nil

	while token == myToken and model.Parent do
		local now = os.clock()
		local position = root.Position
		local playing = 0
		for _, box in boxes do
			if box.Playing then
				playing += 1
			end
		end
		local confused = if playing == 0 then 0.8 else 1

		-- what does it hear?
		local heardPlayer, heardDistance = nil, math.huge
		for _, player in Players:GetPlayers() do
			local radius = noiseRadius(player)
			local playerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local distance = if playerRoot then (playerRoot.Position - position).Magnitude else math.huge
			local near = distance <= 35 -- heartbeat, whether or not you're making noise
			if player:GetAttribute("StalkerNear") ~= near then
				player:SetAttribute("StalkerNear", near)
			end
			if radius > 0 and distance <= radius and distance < heardDistance then
				heardPlayer, heardDistance = player, distance
			end
			player:SetAttribute("Noise", radius / NOISE_LOUD)
		end
		local radioPosition = nil
		for _, radio in radios do
			if now < radio.ActiveUntil and (radio.Position - position).Magnitude <= RADIO_RANGE then
				radioPosition = radio.Position
			end
		end

		if now < windupUntil then
			-- rearing up: the moment to dodge or dive into a locker
			humanoid:MoveTo(position)
		elseif state == "Strike" then
			state = "Wander"
			local victim = target
			local victimRoot = victim
				and victim.Character
				and victim.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if
				victim
				and victimRoot
				and not hidden[victim]
				and (victimRoot.Position - position).Magnitude <= CATCH_RANGE + 2
			then
				caught(victim, position)
				recoverUntil = now + RECOVER
			end
			target = nil
		elseif now < recoverUntil then
			state = "Wander"
		elseif heardPlayer and heardDistance <= HUNT_RANGE and not radioPosition then
			state = "Hunt"
			target = heardPlayer
			lastHeard = now
		elseif radioPosition then
			state = "Investigate"
			targetPosition = radioPosition
			lingerUntil = 0
		elseif heardPlayer then
			state = "Investigate"
			local heardRoot = heardPlayer.Character
				and heardPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			targetPosition = heardRoot and heardRoot.Position
			lingerUntil = 0
		end

		if state == "Hunt" then
			local victim = target
			local victimRoot = victim
				and victim.Character
				and victim.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not victim or not victimRoot or hidden[victim] then
				state = "Investigate"
				targetPosition = if victimRoot then victimRoot.Position else position
			else
				if victim == heardPlayer then
					lastHeard = now
				end
				local distance = (victimRoot.Position - position).Magnitude
				if now - lastHeard > LOSE_TRACK then
					state = "Investigate" -- went quiet: it searches where it last heard them
					targetPosition = victimRoot.Position
				elseif distance <= CATCH_RANGE and now >= windupUntil then
					state = "Strike"
					windupUntil = now + CATCH_WINDUP
					humanoid:MoveTo(position)
					Notify.effect(victim, "Danger", { Windup = CATCH_WINDUP })
				else
					humanoid.WalkSpeed = SPEEDS.Hunt * confused
					if distance < 25 then
						humanoid:MoveTo(victimRoot.Position)
					else
						mover:steer(victimRoot.Position)
					end
				end
			end
		end
		if state == "Investigate" then
			humanoid.WalkSpeed = SPEEDS.Investigate * confused
			local goal = targetPosition or position
			if flatDistance(position, goal) < 4 then
				if lingerUntil == 0 then
					lingerUntil = now + 2.5
				elseif now > lingerUntil then
					state = "Wander"
					wanderGoal = nil
				end
				humanoid:MoveTo(position)
			else
				mover:steer(goal)
			end
		elseif state == "Wander" and now >= windupUntil then
			humanoid.WalkSpeed = SPEEDS.Wander * confused
			if not wanderGoal or flatDistance(position, wanderGoal) < 5 then
				local choices = {}
				for _, box in boxes do
					if box.Playing then
						table.insert(choices, box.Position)
					end
				end
				for _, point in PATROL do
					table.insert(choices, point)
				end
				wanderGoal = choices[rng:NextInteger(1, #choices)]
			end
			mover:steer(wanderGoal :: Vector3)
		end

		model:SetAttribute("State", state)
		glow.Brightness = if state == "Hunt" or state == "Strike" then 4 else 1

		-- nobody hides forever: lockers spring open
		for player, entry in hidden do
			if now - entry.Since > HIDE_SECONDS then
				Notify.player(player, "The locker door creaks open…", "warning")
				leaveLocker(player)
			end
		end
		task.wait(0.2)
	end
end

-- ── level hooks ─────────────────────────────────────────────────────────────

local function clear()
	token = nil
	for player in table.clone(hidden) do
		leaveLocker(player)
	end
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Noise", nil)
		player:SetAttribute("StalkerNear", nil)
	end
	table.clear(boxes)
	table.clear(radios)
	table.clear(lockers)
	ReplicatedStorage:SetAttribute("StealthNight", false)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function Stalker.StartNight()
	clear()
	local myToken = {}
	token = myToken
	local newFolder = Instance.new("Folder")
	newFolder.Name = "StalkerNight"
	newFolder.Parent = workspace
	folder = newFolder
	for _, position in MUSIC_BOXES do
		buildBox(newFolder, position, #MUSIC_BOXES)
	end
	for _, cf in LOCKERS do
		buildLocker(newFolder, cf)
	end
	for _, position in RADIOS do
		buildRadio(newFolder, position)
	end
	ReplicatedStorage:SetAttribute("StealthNight", true)
	task.spawn(runStalker, myToken)
end

function Stalker.EndNight()
	clear()
end

-- Dying or leaving inside a locker frees it (the old character is gone, nothing to move).
local function vacate(player: Player)
	local entry = hidden[player]
	if entry then
		hidden[player] = nil
		entry.Locker.Occupant = nil
		entry.Locker.Prompt:SetAttribute("Occupant", 0)
		entry.Locker.Prompt.ActionText = "Hide"
		if player.Parent then
			player:SetAttribute("Hidden", false)
		end
	end
end
local function watch(player: Player)
	player.CharacterRemoving:Connect(function()
		vacate(player)
	end)
end
Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end
Players.PlayerRemoving:Connect(vacate)

return Stalker
