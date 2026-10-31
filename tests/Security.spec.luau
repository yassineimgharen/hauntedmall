-- Attacks on the real server code through its remotes (in the fake engine). What a cheating
-- client can do is fire any remote with anything; none of it may hand out progress.
--   .tools/bin/lune run tests/Security.spec.luau

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local Check = require("./harness/Check")
local Engine = require("./harness/Engine")
local Sim = require("./harness/Sim")

Check.suite("Security", "Integration-tested")
local test, eq, truthy = Check.test, Check.eq, Check.truthy

local CLIENT_REMOTES = {
	"PurchaseUpgrade",
	"Restock",
	"SetBeam",
	"SaveSettings",
	"RequestPurchase",
	"VoteLevel",
	"SubmitCode",
	"AimUpdate",
}

-- Everything that isn't what a handler expects (a NaN, a table with a cycle, a huge string, ...).
local cycle = {}
cycle.self = cycle
local GARBAGE: { any } = {
	true,
	false,
	0,
	-1,
	1e308,
	-1e308,
	0 / 0,
	math.huge,
	-math.huge,
	1.5,
	"",
	"L01",
	"FREE",
	"Battery",
	"CashSmall",
	"CashMega",
	string.rep("x", 200000),
	"\0\255",
	{},
	{ 1, 2, 3 },
	{ Cash = 1e9 },
	cycle,
	Vector3.new(0, 0, 0),
	Vector3.new(0 / 0, 0, 0),
	Vector3.new(1e30, 1e30, 1e30),
	function() end,
}

local function protectedState(player: any, world: any): string
	local data = world:require("Services.DataService").Get(player)
	local completed, achievements = 0, 0
	for _ in data.Campaign.Completed do
		completed += 1
	end
	for _ in data.Campaign.Achievements do
		achievements += 1
	end
	return string.format(
		"cash=%d xp=%d level=%d done=%d ach=%d",
		data.Cash,
		data.XP,
		data.Level,
		completed,
		achievements
	)
end

local function boot(opts: any?): (any, any)
	local world = Engine.new(opts or { Seed = 7 })
	world:boot()
	local player = world:addPlayer("Cheater")
	world:run(1)
	return world, player
end

test("garbage on every client remote: no server error, no change to cash/XP/progress", function()
	local world, player = boot()
	local before = protectedState(player, world)
	for _, remote in CLIENT_REMOTES do
		world:clientFire(player, remote)
		for _, a in GARBAGE do
			world:run(0.6) -- under the rate limit, so the handler really runs
			world:clientFire(player, remote, a)
			world:clientFire(player, remote, a, a)
			world:clientFire(player, remote, true, a)
			world:clientFire(player, remote, "Product", a)
			world:clientFire(player, remote, "GamePass", a)
		end
	end
	world:run(1)
	Check.noServerErrors(world)
	local seen = {}
	for _, w in world.Warnings do
		if w.Message:find("handler failed", 1, true) then
			table.insert(seen, w.Message:sub(1, 200))
		end
	end
	eq(table.concat(seen, " | "), "", "a handler threw on bad input")
	-- simulated store purchases aren't reachable with a fake key, and upgrades cost cash
	local after = protectedState(player, world)
	eq(after:gsub("cash=%d+ ", ""), (before:gsub("cash=%d+ ", "")), "progress")
end)

test("spamming a remote is rate-limited", function()
	local world, player = boot()
	local data = world:require("Services.DataService").Get(player)
	data.Cash = 1e6
	local UpgradeConfig = world:require("Shared.Config.UpgradeConfig")
	for _ = 1, 500 do
		world:clientFire(player, "PurchaseUpgrade", "Battery")
	end
	world:run(0.1)
	local level = data.Upgrades.Battery or 0
	truthy(level <= 6, "burst limit holds, bought " .. level)
	truthy(level <= UpgradeConfig.ById.Battery.MaxLevel, "never past the max")
end)

test("upgrades: no cash, no upgrade; never above max level; no duplicate charge at max", function()
	local world, player = boot()
	local data = world:require("Services.DataService").Get(player)
	local UpgradeConfig = world:require("Shared.Config.UpgradeConfig")
	data.Cash = 0
	world:clientFire(player, "PurchaseUpgrade", "Battery")
	world:run(0.5)
	eq(data.Upgrades.Battery, nil, "unaffordable")
	eq(data.Cash, 0, "cash")
	data.Cash = 1e7
	for _ = 1, UpgradeConfig.ById.Battery.MaxLevel + 5 do
		world:run(0.5)
		world:clientFire(player, "PurchaseUpgrade", "Battery")
	end
	world:run(0.5)
	eq(data.Upgrades.Battery, UpgradeConfig.ById.Battery.MaxLevel, "capped")
	local cash = data.Cash
	world:clientFire(player, "PurchaseUpgrade", "Battery")
	world:run(0.5)
	eq(data.Cash, cash, "no charge at max")
end)

test("settings can't be used to smuggle fields or out-of-range values", function()
	local world, player = boot()
	local data = world:require("Services.DataService").Get(player)
	world:clientFire(player, "SaveSettings", { Music = 5, Sfx = -1, ReducedEffects = "yes", Cash = 1e9, Version = 99 })
	world:run(1.1)
	world:clientFire(player, "SaveSettings", { Music = 0 / 0 })
	world:run(0.5)
	eq(data.Settings.Music, 0.6, "music")
	eq(data.Settings.Sfx, 0.8, "sfx")
	eq(data.Settings.Cash, nil, "smuggled field")
	eq(data.Version, 2, "version")
end)

test("live server: RequestPurchase never grants cash; it only asks Roblox to prompt", function()
	local world, player = boot({ Seed = 8, Studio = false, DataStore = {} })
	local data = world:require("Services.DataService").Get(player)
	local before = data.Cash
	world:clientFire(player, "RequestPurchase", "Product", "CashSmall")
	world:run(1)
	world:clientFire(player, "RequestPurchase", "GamePass", "NotAPass")
	world:run(1)
	eq(data.Cash, before, "cash")
	eq(#world.Prompted, 0, "unconfigured products (Id 0) don't prompt")
	eq(world.ReplicatedStorage:GetAttribute("StoreMode") == "Test", false, "test store is Studio-only")
end)

test("live server: the Studio-only test hooks do nothing", function()
	local world, player = boot({
		Seed = 9,
		Studio = false,
		DataStore = {},
		Attributes = { MissionTest_CompleteStage = true, StoreTest_OwnPass_VIP = true },
	})
	world:run(3)
	local campaign = world:require("Services.DataService").Get(player).Campaign
	eq(next(campaign.Completed), nil, "no level completed by a test attribute")
	eq(next(campaign.DayCleared), nil, "no day cleared by a test attribute")
end)

test("a receipt is granted once, even when delivered twice or at once", function()
	local world, player = boot({ Seed = 10, Studio = false, DataStore = {} })
	local MonetizationConfig = world:require("Shared.Config.MonetizationConfig")
	local data = world:require("Services.DataService").Get(player)
	-- a configured product, as it will be once a real id is set
	local product = MonetizationConfig.Products.CashSmall
	product.Id = 991
	local byId = MonetizationConfig.productById
	MonetizationConfig.productById = function(id)
		return if id == 991 then product else byId(id)
	end
	local process = world.MarketplaceService.ProcessReceipt
	local receipt =
		{ PlayerId = player.UserId, ProductId = 991, PurchaseId = "r-1", CurrencySpent = 29, PlaceIdWherePurchased = 1 }
	local before = data.Cash
	local decisions = {}
	for _ = 1, 3 do
		world.task.spawn(function()
			table.insert(decisions, process(receipt))
		end)
	end
	world:run(2)
	eq(data.Cash, before + product.Grant.Cash, "paid once")
	eq(#decisions, 3, "all answered")
	world.task.spawn(function()
		table.insert(decisions, process(receipt))
	end)
	world:run(1)
	eq(data.Cash, before + product.Grant.Cash, "re-delivery pays nothing")
	product.Id = 0
end)

test("a receipt whose save fails stays pending and pays once on retry", function()
	local world, player = boot({ Seed = 11, Studio = false, DataStore = {} })
	local MonetizationConfig = world:require("Shared.Config.MonetizationConfig")
	local Enum = roblox.Enum
	local data = world:require("Services.DataService").Get(player)
	local product = MonetizationConfig.Products.CashSmall
	product.Id = 992
	local byId = MonetizationConfig.productById
	MonetizationConfig.productById = function(id)
		return if id == 992 then product else byId(id)
	end
	local process = world.MarketplaceService.ProcessReceipt
	local receipt =
		{ PlayerId = player.UserId, ProductId = 992, PurchaseId = "r-2", CurrencySpent = 29, PlaceIdWherePurchased = 1 }
	local before = data.Cash
	world.StoreFailures.Write = 4 -- every attempt of this save
	local first
	world.task.spawn(function()
		first = process(receipt)
	end)
	world:run(30)
	eq(first, Enum.ProductPurchaseDecision.NotProcessedYet, "not acknowledged while unsaved")
	local second
	world.task.spawn(function()
		second = process(receipt)
	end)
	world:run(10)
	eq(second, Enum.ProductPurchaseDecision.PurchaseGranted, "acknowledged once saved")
	eq(data.Cash, before + product.Grant.Cash, "one grant across both deliveries")
	product.Id = 0
end)

test("a receipt for someone who's offline stays pending and pays nothing", function()
	local world = boot({ Seed = 12, Studio = false, DataStore = {} })
	local Enum = roblox.Enum
	local process = world.MarketplaceService.ProcessReceipt
	local decision
	world.task.spawn(function()
		decision = process({
			PlayerId = 555555,
			ProductId = 991,
			PurchaseId = "r-3",
			CurrencySpent = 29,
			PlaceIdWherePurchased = 1,
		})
	end)
	world:run(30)
	eq(decision, Enum.ProductPurchaseDecision.NotProcessedYet, "pending")
end)

test("the wrong vault code does nothing and locks the keypad out for a moment", function()
	local run = Sim.start("L05", 1, { Seed = 3 })
	run.World:waitForPhase("Day", 100)
	run.World:run(1)
	local world, bot = run.World, run.Bots[1]
	local function progress(): number
		return bot:row("code") and bot:row("code").Progress or 0
	end
	for _, code in { "0000", "", 1234, {}, string.rep("9", 10000) } do
		world:clientFire(bot.Player, "SubmitCode", code)
		world:run(1.2)
	end
	eq(progress(), 0, "no progress from a guess")
	Check.noServerErrors(world)
end)

test("voting: unknown or locked levels don't count", function()
	local world, player = boot({ Seed = 13 })
	world:clientFire(player, "VoteLevel", "L14")
	world:run(0.6)
	world:clientFire(player, "VoteLevel", "L99")
	world:run(0.6)
	world:clientFire(player, "VoteLevel", 5)
	world:run(0.6)
	Check.noServerErrors(world)
	world:waitForPhase("Day", 200)
	world:run(1)
	eq(world.ReplicatedStorage:GetAttribute("LevelId"), "L01", "a new player can't vote their way to L14")
end)

test("a beam aimed behind you or at an impossible angle is refused (server checks the aim)", function()
	local run = Sim.start("L07", 1, { Seed = 3 })
	local world, bot = run.World, run.Bots[1]
	world:waitForPhase("Day", 100)
	world:run(1)
	bot:equip()
	local root = bot:root()
	world:clientFire(bot.Player, "SetBeam", true, -root.CFrame.LookVector)
	world:run(0.5)
	world:clientFire(bot.Player, "AimUpdate", Vector3.new(0, 1, 0))
	world:run(0.5)
	world:clientFire(bot.Player, "AimUpdate", Vector3.new(0 / 0, 0 / 0, 0 / 0))
	world:run(0.5)
	world:clientFire(bot.Player, "SetBeam", false)
	Check.noServerErrors(world)
end)

test("a beam needs an equipped flashlight and battery", function()
	local run = Sim.start("L01", 1, { Seed = 3 })
	local world, bot = run.World, run.Bots[1]
	world:waitForPhase("Day", 100)
	world:run(1)
	local before = bot.Player:GetAttribute("Battery")
	world:clientFire(bot.Player, "SetBeam", true, Vector3.new(0, 0, -1))
	world:run(3)
	eq(bot.Player:GetAttribute("Battery"), before, "no flashlight in hand, no beam, no drain")
	Check.noServerErrors(world)
end)

test("there are no client-to-server remotes beyond the audited list", function()
	local world = boot()
	local remotes = world.ReplicatedStorage:FindFirstChild("Remotes")
	local toClient = { Notify = true, NightResults = true, Effect = true, MissionState = true, MissionResult = true }
	local known = {}
	for _, name in CLIENT_REMOTES do
		known[name] = true
	end
	for _, remote in remotes:GetChildren() do
		truthy(known[remote.Name] or toClient[remote.Name], "unaudited remote " .. remote.Name)
	end
end)

Check.finish()
