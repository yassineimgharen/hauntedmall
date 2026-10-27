-- The only module allowed to change cash, XP, levels and upgrades. Every change is
-- validated here and mirrored to Player attributes for the HUD (read-only on clients).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local DataService = require(script.Parent.DataService)

local ProgressionService = {}
ProgressionService.UpgradePurchased = Signal.new() -- (player, upgradeId, newLevel)

local function syncAll(player: Player, data: { [string]: any })
	player:SetAttribute("Cash", data.Cash)
	player:SetAttribute("Level", data.Level)
	player:SetAttribute("XP", data.XP)
	player:SetAttribute("XPNeeded", EconomyConfig.XPForLevel(data.Level))
	for _, upgrade in UpgradeConfig.List do
		player:SetAttribute("Upg_" .. upgrade.Id, data.Upgrades[upgrade.Id] or 0)
	end
	player:SetAttribute("Set_Music", data.Settings.Music)
	player:SetAttribute("Set_Sfx", data.Settings.Sfx)
	player:SetAttribute("Set_ReducedEffects", data.Settings.ReducedEffects)
	local collected = 0
	for _ in data.Collectibles do
		collected += 1
	end
	player:SetAttribute("CollectiblesFound", collected)
	for flag, done in data.Tutorial do
		player:SetAttribute("Tut_" .. flag, done)
	end
end

local DAY_GOALS = { "Claimed", "Stocked", "Served", "Upgraded" }

-- source "Purchase" marks Robux-bought cash so stats keep earned and bought cash apart.
-- Never yields (receipt processing relies on that to grant and record atomically).
function ProgressionService.AddCash(player: Player, amount: number, source: "Purchase"?): boolean
	local data = DataService.Get(player)
	if not data or not Validate.finite(amount) or amount < 0 then
		return false
	end
	amount = math.floor(amount)
	data.Cash += amount
	if source == "Purchase" then
		data.Stats.CashPurchased += amount
	else
		data.Stats.TotalEarned += amount
	end
	player:SetAttribute("Cash", data.Cash)
	return true
end

function ProgressionService.TrySpend(player: Player, amount: number): boolean
	local data = DataService.Get(player)
	if not data or not Validate.finite(amount) or amount < 0 then
		return false
	end
	amount = math.floor(amount)
	if data.Cash < amount then
		return false
	end
	data.Cash -= amount
	player:SetAttribute("Cash", data.Cash)
	return true
end

function ProgressionService.AddXP(player: Player, amount: number)
	local data = DataService.Get(player)
	if not data or not Validate.finite(amount) or amount <= 0 then
		return
	end
	data.XP += math.floor(amount)
	while data.Level < EconomyConfig.MaxLevel and data.XP >= EconomyConfig.XPForLevel(data.Level) do
		data.XP -= EconomyConfig.XPForLevel(data.Level)
		data.Level += 1
		local reward = EconomyConfig.LevelUpCash(data.Level)
		data.Cash += reward
		player:SetAttribute("Cash", data.Cash)
		Notify.player(player, string.format("LEVEL %d! +$%d bonus", data.Level, reward), "levelup")
	end
	player:SetAttribute("Level", data.Level)
	player:SetAttribute("XP", data.XP)
	player:SetAttribute("XPNeeded", EconomyConfig.XPForLevel(data.Level))
end

function ProgressionService.GetUpgrade(player: Player, id: string): number
	local data = DataService.Get(player)
	return if data then data.Upgrades[id] or 0 else 0
end

-- Multiplier helper: 1 + level * PerLevel
function ProgressionService.UpgradeBonus(player: Player, id: string): number
	return ProgressionService.GetUpgrade(player, id) * UpgradeConfig.ById[id].PerLevel
end

-- Records a tutorial milestone once (persisted). Finishing all day goals pays a one-time
-- training bonus. Safe to call repeatedly: only the first call for a flag does anything.
function ProgressionService.MarkTutorial(player: Player, flag: string)
	local data = DataService.Get(player)
	local tutorial = data and data.Tutorial
	if not tutorial or tutorial[flag] ~= false then
		return
	end
	tutorial[flag] = true
	player:SetAttribute("Tut_" .. flag, true)

	if tutorial.Completed then
		return
	end
	for _, goal in DAY_GOALS do
		if not tutorial[goal] then
			return
		end
	end
	tutorial.Completed = true
	player:SetAttribute("Tut_Completed", true)
	ProgressionService.AddCash(player, EconomyConfig.TutorialBonus)
	Notify.player(
		player,
		string.format("🎓 Training complete! +$%d bonus. Get ready for nightfall.", EconomyConfig.TutorialBonus),
		"levelup"
	)
end

function ProgressionService.AddStat(player: Player, stat: string, amount: number)
	local data = DataService.Get(player)
	if data and data.Stats[stat] ~= nil then
		data.Stats[stat] += amount
	end
end

function ProgressionService.AddCollectible(player: Player, id: string)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Collectibles[id] = (data.Collectibles[id] or 0) + 1
	syncAll(player, data)
end

local function purchaseUpgrade(player: Player, id: any)
	if type(id) ~= "string" then
		return
	end
	local upgrade = UpgradeConfig.ById[id]
	local data = DataService.Get(player)
	if not upgrade or not data then
		return
	end
	local level = data.Upgrades[id] or 0
	if level >= upgrade.MaxLevel then
		Notify.player(player, upgrade.Name .. " is already maxed out.", "warning")
		return
	end
	local cost = UpgradeConfig.Cost(id, level)
	if not ProgressionService.TrySpend(player, cost) then
		Notify.player(player, "Not enough cash for " .. upgrade.Name .. ".", "warning")
		return
	end
	data.Upgrades[id] = level + 1
	player:SetAttribute("Upg_" .. id, level + 1)
	Notify.player(
		player,
		string.format("%s %s upgraded to level %d!", upgrade.Icon, upgrade.Name, level + 1),
		"success"
	)
	Notify.effect(player, "Purchase")
	ProgressionService.MarkTutorial(player, "Upgraded")
	MissionEvents.record(player, "Upgraded")
	ProgressionService.UpgradePurchased:Fire(player, id, level + 1)
end

local function saveSettings(player: Player, settings: any)
	local data = DataService.Get(player)
	if not data or type(settings) ~= "table" then
		return
	end
	if Validate.fraction(settings.Music) then
		data.Settings.Music = settings.Music
	end
	if Validate.fraction(settings.Sfx) then
		data.Settings.Sfx = settings.Sfx
	end
	if type(settings.ReducedEffects) == "boolean" then
		data.Settings.ReducedEffects = settings.ReducedEffects
	end
	player:SetAttribute("Set_Music", data.Settings.Music)
	player:SetAttribute("Set_Sfx", data.Settings.Sfx)
	player:SetAttribute("Set_ReducedEffects", data.Settings.ReducedEffects)
end

function ProgressionService.Init() end

function ProgressionService.Start()
	DataService.ProfileLoaded:Connect(function(player, data)
		-- Saves from before tutorial tracking existed: credit what the stats already prove.
		local tutorial = data.Tutorial
		for _ in data.Upgrades do
			tutorial.Upgraded = true
		end
		if data.Stats.Sales > 0 then
			tutorial.Stocked = true
		end
		if data.Stats.NightsSurvived > 0 then
			tutorial.SurvivedNight = true
		end
		syncAll(player, data)
	end)
	Net.handle("PurchaseUpgrade", 4, 6, purchaseUpgrade)
	Net.handle("SaveSettings", 1, 3, saveSettings)
end

return ProgressionService
