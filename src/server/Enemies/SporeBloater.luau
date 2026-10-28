-- Spore Bloater (Level 13 night): a floating, pulsing spore sac with one eye.
--
--   * Drifts slowly after the nearest player (it never bites).
--   * Next to someone it swells and EXHALES: a green circle warns for EXHALE_WARN seconds,
--     then everyone inside gets a dose of gas (Custom.OnGas(players, center)).
--   * Burned to death it bursts into a lingering gas cloud (Custom.OnPop(position)):
--     burn it from range, not in your face.

local Players = game:GetService("Players")

local MonsterTuning = require(game:GetService("ReplicatedStorage").Shared.Config.MonsterTuning)
local Telegraph = require(script.Parent.Parent.Util.Telegraph)
local Rig = require(script.Parent.Rig)

local SporeBloater = {}

local SAC = Color3.fromRGB(120, 150, 60)
local SPOTS = Color3.fromRGB(150, 255, 90)
local EXHALE_WARN = MonsterTuning.Bloater.ExhaleWarn
local EXHALE_RADIUS = MonsterTuning.Bloater.ExhaleRadius

function SporeBloater.Build(): Model
	local model = Instance.new("Model")
	model.Name = "SporeBloater"
	local hip = 5
	local root = Rig.root(model, Vector3.new(3, 3, 3), hip)
	local body = Rig.ball(model, Vector3.new(5, 4.6, 5), CFrame.new(), SAC, {
		Name = "Body",
		Material = Enum.Material.Glass,
		Transparency = 0.15,
	})
	Rig.motor("BodyJoint", root, body, CFrame.new(0, 0.6, 0))
	local core = Rig.ball(
		model,
		Vector3.new(3, 3, 3),
		body.CFrame,
		Color3.fromRGB(70, 20, 90),
		{ Material = Enum.Material.Neon, Transparency = 0.4 }
	)
	Rig.weld(body, core)
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local spot = Rig.ball(
			model,
			Vector3.new(0.7, 0.7, 0.3),
			body.CFrame
				* CFrame.Angles(0, angle, 0)
				* CFrame.Angles(math.rad((i % 3 - 1) * 30), 0, 0)
				* CFrame.new(0, 0, -2.4),
			SPOTS,
			{ Material = Enum.Material.Neon }
		)
		Rig.weld(body, spot)
	end
	Rig.eye(
		model,
		body,
		body.CFrame * CFrame.new(0, 0.4, -2.45),
		Vector3.new(1.2, 0.8, 0.2),
		Color3.fromRGB(255, 240, 120),
		true
	)
	for i = 1, 3 do
		local tendril = Rig.part(model, {
			Name = "Tendril",
			Size = Vector3.new(0.3, 4, 0.3),
			Color = Color3.fromRGB(80, 100, 40),
			Material = Enum.Material.SmoothPlastic,
		})
		local angle = i * math.pi * 2 / 3
		Rig.motor(
			"Tendril" .. i,
			body,
			tendril,
			CFrame.new(math.cos(angle) * 1.2, -2.2, math.sin(angle) * 1.2),
			CFrame.new(0, 2, 0)
		)
	end
	Rig.particles(body, {
		Color = ColorSequence.new(SPOTS, Color3.fromRGB(60, 80, 30)),
		Transparency = NumberSequence.new(0.55, 1),
		Size = NumberSequence.new(1, 3),
		Lifetime = NumberRange.new(1, 1.8),
		Rate = 6,
		Speed = NumberRange.new(0.3, 1),
		Acceleration = Vector3.new(0, -0.8, 0),
	})
	local glow = Instance.new("PointLight")
	glow.Color = SPOTS
	glow.Range = 12
	glow.Brightness = 1.2
	glow.Parent = body
	local humanoid = Rig.humanoid(model, hip, 7)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	return model
end

function SporeBloater.Think(enemy: any, now: number, ai: any): boolean
	local c = enemy.Custom
	local root: BasePart = enemy.Root
	local humanoid: Humanoid = enemy.Humanoid
	local exhale = c.Exhale
	if exhale then
		humanoid.WalkSpeed = 0
		humanoid:MoveTo(root.Position)
		if now >= exhale.At then
			c.Exhale = nil
			c.NextExhale = now + enemy.Config.AttackCooldown
			enemy.Model:SetAttribute("Swelling", false)
			local victims = Telegraph.playersInCircle(Players:GetPlayers(), exhale.Center, EXHALE_RADIUS)
			Telegraph.burst(exhale.Center, EXHALE_RADIUS, SPOTS)
			if c.OnGas then
				c.OnGas(victims, exhale.Center)
			end
		end
		return true
	end
	local player, target, distance = ai.NearestPlayer(root.Position, enemy.Config.AggroRange, true)
	if player and target then
		if distance <= enemy.Config.AttackRange + 2 and now >= (c.NextExhale or 0) then
			local center = Telegraph.floorBelow(root.Position)
			c.Exhale = { At = now + EXHALE_WARN, Center = center }
			Telegraph.disc(center, EXHALE_RADIUS, EXHALE_WARN, SPOTS)
			ai.Warn(player, EXHALE_WARN)
			enemy.Model:SetAttribute("Swelling", true)
			enemy.Model:SetAttribute("WindupAt", ai.ServerNow())
		elseif distance > 4 then
			ai.Navigate(enemy, target.Position)
		else
			humanoid:MoveTo(root.Position)
		end
	else
		humanoid:MoveTo(root.Position)
	end
	return true
end

function SporeBloater.OnKilled(enemy: any, _ai: any)
	local c = enemy.Custom
	if c.OnPop then
		c.OnPop(Telegraph.floorBelow(enemy.Root.Position))
	end
end

return SporeBloater
