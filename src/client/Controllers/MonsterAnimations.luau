-- Per-type procedural animation for the Chapter 2 monsters, run by EnemyVisualController
-- after its shared pass (legs, body bob, lunges, wind-ups). Each entry may adjust joints
-- found by name in visual.Joints and keep its own state in visual.Custom. Client-only.

local MonsterAnimations = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function flatSpeed(root: BasePart): number
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

local function addToBody(visual: any, offset: CFrame)
	local body: Motor6D? = visual.Body
	if body then
		body.Transform *= offset
	end
end

-- Wheels spin with speed, the lid rattles, it shudders while aiming and spins out dizzy.
MonsterAnimations.PossessedCart = function(visual: any, dt: number, now: number)
	local model: Model = visual.Model
	local c = visual.Custom
	c.Spin = (c.Spin or 0) + dt * flatSpeed(visual.Root) / 0.7
	for i = 1, 4 do
		local wheel = visual.Joints["Wheel" .. i]
		if wheel then
			wheel.Transform = CFrame.Angles(c.Spin, 0, 0)
		end
	end
	local aiming = model:GetAttribute("Aiming") == true
	local lid = visual.Joints.LidJoint
	if lid then
		local k = if aiming then 2.5 else 1
		lid.Transform = CFrame.new(0, math.abs(math.sin(now * 23)) * 0.12 * k, 0)
			* CFrame.Angles(math.sin(now * 31) * 0.06 * k, 0, 0)
	end
	if aiming then
		addToBody(visual, CFrame.new((math.random() - 0.5) * 0.25, 0, 0) * CFrame.Angles(-0.12, 0, 0))
	elseif serverNow() < ((model:GetAttribute("DizzyUntil") or 0) :: number) then
		addToBody(visual, CFrame.Angles(0, math.sin(now * 14) * 0.5, math.sin(now * 9) * 0.1))
	end
end

-- Disguised: a still box (legs and eyes hidden) with the faintest breathing as its only
-- tell. Revealing: scraps burst off, the flaps fly open, it rises onto its legs, shaking.
-- Revealed: the flaps chew like jaws, gaping wide while it winds up an attack.
MonsterAnimations.ParcelMimic = function(visual: any, _dt: number, now: number)
	local model: Model = visual.Model
	local c = visual.Custom
	local revealed = model:GetAttribute("Revealed") == true
	if c.Shown ~= revealed then
		c.Shown = revealed
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				if part.Name:match("Leg%d") then
					part.LocalTransparencyModifier = if revealed then 0 else 1
				elseif part.Name == "Eye" then
					part.Transparency = if revealed then 0 else 1
				end
			end
		end
		local scraps = model:FindFirstChild("Scraps", true)
		if revealed and scraps and scraps:IsA("ParticleEmitter") then
			scraps:Emit(16)
		end
	end
	local since = serverNow() - ((model:GetAttribute("RevealedAt") or 0) :: number)
	local open = if revealed then math.clamp(since / 0.35, 0, 1) else 0
	local windup = serverNow() - ((model:GetAttribute("WindupAt") or 0) :: number)
		< (model:GetAttribute("Windup") or 0.6) :: number
	local angle = if not revealed then 0 elseif windup then 2 else 1.2 + math.sin(now * 9) * 0.35
	for name, sign in { FlapL = 1, FlapR = -1 } do
		local flap = visual.Joints[name]
		if flap then
			flap.Transform = CFrame.Angles(0, 0, sign * angle * open)
		end
	end
	local body: Motor6D? = visual.Body
	if body then
		if not revealed then
			body.Transform = CFrame.new(0, math.max(0, math.sin(now * 1.3)) * 0.03, 0)
		else
			local rise = CFrame.new(0, 0.9 * open, 0) -- stands up on its legs
			local shake = if since < 0.8 then CFrame.new((math.random() - 0.5) * 0.3, 0, 0) else CFrame.new()
			body.Transform *= rise * shake
		end
	end
end

-- Arms sway; they rise while it breathes frost; light makes it shudder.
MonsterAnimations.FrostWraith = function(visual: any, _dt: number, now: number)
	local model: Model = visual.Model
	local breathing = model:GetAttribute("Breathing") == true
	for name, sign in { ArmL = -1, ArmR = 1 } do
		local arm = visual.Joints[name]
		if arm then
			local raise = if breathing then -0.9 else math.sin(now * 1.4 + sign) * 0.25
			arm.Transform = CFrame.Angles(raise, 0, sign * (0.1 + math.sin(now * 0.9) * 0.08))
		end
	end
	addToBody(visual, CFrame.new(0, math.sin(now * 1.1) * 0.35, 0))
	if serverNow() < ((model:GetAttribute("SlowedUntil") or 0) :: number) then
		addToBody(visual, CFrame.new((math.random() - 0.5) * 0.2, 0, 0))
	end
end

-- Tendrils drift; it throbs, and swells violently before exhaling.
MonsterAnimations.SporeBloater = function(visual: any, _dt: number, now: number)
	local model: Model = visual.Model
	for i = 1, 3 do
		local tendril = visual.Joints["Tendril" .. i]
		if tendril then
			tendril.Transform = CFrame.Angles(math.sin(now * 1.7 + i * 2) * 0.35, 0, math.cos(now * 1.3 + i) * 0.25)
		end
	end
	local swelling = model:GetAttribute("Swelling") == true
	local throb = math.sin(now * (if swelling then 18 else 3)) * (if swelling then 0.2 else 0.08)
	addToBody(visual, CFrame.new(0, math.sin(now * 0.8) * 0.5 + throb, 0))
end

-- Rolls forward as it moves.
MonsterAnimations.Meatball = function(visual: any, dt: number, _now: number)
	local c = visual.Custom
	c.Roll = (c.Roll or 0) + dt * flatSpeed(visual.Root) / 1.6
	addToBody(visual, CFrame.Angles(-c.Roll, 0, 0))
end

return MonsterAnimations
