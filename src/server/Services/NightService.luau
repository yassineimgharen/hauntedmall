-- Orchestrates each night: enemy waves, the fuse-box (breaker) co-op objective, safe
-- zones, blackouts, participation tracking, and dawn rewards (cash, XP, collectibles).
-- What a night contains comes from MissionService.GetNightRules() (the active campaign
-- level, or the classic loop in Free Shift); objective progress goes out via MissionEvents.
--
-- Reward fairness: every player who damaged an enemy gets full kill credit (no kill
-- stealing). Survival bonus is full for anyone who contributed, half for idle players.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CollectibleConfig = require(ReplicatedStorage.Shared.Config.CollectibleConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Net = require(ReplicatedStorage.Shared.Net)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Telegraph = require(script.Parent.Parent.Util.Telegraph)
local Notify = require(script.Parent.Parent.Util.Notify)
local EnemyService = require(script.Parent.EnemyService)
local GameStateService = require(script.Parent.GameStateService)
local MissionService = require(script.Parent.MissionService)
local ProgressionService = require(script.Parent.ProgressionService)

type NightStats = {
	Kills: number,
	Fuses: number,
	Deaths: number,
	Earned: number,
	XP: number,
}

type Fuse = {
	Model: Model,
	Prompt: ProximityPrompt,
	Indicator: BasePart,
	Status: PointLight,
	Sparks: ParticleEmitter,
	Repaired: boolean,
}

local NightService = {}

local stats: { [Player]: NightStats } = {}
local fuses: { Fuse } = {}
local spawnPoints: { BasePart } = {}
local nightToken: {}? = nil
local allFusesDone = false
local rules: { [string]: any } = { Tier = 1, Fuses = true, Blackout = false, Free = true }
local powered: { [string]: boolean } = {}
local rng = Random.new()

local function multiplier(): number
	return 1 + ((rules.Tier or 1) - 1) * EconomyConfig.Night.ScalingPerNight
end

local function statsFor(player: Player): NightStats
	local s = stats[player]
	if not s then
		s = { Kills = 0, Fuses = 0, Deaths = 0, Earned = 0, XP = 0 }
		stats[player] = s
	end
	return s
end

local function reward(player: Player, cash: number, xp: number)
	local s = statsFor(player)
	cash = math.floor(cash + 0.5)
	if cash > 0 then
		ProgressionService.AddCash(player, cash)
		s.Earned += cash
	end
	if xp > 0 then
		ProgressionService.AddXP(player, xp)
		s.XP += xp
	end
end

local function setFuseVisual(fuse: Fuse, mode: "Idle" | "Broken" | "Repaired")
	fuse.Repaired = mode == "Repaired"
	fuse.Model:SetAttribute("Repaired", fuse.Repaired)
	fuse.Model:SetAttribute("Broken", mode == "Broken")
	fuse.Sparks.Enabled = mode == "Broken"
	fuse.Prompt.Enabled = mode == "Broken"
	if mode == "Idle" then
		fuse.Indicator.Color = Palette.DarkMetal
		fuse.Status.Brightness = 0
	else
		local color = if mode == "Broken" then Palette.NeonRed else Palette.NeonGreen
		fuse.Indicator.Color = color
		fuse.Status.Color = color
		fuse.Status.Brightness = 2
	end
end

local function publishFuses()
	local repaired = 0
	for _, fuse in fuses do
		if fuse.Repaired then
			repaired += 1
		end
	end
	ReplicatedStorage:SetAttribute("FusesRepaired", repaired)
	ReplicatedStorage:SetAttribute("FusesTotal", if rules.Fuses then #fuses else 0)
	return repaired
end

local function publishPower()
	local zones = {}
	for zone in powered do
		table.insert(zones, zone)
	end
	ReplicatedStorage:SetAttribute("PoweredZones", table.concat(zones, ","))
end

local function onFuseRepaired(fuse: Fuse, player: Player)
	if fuse.Repaired or not GameStateService.IsNight() or not rules.Fuses then
		return
	end
	setFuseVisual(fuse, "Repaired")
	powered[tostring(fuse.Model:GetAttribute("FuseId"))] = true
	publishPower()
	MissionEvents.record(player, "BreakerRestored")
	statsFor(player).Fuses += 1
	ProgressionService.AddStat(player, "FusesRepaired", 1)
	reward(player, 0, EconomyConfig.XP.Fuse)
	local repaired = publishFuses()
	Notify.all(
		string.format(
			"⚡ %s restored %s! (%d/%d)",
			player.DisplayName,
			tostring(fuse.Model:GetAttribute("Zone")),
			repaired,
			#fuses
		),
		"success"
	)
	Notify.effectAll("FuseRepaired", { Position = fuse.Indicator.Position })

	if repaired == #fuses and not allFusesDone then
		allFusesDone = true
		EnemyService.StunAll(EnemyConfig.Fuses.AllRepairedStun)
		ReplicatedStorage:SetAttribute("Blackout", false)
		MissionEvents.record(nil, "PowerRestored")
		local elapsed = workspace:GetServerTimeNow() - (ReplicatedStorage:GetAttribute("PhaseStartedAt") or 0)
		local duration = ReplicatedStorage:GetAttribute("PhaseDuration") or 1
		if rules.EarlyFraction and elapsed < duration * rules.EarlyFraction then
			MissionEvents.record(nil, "PowerRestoredEarly")
		end
		Notify.all("💡 POWER RESTORED: the shadows are stunned!", "success")
		Notify.effectAll("PowerRestored")
	end
end

local function pickSpawn(): BasePart?
	-- a level may use its own spawn points (e.g. the food court's "FoodCourtSpawn")
	local points = spawnPoints
	if type(rules.SpawnTag) == "string" then
		points = {}
		for _, point in CollectionService:GetTagged(rules.SpawnTag) do
			table.insert(points, point :: BasePart)
		end
	end
	if #points == 0 then
		return nil
	end
	-- prefer points not right next to a player, so enemies don't pop in on top of anyone
	local candidates = {}
	for _, point in points do
		local tooClose = false
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - point.Position).Magnitude < 20 then
				tooClose = true
			end
		end
		if not tooClose then
			table.insert(candidates, point)
		end
	end
	local pool = if #candidates > 0 then candidates else points
	return pool[rng:NextInteger(1, #pool)]
end

-- Wave pacing: the level's Waves table, or the classic formula in Free Shift.
local function waveSize(wave: number, players: number): number
	local waves = rules.Waves
	if waves then
		return waves.Base + math.floor(players * waves.PerPlayer) + (wave - 1) * waves.Growth
	end
	return EnemyConfig.WaveSize(rules.Tier, players)
end

local function maxAlive(players: number): number
	local waves = rules.Waves
	if waves then
		return math.min(waves.MaxAlive, EnemyConfig.Waves.MaxAlive)
	end
	return EnemyConfig.MaxAlive(rules.Tier, players)
end

-- Guards start the night standing watch at the first patrol points (the breakers).
local function spawnGuards(token: {})
	local points = rules.PatrolPoints
	if not points or not rules.Guards then
		return
	end
	task.wait(2)
	for i = 1, math.min(rules.Guards, #points) do
		if nightToken ~= token then
			return
		end
		local position = points[i]
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - position).Magnitude < 15 then
				local fallback = pickSpawn()
				position = if fallback then fallback.Position else position
			end
		end
		local enemy = EnemyService.Spawn("ShadowCrawler", position, rules.Tier)
		if enemy then
			enemy.Patrols = true
		end
		task.wait(0.3)
	end
end

local function runWaves(token: {})
	task.wait(if rules.Waves then rules.Waves.FirstDelay else EnemyConfig.Waves.FirstWaveDelay)
	local interval = if rules.Waves then rules.Waves.Interval else EnemyConfig.Waves.Interval
	local wave = 0
	while nightToken == token do
		wave += 1
		ReplicatedStorage:SetAttribute("Wave", wave)
		Notify.all(string.format("👁️ Wave %d: they're coming!", wave), "danger")
		local players = #Players:GetPlayers()
		for _ = 1, waveSize(wave, players) do
			if nightToken ~= token then
				return
			end
			if EnemyService.AliveCount() < maxAlive(players) then
				local point = pickSpawn()
				if point then
					EnemyService.Spawn("ShadowCrawler", point.Position, rules.Tier)
				end
			end
			task.wait(EnemyConfig.Waves.SpawnStagger)
		end
		local waited = 0
		while waited < interval and nightToken == token do
			task.wait(0.5)
			waited += 0.5
		end
	end
end

-- Repaired fuse boxes light up their area; shadows inside it slowly burn.
local function runSafeZones(token: {})
	local radius = EnemyConfig.Fuses.SafeRadius
	local damage = EnemyConfig.Fuses.SafeDPS * 0.5
	while nightToken == token do
		task.wait(0.5)
		for _, fuse in fuses do
			if fuse.Repaired then
				local center = fuse.Indicator.Position
				for _, enemy in table.clone(EnemyService.GetAll()) do
					if (enemy.Root.Position - center).Magnitude < radius then
						EnemyService.Damage(enemy, damage, nil)
					end
				end
			end
		end
	end
end

local function rollCollectible(s: NightStats): CollectibleConfig.Collectible?
	if rng:NextNumber() > CollectibleConfig.DropChance(s.Kills, s.Fuses) then
		return nil
	end
	local total = 0
	for _, item in CollectibleConfig.Items do
		total += CollectibleConfig.Rarities[item.Rarity].Weight
	end
	local roll = rng:NextNumber() * total
	for _, item in CollectibleConfig.Items do
		roll -= CollectibleConfig.Rarities[item.Rarity].Weight
		if roll <= 0 then
			return item
		end
	end
	return CollectibleConfig.Items[1]
end

local function startDusk()
	stats = {}
	allFusesDone = false
	for _, player in Players:GetPlayers() do
		statsFor(player)
	end
	Notify.all("🌙 The mall is closing... something is waking up.", "danger")
end

local function startNight()
	local token = {}
	nightToken = token
	rules = MissionService.GetNightRules()
	table.clear(powered)
	publishPower()
	for _, fuse in fuses do
		fuse.Prompt.HoldDuration = rules.RepairTime or EnemyConfig.Fuses.RepairTime
		setFuseVisual(fuse, if rules.Fuses then "Broken" else "Idle")
	end
	publishFuses()
	ReplicatedStorage:SetAttribute("Blackout", rules.Blackout == true)
	ReplicatedStorage:SetAttribute("NightPreset", rules.Preset or "")
	EnemyService.SetBehavior({
		PatrolPoints = if rules.Patrol then rules.PatrolPoints else nil,
		PatrolShare = 0.6,
		SightScale = rules.SightScale or 1,
	})
	Notify.all(
		rules.Intro or "⚡ The power is out! Repair the fuse boxes and survive until dawn.",
		if rules.Blackout then "danger" else "warning"
	)
	task.spawn(spawnGuards, token)
	if not rules.NoWaves then
		task.spawn(runWaves, token)
	end
	if rules.Fuses then
		task.spawn(runSafeZones, token)
	end
end

local function startDawn()
	nightToken = nil
	EnemyService.ClearAll()
	EnemyService.SetBehavior(nil)
	Telegraph.clear()
	ReplicatedStorage:SetAttribute("Wave", 0)
	ReplicatedStorage:SetAttribute("Blackout", false)
	ReplicatedStorage:SetAttribute("NightPreset", "")
	table.clear(powered)
	publishPower()
	local night = rules.LevelIndex or GameStateService.GetNight()
	local mult = multiplier()
	local cfg = EconomyConfig.Night

	for player, s in stats do
		if player.Parent then
			local contributed = s.Kills > 0 or s.Fuses > 0
			local bonus = cfg.SurviveBonus * (if contributed then 1 else 0.5)
			bonus += s.Fuses * cfg.PerFuse
			if allFusesDone and rules.Fuses then
				bonus += cfg.AllFusesBonus
			end
			reward(player, bonus * mult, EconomyConfig.XP.Survive)
			ProgressionService.AddStat(player, "NightsSurvived", 1)
			ProgressionService.MarkTutorial(player, "SurvivedNight")

			local item = rollCollectible(s)
			if item then
				ProgressionService.AddCollectible(player, item.Id)
			end

			Net.get("NightResults"):FireClient(player, {
				Night = night,
				Kills = s.Kills,
				Fuses = s.Fuses,
				Deaths = s.Deaths,
				AllFuses = allFusesDone,
				Cash = s.Earned,
				XP = s.XP,
				Collectible = if item
					then { Id = item.Id, Name = item.Name, Icon = item.Icon, Rarity = item.Rarity }
					else nil,
			})
		end
	end

	for _, fuse in fuses do
		setFuseVisual(fuse, "Idle")
	end
	publishFuses()
end

function NightService.Init() end

function NightService.Start()
	for _, model in CollectionService:GetTagged("FuseBox") do
		local fuse: Fuse = {
			Model = model,
			Prompt = model:FindFirstChild("RepairPrompt", true) :: ProximityPrompt,
			Indicator = model:FindFirstChild("Indicator") :: BasePart,
			Status = model:FindFirstChild("Status", true) :: PointLight,
			Sparks = model:FindFirstChild("Sparks", true) :: ParticleEmitter,
			Repaired = false,
		}
		fuse.Prompt.HoldDuration = EnemyConfig.Fuses.RepairTime
		fuse.Prompt.Triggered:Connect(function(player)
			onFuseRepaired(fuse, player)
		end)
		setFuseVisual(fuse, "Idle")
		table.insert(fuses, fuse)
	end
	publishFuses()

	for _, point in CollectionService:GetTagged("EnemySpawn") do
		table.insert(spawnPoints, point :: BasePart)
	end

	EnemyService.Killed:Connect(function(enemy, contributors)
		local cash = EconomyConfig.Night.PerKill * multiplier()
		MissionEvents.record(nil, "EnemyDefeated")
		if enemy.Type == "PhantomShopper" then
			MissionEvents.record(nil, "PhantomDefeated")
		end
		for player in contributors do
			if player.Parent then
				statsFor(player).Kills += 1
				ProgressionService.AddStat(player, "Kills", 1)
				MissionEvents.record(player, "Kill")
				reward(player, cash, EconomyConfig.XP.Kill)
				Notify.effect(player, "Kill", { Amount = math.floor(cash + 0.5) })
			end
		end
	end)

	local function trackDeaths(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid then
				humanoid.Died:Connect(function()
					local phase = GameStateService.GetPhase()
					if phase == "Night" or phase == "Dusk" then
						statsFor(player).Deaths += 1
					end
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(trackDeaths)
	for _, player in Players:GetPlayers() do
		trackDeaths(player)
	end
	Players.PlayerAdded:Connect(function(player)
		local phase = GameStateService.GetPhase()
		if phase == "Dusk" or phase == "Night" then
			statsFor(player) -- late joiners still get a dawn report
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		stats[player] = nil
	end)

	GameStateService.PhaseChanged:Connect(function(phase)
		if phase == "Dusk" then
			startDusk()
		elseif phase == "Night" then
			startNight()
		elseif phase == "Dawn" then
			startDawn()
		end
	end)
end

return NightService
