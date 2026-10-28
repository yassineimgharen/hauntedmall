-- Frost Wraith (Level 11 night): a tall, hooded thing of ice from the hidden freezer.
--
--   * Light can't hurt it (LightScale 0); a beam on it slows it to a crawl for a moment.
--   * It ignores anyone standing in a heat lamp's glow (the level sets Custom.IsSafe).
--   * Up close it claws (the standard telegraphed bite); at mid range it breathes frost
--     down a lane (red strip, then Damage + Custom.OnBreath(player) for the chill).
--   * With nobody to chase it drifts to Custom.LureTo (melting ice draws it) or patrols
--     Custom.Patrol.
-- Its chilling aura is applied by the level (it knows each player's cold meter).

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterTuning = require(ReplicatedStorage.Shared.Config.MonsterTuning)
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Telegraph = require(script.Parent.Parent.Util.Telegraph)
local Rig = require(script.Parent.Rig)

local FrostWraith = {}

local ICE = Color3.fromRGB(170, 220, 255)
local DEEP = Color3.fromRGB(60, 110, 170)
local T = MonsterTuning.Wraith
local BREATH_WARN = T.BreathWarn
local BREATH_LENGTH = T.BreathLength
local BREATH_WIDTH = T.BreathWidth
local BREATH_DAMAGE = T.BreathDamage
local BREATH_COOLDOWN = T.BreathCooldown
local LIT_SLOW = T.LitSlow

function FrostWraith.Build(): Model
	local model = Instance.new("Model")
	model.Name = "FrostWraith"
	local hip = 3
	local root = Rig.root(model, Vector3.new(3, 5, 2.4), hip)
	local body = Rig.part(model, {
		Name = "Body",
		Size = Vector3.new(3.4, 5.2, 2.2),
		Color = ICE,
		Material = Enum.Material.Glass,
		Transparency = 0.2,
	})
	Rig.motor("BodyJoint", root, body, CFrame.new(0, 0.6, 0))
	local function welded(size: Vector3, offset: CFrame, color: Color3, props: { [string]: any }?): BasePart
		local p = Rig.part(model, {
			Size = size,
			CFrame = body.CFrame * offset,
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.25,
		})
		for key, value in (props or {}) :: { [string]: any } do
			(p :: any)[key] = value
		end
		Rig.weld(body, p)
		return p
	end
	-- ragged robe below the torso, drifting into mist
	for i = 0, 5 do
		local angle = i * math.pi / 3
		welded(
			Vector3.new(1.4, 4, 0.3),
			CFrame.new(math.cos(angle) * 1.2, -4.2, math.sin(angle) * 0.9) * CFrame.Angles(0, -angle, 0.12),
			DEEP,
			{ Material = Enum.Material.Fabric, Transparency = 0.35 }
		)
	end
	-- hood and face
	local head = welded(
		Vector3.new(2.6, 2.8, 2.4),
		CFrame.new(0, 3.9, -0.1),
		Color3.fromRGB(30, 50, 80),
		{ Material = Enum.Material.Fabric, Transparency = 0 }
	)
	head.Name = "Hood"
	welded(
		Vector3.new(1.8, 1.9, 0.3),
		CFrame.new(0, 3.7, -1.2),
		Color3.fromRGB(8, 12, 20),
		{ Material = Enum.Material.SmoothPlastic, Transparency = 0 }
	)
	for _, x in { -0.45, 0.45 } do
		Rig.eye(
			model,
			body,
			body.CFrame * CFrame.new(x, 3.9, -1.38),
			Vector3.new(0.42, 0.22, 0.08),
			Color3.fromRGB(200, 240, 255),
			x > 0
		)
	end
	-- icicle crown
	for i = -2, 2 do
		welded(
			Vector3.new(0.3, 1.2 + (2 - math.abs(i)) * 0.4, 0.3),
			CFrame.new(i * 0.5, 5.6 + (2 - math.abs(i)) * 0.2, 0) * CFrame.Angles(0, 0, i * 0.15),
			ICE,
			{ Material = Enum.Material.Ice }
		)
	end
	-- long arms with icicle claws (client sways ArmL/ArmR)
	for _, side in { -1, 1 } do
		local arm = Rig.part(model, {
			Name = "Arm",
			Size = Vector3.new(0.6, 5.5, 0.6),
			Color = ICE,
			Material = Enum.Material.Glass,
			Transparency = 0.25,
		})
		Rig.motor(
			if side < 0 then "ArmL" else "ArmR",
			body,
			arm,
			CFrame.new(side * 2, 2, 0) * CFrame.Angles(0, 0, side * 0.25),
			CFrame.new(0, 2.6, 0)
		)
		for k = -1, 1 do
			local claw = Rig.part(model, {
				Size = Vector3.new(0.18, 1.4, 0.18),
				CFrame = arm.CFrame * CFrame.new(k * 0.22, -3.3, -0.1) * CFrame.Angles(0.3, 0, k * 0.2),
				Color = Color3.fromRGB(230, 250, 255),
				Material = Enum.Material.Ice,
			})
			Rig.weld(arm, claw)
		end
	end
	Rig.particles(body, {
		Color = ColorSequence.new(Color3.fromRGB(230, 245, 255), ICE),
		Transparency = NumberSequence.new(0.5, 1),
		Size = NumberSequence.new(2, 4.5),
		Lifetime = NumberRange.new(1.2, 2),
		Rate = 10,
		Speed = NumberRange.new(0.5, 1.5),
		Acceleration = Vector3.new(0, -1.5, 0),
	})
	local aura = Instance.new("PointLight")
	aura.Color = Color3.fromRGB(140, 200, 255)
	aura.Range = 18
	aura.Brightness = 1.4
	aura.Parent = body
	Rig.humanoid(model, hip, 12.5)
	return model
end

-- The nearest living player it can see who isn't sheltering by a heat lamp.
local function pickTarget(enemy: any, ai: any): (Player?, BasePart?, number)
	local c = enemy.Custom
	local position = enemy.Root.Position
	local best, bestRoot, bestDistance = nil, nil, enemy.Config.AggroRange
	for _, player in Players:GetPlayers() do
		local root = ai.LivingRoot(player)
		if root and not (c.IsSafe and c.IsSafe(root.Position)) then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance and (distance < 20 or ai.LineOfSight(position, root.Position)) then
				best, bestRoot, bestDistance = player, root, distance
			end
		end
	end
	return best, bestRoot, bestDistance
end

function FrostWraith.Think(enemy: any, now: number, ai: any): boolean
	local c = enemy.Custom
	local root: BasePart = enemy.Root
	local humanoid: Humanoid = enemy.Humanoid
	local speed = enemy.Config.WalkSpeed * (if now < (c.SlowUntil or 0) then LIT_SLOW else 1)
	humanoid.WalkSpeed = speed

	local breath = c.Breath
	if breath then
		humanoid.WalkSpeed = 0
		humanoid:MoveTo(root.Position)
		if now >= breath.At then
			c.Breath = nil
			c.NextBreath = now + BREATH_COOLDOWN
			enemy.Model:SetAttribute("Breathing", false)
			for _, player in Telegraph.playersInLane(Players:GetPlayers(), breath.From, breath.To, BREATH_WIDTH) do
				ai.HitPlayer(player, BREATH_DAMAGE, breath.From)
				if c.OnBreath then
					c.OnBreath(player)
				end
			end
		end
		return true
	end
	if now < enemy.WindupUntil then
		humanoid:MoveTo(root.Position)
		return true
	end

	local player, target, distance = pickTarget(enemy, ai)
	if player and target then
		if distance <= enemy.Config.AttackRange then
			humanoid:MoveTo(root.Position)
			ai.Face(enemy, target.Position)
			ai.Attack(enemy, player, now)
		elseif distance >= 7 and distance <= BREATH_LENGTH and now >= (c.NextBreath or 0) then
			local from = Telegraph.floorBelow(root.Position)
			local direction = Vector3.new(target.Position.X - from.X, 0, target.Position.Z - from.Z).Unit
			local to = from + direction * BREATH_LENGTH
			c.Breath = { At = now + BREATH_WARN, From = from, To = to }
			Telegraph.lane(from, to, BREATH_WIDTH, BREATH_WARN, Color3.fromRGB(120, 200, 255))
			ai.Face(enemy, target.Position)
			ai.Warn(player, BREATH_WARN)
			enemy.Model:SetAttribute("Breathing", true)
			enemy.Model:SetAttribute("WindupAt", ai.ServerNow())
		else
			ai.Navigate(enemy, target.Position)
		end
		return true
	end

	local goal = c.LureTo
	if not goal and c.Patrol and #c.Patrol > 0 then
		goal = c.PatrolTarget
		if not goal or ai.FlatDistance(root.Position, goal) < 6 then
			goal = c.Patrol[math.random(1, #c.Patrol)]
			c.PatrolTarget = goal
		end
	end
	if goal and ai.FlatDistance(root.Position, goal) > 5 then
		humanoid.WalkSpeed = speed * 0.7
		ai.Navigate(enemy, goal)
	else
		humanoid:MoveTo(root.Position)
	end
	return true
end

function FrostWraith.OnLit(enemy: any, _player: Player, _dt: number, _ai: any)
	enemy.Custom.SlowUntil = os.clock() + 0.5
	enemy.Model:SetAttribute("SlowedUntil", workspace:GetServerTimeNow() + 0.5)
end

FrostWraith.Colors = { Ice = ICE, Glow = Palette.CoolLight }

return FrostWraith
