-- Orchestrates each night: enemy waves, the fuse-box co-op objective, safe zones,
-- participation tracking, and dawn rewards (cash, XP, collectibles).
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
local Notify = require(script.Parent.Parent.Util.Notify)
local EnemyService = require(script.Parent.EnemyService)
local GameStateService = require(script.Parent.GameStateService)
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
local rng = Random.new()

local function multiplier(): number
	return 1 + (GameStateService.GetNight() - 1) * EconomyConfig.Night.ScalingPerNight
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
	ReplicatedStorage:SetAttribute("FusesTotal", #fuses)
	return repaired
end

local function onFuseRepaired(fuse: Fuse, player: Player)
	if fuse.Repaired or not GameStateService.IsNight() then
		return
	end
	setFuseVisual(fuse, "Repaired")
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
		Notify.all("💡 EMERGENCY POWER RESTORED — the shadows are stunned!", "success")
		Notify.effectAll("PowerRestored")
	end
end

local function pickSpawn(): BasePart?
	if #spawnPoints == 0 then
		return nil
	end
	-- prefer points not right next to a player, so enemies don't pop in on top of anyone
	local candidates = {}
	for _, point in spawnPoints do
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
	local pool = if #candidates > 0 then candidates else spawnPoints
	return pool[rng:NextInteger(1, #pool)]
end

local function runWaves(token: {})
	task.wait(EnemyConfig.Waves.FirstWaveDelay)
	local wave = 0
	while nightToken == token do
		wave += 1
		ReplicatedStorage:SetAttribute("Wave", wave)
		Notify.all(string.format("👁️ Wave %d — they're coming!", wave), "danger")
		local count = EnemyConfig.WaveSize(GameStateService.GetNight(), #Players:GetPlayers())
		for _ = 1, count do
			if nightToken ~= token then
				return
			end
			if EnemyService.AliveCount() < EnemyConfig.Waves.MaxAlive then
				local point = pickSpawn()
				if point then
					EnemyService.Spawn("ShadowCrawler", point.Position)
				end
			end
			task.wait(EnemyConfig.Waves.SpawnStagger)
		end
		local waited = 0
		while waited < EnemyConfig.Waves.Interval and nightToken == token do
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
	for _, fuse in fuses do
		setFuseVisual(fuse, "Broken")
	end
	publishFuses()
	Notify.all("⚡ The power is out! Repair the fuse boxes and survive until dawn.", "warning")
	task.spawn(runWaves, token)
	task.spawn(runSafeZones, token)
end

local function startDawn()
	nightToken = nil
	EnemyService.ClearAll()
	ReplicatedStorage:SetAttribute("Wave", 0)
	local night = GameStateService.GetNight()
	local mult = multiplier()
	local cfg = EconomyConfig.Night

	for player, s in stats do
		if player.Parent then
			local contributed = s.Kills > 0 or s.Fuses > 0
			local bonus = cfg.SurviveBonus * (if contributed then 1 else 0.5)
			bonus += s.Fuses * cfg.PerFuse
			if allFusesDone then
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

	EnemyService.Killed:Connect(function(_enemy, contributors)
		local cash = EconomyConfig.Night.PerKill * multiplier()
		for player in contributors do
			if player.Parent then
				statsFor(player).Kills += 1
				ProgressionService.AddStat(player, "Kills", 1)
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
