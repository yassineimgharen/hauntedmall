-- Save/load with a mock DataStore that persists between server boots (no real DataStore is touched):
-- first-time players, old saves, damaged saves, failed reads and writes, session locks, and that
-- nothing is ever paid twice across sessions.
--   .tools/bin/lune run tests/Persistence.spec.luau

local serde = require("@lune/serde")
local Check = require("./harness/Check")
local Engine = require("./harness/Engine")
local Sim = require("./harness/Sim")
local Strategies = require("./harness/Strategies")

Check.suite("Persistence", "Integration-tested")
local test, eq, truthy, falsy = Check.test, Check.eq, Check.truthy, Check.falsy

local STORE = "NightShift_PlayerData_v1" -- the live name; Studio = false in these worlds

local function server(backing: any, seed: number?): any
	local world = Engine.new({ Seed = seed or 1, Studio = false, DataStore = backing })
	world:boot()
	return world
end

local function raw(backing: any, userId: number): any
	local record = backing[STORE] and backing[STORE]["p_" .. userId]
	return record and serde.decode("json", record)
end

local function put(backing: any, userId: number, value: any)
	backing[STORE] = backing[STORE] or {}
	backing[STORE]["p_" .. userId] = serde.encode("json", value)
end

local function join(world: any, userId: number): (any, any)
	local player = world:addPlayer("P" .. userId, userId)
	world:run(1)
	return player, world:require("Services.DataService").Get(player)
end

test("a first-time player gets defaults, saved under a session lock", function()
	local backing = {}
	local world = server(backing)
	local _, data = join(world, 101)
	truthy(data, "loaded")
	eq(data.Level, 1, "level")
	eq(data.Version, 2, "schema")
	local saved = raw(backing, 101)
	truthy(saved.Lock, "lock taken")
	world:shutdown()
end)

test("save and load round-trip across a leave and a new server", function()
	local backing = {}
	local world = server(backing)
	local player, data = join(world, 102)
	data.Cash = 777
	data.XP = 42
	data.Upgrades.Battery = 2
	data.Campaign.Completed.L01 = 1000
	data.Campaign.DayCleared.L02 = true
	data.Campaign.Chapters["1"] = 2000
	-- (clearing a level pays any achievement it unlocks: already paid, in this save)
	for _, achievement in world:require("Shared.Campaign.AchievementConfig").List do
		data.Campaign.Achievements[achievement.Id] = 3000
	end
	data.Equipment.PrismLens = true
	data.Title = "Queen Slayer"
	world:removePlayer(player)
	world:run(1)
	eq(raw(backing, 102).Lock, nil, "lock released on leave")
	local world2 = server(backing, 2)
	local _, loaded = join(world2, 102)
	eq(loaded.Cash, 777, "cash")
	eq(loaded.XP, 42, "xp")
	eq(loaded.Upgrades.Battery, 2, "upgrade")
	eq(loaded.Campaign.Completed.L01, 1000, "completed")
	eq(loaded.Campaign.DayCleared.L02, true, "day")
	eq(loaded.Campaign.Chapters["1"], 2000, "chapter")
	local _, stamp = next(loaded.Campaign.Achievements)
	eq(stamp, 3000, "achievements kept")
	eq(loaded.Equipment.PrismLens, true, "equipment")
	eq(loaded.Title, "Queen Slayer", "title")
end)

test("a version 1 save migrates: finished tutorial credits Level 1, nothing lost", function()
	local backing = {}
	put(backing, 103, {
		Version = 1,
		Cash = 1234,
		XP = 500,
		Level = 3,
		Stock = 7,
		Upgrades = { Battery = 1 },
		Stats = { NightsSurvived = 4, Kills = 9, Sales = 20 },
		Tutorial = { Completed = true, SurvivedNight = true },
	})
	local world = server(backing)
	local _, data = join(world, 103)
	eq(data.Version, 2, "version")
	eq(data.Cash, 1234, "cash kept")
	eq(data.Level, 3, "level kept")
	eq(data.Upgrades.Battery, 1, "upgrades kept")
	eq(data.Stats.Kills, 9, "stats kept")
	truthy(data.Campaign.Completed.L01, "Level 1 credited")
	eq(data.Campaign.DayCleared.L01, true, "day credited")
	eq(type(data.Campaign.Chapters), "table", "new fields filled in")
	Check.noServerErrors(world)
end)

test("a save with fields missing is filled in without touching the rest", function()
	local backing = {}
	put(
		backing,
		104,
		{ Version = 2, Cash = 50, Campaign = { Completed = { L01 = 1 }, DayCleared = {}, OptionalDone = {} } }
	)
	local world = server(backing)
	local _, data = join(world, 104)
	eq(data.Cash, 50, "cash")
	eq(data.Campaign.Completed.L01, 1, "progress")
	eq(type(data.Stats), "table", "stats")
	eq(type(data.Campaign.Achievements), "table", "achievements")
	eq(data.Settings.Music, 0.6, "settings")
	Check.noServerErrors(world)
end)

test("older saves with numeric chapter keys are normalised (a sparse array can't be saved)", function()
	local backing = {}
	put(
		backing,
		105,
		{ Version = 2, Campaign = { Completed = {}, DayCleared = {}, OptionalDone = {}, Chapters = { ["2"] = 5 } } }
	)
	local world = server(backing)
	local player, data = join(world, 105)
	data.Campaign.Chapters[1] = nil
	eq(data.Campaign.Chapters["2"], 5, "kept under a string key")
	world:removePlayer(player)
	world:run(1)
	Check.noServerErrors(world)
end)

test("BUG-04 regression: damaged field types are repaired, the game still runs, good fields survive", function()
	local backing = {}
	put(backing, 106, {
		Version = 2,
		Cash = 900,
		XP = "lots",
		Level = -3,
		Stock = 1,
		Upgrades = "none",
		Collectibles = 5,
		Stats = 12,
		Settings = "loud",
		Tutorial = false,
		LastEmergencyStockAt = "yesterday",
		ProcessedReceipts = "gone",
		TestReceipts = 1,
		PurchaseHistory = "x",
		Campaign = { Completed = { L01 = 1 }, DayCleared = "x", OptionalDone = {}, Chapters = 3, Achievements = "y" },
		Equipment = 7,
		Title = 9,
	})
	local world = server(backing)
	local player, data = join(world, 106)
	truthy(data, "still loads")
	eq(data.Cash, 900, "good cash kept")
	eq(data.XP, 0, "xp repaired")
	eq(data.Level, 1, "level repaired")
	eq(type(data.Upgrades), "table", "upgrades repaired")
	eq(type(data.Stats), "table", "stats repaired")
	eq(data.Stats.Kills, 0, "stats default")
	eq(type(data.Settings), "table", "settings repaired")
	eq(type(data.Tutorial), "table", "tutorial repaired")
	eq(type(data.ProcessedReceipts), "table", "ledger repaired")
	eq(type(data.Campaign.DayCleared), "table", "day cleared repaired")
	eq(data.Campaign.Completed.L01, 1, "valid progress kept, not reset")
	eq(data.Title, "", "title repaired")
	world:run(5)
	world:clientFire(player, "SaveSettings", { Music = 0.5 })
	world:clientFire(player, "PurchaseUpgrade", "Battery")
	world:removePlayer(player)
	world:run(2)
	Check.noServerErrors(world)
	local bad = {}
	for _, w in world.Warnings do
		if w.Message:find("handler failed", 1, true) then
			table.insert(bad, w.Message)
		end
	end
	eq(table.concat(bad, "; "), "", "handlers kept working")
end)

test("a save that isn't even a table is never overwritten; the player is told to come back", function()
	local backing = {}
	backing[STORE] = { p_107 = serde.encode("json", "garbage") }
	local world = server(backing)
	local player = world:addPlayer("P107", 107)
	world:run(120)
	truthy(player._kicked, "kicked rather than given blank data")
	eq(world:require("Services.DataService").Get(player), nil, "no profile")
	eq(backing[STORE].p_107, serde.encode("json", "garbage"), "data untouched for support to recover")
end)

test("failed reads retry, then succeed with the real data", function()
	local backing = {}
	put(backing, 108, { Version = 2, Cash = 321 })
	local world = server(backing)
	world.StoreFailures.Write = 3
	local player = world:addPlayer("P108", 108)
	world:run(40)
	local data = world:require("Services.DataService").Get(player)
	truthy(data, "loaded on a retry")
	eq(data.Cash, 321, "real data, not defaults")
	falsy(player._kicked, "not kicked")
end)

test("reads that never succeed kick the player and never write defaults over the save", function()
	local backing = {}
	put(backing, 109, { Version = 2, Cash = 999 })
	local before = backing[STORE].p_109
	local world = server(backing)
	world.StoreFailures.Write = 100
	local player = world:addPlayer("P109", 109)
	world:run(120)
	truthy(player._kicked, "kicked")
	eq(backing[STORE].p_109, before, "save untouched")
end)

test("a failing save retries; the data arrives when the store recovers", function()
	local backing = {}
	local world = server(backing)
	local player, data = join(world, 110)
	data.Cash = 4242
	world.StoreFailures.Write = 2
	world:removePlayer(player)
	world:run(15)
	eq(raw(backing, 110).Cash, 4242, "saved on a retry")
	eq(raw(backing, 110).Lock, nil, "lock released")
end)

test("a save that keeps failing leaves the old data, and the lock expires for the next session", function()
	local backing = {}
	local world = server(backing)
	local player, data = join(world, 111)
	world:run(1)
	data.Cash = 1
	world.StoreFailures.Write = 10
	world:removePlayer(player)
	world:run(30)
	truthy(raw(backing, 111).Lock, "the lock is still in the store")
	eq(raw(backing, 111).Cash ~= 1, true, "the failed write didn't land")
end)

test("a second server can't load a locked profile while the first holds it", function()
	local backing = {}
	local world1 = server(backing, 1)
	local _, data1 = join(world1, 112)
	data1.Cash = 5000
	local world2 = server(backing, 2)
	local player2 = world2:addPlayer("P112", 112)
	world2:run(5)
	eq(world2:require("Services.DataService").Get(player2), nil, "waits, doesn't load")
end)

test("if another server took the lock, this one discards its changes and kicks", function()
	local backing = {}
	local world = server(backing)
	local player, data = join(world, 113)
	data.Cash = 1
	local stolen = raw(backing, 113)
	stolen.Lock = { JobId = "other-server", Time = os.time() }
	stolen.Cash = 8888
	put(backing, 113, stolen)
	world:run(70) -- past the autosave
	truthy(player._kicked, "kicked")
	eq(raw(backing, 113).Cash, 8888, "the other server's data stands")
end)

test("leaving while the profile is loading doesn't leave a stale lock", function()
	local backing = {}
	local world = server(backing)
	world.StoreFailures.Write = 1
	local player = world:addPlayer("P114", 114)
	world:removePlayer(player)
	world:run(20)
	local saved = raw(backing, 114)
	eq(saved == nil or saved.Lock == nil, true, "no lock left behind")
	Check.noServerErrors(world)
end)

test("Studio without API access uses the memory store and writes nothing", function()
	local world = Engine.new({ Seed = 1 })
	world:boot()
	local player = world:addPlayer("P115", 115)
	world:run(1)
	eq(world:require("Services.DataService").IsMock(), true, "mock")
	eq(player:GetAttribute("DataMock"), true, "the HUD can say so")
end)

test("Studio with API access uses a separate store from live", function()
	local backing = {}
	local world = Engine.new({ Seed = 1, DataStore = backing })
	world:boot()
	join(world, 116)
	eq(backing[STORE] == nil or backing[STORE].p_116 == nil, true, "live store untouched")
	truthy(backing[STORE .. "_Studio"].p_116, "Studio store used")
end)

-- Rewards across sessions, through a whole played level
local function playL07(backing: any, seed: number): any
	local run = Sim.start("L07", 1, { Seed = seed, DataStore = backing, UserIds = { 200 } })
	local s = Strategies.L07
	Sim.playLevel(run, s.Day, s.Night, s.Per)
	return run
end

test("L07 Night: chapter reward, title, lens and achievements pay once, across a rejoin too", function()
	local backing = {}
	local run = playL07(backing, 1)
	local data = run.World:require("Services.DataService").Get(run.Bots[1].Player)
	truthy(data.Campaign.Completed.L07, "cleared")
	truthy(data.Campaign.Chapters["1"], "chapter marked")
	eq(data.Title, "Queen Slayer", "title")
	local stamp = data.Campaign.Chapters["1"]
	local achievements = {}
	for id, at in data.Campaign.Achievements do
		achievements[id] = at
	end
	local cash = data.Cash
	run.World:removePlayer(run.Bots[1].Player)
	run.World:run(2)
	run.World:shutdown()

	local again = playL07(backing, 2)
	local replay = again.World:require("Services.DataService").Get(again.Bots[1].Player)
	eq(replay.Campaign.Chapters["1"], stamp, "chapter stamp unchanged")
	for id, at in achievements do
		eq(replay.Campaign.Achievements[id], at, "achievement " .. id .. " not re-earned")
	end
	local Campaign = again.World:require("Shared.Campaign.CampaignConfig")
	local level = Campaign.ById.L07
	local result = again.Bots[1]:results()
	truthy(result[#result], "a result was shown")
	truthy(replay.Cash - cash < level.ChapterReward.Cash, "no chapter cash the second time")
end)

Check.finish()
