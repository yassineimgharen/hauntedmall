-- Campaign director. Runs the active level on top of the shared day/night clock:
--
--   Server clock     GameStateService (Day → Dusk → Night → Dawn), never stops.
--   Active level     picked at each sunrise by player votes (CampaignLogic.pickLevel);
--                    fixed for that Day + Night. "FREE" = Free Shift (the classic loop).
--   Objectives       one tracker per stage; game systems report events via MissionEvents.
--   Personal credit  only for players who have the level unlocked (others play as guests);
--                    persisted in data.Campaign (Completed, DayCleared, OptionalDone).
--
-- Per-player objective snapshots go to clients over the MissionState remote (coalesced,
-- at most 4/s); level identity is published as ReplicatedStorage attributes.
--
-- Studio helpers (Workspace attributes, Server view):
--   MissionTest_Level = "L02"        play this level from the next sunrise; credit is
--                                    granted even if locked (Studio DataStore only)
--   MissionTest_CompleteStage = true  completes the current stage's required objectives

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
local CampaignLogic = require(ReplicatedStorage.Shared.Campaign.CampaignLogic)
local Net = require(ReplicatedStorage.Shared.Net)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local DataService = require(script.Parent.DataService)
local GameStateService = require(script.Parent.GameStateService)
local ProgressionService = require(script.Parent.ProgressionService)
local ShopService = require(script.Parent.ShopService)

local LEVEL_MODULES: { [string]: any } = {
	PowerGrid = require(script.Parent.Parent.Levels.PowerGrid),
}

type Stage = "Day" | "Night"

local MissionService = {}

local LEVELS = CampaignConfig.Levels
local active: any? = nil -- level config; nil = Free Shift
local stage: Stage? = nil
local tracker: CampaignLogic.Tracker? = nil
local stageFinal = false -- Dusk/Dawn: the stage just ended, rows show its final state
local forcedLevel = false -- Studio MissionTest_Level in effect
local roster: { [Player]: boolean } = {} -- present when the night began
local announced: { [Player]: boolean } = {} -- "stage objectives complete" toast sent
local votes: { [Player]: string } = {}
local dirty: { [Player]: boolean } = {}
local allDirty = false

-- ── helpers ─────────────────────────────────────────────────────────────────

local function campaignOf(player: Player): { [string]: any }?
	local data = DataService.Get(player)
	return data and data.Campaign
end

local function nextLevelId(player: Player): string
	local campaign = campaignOf(player)
	local level = campaign and CampaignLogic.nextLevel(LEVELS, campaign.Completed)
	return if level then level.Id else "FREE"
end

local function eligible(player: Player): boolean
	local campaign = campaignOf(player)
	if not active or not campaign then
		return false
	end
	return forcedLevel or CampaignLogic.isUnlocked(LEVELS, campaign.Completed, active.Id)
end

local function markDirty(player: Player?)
	if player then
		dirty[player] = true
	else
		allDirty = true
	end
end

local function keys(map: { [string]: any }): { string }
	local list = {}
	for key in map do
		table.insert(list, key)
	end
	table.sort(list)
	return list
end

local function syncCampaign(player: Player)
	local campaign = campaignOf(player)
	if not campaign then
		return
	end
	player:SetAttribute(
		"CampaignState",
		HttpService:JSONEncode({
			Completed = keys(campaign.Completed),
			DayCleared = keys(campaign.DayCleared),
			Next = nextLevelId(player),
			Vote = votes[player] or nextLevelId(player),
		})
	)
end

local function currentVotes(): { [Player]: string }
	local result = {}
	for _, player in Players:GetPlayers() do
		if campaignOf(player) then
			result[player] = votes[player] or nextLevelId(player)
		end
	end
	return result
end

local function publishVotes()
	local counts = {}
	for _, vote in currentVotes() do
		counts[vote] = (counts[vote] or 0) + 1
	end
	ReplicatedStorage:SetAttribute("LevelVotes", HttpService:JSONEncode(counts))
end

local function stageConfig(): any?
	return if active and stage then active[stage] else nil
end

local function title(): string
	local config = stageConfig()
	if not active or not config or not stage then
		return "FREE SHIFT"
	end
	return string.format("%s %d · %s", string.upper(stage), active.Index, string.upper(config.Name))
end

local function snapshot(player: Player): { [string]: any }
	if not active then
		return { Stage = "Free" }
	end
	local campaign = campaignOf(player)
	local base = {
		LevelId = active.Id,
		LevelIndex = active.Index,
		Chapter = active.Chapter,
		Guest = campaign ~= nil and not eligible(player),
		DayCleared = campaign ~= nil and campaign.DayCleared[active.Id] == true,
	}
	if not stage or not tracker then
		base.Stage = "Waiting"
		base.Title = string.format("LEVEL %d", active.Index)
		return base
	end
	local rows = CampaignLogic.rows(tracker, player.UserId, stageFinal)
	local hint = nil
	for _, row in rows do
		if not row.Done and not row.Optional and row.Hint then
			hint = row.Hint
			break
		end
	end
	base.Stage = stage
	base.Final = stageFinal
	base.Title = title()
	base.Story = (stageConfig() :: any).Story
	base.Rows = rows
	base.Hint = hint
	base.LateJoin = stage == "Night" and not roster[player]
	return base
end

local function flush()
	local targets: { Player } = {}
	if allDirty then
		targets = Players:GetPlayers()
	else
		for player in dirty do
			table.insert(targets, player)
		end
	end
	allDirty = false
	table.clear(dirty)
	local remote = Net.get("MissionState")
	for _, player in targets do
		if player.Parent then
			remote:FireClient(player, snapshot(player))
		end
	end
end

local function callModules(hook: string)
	if not active then
		return
	end
	for _, name in active.Modules do
		local module = LEVEL_MODULES[name]
		if module and module[hook] then
			local ok, err = pcall(module[hook])
			if not ok then
				warn(string.format("[MissionService] %s.%s failed: %s", name, hook, tostring(err)))
			end
		end
	end
end

-- ── level selection (runs inside the phase hook: must not yield) ────────────

local function chooseLevel()
	local forced = if RunService:IsStudio() then workspace:GetAttribute("MissionTest_Level") else nil
	local forcedConfig = if type(forced) == "string" then CampaignConfig.ById[forced] else nil
	local id
	if forcedConfig and forcedConfig.Implemented then
		id = forced
		forcedLevel = true
	else
		local list = {}
		for _, vote in currentVotes() do
			table.insert(list, vote)
		end
		id = CampaignLogic.pickLevel(list, CampaignConfig.IndexOf) or "L01"
		forcedLevel = false
	end
	active = if id == "FREE" then nil else CampaignConfig.ById[id]
	ReplicatedStorage:SetAttribute("LevelId", if active then active.Id else "")
	ReplicatedStorage:SetAttribute("LevelIndex", if active then active.Index else 0)
	ReplicatedStorage:SetAttribute("LevelChapter", if active then active.Chapter else 0)
	ReplicatedStorage:SetAttribute("LevelDayName", if active then active.Day.Name else "")
	ReplicatedStorage:SetAttribute("LevelNightName", if active then active.Night.Name else "")
end

local function phaseHook(phase: GameStateService.Phase): number?
	if phase == "Day" then
		chooseLevel()
	end
	if active and (phase == "Day" or phase == "Night") then
		return active[phase].Duration
	end
	return nil
end

-- ── stages ──────────────────────────────────────────────────────────────────

local function grantOptional(player: Player, done: { string })
	local campaign = campaignOf(player)
	if not active or not campaign then
		return
	end
	for _, id in done do
		local key = active.Id .. "/" .. id
		if not campaign.OptionalDone[key] then
			campaign.OptionalDone[key] = true
			ProgressionService.AddXP(player, CampaignConfig.OptionalXP)
			Notify.player(
				player,
				string.format("★ Bonus objective complete: +%d XP", CampaignConfig.OptionalXP),
				"success"
			)
		end
	end
end

local function startStage(newStage: Stage)
	stage = newStage
	stageFinal = false
	table.clear(announced)
	tracker = if active then CampaignLogic.newTracker(active[newStage].Objectives) else nil
	if not active then
		markDirty(nil)
		return
	end
	local config = active[newStage]
	Notify.all(
		string.format(
			"%s %s %d: %s. %s",
			if newStage == "Day" then "☀️" else "🌙",
			string.upper(newStage),
			active.Index,
			config.Name,
			config.Story
		),
		"info"
	)

	if newStage == "Day" then
		for _, player in Players:GetPlayers() do
			if ShopService.GetShopOf(player) then
				MissionEvents.record(player, "ShopClaimed") -- already running a shop
			end
		end
		callModules("StartDay")
	else
		table.clear(roster)
		for _, player in Players:GetPlayers() do
			if campaignOf(player) then
				roster[player] = true
			end
			if player.Character and player.Character:FindFirstChild("Flashlight") then
				MissionEvents.record(player, "FlashlightEquipped")
			end
		end
		callModules("StartNight")
	end
	markDirty(nil)
end

local function endDay()
	stageFinal = true
	local level, dayTracker = active, tracker
	if level and dayTracker then
		for _, player in Players:GetPlayers() do
			local campaign = campaignOf(player)
			if campaign and eligible(player) then
				if CampaignLogic.requiredComplete(dayTracker, player.UserId, true) then
					if not campaign.DayCleared[level.Id] then
						campaign.DayCleared[level.Id] = true
						Notify.player(player, "✅ Day cleared! Now survive the night to finish the level.", "success")
					end
				elseif campaign.DayCleared[level.Id] then
					Notify.player(
						player,
						"Day objectives unfinished, but you cleared this day before: tonight still counts.",
						"info"
					)
				else
					Notify.player(
						player,
						"❌ Day objectives unfinished. You can still play tonight, but the level needs this day cleared: retry next shift.",
						"warning"
					)
				end
				grantOptional(player, CampaignLogic.optionalDone(dayTracker, player.UserId))
				syncCampaign(player)
			end
		end
	end
	callModules("EndDay")
	markDirty(nil)
end

local OUTCOME_TEXT = {
	FirstClear = "LEVEL COMPLETE",
	Replay = "LEVEL REPLAYED",
	Guest = "PLAYED AS GUEST",
	LateJoin = "JOINED MID-NIGHT",
	NightFailed = "LEVEL FAILED",
	DayMissing = "DAY NOT CLEARED",
}

local function endNight()
	stageFinal = true
	local level, nightTracker = active, tracker
	if level and nightTracker then
		for _, player in Players:GetPlayers() do
			local campaign = campaignOf(player)
			if not campaign then
				continue
			end
			local first = campaign.Completed[level.Id] == nil
			local outcome = CampaignLogic.outcome({
				Eligible = eligible(player),
				InRoster = roster[player] == true,
				DayCleared = campaign.DayCleared[level.Id] == true,
				NightSuccess = CampaignLogic.requiredComplete(nightTracker, player.UserId, true),
				AlreadyCompleted = not first,
			})
			local result: { [string]: any } = {
				LevelId = level.Id,
				Title = string.format("LEVEL %d · %s / %s", level.Index, level.Day.Name, level.Night.Name),
				Outcome = outcome,
				Heading = OUTCOME_TEXT[outcome],
				Cash = 0,
				XP = 0,
			}
			if outcome == "FirstClear" or outcome == "Replay" then
				local reward = CampaignLogic.reward(level.Rewards, first, CampaignConfig.ReplayFraction)
				ProgressionService.AddCash(player, reward.Cash)
				ProgressionService.AddXP(player, reward.XP)
				result.Cash, result.XP = reward.Cash, reward.XP
				if first then
					campaign.Completed[level.Id] = os.time()
					if votes[player] == level.Id then
						votes[player] = nil -- follow your progress by default
					end
					local nextLevel = CampaignConfig.Levels[level.Index + 1]
					if nextLevel then
						result.Next = {
							Index = nextLevel.Index,
							Day = nextLevel.Day.Name,
							Night = nextLevel.Night.Name,
							ComingSoon = not nextLevel.Implemented,
						}
					end
				end
			end
			if outcome == "Guest" or outcome == "LateJoin" then
				result.Reason = if outcome == "Guest"
					then string.format("Finish your own next level first to unlock Level %d.", level.Index)
					else "You joined after the night began; tonight's level credit needs the whole night."
			elseif outcome == "NightFailed" then
				result.Reason =
					"The night's required objectives weren't met. The level stays open: retry it next shift."
			elseif outcome == "DayMissing" then
				result.Reason =
					"Night survived, but this level's day objectives aren't cleared yet. Clear the day next shift."
			end
			if eligible(player) and roster[player] then
				grantOptional(player, CampaignLogic.optionalDone(nightTracker, player.UserId))
			end
			Net.get("MissionResult"):FireClient(player, result)
			syncCampaign(player)
			task.spawn(DataService.SaveNow, player)
		end
		publishVotes()
	end
	callModules("EndNight")
	markDirty(nil)
end

-- ── events ──────────────────────────────────────────────────────────────────

local function onEvent(player: Player?, event: string, amount: number)
	local current = tracker
	if not current or stageFinal then
		return
	end
	local key = if player then player.UserId else nil
	local before = {}
	for _, objective in current.Objectives do
		if objective.Event == event then
			before[objective.Id] = CampaignLogic.isDone(current, key, objective)
		end
	end
	if not CampaignLogic.record(current, key, event, amount) then
		return
	end
	for _, objective in current.Objectives do
		if objective.Event == event and (objective.Kind or "Count") == "Count" then
			if not before[objective.Id] and CampaignLogic.isDone(current, key, objective) then
				local text = (if objective.Optional then "★ Bonus: " else "✅ ") .. objective.Text
				if objective.Scope == "Team" then
					Notify.all(text, "success")
				elseif player then
					Notify.player(player, text, "success")
				end
			end
		end
	end
	-- Survive/Avoid finish at stage end, so "all set" means every required Count is done
	for _, target in Players:GetPlayers() do
		if
			not announced[target]
			and stage == "Day"
			and CampaignLogic.requiredComplete(current, target.UserId, true)
		then
			announced[target] = true
			Notify.player(target, "🌟 All day objectives done! Keep your shop busy until nightfall.", "levelup")
		end
	end
	markDirty(nil)
end

local function vote(player: Player, levelId: any)
	local campaign = campaignOf(player)
	if type(levelId) ~= "string" or #levelId > 8 or not campaign then
		return
	end
	if levelId ~= "FREE" then
		local level = CampaignConfig.ById[levelId]
		if not level or not level.Implemented or not CampaignLogic.isUnlocked(LEVELS, campaign.Completed, levelId) then
			Notify.player(player, "That level isn't unlocked yet.", "warning")
			return
		end
	end
	votes[player] = levelId
	syncCampaign(player)
	publishVotes()
	local label = if levelId == "FREE" then "Free Shift" else "Level " .. CampaignConfig.IndexOf[levelId]
	Notify.player(player, "🗳️ You voted for " .. label .. ". The mall picks the next level at sunrise.", "info")
end

local function watchCharacter(player: Player, character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Flashlight" then
			MissionEvents.record(player, "FlashlightEquipped")
		end
	end)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.Died:Connect(function()
			if stage == "Night" and not stageFinal then
				MissionEvents.record(player, "Downed")
			end
		end)
	end
end

-- ── public ──────────────────────────────────────────────────────────────────

-- Night rules for NightService: the active level's, or the classic loop in Free Shift.
function MissionService.GetNightRules(): { [string]: any }
	if not active then
		return { Tier = math.max(GameStateService.GetNight(), 1), Fuses = true, Blackout = false, Free = true }
	end
	local rules = table.clone(active.Night.Rules)
	rules.Free = false
	rules.LevelIndex = active.Index
	rules.Duration = active.Night.Duration
	for _, name in active.Modules do
		local module = LEVEL_MODULES[name]
		if module and module.PatrolPoints then
			rules.PatrolPoints = module.PatrolPoints()
		end
	end
	return rules
end

function MissionService.GetLevel(): any?
	return active
end

function MissionService.Init()
	ReplicatedStorage:SetAttribute("LevelId", "")
	GameStateService.SetPhaseHook(phaseHook)
end

function MissionService.Start()
	MissionEvents.Recorded:Connect(onEvent)
	Net.handle("VoteLevel", 2, 4, vote)

	GameStateService.PhaseChanged:Connect(function(phase)
		if phase == "Day" then
			startStage("Day")
		elseif phase == "Dusk" then
			endDay()
		elseif phase == "Night" then
			startStage("Night")
		elseif phase == "Dawn" then
			endNight()
		end
	end)

	DataService.ProfileLoaded:Connect(function(player)
		syncCampaign(player)
		publishVotes()
		markDirty(player)
	end)
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		votes[player] = nil
		roster[player] = nil
		announced[player] = nil
		dirty[player] = nil
		publishVotes()
	end)

	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("MissionTest_CompleteStage"):Connect(function()
			if workspace:GetAttribute("MissionTest_CompleteStage") ~= true then
				return
			end
			workspace:SetAttribute("MissionTest_CompleteStage", false)
			if tracker and not stageFinal then
				local ids = {}
				for _, player in Players:GetPlayers() do
					table.insert(ids, player.UserId)
				end
				CampaignLogic.completeRequired(tracker, ids)
				Notify.all("[TEST] Required objectives for this stage marked complete.", "warning")
				markDirty(nil)
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(0.25)
			if allDirty or next(dirty) ~= nil then
				flush()
			end
		end
	end)
end

return MissionService
