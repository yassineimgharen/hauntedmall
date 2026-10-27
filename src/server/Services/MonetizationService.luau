-- The only place that talks to MarketplaceService (one ProcessReceipt handler, no others).
--
--   Developer products → ReceiptProcessor (idempotent, persisted before acknowledging)
--   Game passes        → UserOwnsGamePassAsync on join (+ re-check after a purchase);
--                        exposed as OwnsPass() and Player attributes "Pass_<Key>"
--   Purchase requests  → RequestPurchase remote, validated against MonetizationConfig.
--                        The client never reports a purchase; Roblox's receipt does.
--
-- Store modes (ReplicatedStorage attribute "StoreMode"):
--   "Closed" config Enabled = false: no real prompts (current state)
--   "Live"   config Enabled = true: real prompts for items with Ids
--   "Test"   Studio + TestMode: simulated purchases through the SAME grant pipeline, into a
--            separate ledger (TestReceipts) and the Studio-only DataStore. Never in live servers.
--
-- Studio test scenarios (Workspace attributes, set in the Server view):
--   StoreTest_Decline (bool)       simulate the player cancelling the prompt
--   StoreTest_FailSave (bool)      simulate DataStore write failures (Roblox-style retries)
--   StoreTest_Duplicate (bool)     deliver every simulated receipt twice
--   StoreTest_DelaySeconds (number) wait before processing (leave mid-purchase test)
--   StoreTest_OwnPass_<Key> (bool) simulated game-pass ownership, e.g. StoreTest_OwnPass_VIP

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
local ReceiptProcessor = require(script.Parent.Parent.Monetization.ReceiptProcessor)
local Notify = require(script.Parent.Parent.Util.Notify)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)

local MonetizationService = {}
MonetizationService.PassChanged = Signal.new() -- (player, passKey, owned)

local TEST_MODE = RunService:IsStudio() and MonetizationConfig.TestMode == true
local PROFILE_WAIT = 15 -- seconds a receipt waits for a joining player's profile to load
local SIMULATED_RETRIES = 4

local passOwnership: { [Player]: { [string]: boolean } } = {}

local function storeMode(): string
	if TEST_MODE then
		return "Test"
	end
	return if MonetizationConfig.Enabled then "Live" else "Closed"
end

local function log(message: string)
	warn("[MonetizationService] " .. message)
end

local function waitForData(player: Player): { [string]: any }?
	local deadline = os.clock() + PROFILE_WAIT
	local data = DataService.Get(player)
	while not data and player.Parent and os.clock() < deadline do
		task.wait(0.25)
		data = DataService.Get(player)
	end
	return data
end

-- Applies a product's rewards. Must not yield (see ReceiptProcessor guarantee 1).
local function grant(player: Player, _data: { [string]: any }, product: any): boolean
	local cash = product.Grant.Cash
	if cash then
		return ProgressionService.AddCash(player, cash, "Purchase")
	end
	return false -- no grant kinds this phase understands: keep the receipt pending
end

local function baseDeps(ledger: string, test: boolean): ReceiptProcessor.Deps
	return {
		ledger = ledger,
		test = test,
		getPlayer = function(userId)
			return Players:GetPlayerByUserId(userId)
		end,
		getData = waitForData,
		isActive = DataService.IsActive,
		findProduct = function(receipt)
			return MonetizationConfig.productById(receipt.ProductId)
		end,
		grant = grant,
		saveNow = DataService.SaveNow,
		now = os.time,
		log = log,
		limits = MonetizationConfig.Ledger,
	}
end

local realProcessor = ReceiptProcessor.new(baseDeps("ProcessedReceipts", false))

local testDeps = baseDeps("TestReceipts", true)
testDeps.findProduct = function(receipt)
	return receipt.ProductKey and MonetizationConfig.Products[receipt.ProductKey] or nil
end
testDeps.saveNow = function(player)
	if workspace:GetAttribute("StoreTest_FailSave") == true then
		return false
	end
	return DataService.SaveNow(player)
end
local testProcessor = ReceiptProcessor.new(testDeps)

local function confirm(player: Player, product: MonetizationConfig.Product, test: boolean)
	local cash = product.Grant.Cash
	local what = if cash then string.format("+$%d", cash) else product.Name
	Notify.player(player, string.format("✅ %s%s: %s", if test then "[TEST] " else "", product.Name, what), "success")
	Notify.effect(player, "Purchase")
end

-- ── developer products ─────────────────────────────────────────────────────

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local decision, fresh = realProcessor:process(info :: any)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local product = MonetizationConfig.productById(info.ProductId)
	if player and product and fresh then
		if decision == "Granted" then
			confirm(player, product, false)
		else
			Notify.player(player, "Purchase received — saving it to your profile…", "info")
		end
	end
	return if decision == "Granted"
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Studio only: a fake receipt through the real pipeline, retried the way Roblox would.
local function simulateProductPurchase(player: Player, product: MonetizationConfig.Product)
	if workspace:GetAttribute("StoreTest_Decline") == true then
		Notify.player(player, "[TEST] Purchase cancelled — nothing granted.", "warning")
		return
	end
	local receipt = {
		PurchaseId = "TEST-" .. HttpService:GenerateGUID(false),
		PlayerId = player.UserId,
		ProductId = product.Id,
		ProductKey = product.Key,
		CurrencySpent = 0,
	}
	local delay = workspace:GetAttribute("StoreTest_DelaySeconds")
	if type(delay) == "number" and delay > 0 then
		Notify.player(player, string.format("[TEST] Processing in %ds (leave now to test)…", delay), "info")
		task.wait(math.min(delay, 60))
	end

	local deliveries = if workspace:GetAttribute("StoreTest_Duplicate") == true then 2 else 1
	for delivery = 1, deliveries do
		for attempt = 1, SIMULATED_RETRIES do
			local decision, fresh = testProcessor:process(receipt)
			local live = Players:GetPlayerByUserId(player.UserId)
			if decision == "Granted" then
				if live and fresh then
					confirm(live, product, true)
				elseif live then
					Notify.player(
						live,
						string.format(
							"[TEST] Delivery %d: duplicate receipt acknowledged, nothing regranted.",
							delivery
						),
						"info"
					)
				end
				break
			end
			if live then
				Notify.player(
					live,
					string.format(
						"[TEST] Receipt pending (attempt %d/%d) — retrying in 5s.",
						attempt,
						SIMULATED_RETRIES
					),
					"warning"
				)
			end
			task.wait(5)
		end
	end
end

-- ── game passes ────────────────────────────────────────────────────────────

local function setOwned(player: Player, key: string, owned: boolean)
	local owners = passOwnership[player]
	if not owners or owners[key] == owned then
		return
	end
	owners[key] = owned
	player:SetAttribute("Pass_" .. key, owned)
	MonetizationService.PassChanged:Fire(player, key, owned)
end

local function checkOwnership(player: Player, pass: MonetizationConfig.GamePass): boolean
	if TEST_MODE then
		return workspace:GetAttribute("StoreTest_OwnPass_" .. pass.Key) == true
	end
	if pass.Id == 0 then
		return false
	end
	for attempt = 1, 3 do
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
		if ok then
			return owns == true
		end
		task.wait(2 ^ attempt)
	end
	log("could not verify " .. pass.Key .. " for " .. player.Name .. "; treating as not owned this session")
	return false
end

local function refreshPasses(player: Player)
	for key, pass in MonetizationConfig.GamePasses do
		setOwned(player, key, checkOwnership(player, pass))
	end
end

function MonetizationService.OwnsPass(player: Player, key: string): boolean
	local owners = passOwnership[player]
	return owners ~= nil and owners[key] == true
end

-- ── purchase requests (client asks; server decides) ─────────────────────────

local function requestPurchase(player: Player, kind: any, key: any)
	if (kind ~= "Product" and kind ~= "GamePass") or not Validate.shortString(key, 40) then
		return
	end
	local mode = storeMode()

	if kind == "Product" then
		local product = MonetizationConfig.Products[key]
		if not product then
			return
		end
		if mode == "Test" then
			task.spawn(simulateProductPurchase, player, product)
		elseif mode == "Live" and product.Id ~= 0 then
			MarketplaceService:PromptProductPurchase(player, product.Id)
		else
			Notify.player(player, "The store opens soon!", "info")
		end
		return
	end

	local pass = MonetizationConfig.GamePasses[key]
	if not pass then
		return
	end
	if MonetizationService.OwnsPass(player, key) then
		Notify.player(player, "You already own " .. pass.Name .. ".", "info")
	elseif mode == "Test" then
		if workspace:GetAttribute("StoreTest_Decline") == true then
			Notify.player(player, "[TEST] Purchase cancelled — nothing granted.", "warning")
			return
		end
		-- simulated ownership is a Studio-server attribute, never stored in player data
		workspace:SetAttribute("StoreTest_OwnPass_" .. key, true)
		Notify.player(player, "[TEST] " .. pass.Name .. " ownership simulated for this Studio session.", "success")
	elseif mode == "Live" and pass.Id ~= 0 then
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	else
		Notify.player(player, "The store opens soon!", "info")
	end
end

function MonetizationService.Init()
	for _, problem in MonetizationConfig.validate() do
		warn("[MonetizationService] config: " .. problem)
	end
	ReplicatedStorage:SetAttribute("StoreMode", storeMode())
end

function MonetizationService.Start()
	-- Set unconditionally: receipts for products that aren't configured stay pending
	-- (never lost) instead of being dropped by a missing handler.
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = MonetizationConfig.passById(passId)
		if not pass or not purchased then
			return
		end
		-- Server-side signal from Roblox (not the client): grant for this session now,
		-- then confirm via the ownership API, which can lag a few seconds.
		setOwned(player, pass.Key, true)
		Notify.player(player, "✅ " .. pass.Name .. " unlocked — thank you!", "success")
		task.delay(10, function()
			if player.Parent and checkOwnership(player, pass) then
				setOwned(player, pass.Key, true)
			end
		end)
	end)

	local function onPlayer(player: Player)
		passOwnership[player] = {}
		refreshPasses(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		passOwnership[player] = nil
	end)

	if TEST_MODE then
		for key in MonetizationConfig.GamePasses do
			workspace:GetAttributeChangedSignal("StoreTest_OwnPass_" .. key):Connect(function()
				for _, player in Players:GetPlayers() do
					if passOwnership[player] then
						setOwned(player, key, workspace:GetAttribute("StoreTest_OwnPass_" .. key) == true)
					end
				end
			end)
		end
		warn("[MonetizationService] STUDIO TEST STORE active: purchases are simulated, no Robux involved.")
	end

	Net.handle("RequestPurchase", 2, 3, requestPurchase)
end

return MonetizationService
