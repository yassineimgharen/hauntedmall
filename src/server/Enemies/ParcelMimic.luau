-- Infected deliveries (Level 10 night).
--
-- Parcel Mimic: looks like an ordinary cardboard parcel (attribute Revealed = false: no
-- legs or eyes) until a player comes within REVEAL_RANGE or shines a light on it. Then
-- it bursts open and hunts: up close it bites; at mid range it crouches and POUNCES at
-- the spot a red circle marks. When destroyed it splits into two Parcel Mites.
-- Parcel Mite: a small, quick biter (still slower than players).

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterTuning = require(ReplicatedStorage.Shared.Config.MonsterTuning)
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Telegraph = require(script.Parent.Parent.Util.Telegraph)
local Rig = require(script.Parent.Rig)

local ParcelMimic = {}

local T = MonsterTuning.Mimic
local REVEAL_RANGE = T.RevealRange
local REVEAL_PAUSE = T.RevealPause
local POUNCE_WARN = T.PounceWarn
local POUNCE_RADIUS = T.PounceRadius
local POUNCE_SPEED = T.PounceSpeed
local POUNCE_COOLDOWN = T.PounceCooldown
local POUNCE_MIN, POUNCE_MAX = T.PounceMin, T.PounceMax
local CARDBOARD = Color3.fromRGB(196, 154, 104)
local INFECTION = Color3.fromRGB(170, 60, 255)

local function buildMimic(): Model
	local model = Instance.new("Model")
	model.Name = "ParcelMimic"
	local hip = 1.4
	local root = Rig.root(model, Vector3.new(3, 2.4, 3), hip)
	local body = Rig.part(model, {
		Name = "Body",
		Size = Vector3.new(3.2, 2.6, 3.2),
		Color = CARDBOARD,
		Material = Enum.Material.Cardboard,
	})
	Rig.motor("BodyJoint", root, body, CFrame.new(0, -1.2, 0)) -- sits on the floor like a parcel
	local function welded(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, name: string?)
		local p = Rig.part(model, {
			Name = name or "Part",
			Size = size,
			CFrame = body.CFrame * offset,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
		})
		Rig.weld(body, p)
		return p
	end
	welded(Vector3.new(3.25, 0.5, 0.3), CFrame.new(0, 0, -1.48), Color3.fromRGB(150, 120, 80), Enum.Material.Fabric) -- tape
	local label =
		welded(Vector3.new(1.4, 1, 0.05), CFrame.new(-0.6, 0.3, 1.62), Color3.fromRGB(240, 236, 226), nil, "Label")
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "FRAGILE\n⬆ THIS SIDE UP"
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(200, 40, 40)
	text.Parent = gui
	gui.Parent = label
	-- the flaps (the client opens them once Revealed) and what's inside
	for _, side in { -1, 1 } do
		local flap = Rig.part(model, {
			Name = "Flap",
			Size = Vector3.new(1.6, 0.12, 3.2),
			Color = CARDBOARD,
			Material = Enum.Material.Cardboard,
		})
		Rig.motor(
			if side < 0 then "FlapL" else "FlapR",
			body,
			flap,
			CFrame.new(side * 1.6, 1.3, 0),
			CFrame.new(side * 0.8, 0, 0)
		)
	end
	welded(
		Vector3.new(2.8, 0.1, 2.8),
		CFrame.new(0, 1.24, 0),
		Color3.fromRGB(30, 8, 40),
		Enum.Material.SmoothPlastic,
		"Maw"
	)
	for _, x in { -0.6, 0.6 } do
		local eye =
			Rig.eye(model, body, body.CFrame * CFrame.new(x, 1.32, -0.6), Vector3.new(0.6, 0.12, 0.4), INFECTION, x > 0)
		eye.Transparency = 1 -- shown by the client once Revealed
	end
	for i = 0, 3 do
		local angle = i * math.pi / 2 + math.pi / 4
		local hipC0 = CFrame.new(math.cos(angle) * 1.2, -0.6, math.sin(angle) * 1.2)
			* CFrame.Angles(0, -angle, 0)
			* CFrame.Angles(0, 0, math.rad(30))
		Rig.leg(model, root, i + 1, hipC0, 1.8, 2.4, Color3.fromRGB(60, 30, 80), i * math.pi / 2)
	end
	Rig.particles(body, {
		Color = ColorSequence.new(INFECTION, Color3.fromRGB(30, 10, 40)),
		Transparency = NumberSequence.new(0.6, 1),
		Size = NumberSequence.new(0.4, 1),
		Lifetime = NumberRange.new(0.6, 1),
		Rate = 3,
		Speed = NumberRange.new(0.5, 1),
	})
	Rig.humanoid(model, hip, 10)
	model:SetAttribute("Revealed", false)
	return model
end

local function buildMite(): Model
	local model = Instance.new("Model")
	model.Name = "ParcelMite"
	local hip = 0.6
	local root = Rig.root(model, Vector3.new(1.6, 1, 1.6), hip)
	local body = Rig.ball(model, Vector3.new(1.8, 1.1, 2), CFrame.new(), Color3.fromRGB(70, 34, 96))
	body.Name = "Body"
	Rig.motor("BodyJoint", root, body, CFrame.new(0, 0.2, 0))
	local scrap = Rig.part(model, {
		Size = Vector3.new(1.2, 0.1, 1),
		CFrame = body.CFrame * CFrame.new(0, 0.55, 0.2) * CFrame.Angles(0.2, 0.4, 0),
		Color = CARDBOARD,
		Material = Enum.Material.Cardboard,
	})
	Rig.weld(body, scrap)
	for _, x in { -0.3, 0.3 } do
		Rig.eye(model, body, body.CFrame * CFrame.new(x, 0.25, -0.9), Vector3.new(0.25, 0.18, 0.08), INFECTION)
	end
	for i = 1, 6 do
		local side = if i <= 3 then 1 else -1
		local z = ((i - 1) % 3 - 1) * 0.5
		local hipC0 = CFrame.new(side * 0.7, 0, z)
			* CFrame.Angles(0, if side < 0 then math.pi else 0, 0)
			* CFrame.Angles(0, 0, math.rad(35))
		Rig.leg(model, root, i, hipC0, 0.8, 1.2, Color3.fromRGB(40, 20, 56), if i % 2 == 0 then 0 else math.pi)
	end
	Rig.humanoid(model, hip, 14)
	return model
end

local function reveal(enemy: any, now: number)
	local c = enemy.Custom
	if c.Revealed then
		return
	end
	c.Revealed = true
	c.WakeAt = now + REVEAL_PAUSE
	c.NextPounce = now + REVEAL_PAUSE + 1
	enemy.Model:SetAttribute("Revealed", true)
	enemy.Model:SetAttribute("AttackAt", workspace:GetServerTimeNow())
end

local function think(enemy: any, now: number, ai: any): boolean
	local c = enemy.Custom
	local root: BasePart = enemy.Root
	local humanoid: Humanoid = enemy.Humanoid
	if not c.Revealed then
		humanoid.WalkSpeed = 0
		local _, _, distance = ai.NearestPlayer(root.Position, REVEAL_RANGE, false)
		if distance < REVEAL_RANGE then
			reveal(enemy, now)
		end
		return true
	end
	if now < (c.WakeAt or 0) then
		humanoid.WalkSpeed = 0
		return true
	end
	local pounce = c.Pounce
	if pounce then
		if now < pounce.LeapAt then
			humanoid.WalkSpeed = 0
			humanoid:MoveTo(root.Position)
		elseif now < pounce.At then
			humanoid.WalkSpeed = POUNCE_SPEED
			humanoid.Jump = true
			humanoid:MoveTo(pounce.Target)
		else
			c.Pounce = nil
			c.NextPounce = now + POUNCE_COOLDOWN
			for _, player in Telegraph.playersInCircle(Players:GetPlayers(), pounce.Target, POUNCE_RADIUS) do
				ai.HitPlayer(player, enemy.Config.Damage, pounce.Target)
			end
			Telegraph.burst(pounce.Target, POUNCE_RADIUS, INFECTION)
		end
		return true
	end
	if now >= (c.NextPounce or 0) then
		local player, target, distance = ai.NearestPlayer(root.Position, enemy.Config.AggroRange, true)
		if player and target and distance >= POUNCE_MIN and distance <= POUNCE_MAX then
			local spot = Telegraph.floorBelow(target.Position)
			c.Pounce = { Target = spot, LeapAt = now + POUNCE_WARN * 0.5, At = now + POUNCE_WARN }
			Telegraph.disc(spot, POUNCE_RADIUS, POUNCE_WARN, INFECTION)
			ai.Face(enemy, spot)
			ai.Warn(player, POUNCE_WARN)
			enemy.Model:SetAttribute("WindupAt", ai.ServerNow())
			return true
		end
	end
	return false -- chase and bite like any crawler
end

ParcelMimic.Mimic = {
	Build = buildMimic,
	Think = think,
	OnLit = function(enemy: any, _player: Player, _dt: number, _ai: any)
		reveal(enemy, os.clock())
	end,
	OnKilled = function(enemy: any, ai: any)
		local position = enemy.Root.Position
		for i = 1, T.Split do
			local angle = i * math.pi
			local offset = Vector3.new(math.cos(angle) * 2, -enemy.Config.HipHeight, math.sin(angle) * 2)
			ai.Spawn("ParcelMite", position + offset, enemy.Custom.Tier)
		end
	end,
}

ParcelMimic.Mite = {
	Build = buildMite,
}

-- A disguised mimic as a prop: used by the level to hide them among real parcels.
ParcelMimic.Palette = { Cardboard = CARDBOARD, Infection = INFECTION, Glow = Palette.NeonPurple }

return ParcelMimic
