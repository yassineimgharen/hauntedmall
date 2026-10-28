-- Possessed Cart (Level 8 night): a haunted kitchen trolley with a knife-tooth grin.
--
--   Roll    → creeps after the nearest player (default AI; bites up close)
--   Aim     → stops and shakes; a red lane shows its charge path (AIM seconds)
--   Charge  → races along the lane; anyone it touches takes Damage once
--   Dizzy   → spins out for a moment afterwards: the window to burn it
-- Charge speed is twice a player's, so the counter is to step out of the lane.

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterTuning = require(ReplicatedStorage.Shared.Config.MonsterTuning)
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Telegraph = require(script.Parent.Parent.Util.Telegraph)
local Rig = require(script.Parent.Rig)

local PossessedCart = {}

local T = MonsterTuning.Cart
local AIM = T.Aim
local CHARGE_SPEED = T.ChargeSpeed
local CHARGE_TIME = T.ChargeTime
local DIZZY = T.Dizzy
local COOLDOWN = T.Cooldown
local MIN_RANGE, MAX_RANGE = T.MinRange, T.MaxRange
local HIT_RADIUS = T.HitRadius
local LANE_WIDTH = T.LaneWidth
local STEEL = Color3.fromRGB(176, 182, 190)

function PossessedCart.Build(): Model
	local model = Instance.new("Model")
	model.Name = "PossessedCart"
	local hip = 1.6
	local root = Rig.root(model, Vector3.new(4, 3, 6), hip)
	local body = Rig.part(model, {
		Name = "Body",
		Size = Vector3.new(4, 0.3, 6),
		Color = STEEL,
		Material = Enum.Material.Metal,
	})
	Rig.motor("BodyJoint", root, body, CFrame.new(0, 0.6, 0))
	local function welded(
		size: Vector3,
		offset: CFrame,
		color: Color3,
		material: Enum.Material?,
		name: string?
	): BasePart
		local p = Rig.part(model, {
			Name = name or "Part",
			Size = size,
			CFrame = body.CFrame * offset,
			Color = color,
			Material = material or Enum.Material.Metal,
		})
		Rig.weld(body, p)
		return p
	end
	welded(Vector3.new(4, 0.3, 6), CFrame.new(0, -2, 0), STEEL)
	for _, x in { -1.85, 1.85 } do
		for _, z in { -2.85, 2.85 } do
			welded(Vector3.new(0.25, 2.3, 0.25), CFrame.new(x, -1, z), STEEL)
		end
	end
	welded(Vector3.new(3.6, 0.25, 0.25), CFrame.new(0, 1.4, 3.1), Palette.DarkMetal) -- push handle
	for _, x in { -1.6, 1.6 } do
		welded(Vector3.new(0.2, 1.4, 0.2), CFrame.new(x, 0.75, 3.05), Palette.DarkMetal)
	end
	-- the face on the front shelf: eyes and a row of knife teeth
	for _, x in { -1, 1 } do
		Rig.eye(
			model,
			body,
			body.CFrame * CFrame.new(x, -0.6, -3.05) * CFrame.Angles(0, 0, x * 0.25),
			Vector3.new(0.9, 0.45, 0.1),
			Palette.NeonRed,
			x > 0
		)
	end
	for i = -3, 3 do
		welded(
			Vector3.new(0.18, 0.9, 0.06),
			CFrame.new(i * 0.42, -1.5, -3.08) * CFrame.Angles(0, 0, if i % 2 == 0 then 0.15 else -0.15),
			Color3.fromRGB(230, 236, 242),
			Enum.Material.Metal,
			"Knife"
		)
	end
	-- a rattling pot on top, leaking purple smoke
	local pot = Rig.part(model, {
		Name = "Pot",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.8, 2.4, 2.4),
		CFrame = body.CFrame * CFrame.new(0.4, 1.05, 0.6) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 60, 66),
		Material = Enum.Material.Metal,
	})
	Rig.weld(body, pot)
	local lid = Rig.part(model, {
		Name = "Lid",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 2.5, 2.5),
		Color = Color3.fromRGB(80, 80, 88),
		Material = Enum.Material.Metal,
	})
	Rig.motor("LidJoint", body, lid, CFrame.new(0.4, 2.05, 0.6) * CFrame.Angles(0, 0, math.rad(90)))
	Rig.particles(lid, {
		Color = ColorSequence.new(Palette.NeonPurple, Color3.fromRGB(30, 10, 50)),
		Transparency = NumberSequence.new(0.4, 1),
		Size = NumberSequence.new(0.8, 2.2),
		Lifetime = NumberRange.new(0.8, 1.4),
		Rate = 10,
		Speed = NumberRange.new(1, 2),
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Right,
	})
	-- caster wheels (the client spins Wheel1..4)
	local i = 0
	for _, x in { -1.7, 1.7 } do
		for _, z in { -2.5, 2.5 } do
			i += 1
			local wheel = Rig.part(model, {
				Name = "Wheel" .. i,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.5, 1.4, 1.4),
				Color = Color3.fromRGB(24, 24, 28),
				Material = Enum.Material.Rubber,
			})
			Rig.motor("Wheel" .. i, root, wheel, CFrame.new(x, -2.2, z))
		end
	end
	local aura = Instance.new("PointLight")
	aura.Color = Palette.NeonRed
	aura.Range = 9
	aura.Brightness = 0.8
	aura.Parent = body
	Rig.humanoid(model, hip, 10)
	return model
end

local function flatUnit(v: Vector3): Vector3?
	local flat = Vector3.new(v.X, 0, v.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else nil
end

function PossessedCart.Think(enemy: any, now: number, ai: any): boolean
	local c = enemy.Custom
	local root: BasePart = enemy.Root
	local humanoid: Humanoid = enemy.Humanoid
	if c.Mode == "Aim" then
		humanoid.WalkSpeed = 0
		humanoid:MoveTo(root.Position)
		if now >= c.Until then
			c.Mode = "Charge"
			c.Until = now + CHARGE_TIME
			c.Hit = {}
			enemy.Model:SetAttribute("Charging", true)
			enemy.Model:SetAttribute("Aiming", false)
		end
		return true
	elseif c.Mode == "Charge" then
		humanoid.WalkSpeed = CHARGE_SPEED
		humanoid:MoveTo(c.To)
		for _, player in Players:GetPlayers() do
			local target = ai.LivingRoot(player)
			if target and not c.Hit[player] then
				local offset = target.Position - root.Position
				if Vector3.new(offset.X, 0, offset.Z).Magnitude <= HIT_RADIUS and math.abs(offset.Y) < 5 then
					c.Hit[player] = true
					ai.HitPlayer(player, enemy.Config.Damage, root.Position)
				end
			end
		end
		if now >= c.Until or ai.FlatDistance(root.Position, c.To) < 2.5 then
			c.Mode = "Dizzy"
			c.Until = now + DIZZY
			enemy.Model:SetAttribute("Charging", false)
			enemy.Model:SetAttribute("DizzyUntil", ai.ServerNow() + DIZZY)
		end
		return true
	elseif c.Mode == "Dizzy" then
		humanoid.WalkSpeed = 0
		humanoid:MoveTo(root.Position)
		if now >= c.Until then
			c.Mode = nil
			c.NextCharge = now + COOLDOWN
		end
		return true
	end

	if now >= (c.NextCharge or now + 2) and c.NextCharge ~= nil then
		local player, target, distance = ai.NearestPlayer(root.Position, enemy.Config.AggroRange, true)
		if player and target and distance >= MIN_RANGE and distance <= MAX_RANGE then
			local direction = flatUnit(target.Position - root.Position)
			if direction and math.abs(target.Position.Y - root.Position.Y) < 5 then
				local length = math.min(distance + 10, MAX_RANGE + 8)
				c.To = root.Position + direction * length
				c.Mode = "Aim"
				c.Until = now + AIM
				humanoid.WalkSpeed = 0
				humanoid:MoveTo(root.Position)
				ai.Face(enemy, target.Position)
				local floor = Telegraph.floorBelow(root.Position)
				Telegraph.lane(floor, Vector3.new(c.To.X, floor.Y, c.To.Z), LANE_WIDTH, AIM + CHARGE_TIME * 0.6)
				enemy.Model:SetAttribute("Aiming", true)
				ai.Warn(player, AIM)
				return true
			end
		end
	end
	c.NextCharge = c.NextCharge or now + 2.5 -- first charge a moment after spawning
	return false
end

return PossessedCart
