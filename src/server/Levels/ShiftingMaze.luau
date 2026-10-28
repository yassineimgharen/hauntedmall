-- Level 12: Day "Under the Floor" / Night "The Shifting Maze".
--
-- The basement under the kitchen (Layout.FoodCourt.Basement, reached by the ramp in the
-- storage room) becomes an 8 × 8 maze of brick walls (FoodCourtRules maze).
--
-- Day:   the maze is still. A scanner (📡 HUD meter) hums louder near hidden anomalies;
--        they show themselves up close: hold E to record one. Glowing chalk spots along
--        the route to the maze's heart: hold E to draw an arrow (it points at the heart
--        and stays for the night).
-- Night: the maze SHIFTS every ShiftEvery seconds (red lines warn where walls will rise).
--        Crawlers prowl the corridors. Collect the four seals in the far corners; the
--        heart's portal opens and carries you back up to the dining hall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Telegraph = require(script.Parent.Parent.Util.Telegraph)
local Builder = require(script.Parent.Parent.World.Builder)
local Layout = require(script.Parent.Parent.World.Layout)
local FoodCourtRules = require(script.Parent.FoodCourtRules)

local ShiftingMaze = {}

local R = FoodCourtRules.L12
local B = Layout.FoodCourt.Basement
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local SEAL = Color3.fromRGB(190, 110, 255)
local CHALK = Color3.fromRGB(240, 240, 220)
local BRICK = Color3.fromRGB(96, 70, 62)
local SAFE_SPOT = Vector3.new(-141, 3, -20) -- where the portal sends you (dining hall)

local mazeFolder: Folder? = nil -- walls + chalk: built for the day, kept through the night
local stageFolder: Folder? = nil
local token: {}? = nil
local walls: FoodCourtRules.Walls = {}
local wallParts: { [string]: BasePart } = {}
local escaped: { [Player]: boolean } = {}
local sealsTaken = 0
local rng = Random.new()

local function cellCenter(cell: { number }): Vector3
	return Vector3.new(B.MinX + (cell[1] - 0.5) * B.Cell, B.FloorY, B.MinZ + (cell[2] - 0.5) * B.Cell)
end

local function inBasement(position: Vector3): boolean
	return position.Y < B.FloorY + B.Height + 2
		and position.X >= B.MinX
		and position.X <= B.MaxX
		and position.Z >= B.MinZ - 40
		and position.Z <= B.MaxZ
end

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function markDone(part: BasePart, prompt: ProximityPrompt?)
	part:SetAttribute("Done", true)
	if prompt then
		prompt:SetAttribute("Done", true)
		prompt.Enabled = false
	end
end

-- ── the walls ───────────────────────────────────────────────────────────────

local function wallCFrame(key: string, up: boolean): (CFrame, Vector3)
	local kind, a, b = key:match("^(%a):(%d+):(%d+)$")
	local c, r = tonumber(a) :: number, tonumber(b) :: number
	local y = B.FloorY + (if up then B.Height / 2 else -B.Height / 2 - 0.6)
	if kind == "V" then
		return CFrame.new(B.MinX + c * B.Cell, y, B.MinZ + (r - 0.5) * B.Cell), Vector3.new(1.2, B.Height, B.Cell + 1.2)
	end
	return CFrame.new(B.MinX + (c - 0.5) * B.Cell, y, B.MinZ + r * B.Cell), Vector3.new(B.Cell + 1.2, B.Height, 1.2)
end

local function setWall(key: string, up: boolean, instant: boolean)
	local part = wallParts[key]
	if not part then
		return
	end
	local goal = wallCFrame(key, up)
	if instant then
		part.CFrame = goal
		part.CanCollide = up
		part.Transparency = if up then 0 else 1
		return
	end
	part.CanCollide = false
	part.Transparency = 0
	TweenService:Create(part, TweenInfo.new(R.ShiftMove, Enum.EasingStyle.Quad), { CFrame = goal }):Play()
	task.delay(R.ShiftMove, function()
		if wallParts[key] == part then
			part.CanCollide = up
			part.Transparency = if up then 0 else 1
		end
	end)
end

local function buildWalls(parent: Instance, layout: FoodCourtRules.Walls)
	walls = layout
	for _, key in FoodCourtRules.allWalls() do
		local cf, size = wallCFrame(key, layout[key] == true)
		local part = Builder.part({
			Name = "MazeWall",
			Parent = parent,
			Size = size,
			CFrame = cf,
			Color = BRICK,
			Material = Enum.Material.Brick,
			CanCollide = layout[key] == true,
			Transparency = if layout[key] then 0 else 1,
		})
		wallParts[key] = part
	end
end

-- ── day ─────────────────────────────────────────────────────────────────────

local function buildAnomaly(
	parent: Instance,
	cell: { number },
	index: number,
	myToken: {},
	found: { [number]: boolean }
)
	local at = cellCenter(cell) + Vector3.new(rng:NextNumber(-3, 3), 4, rng:NextNumber(-3, 3))
	local orb = Builder.part({
		Name = "Anomaly",
		Parent = parent,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.8,
		CFrame = CFrame.new(at),
		Color = SEAL,
		Material = Enum.Material.Neon,
		Transparency = 1,
		CanCollide = false,
		Tags = { "Anomaly" },
	})
	orb:SetAttribute("Hidden", true)
	local whisper = Instance.new("ParticleEmitter")
	whisper.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	whisper.Color = ColorSequence.new(SEAL)
	whisper.Size = NumberSequence.new(0.4, 0)
	whisper.Lifetime = NumberRange.new(1, 2)
	whisper.Rate = 0
	whisper.Speed = NumberRange.new(0.5, 1.5)
	whisper.Parent = orb
	local prompt = Builder.prompt(orb, {
		ActionText = "Record",
		ObjectText = "Anomaly",
		HoldDuration = R.RecordSeconds,
		MaxActivationDistance = 9,
		Enabled = false,
	})
	prompt.Triggered:Connect(function(player)
		if token ~= myToken or found[index] then
			return
		end
		found[index] = true
		markDone(orb, prompt)
		whisper.Rate = 0
		TweenService:Create(orb, TweenInfo.new(0.8), { Transparency = 1, Size = Vector3.one * 4 }):Play()
		MissionEvents.record(player, "AnomalyFound")
		Notify.all(
			string.format("📡 %s recorded an anomaly: whispers about the chef's 'secret recipe'.", player.DisplayName),
			"success"
		)
	end)
	return orb, prompt, whisper
end

local function buildChalk(parent: Instance, cell: { number }, myToken: {})
	local center = cellCenter(cell)
	local heart = cellCenter(R.Heart)
	local spot = Builder.part({
		Name = "ChalkSpot",
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.06, 3.4, 3.4),
		CFrame = CFrame.new(center + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = CHALK,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CanCollide = false,
		Tags = { "ChalkSpot" },
	})
	local prompt = Builder.prompt(spot, {
		ActionText = "Draw Arrow",
		ObjectText = "Chalk Mark",
		HoldDuration = 1,
		MaxActivationDistance = 8,
	})
	prompt.Triggered:Connect(function(player)
		if token ~= myToken or spot:GetAttribute("Done") then
			return
		end
		markDone(spot, prompt)
		spot.Transparency = 1
		-- the arrow points at the heart, so it still helps when the walls move
		local facing = CFrame.lookAt(center + Vector3.new(0, 0.06, 0), Vector3.new(heart.X, center.Y + 0.06, heart.Z))
		for _, data in
			{
				{ Vector3.new(0.4, 0.04, 3), CFrame.new(0, 0, 0) },
				{ Vector3.new(0.4, 0.04, 1.4), CFrame.new(0.45, 0, -1.1) * CFrame.Angles(0, math.rad(40), 0) },
				{ Vector3.new(0.4, 0.04, 1.4), CFrame.new(-0.45, 0, -1.1) * CFrame.Angles(0, math.rad(-40), 0) },
			}
		do
			Builder.decor({
				Name = "ChalkArrow",
				Parent = mazeFolder,
				Size = data[1],
				CFrame = facing * data[2],
				Color = CHALK,
				Material = Enum.Material.Neon,
			})
		end
		MissionEvents.record(player, "RouteChalked")
	end)
end

local function runScanner(
	anomalies: { BasePart },
	prompts: { ProximityPrompt },
	whispers: { ParticleEmitter },
	found: { [number]: boolean },
	myToken: {}
)
	while token == myToken do
		task.wait(0.25)
		for _, player in Players:GetPlayers() do
			local root = livingRoot(player)
			if not root or not inBasement(root.Position) then
				if player:GetAttribute("Meter_Signal") ~= nil then
					player:SetAttribute("Meter_Signal", nil)
				end
				continue
			end
			local nearest = math.huge
			for index, orb in anomalies do
				if not found[index] then
					local distance = (orb.Position - root.Position).Magnitude
					nearest = math.min(nearest, distance)
					if distance <= R.RevealRange and orb:GetAttribute("Hidden") then
						orb:SetAttribute("Hidden", false)
						orb.Transparency = 0.15
						prompts[index].Enabled = true
						whispers[index].Rate = 12
					end
				end
			end
			player:SetAttribute("Meter_Signal", FoodCourtRules.signal(nearest))
		end
	end
end

local function clearStage()
	token = nil
	if stageFolder then
		stageFolder:Destroy()
		stageFolder = nil
	end
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Meter_Signal", nil)
	end
end

local function clearMaze()
	clearStage()
	table.clear(wallParts)
	table.clear(escaped)
	walls = {}
	if mazeFolder then
		mazeFolder:Destroy()
		mazeFolder = nil
	end
end

local function newFolder(name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = workspace
	return folder
end

function ShiftingMaze.StartDay()
	clearMaze()
	local myToken = {}
	token = myToken
	mazeFolder = newFolder("BasementMaze")
	stageFolder = newFolder("UnderTheFloorDay")
	local dayRng = Random.new(R.DaySeed)
	buildWalls(
		mazeFolder :: Folder,
		FoodCourtRules.maze(function()
			return dayRng:NextNumber()
		end, R.ExtraOpenings)
	)
	local found = {}
	local anomalies, prompts, whispers = {}, {}, {}
	for index, cell in R.Anomalies do
		local orb, prompt, whisper = buildAnomaly(stageFolder :: Folder, cell, index, myToken, found)
		table.insert(anomalies, orb)
		table.insert(prompts, prompt)
		table.insert(whispers, whisper)
	end
	-- chalk spots spread along today's route to the heart
	local path = FoodCourtRules.mazePath(walls, R.Entrance, R.Heart) or { R.Entrance, R.Heart }
	for i = 1, R.ChalkSpots do
		local cell = path[math.clamp(math.round(i * #path / (R.ChalkSpots + 1)), 1, #path)]
		buildChalk(stageFolder :: Folder, cell, myToken)
	end
	task.spawn(runScanner, anomalies, prompts, whispers, found, myToken)
end

function ShiftingMaze.EndDay()
	clearStage() -- the maze and the chalk arrows stay for the night
end

-- ── night ───────────────────────────────────────────────────────────────────

local function shift(myToken: {})
	local nextLayout = FoodCourtRules.maze(function()
		return rng:NextNumber()
	end, R.ExtraOpenings)
	local rise, sink = FoodCourtRules.mazeDiff(walls, nextLayout)
	Notify.effectAll("Popup", { Text = "⚠️ THE MAZE IS SHIFTING: step off the red lines!", Color = "Red", Y = 0.4 })
	for _, key in rise do
		local cf, size = wallCFrame(key, true)
		local floor = Vector3.new(cf.Position.X, B.FloorY, cf.Position.Z)
		local half = if size.X > size.Z then Vector3.new(size.X / 2, 0, 0) else Vector3.new(0, 0, size.Z / 2)
		Telegraph.lane(floor - half, floor + half, 2.4, R.ShiftWarn)
	end
	task.delay(R.ShiftWarn, function()
		if token ~= myToken then
			return
		end
		walls = nextLayout
		for _, key in rise do
			setWall(key, true, false)
		end
		for _, key in sink do
			setWall(key, false, false)
		end
		Notify.effectAll("Shake", { Strength = 0.5 })
	end)
end

local function buildSeal(parent: Instance, cell: { number }, myToken: {}, onTaken: (Player) -> ())
	local at = cellCenter(cell) + Vector3.new(0, 3, 0)
	local sigil = Builder.part({
		Name = "Seal",
		Parent = parent,
		Size = Vector3.new(3, 3, 0.4),
		CFrame = CFrame.new(at),
		Color = SEAL,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "MazeSeal" },
	})
	TweenService:Create(sigil, TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), {
		CFrame = CFrame.new(at) * CFrame.Angles(0, math.pi, 0),
	}):Play()
	Builder.light("PointLight", sigil, { Color = SEAL, Range = 14, Brightness = 2 })
	local prompt = Builder.prompt(sigil, {
		ActionText = "Take Seal",
		ObjectText = "Basement Seal",
		HoldDuration = 1,
		MaxActivationDistance = 8,
	})
	prompt.Triggered:Connect(function(player)
		if token ~= myToken or sigil:GetAttribute("Done") then
			return
		end
		markDone(sigil, prompt)
		TweenService:Create(sigil, TweenInfo.new(0.6), { Transparency = 1, Size = Vector3.new(0.5, 0.5, 0.1) }):Play()
		onTaken(player)
	end)
end

local function buildPortal(parent: Instance): (BasePart, TextLabel)
	local center = cellCenter(R.Heart)
	local ring = Builder.part({
		Name = "HeartPortal",
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 8, 8),
		CFrame = CFrame.new(center + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.DarkMetal,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "MazeHeart" },
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(170, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = FONT
	label.TextColor3 = Palette.NeonRed
	label.TextStrokeTransparency = 0.3
	label.Text = "🔒 SEALED (0/4)"
	label.Parent = gui
	gui.Parent = ring
	return ring, label
end

local function runNight(portal: BasePart, myToken: {})
	local nextShift = os.clock() + R.ShiftEvery
	local heart = cellCenter(R.Heart)
	while token == myToken do
		task.wait(0.25)
		local now = os.clock()
		if now >= nextShift then
			nextShift = now + R.ShiftEvery
			shift(myToken)
		end
		if sealsTaken < #R.Seals then
			continue
		end
		for _, player in Players:GetPlayers() do
			local root = livingRoot(player)
			if root and not escaped[player] then
				local offset = root.Position - heart
				if Vector3.new(offset.X, 0, offset.Z).Magnitude <= 4.5 and math.abs(offset.Y) < 8 then
					escaped[player] = true
					MissionEvents.record(player, "MazeEscaped")
					local remaining = (ReplicatedStorage:GetAttribute("PhaseStartedAt") or 0)
						+ (ReplicatedStorage:GetAttribute("PhaseDuration") or 0)
						- workspace:GetServerTimeNow()
					if remaining >= R.QuickEscapeLeft then
						MissionEvents.record(player, "QuickEscape")
					end
					local character = player.Character
					if character then
						character:PivotTo(
							CFrame.new(SAFE_SPOT + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)))
						)
					end
					Notify.all(string.format("🌀 %s escaped the shifting maze!", player.DisplayName), "success")
				end
			end
		end
		portal.Color = SEAL
	end
end

function ShiftingMaze.StartNight()
	clearStage()
	local myToken = {}
	token = myToken
	sealsTaken = 0
	table.clear(escaped)
	stageFolder = newFolder("ShiftingMazeNight")
	if not mazeFolder then
		-- the day didn't run (e.g. a Studio skip): build the maze now
		local fresh = newFolder("BasementMaze")
		mazeFolder = fresh
		buildWalls(
			fresh,
			FoodCourtRules.maze(function()
				return rng:NextNumber()
			end, R.ExtraOpenings)
		)
	end
	local portal, label = buildPortal(stageFolder :: Folder)
	for _, cell in R.Seals do
		buildSeal(stageFolder :: Folder, cell, myToken, function(player)
			sealsTaken += 1
			MissionEvents.record(player, "SealCollected")
			label.Text = string.format("🔒 SEALED (%d/%d)", sealsTaken, #R.Seals)
			if sealsTaken >= #R.Seals then
				label.Text = "🌀 PORTAL OPEN: STEP IN!"
				label.TextColor3 = SEAL
				Builder.light("PointLight", portal, { Color = SEAL, Range = 20, Brightness = 3 })
				Notify.effectAll("Banner", {
					Title = "THE HEART IS OPEN",
					Subtitle = "Reach the centre of the maze to escape!",
					Color = "Purple",
					Sound = "PowerUp",
				})
			else
				Notify.all(
					string.format("🔮 %s took a seal (%d/%d).", player.DisplayName, sealsTaken, #R.Seals),
					"success"
				)
			end
		end)
	end
	-- crawlers prowl the corridors (spread over the maze, away from the ramp)
	local count = math.min(2 + #Players:GetPlayers(), 5)
	for i = 1, count do
		local cell = { rng:NextInteger(3, R.Cols), rng:NextInteger(3, R.Rows) }
		task.delay(2 + i, function()
			if token == myToken then
				local enemy = EnemyService.Spawn("ShadowCrawler", cellCenter(cell), R.Tier)
				if enemy then
					enemy.Patrols = true
				end
			end
		end)
	end
	task.spawn(runNight, portal, myToken)
end

function ShiftingMaze.EndNight()
	clearMaze()
end

-- Crawlers patrol the maze's cell centres (NightService passes these to EnemyService).
function ShiftingMaze.PatrolPoints(): { Vector3 }
	local points = {}
	for c = 1, R.Cols, 2 do
		for r = 1, R.Rows, 2 do
			table.insert(points, cellCenter({ c, r }))
		end
	end
	return points
end

return ShiftingMaze
