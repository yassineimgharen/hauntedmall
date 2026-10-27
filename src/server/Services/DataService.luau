-- Player data persistence.
--
-- Safeguards against data loss / duplication:
--   * Session lock: a profile is only writable by the server that loaded it. Another server
--     must wait for the lock to be released (or expire after LOCK_TTL of silence).
--   * Never saves a profile that failed to load, so defaults can't overwrite real data.
--   * All writes use UpdateAsync and verify the lock is still ours before writing.
--   * Retries with backoff, periodic autosave, and a flush on shutdown (BindToClose).
--   * Studio without API access falls back to an in-memory store and says so loudly.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local STORE_NAME = "NightShift_PlayerData_v1"
	.. (if RunService:IsStudio() then GameConfig.StudioDataStoreSuffix else "")
local SCHEMA_VERSION = 1
local LOCK_TTL = GameConfig.AutosaveInterval * 3
local LOAD_ATTEMPTS = 6
local LOCK_RETRY_DELAY = 4
local SAVE_ATTEMPTS = 4

local JOB_ID = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

type Profile = {
	Key: string,
	Data: { [string]: any },
	SessionLost: boolean,
}

local DataService = {}
DataService.ProfileLoaded = Signal.new() -- (player, data)

local profiles: { [Player]: Profile } = {}
local store: DataStore? = nil
local mockStore: { [string]: any } = {}
local usingMock = false
local activeSaves = 0

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function defaultData(): { [string]: any }
	return {
		Version = SCHEMA_VERSION,
		Cash = EconomyConfig.StartingCash,
		XP = 0,
		Level = 1,
		Stock = 0,
		Upgrades = {},
		Collectibles = {},
		Stats = {
			NightsSurvived = 0,
			Kills = 0,
			Sales = 0,
			TotalEarned = 0,
			FusesRepaired = 0,
		},
		Settings = {
			Music = 0.6,
			Sfx = 0.8,
			ReducedEffects = false,
		},
		Tutorial = {
			Claimed = false,
			Stocked = false,
			Served = false,
			Upgraded = false,
			Completed = false,
			SurvivedNight = false,
		},
		LastEmergencyStockAt = 0,
		ProcessedReceipts = {}, -- Phase 5: purchase ids already granted (dedupe)
		CreatedAt = os.time(),
	}
end

-- Schema migrations: MIGRATIONS[n] upgrades data from version n to n + 1.
local MIGRATIONS: { [number]: (data: { [string]: any }) -> () } = {}

local function reconcile(data: { [string]: any }, template: { [string]: any })
	for key, value in template do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" then
			reconcile(data[key], value)
		end
	end
end

local function sanitize(data: { [string]: any })
	local function finite(n: any): boolean
		return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
	end
	if not finite(data.Cash) or data.Cash < 0 then
		data.Cash = 0
	end
	if not finite(data.XP) or data.XP < 0 then
		data.XP = 0
	end
	if not finite(data.Level) or data.Level < 1 then
		data.Level = 1
	end
	if not finite(data.Stock) or data.Stock < 0 then
		data.Stock = 0
	end
end

local function updateAsync(key: string, transform: (any) -> any)
	if usingMock then
		local result = transform(deepCopy(mockStore[key]))
		if result ~= nil then
			mockStore[key] = deepCopy(result)
		end
		return
	end
	(store :: DataStore):UpdateAsync(key, transform)
end

local function loadProfile(player: Player)
	local key = "p_" .. player.UserId
	local loaded: { [string]: any }? = nil

	for attempt = 1, LOAD_ATTEMPTS do
		if not player.Parent then
			return
		end
		local lockedElsewhere = false
		local ok, err = pcall(updateAsync, key, function(old)
			loaded = nil
			lockedElsewhere = false
			local data = old or defaultData()
			local lock = data.Lock
			if lock and lock.JobId ~= JOB_ID and os.time() - (lock.Time or 0) < LOCK_TTL then
				lockedElsewhere = true
				return nil -- cancel the write; retry once the other server releases it
			end
			data.Lock = { JobId = JOB_ID, Time = os.time() }
			loaded = data
			return data
		end)
		if ok and loaded then
			break
		end
		if not ok then
			warn(string.format("[DataService] load attempt %d for %s failed: %s", attempt, player.Name, tostring(err)))
		end
		task.wait(if lockedElsewhere then LOCK_RETRY_DELAY else math.min(2 ^ attempt, 10))
	end

	if not loaded then
		if player.Parent then
			player:Kick(
				"Night Shift couldn't load your save safely. Please rejoin in a minute — your progress is protected."
			)
		end
		return
	end

	local data = loaded :: { [string]: any }
	data.Lock = nil
	local version = data.Version or 1
	while version < SCHEMA_VERSION do
		local migrate = MIGRATIONS[version]
		if migrate then
			migrate(data)
		end
		version += 1
	end
	data.Version = SCHEMA_VERSION
	reconcile(data, defaultData())
	sanitize(data)

	local profile: Profile = { Key = key, Data = data, SessionLost = false }
	profiles[player] = profile

	if not player.Parent then
		-- left while loading: release the lock right away
		profiles[player] = nil
		DataService._save(player, profile, true)
		return
	end

	player:SetAttribute("DataLoaded", true)
	player:SetAttribute("DataMock", usingMock)
	DataService.ProfileLoaded:Fire(player, data)
end

-- Returns true if the write succeeded.
function DataService._save(player: Player, profile: Profile, release: boolean): boolean
	if profile.SessionLost then
		return false
	end
	activeSaves += 1
	local ok = DataService._write(player, profile, release)
	activeSaves -= 1
	return ok
end

function DataService._write(player: Player, profile: Profile, release: boolean): boolean
	local snapshot = deepCopy(profile.Data)
	snapshot.Lock = if release then nil else { JobId = JOB_ID, Time = os.time() }

	for attempt = 1, SAVE_ATTEMPTS do
		local lost = false
		local ok, err = pcall(updateAsync, profile.Key, function(old)
			lost = false
			if not old or not old.Lock or old.Lock.JobId ~= JOB_ID then
				lost = true -- another server owns this profile now; never overwrite it
				return nil
			end
			return snapshot
		end)
		if ok then
			if lost then
				profile.SessionLost = true
				warn("[DataService] session lock lost for " .. player.Name .. "; discarding local changes")
				if player.Parent then
					player:Kick("Your Night Shift session was opened on another server.")
				end
				return false
			end
			return true
		end
		warn(string.format("[DataService] save attempt %d for %s failed: %s", attempt, player.Name, tostring(err)))
		task.wait(attempt * 2)
	end
	return false
end

-- Loaded data table for a player, or nil while loading. Mutate it directly; it is saved
-- on autosave, on leave and on shutdown.
function DataService.Get(player: Player): { [string]: any }?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService.IsMock(): boolean
	return usingMock
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	end

	if RunService:IsStudio() then
		local probeOk = ok and pcall(function()
			(store :: DataStore):GetAsync("__probe")
		end)
		if not probeOk then
			usingMock = true
			warn(
				"[DataService] DataStores unavailable in Studio — using an in-memory store. "
					.. "Enable Game Settings › Security › 'Enable Studio Access to API Services' to test saving."
			)
		end
	elseif not ok then
		error("[DataService] DataStoreService unavailable: " .. tostring(result))
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(loadProfile)
	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			profiles[player] = nil
			DataService._save(player, profile, true)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveInterval)
			for player, profile in profiles do
				task.spawn(DataService._save, player, profile, false)
				task.wait(0.5) -- spread requests across the budget
			end
		end
	end)

	game:BindToClose(function()
		-- release everyone still here; saves started by PlayerRemoving are counted too
		for player, profile in profiles do
			profiles[player] = nil
			task.spawn(DataService._save, player, profile, true)
		end
		local deadline = os.clock() + 25
		repeat
			task.wait(0.1)
		until activeSaves == 0 or os.clock() > deadline
	end)
end

return DataService
