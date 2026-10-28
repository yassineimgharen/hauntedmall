-- Level 8 (Chapter 2 opener): Day "Grand Reopening" / Night "Kitchen Nightmare".
--
-- Day:   the food court has been sealed for years. Every restaurant's shutter is down and
--        black slime covers the floors. Grab a mop at the janitor cart (one carried item)
--        and scrub the puddles (hold E); hold E at a restaurant's yellow switch box to raise
--        its shutter and light its sign.
-- Night: the kitchen equipment is possessed. Possessed appliances (purple glow, shaking)
--        hurl cutlery down a red lane at the nearest player in sight; holding a flashlight
--        on one suppresses it and slowly exorcises it (ExorciseSeconds of beam, shared by
--        everyone lighting it). Possessed carts roam and charge. Balance (how many
--        appliances at once, carts, volley rate) comes from FoodCourtRules.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local CombatService = require(script.Parent.Parent.Services.CombatService)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Telegraph = require(script.Parent.Parent.Util.Telegraph)
local Builder = require(script.Parent.Parent.World.Builder)
local Carry = require(script.Parent.Carry)
local FoodCourtRules = require(script.Parent.FoodCourtRules)

local GrandReopening = {}

local R = FoodCourtRules.L08
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local SLIME = Color3.fromRGB(40, 12, 54)
local GHOST = Color3.fromRGB(180, 90, 255)
local SHUTTER_OPEN = Vector3.new(22, 1.2, 1.2)
local SHUTTER_CLOSED = Vector3.new(22, 14, 0.5)
local CART_SPOT = CFrame.lookAt(Vector3.new(-118, 0, 0), Vector3.new(-100, 0, 0))
local PUDDLES = {
	Vector3.new(-120, 0, -30),
	Vector3.new(-150, 0, 34),
	Vector3.new(-162, 0, -34),
	Vector3.new(-136, 0, 32),
	Vector3.new(-176, 0, 6),
	Vector3.new(-113, 0, 57),
	Vector3.new(-169, 0, 57),
	Vector3.new(-141, 0, -57),
	Vector3.new(-210, 0, 0),
	Vector3.new(-230, 0, -14),
	Vector3.new(-215, 0, -60),
	Vector3.new(-125, 0, -110),
}

type Appliance = {
	Model: Model,
	Body: BasePart,
	Name: string,
	Possessed: boolean,
	Done: boolean,
	Progress: number,
	Contributors: { [Player]: number },
	NextVolley: number,
	LastLit: number,
	Fx: { Instance },
	Bar: Frame?,
}

local dayFolder: Folder? = nil
local nightToken: {}? = nil
local appliances: { Appliance } = {}
local killedConnection: any = nil -- EnemyService.Killed (Signal) connection
local rng = Random.new()

local function restaurants(): { Model }
	local list = {}
	for _, model in CollectionService:GetTagged("FCRestaurant") do
		if model:IsA("Model") then
			table.insert(list, model)
		end
	end
	return list
end

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- ── restaurants: shutters and signs ─────────────────────────────────────────

local function setSign(restaurant: Model, lit: boolean)
	local sign = restaurant:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("Gui")
	if gui and gui:IsA("SurfaceGui") then
		gui.Enabled = lit
	end
	for _, strip in restaurant:GetChildren() do
		if strip.Name == "SignStrip" and strip:IsA("BasePart") then
			local accent = strip:GetAttribute("Accent")
			if typeof(accent) ~= "Color3" then
				accent = strip.Color
				strip:SetAttribute("Accent", accent)
			end
			local color = if lit then accent :: Color3 else Color3.fromRGB(30, 26, 34)
			strip:SetAttribute("BaseColor", color) -- LightingController keeps this as the neon's base
			strip.Color = color
		end
	end
end

local function setShutter(restaurant: Model, closed: boolean, instant: boolean?)
	local shutter = restaurant:FindFirstChild("Shutter")
	if not shutter or not shutter:IsA("BasePart") then
		return
	end
	local goal = {
		Size = if closed then SHUTTER_CLOSED else SHUTTER_OPEN,
		CFrame = shutter:GetAttribute(if closed then "ClosedCFrame" else "OpenCFrame"),
	}
	shutter.CanCollide = closed
	if instant then
		shutter.Size, shutter.CFrame = goal.Size, goal.CFrame
	else
		TweenService:Create(shutter, TweenInfo.new(1.6, Enum.EasingStyle.Quad), goal):Play()
	end
	restaurant:SetAttribute("Closed", closed)
end

local function openAll()
	for _, restaurant in restaurants() do
		if restaurant:GetAttribute("Closed") then
			setShutter(restaurant, false)
			setSign(restaurant, true)
		end
	end
end

-- ── day ─────────────────────────────────────────────────────────────────────

local function markDone(part: BasePart, prompt: ProximityPrompt)
	part:SetAttribute("Done", true)
	prompt:SetAttribute("Done", true)
	prompt.Enabled = false
end

local function buildJanitorCart(parent: Instance)
	local model = Builder.model("JanitorCart", parent)
	Builder.part({
		Parent = model,
		Size = Vector3.new(4, 2.6, 3),
		CFrame = CART_SPOT * CFrame.new(0, 1.6, 0),
		Color = Color3.fromRGB(240, 196, 40),
		Material = Enum.Material.SmoothPlastic,
	})
	Builder.cylinder((CART_SPOT * CFrame.new(-1, 3.4, 0)).Position, 1.1, 1.4, {
		Parent = model,
		Color = Color3.fromRGB(60, 120, 200),
		Material = Enum.Material.SmoothPlastic,
	})
	local bin = Builder.part({
		Name = "SupplyMop",
		Parent = model,
		Size = Vector3.new(1.6, 1, 1.6),
		CFrame = CART_SPOT * CFrame.new(1.1, 3.4, 0),
		Color = Color3.fromRGB(90, 70, 50),
		Material = Enum.Material.Wood,
		Tags = { "SupplyMop" },
	})
	for i = 0, 2 do
		Builder.decor({
			Parent = model,
			Size = Vector3.new(0.25, 5, 0.25),
			CFrame = CART_SPOT
				* CFrame.new(0.8 + i * 0.3, 5.6, -0.4 + i * 0.4)
				* CFrame.Angles(0.1 * i, 0, -0.15 + i * 0.12),
			Color = Palette.Wood,
			Material = Enum.Material.Wood,
		})
	end
	local sign = Builder.decor({
		Parent = model,
		Size = Vector3.new(4, 1.2, 0.2),
		CFrame = CART_SPOT * CFrame.new(0, 3.3, -1.7),
		Color = Color3.fromRGB(20, 18, 24),
	})
	Builder.label(sign, Enum.NormalId.Front, "🧹 MOPS", { Color = Palette.NeonGold, Font = FONT })
	local prompt = Builder.prompt(bin, {
		ActionText = "Take Mop",
		ObjectText = "Janitor Cart",
		HoldDuration = 0,
		MaxActivationDistance = 9,
	})
	prompt.Triggered:Connect(function(player)
		if GameStateService.GetPhase() == "Day" and Carry.pickUp(player, "Mop") then
			Notify.player(player, "🧹 Mop in hand: scrub the black slime puddles (hold E).", "info")
		end
	end)
end

local function buildPuddle(parent: Instance, position: Vector3)
	local disc = Builder.part({
		Name = "SlimePuddle",
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 6, 6),
		CFrame = CFrame.new(position + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), math.rad(90)),
		Color = SLIME,
		Material = Enum.Material.Glass,
		Reflectance = 0.25,
		CanCollide = false,
		CastShadow = false,
		Tags = { "SlimePuddle" },
	})
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(150, 60, 220))
	bubbles.Size = NumberSequence.new(0.3, 0)
	bubbles.Lifetime = NumberRange.new(0.6, 1)
	bubbles.Rate = 4
	bubbles.Speed = NumberRange.new(0.5, 1.5)
	bubbles.EmissionDirection = Enum.NormalId.Right -- cylinder rotated: local +X is up
	bubbles.Parent = disc
	local prompt = Builder.prompt(disc, {
		ActionText = "Scrub",
		ObjectText = "Black Slime",
		HoldDuration = R.ScrubSeconds,
		MaxActivationDistance = 8,
	})
	prompt:SetAttribute("RequiresCarry", "Mop")
	Builder.tag(prompt, "CarryPrompt")
	prompt.Triggered:Connect(function(player)
		if GameStateService.GetPhase() ~= "Day" or disc:GetAttribute("Done") or Carry.item(player) ~= "Mop" then
			return
		end
		markDone(disc, prompt)
		bubbles.Enabled = false
		TweenService:Create(disc, TweenInfo.new(0.8), { Size = Vector3.new(0.12, 0.5, 0.5), Transparency = 1 }):Play()
		MissionEvents.record(player, "SlimeScrubbed")
		Notify.effect(
			player,
			"WorldPopup",
			{ Position = position + Vector3.new(0, 3, 0), Text = "✨ CLEAN!", Color = "Cyan" }
		)
	end)
end

local function bindSwitch(restaurant: Model, parent: Instance)
	local switch = restaurant:FindFirstChild("SignSwitch")
	if not switch or not switch:IsA("BasePart") then
		return
	end
	switch:SetAttribute("Done", nil)
	Builder.tag(switch, "ReopenSwitch")
	local prompt = Builder.prompt(switch, {
		Name = "ReopenPrompt",
		ActionText = "Reopen",
		ObjectText = restaurant:GetAttribute("RestaurantName") or "Restaurant",
		HoldDuration = R.ReopenSeconds,
		MaxActivationDistance = 9,
	})
	-- the prompt lives on the world switch: remove it with the day folder
	parent.Destroying:Connect(function()
		prompt:Destroy()
		CollectionService:RemoveTag(switch, "ReopenSwitch")
	end)
	prompt.Triggered:Connect(function(player)
		if GameStateService.GetPhase() ~= "Day" or not restaurant:GetAttribute("Closed") then
			return
		end
		markDone(switch, prompt)
		setShutter(restaurant, false)
		task.spawn(function()
			-- the sign sputters back to life
			for i = 1, 5 do
				setSign(restaurant, i % 2 == 1)
				task.wait(0.12 + i * 0.03)
			end
			setSign(restaurant, true)
		end)
		MissionEvents.record(player, "RestaurantReopened")
		Notify.all(
			string.format(
				"🍔 %s reopened %s!",
				player.DisplayName,
				tostring(restaurant:GetAttribute("RestaurantName"))
			),
			"success"
		)
	end)
end

function GrandReopening.StartDay()
	GrandReopening.EndDay()
	local folder = Instance.new("Folder")
	folder.Name = "GrandReopeningDay"
	folder.Parent = workspace
	dayFolder = folder
	for _, restaurant in restaurants() do
		setShutter(restaurant, true, true)
		setSign(restaurant, false)
		bindSwitch(restaurant, folder)
	end
	buildJanitorCart(folder)
	for _, position in PUDDLES do
		buildPuddle(folder, position)
	end
end

function GrandReopening.EndDay()
	Carry.clearAll()
	if dayFolder then
		dayFolder:Destroy()
		dayFolder = nil
	end
end

-- ── night: possessed appliances ─────────────────────────────────────────────

local function flat(v: Vector3): { number }
	return { v.X, v.Z }
end

local function clearFx(app: Appliance)
	for _, instance in app.Fx do
		instance:Destroy()
	end
	table.clear(app.Fx)
	app.Bar = nil
	CollectionService:RemoveTag(app.Body, "PossessedAppliance")
	app.Body:SetAttribute("Done", nil)
end

local function exorcised(app: Appliance, finisher: Player)
	app.Done = true
	app.Possessed = false
	CombatService.UnregisterLightTarget(app.Model)
	clearFx(app)
	MissionEvents.record(finisher, "ApplianceExorcised")
	for player, seconds in app.Contributors do
		if player.Parent and (seconds >= 0.75 or player == finisher) then
			MissionEvents.record(player, "ExorcismHelped")
		end
	end
	local count = 0
	for _, other in appliances do
		if other.Done then
			count += 1
		end
	end
	Notify.effectAll(
		"WorldPopup",
		{ Position = app.Body.Position + Vector3.new(0, 4, 0), Text = "✨ EXORCISED!", Color = "Cyan" }
	)
	Notify.all(
		string.format("✨ %s exorcised the %s! (%d exorcised)", finisher.DisplayName, app.Name, count),
		"success"
	)
end

local function onLit(app: Appliance, player: Player, dt: number)
	if not app.Possessed or app.Done or not nightToken then
		return
	end
	app.LastLit = os.clock()
	app.Contributors[player] = (app.Contributors[player] or 0) + dt
	local progress, done = FoodCourtRules.exorcise(app.Progress, dt)
	app.Progress = progress
	local bar = app.Bar
	if bar then
		bar.Size = UDim2.fromScale(progress / R.ExorciseSeconds, 1)
	end
	if done then
		exorcised(app, player)
	end
end

local function possess(app: Appliance)
	app.Possessed = true
	app.Progress = 0
	table.clear(app.Contributors)
	app.NextVolley = os.clock() + 3
	CollectionService:AddTag(app.Body, "PossessedAppliance")
	local highlight = Instance.new("Highlight")
	highlight.FillColor = GHOST
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = Color3.fromRGB(230, 200, 255)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = app.Model
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(GHOST, Color3.fromRGB(30, 10, 50))
	smoke.Transparency = NumberSequence.new(0.4, 1)
	smoke.Size = NumberSequence.new(1.5, 4)
	smoke.Lifetime = NumberRange.new(1, 1.6)
	smoke.Rate = 8
	smoke.Speed = NumberRange.new(1, 2.5)
	smoke.Parent = app.Body
	local glow = Instance.new("PointLight")
	glow.Color = GHOST
	glow.Range = 14
	glow.Brightness = 1.5
	glow.Parent = app.Body
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(150, 36)
	gui.StudsOffsetWorldSpace = Vector3.new(0, app.Body.Size.Y / 2 + 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 20)
	label.BackgroundTransparency = 1
	label.Text = "👻 POSSESSED"
	label.TextColor3 = Color3.fromRGB(230, 200, 255)
	label.TextScaled = true
	label.FontFace = FONT
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 10)
	back.Position = UDim2.fromOffset(0, 24)
	back.BackgroundColor3 = Color3.fromRGB(30, 16, 50)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(120, 255, 255)
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = app.Body
	app.Bar = fill
	app.Fx = { highlight, smoke, glow, gui }
	local radius = math.max(app.Body.Size.X, app.Body.Size.Y, app.Body.Size.Z) / 2 + 0.5
	CombatService.RegisterLightTarget(app.Model, function(player, dt)
		onLit(app, player, dt)
	end, { Parts = { app.Body }, Radius = { radius } })
	Notify.all(string.format("👻 The %s is possessed! Burn it out with your flashlight.", app.Name), "danger")
end

local function sees(app: Appliance, target: BasePart): boolean
	local origin = app.Body.Position + Vector3.new(0, app.Body.Size.Y / 2 + 1, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { app.Model, workspace:FindFirstChild("Telegraphs") or app.Model }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(origin, target.Position - origin, params)
	return hit == nil or (target.Parent ~= nil and hit.Instance:IsDescendantOf(target.Parent))
end

local function volley(app: Appliance, player: Player, target: BasePart, myToken: {})
	local from = Telegraph.floorBelow(app.Body.Position + Vector3.new(0, 2, 0))
	local direction = Vector3.new(target.Position.X - from.X, 0, target.Position.Z - from.Z)
	if direction.Magnitude < 0.5 then
		return
	end
	direction = direction.Unit
	from += direction * (math.max(app.Body.Size.X, app.Body.Size.Z) / 2 + 0.5)
	local to = from + direction * R.VolleyLength
	Telegraph.lane(from, to, R.VolleyWidth, R.VolleyWarn, Color3.fromRGB(255, 70, 160))
	Notify.effect(player, "Danger", { Windup = R.VolleyWarn })
	task.delay(R.VolleyWarn, function()
		if nightToken ~= myToken or app.Done then
			return
		end
		for _, victim in Telegraph.playersInLane(Players:GetPlayers(), from, to, R.VolleyWidth) do
			EnemyService.HitPlayer(victim, R.VolleyDamage, from)
		end
		-- the cutlery itself: a few glinting knives racing down the lane
		for i = 1, 4 do
			local knife = Builder.decor({
				Parent = workspace:FindFirstChild("Telegraphs") or workspace,
				Size = Vector3.new(0.25, 0.1, 1.6),
				CFrame = CFrame.lookAt(from + Vector3.new((i - 2.5) * 0.6, 3, 0), to + Vector3.new(0, 3, 0)),
				Color = Color3.fromRGB(230, 236, 245),
				Material = Enum.Material.Neon,
			})
			TweenService
				:Create(knife, TweenInfo.new(0.35 + i * 0.04, Enum.EasingStyle.Linear), {
					CFrame = CFrame.lookAt(
						to + Vector3.new((i - 2.5) * 0.6, 3, 0),
						to + direction + Vector3.new(0, 3, 0)
					),
				})
				:Play()
			task.delay(0.5, function()
				knife:Destroy()
			end)
		end
	end)
end

local function runVolleys(myToken: {})
	local turn = 0
	while nightToken == myToken do
		task.wait(R.VolleyGap)
		local now = os.clock()
		local count = #appliances
		for step = 1, count do
			local app = appliances[(turn + step - 1) % count + 1]
			-- a beam on it suppresses it: lighting an appliance is also your shield
			if app.Possessed and not app.Done and now >= app.NextVolley and now - app.LastLit > 0.6 then
				local best, bestRoot, bestDistance = nil, nil, R.VolleyRange
				for _, player in Players:GetPlayers() do
					local root = livingRoot(player)
					if root then
						local distance = (root.Position - app.Body.Position).Magnitude
						if distance < bestDistance and sees(app, root) then
							best, bestRoot, bestDistance = player, root, distance
						end
					end
				end
				if best and bestRoot then
					app.NextVolley = now + R.ApplianceCooldown + rng:NextNumber(0, 1.5)
					turn = (turn + step) % count
					volley(app, best, bestRoot, myToken)
					break
				end
			end
		end
	end
end

local function runPossessions(myToken: {})
	local possessed = 0
	local nextAt = os.clock() + 3
	local first = true
	while nightToken == myToken do
		task.wait(1)
		local active = 0
		for _, app in appliances do
			if app.Possessed and not app.Done then
				active += 1
			end
		end
		local want = FoodCourtRules.activePossessions(#Players:GetPlayers())
		local now = os.clock()
		if active < want and possessed < R.MaxPossessions and now >= nextAt then
			local free, positions = {}, {}
			for _, app in appliances do
				if not app.Possessed and not app.Done then
					table.insert(free, app)
					table.insert(positions, flat(app.Body.Position))
				end
			end
			local playerPositions = {}
			for _, player in Players:GetPlayers() do
				local root = livingRoot(player)
				if root then
					table.insert(playerPositions, flat(root.Position))
				end
			end
			if #free > 0 then
				local index = FoodCourtRules.pickPossession(positions, playerPositions) or rng:NextInteger(1, #free)
				possess(free[index])
				possessed += 1
				local opening = first and possessed < R.FirstPossessions
				nextAt = now + (if opening then 1 else R.PossessEvery)
				if possessed >= R.FirstPossessions then
					first = false
				end
			end
		end
	end
end

local function spawnPoint(): Vector3?
	local best, bestDistance = nil, -1
	for _, point in CollectionService:GetTagged("FoodCourtSpawn") do
		local position = (point :: BasePart).Position
		local nearest = math.huge
		for _, player in Players:GetPlayers() do
			local root = livingRoot(player)
			if root then
				nearest = math.min(nearest, (root.Position - position).Magnitude)
			end
		end
		-- a random point at least 25 studs from everyone; else the farthest one
		local score = if nearest >= 25 then 1000 + rng:NextNumber() else nearest
		if score > bestDistance then
			best, bestDistance = position, score
		end
	end
	return best
end

local function runCarts(myToken: {})
	task.wait(R.CartFirst)
	while nightToken == myToken do
		local alive = 0
		for _, enemy in EnemyService.GetAll() do
			if enemy.Type == "PossessedCart" and not enemy.Dead then
				alive += 1
			end
		end
		if alive < FoodCourtRules.cartCap(#Players:GetPlayers()) then
			local at = spawnPoint()
			if at then
				EnemyService.Spawn("PossessedCart", at - Vector3.new(0, 3, 0), R.Tier)
				Notify.all(
					"🛒 A possessed cart came rattling out of a kitchen! Sidestep its red charge lane.",
					"warning"
				)
			end
		end
		local waited = 0
		while waited < R.CartEvery and nightToken == myToken do
			task.wait(0.5)
			waited += 0.5
		end
	end
end

local function clearNight()
	nightToken = nil
	if killedConnection then
		killedConnection:Disconnect()
		killedConnection = nil
	end
	for _, app in appliances do
		CombatService.UnregisterLightTarget(app.Model)
		clearFx(app)
	end
	table.clear(appliances)
end

function GrandReopening.StartNight()
	clearNight()
	local myToken = {}
	nightToken = myToken
	openAll() -- the possession bursts every shutter open
	for _, model in CollectionService:GetTagged("FCAppliance") do
		local body = model:IsA("Model") and model.PrimaryPart
		if body then
			local restaurant = model:FindFirstAncestorWhichIsA("Model")
			local place = restaurant and restaurant:GetAttribute("RestaurantName")
			table.insert(appliances, {
				Model = model :: Model,
				Body = body,
				Name = string.lower(tostring(model:GetAttribute("Kind") or "appliance"))
					.. (if place then " in " .. tostring(place) else " in the grand kitchen"),
				Possessed = false,
				Done = false,
				Progress = 0,
				Contributors = {},
				NextVolley = 0,
				LastLit = 0,
				Fx = {},
				Bar = nil,
			})
		end
	end
	killedConnection = EnemyService.Killed:Connect(function(enemy)
		if enemy.Type == "PossessedCart" and nightToken == myToken then
			MissionEvents.record(nil, "CartWrecked")
		end
	end)
	task.spawn(runPossessions, myToken)
	task.spawn(runVolleys, myToken)
	task.spawn(runCarts, myToken)
end

function GrandReopening.EndNight()
	clearNight()
	Telegraph.clear()
end

return GrandReopening
