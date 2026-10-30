-- Infected deliveries (Level 10 night).
--
-- Parcel Mimic: disguised, it looks exactly like the real parcels around it (ParcelMimic.decoy):
-- no legs, eyes, smoke or glow, and it doesn't move (ParcelMimic.disguise anchors it). A
-- player coming close in plain sight, or a light on it, makes it burst open. Then it hunts:
-- up close it bites; at mid range, with a clear line to you, it crouches and POUNCES at the
-- spot a purple circle marks. The pounce only hurts if it really got there. When destroyed
-- it splits into two Parcel Mites.
-- Parcel Mite: a small, quick biter (still slower than players).
-- Awake creatures with nobody in sight head for the nearest player, not for shops.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterTuning = require(ReplicatedStorage.Shared.Config.MonsterTuning)
local Telegraph = require(script.Parent.Parent.Util.Telegraph)
local Rig = require(script.Parent.Rig)

local ParcelMimic = {}

local T = MonsterTuning.Mimic
local REVEAL_RANGE = T.RevealRange
local REVEAL_PAUSE = T.RevealPause
local POUNCE_RADIUS = T.PounceRadius
local POUNCE_SPEED = T.PounceSpeed
local POUNCE_COOLDOWN = T.PounceCooldown
local POUNCE_MIN, POUNCE_MAX = T.PounceMin, T.PounceMax
local CARDBOARD = Color3.fromRGB(196, 154, 104)
local INFECTION = Color3.fromRGB(170, 60, 255)
local TAPE = Color3.fromRGB(150, 120, 80)
local SIZE = Vector3.new(3.2, 2.6, 3.2)

-- The tape and shipping label every parcel wears (real ones and mimics alike).
local function dress(place: (Vector3, CFrame, Color3, Enum.Material, string) -> BasePart)
	place(Vector3.new(3.25, 0.5, 0.3), CFrame.new(0, 0, -1.48), TAPE, Enum.Material.Fabric, "Tape")
	local label = place(
		Vector3.new(1.4, 1, 0.05),
		CFrame.new(-0.6, 0.3, 1.62),
		Color3.fromRGB(240, 236, 226),
		Enum.Material.SmoothPlastic,
		"Label"
	)
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
end

local function buildMimic(): Model
	local model = Instance.new("Model")
	model.Name = "ParcelMimic"
	local hip = 1.4
	local root = Rig.root(model, Vector3.new(3, 2.4, 3), hip)
	local body = Rig.part(model, {
		Name = "Body",
		Size = SIZE,
		Color = CARDBOARD,
		Material = Enum.Material.Cardboard,
	})
	Rig.motor("BodyJoint", root, body, CFrame.new(0, -1.2, 0)) -- sits on the floor like a parcel
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
			Material = material or Enum.Material.SmoothPlastic,
		})
		Rig.weld(body, p)
		return p
	end
	dress(welded)
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
		-- teeth under the flap: hidden inside the box until it opens
		for k = -1, 1 do
			local tooth = Rig.part(model, {
				Name = "Tooth",
				Size = Vector3.new(0.3, 0.55, 0.3),
				CFrame = flap.CFrame * CFrame.new(side * -0.55, -0.3, k * 1),
				Color = Color3.fromRGB(245, 235, 215),
			})
			Rig.weld(flap, tooth)
		end
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
	-- nothing glows or smokes until it reveals itself (a lit box would give it away)
	Rig.particles(body, {
		Name = "Goo",
		Color = ColorSequence.new(INFECTION, Color3.fromRGB(30, 10, 40)),
		Transparency = NumberSequence.new(0.6, 1),
		Size = NumberSequence.new(0.4, 1),
		Lifetime = NumberRange.new(0.6, 1),
		Rate = 3,
		Speed = NumberRange.new(0.5, 1),
		Enabled = false,
	})
	Rig.particles(body, {
		Name = "Scraps", -- the client bursts these when it transforms
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(CARDBOARD),
		LightEmission = 0,
		Size = NumberSequence.new(0.7, 0.3),
		Lifetime = NumberRange.new(0.5, 0.9),
		Rate = 0,
		Speed = NumberRange.new(10, 18),
		Acceleration = Vector3.new(0, -40, 0),
		Enabled = false,
	})
	for _, light in model:GetDescendants() do
		if light:IsA("Light") then
			light.Enabled = false
		end
	end
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

local function reveal(enemy: any, now: number, ai: any)
	local c = enemy.Custom
	if c.Revealed then
		return
	end
	c.Revealed = true
	c.WakeAt = now + REVEAL_PAUSE
	c.NextPounce = now + REVEAL_PAUSE + 1
	local root: BasePart = enemy.Root
	if root.Anchored then
		root.Anchored = false
		root:SetNetworkOwner(nil)
	end
	local model: Model = enemy.Model
	for _, child in model:GetDescendants() do
		if child:IsA("Light") or child.Name == "Goo" then
			(child :: any).Enabled = true
		end
	end
	model:SetAttribute("Disguised", nil)
	model:SetAttribute("Revealed", true)
	model:SetAttribute("RevealedAt", ai.ServerNow())
	if c.OnReveal then
		c.OnReveal(enemy)
	end
end

-- Nobody in sight: head for the nearest player anywhere (the default AI would wander off
-- to raid shops in another wing). false = someone's in sight, the default AI hunts them.
local function prowl(enemy: any, _now: number, ai: any): boolean
	local position = enemy.Root.Position
	if ai.NearestPlayer(position, enemy.Config.AggroRange, true) then
		return false
	end
	local _, anyone = ai.NearestPlayer(position, math.huge, false)
	if anyone then
		ai.Navigate(enemy, anyone.Position)
	else
		enemy.Humanoid:MoveTo(position)
	end
	return true
end

local function land(enemy: any, pounce: { [string]: any }, now: number, ai: any)
	local c = enemy.Custom
	c.Pounce = nil
	c.NextPounce = now + POUNCE_COOLDOWN
	if ai.FlatDistance(enemy.Root.Position, pounce.Target) > T.PounceReach then
		return -- it fell short (blocked by something): no hit from thin air
	end
	enemy.Model:SetAttribute("AttackAt", ai.ServerNow())
	for _, player in Telegraph.playersInCircle(Players:GetPlayers(), pounce.Target, POUNCE_RADIUS) do
		ai.HitPlayer(player, enemy.Config.Damage, pounce.Target)
	end
	Telegraph.burst(pounce.Target, POUNCE_RADIUS, INFECTION)
end

local function think(enemy: any, now: number, ai: any): boolean
	local c = enemy.Custom
	local root: BasePart = enemy.Root
	local humanoid: Humanoid = enemy.Humanoid
	if not c.Revealed then
		humanoid.WalkSpeed = 0
		local _, target, distance = ai.NearestPlayer(root.Position, REVEAL_RANGE, false)
		local sees = target ~= nil
			and (distance < 4 or ai.LineOfSight(root.Position + Vector3.new(0, 1, 0), target.Position))
		if c.Wake or sees then
			reveal(enemy, now, ai)
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
		elseif now < pounce.At and ai.FlatDistance(root.Position, pounce.Target) > 2.5 then
			humanoid.WalkSpeed = POUNCE_SPEED
			if not pounce.Jumped then
				pounce.Jumped = true
				humanoid.Jump = true
			end
			humanoid:MoveTo(pounce.Target)
		else
			land(enemy, pounce, now, ai)
		end
		return true
	end
	if now >= (c.NextPounce or 0) then
		local player, target, distance = ai.NearestPlayer(root.Position, enemy.Config.AggroRange, true)
		if
			player
			and target
			and distance >= POUNCE_MIN
			and distance <= POUNCE_MAX
			and ai.LineOfSight(root.Position, target.Position)
		then
			local spot = Telegraph.floorBelow(target.Position)
			local leapAfter, landAfter = MonsterTuning.pounceTimes(distance)
			c.Pounce = { Target = spot, LeapAt = now + leapAfter, At = now + landAfter }
			Telegraph.disc(spot, POUNCE_RADIUS, landAfter, INFECTION)
			ai.Face(enemy, spot)
			ai.Warn(player, landAfter)
			enemy.Model:SetAttribute("WindupAt", ai.ServerNow())
			return true
		end
	end
	return prowl(enemy, now, ai)
end

-- Turns a freshly spawned mimic into a still, silent parcel on the floor.
function ParcelMimic.disguise(enemy: any, floorY: number)
	local root: BasePart = enemy.Root
	local p = root.Position
	root.CFrame = CFrame.new(p.X, floorY + 2.5, p.Z) * root.CFrame.Rotation
	root.Anchored = true
	enemy.Model:SetAttribute("Disguised", true)
end

-- A real parcel, identical to a disguised mimic.
function ParcelMimic.decoy(parent: Instance, at: Vector3, yaw: number): Model
	local model = Instance.new("Model")
	model.Name = "Parcel"
	local base = CFrame.new(at + Vector3.new(0, SIZE.Y / 2, 0)) * CFrame.Angles(0, yaw, 0)
	local function place(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, name: string): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.CFrame = base * offset
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local box = place(SIZE, CFrame.new(), CARDBOARD, Enum.Material.Cardboard, "Body")
	box.CanCollide = true
	box.CanQuery = true
	dress(place)
	for _, side in { -1, 1 } do
		place(Vector3.new(1.6, 0.12, 3.2), CFrame.new(side * 0.8, 1.3, 0), CARDBOARD, Enum.Material.Cardboard, "Flap")
	end
	model.Parent = parent
	return model
end

ParcelMimic.Mimic = {
	Build = buildMimic,
	Think = think,
	OnLit = function(enemy: any, _player: Player, _dt: number, ai: any)
		reveal(enemy, os.clock(), ai)
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
	Think = prowl,
}

return ParcelMimic
