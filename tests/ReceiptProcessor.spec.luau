-- Unit tests for the receipt processor, run outside Roblox with Lune:
--   .tools/bin/lune run tests/ReceiptProcessor.spec.luau     (also part of scripts/check.sh)
-- The processor is the same module the game uses; only its dependencies are faked here.

local process = require("@lune/process")
local ReceiptProcessor = require("../src/server/Monetization/ReceiptProcessor")

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ✓ " .. name)
	else
		failed += 1
		print("  ✗ " .. name .. "\n      " .. tostring(err))
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
	end
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

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

-- Fake world: players, profiles, a "DataStore" snapshot per user, and switchable failures.
local function world(ledger: string?)
	local w = {
		players = {} :: { [number]: any },
		data = {} :: { [any]: any },
		active = {} :: { [any]: boolean },
		store = {} :: { [number]: any },
		saves = 0,
		saveOk = true,
		logs = {} :: { string },
		clock = 1_000_000_000,
		products = { [101] = { Key = "CashSmall", Id = 101, Grant = { Cash = 500 } } },
	}
	function w.join(userId: number)
		local player = { UserId = userId }
		w.players[userId] = player
		w.data[player] = deepCopy(w.store[userId])
			or { Cash = 0, ProcessedReceipts = {}, TestReceipts = {}, PurchaseHistory = {} }
		w.active[player] = true
		return player
	end
	function w.leave(player: any, saveSucceeds: boolean)
		w.active[player] = false
		w.players[player.UserId] = nil
		if saveSucceeds then
			w.store[player.UserId] = deepCopy(w.data[player])
		end
	end
	w.deps = {
		ledger = ledger or "ProcessedReceipts",
		test = ledger == "TestReceipts",
		getPlayer = function(id)
			return w.players[id]
		end,
		getData = function(player)
			return w.data[player]
		end,
		isActive = function(player, data)
			return w.active[player] == true and w.data[player] == data
		end,
		findProduct = function(receipt)
			return w.products[receipt.ProductId]
		end,
		grant = function(_player, data, product)
			data.Cash += product.Grant.Cash
			return true
		end,
		saveNow = function(player)
			w.saves += 1
			if w.saveOk then
				w.store[player.UserId] = deepCopy(w.data[player])
			end
			return w.saveOk
		end,
		now = function()
			return w.clock
		end,
		log = function(message)
			table.insert(w.logs, message)
		end,
		limits = { MaxReceipts = 300, RetentionDays = 60, MaxHistory = 50 },
	}
	return w
end

local function receipt(id: string, userId: number?, productId: number?)
	return { PurchaseId = id, PlayerId = userId or 1, ProductId = productId or 101, CurrencySpent = 29 }
end

print("ReceiptProcessor")

test("successful purchase grants once and is persisted before acknowledging", function()
	local w = world()
	local p = w.join(1)
	local rp = ReceiptProcessor.new(w.deps)
	local decision, fresh = rp:process(receipt("A"))
	eq(decision, "Granted", "decision")
	eq(fresh, true, "fresh")
	eq(w.data[p].Cash, 500, "cash")
	eq(w.store[1].Cash, 500, "persisted cash")
	eq(w.store[1].ProcessedReceipts.A ~= nil, true, "persisted receipt id")
	eq(#w.data[p].PurchaseHistory, 1, "history entry")
end)

test("duplicate delivery of the same receipt never grants twice", function()
	local w = world()
	local p = w.join(1)
	local rp = ReceiptProcessor.new(w.deps)
	rp:process(receipt("A"))
	local savesBefore = w.saves
	local decision, fresh = rp:process(receipt("A"))
	eq(decision, "Granted", "decision")
	eq(fresh, false, "fresh")
	eq(w.data[p].Cash, 500, "cash unchanged")
	eq(w.saves, savesBefore, "no extra save")
end)

test("duplicate receipt after rejoining (new server) is acknowledged without regranting", function()
	local w = world()
	local p = w.join(1)
	ReceiptProcessor.new(w.deps):process(receipt("A"))
	w.leave(p, true)
	local p2 = w.join(1)
	local decision = ReceiptProcessor.new(w.deps):process(receipt("A"))
	eq(decision, "Granted", "decision")
	eq(w.data[p2].Cash, 500, "cash restored once")
end)

test("unknown product stays pending and grants nothing", function()
	local w = world()
	local p = w.join(1)
	local decision = ReceiptProcessor.new(w.deps):process(receipt("A", 1, 999))
	eq(decision, "NotProcessedYet", "decision")
	eq(w.data[p].Cash, 0, "cash")
	eq(count(w.data[p].ProcessedReceipts), 0, "ledger empty")
end)

test("player not in the server: pending, then granted once when they are back", function()
	local w = world()
	local rp = ReceiptProcessor.new(w.deps)
	eq(rp:process(receipt("A")), "NotProcessedYet", "while absent")
	local p = w.join(1)
	eq(rp:process(receipt("A")), "Granted", "after join")
	eq(w.data[p].Cash, 500, "cash")
end)

test("profile not loaded yet: pending", function()
	local w = world()
	w.players[1] = { UserId = 1 } -- in game, but no profile yet
	eq(ReceiptProcessor.new(w.deps):process(receipt("A")), "NotProcessedYet", "decision")
end)

test("DataStore failure: not acknowledged; retries never regrant; acknowledged once saved", function()
	local w = world()
	local p = w.join(1)
	local rp = ReceiptProcessor.new(w.deps)
	w.saveOk = false
	local decision, fresh = rp:process(receipt("A"))
	eq(decision, "NotProcessedYet", "first attempt")
	eq(fresh, true, "granted in memory")
	eq(rp:process(receipt("A")), "NotProcessedYet", "retry while store still failing")
	eq(w.data[p].Cash, 500, "still granted exactly once")
	w.saveOk = true
	eq(rp:process(receipt("A")), "Granted", "retry after recovery")
	eq(w.data[p].Cash, 500, "no double grant")
	eq(w.store[1].Cash, 500, "persisted")
end)

test("save fails, player leaves (leave-save succeeds): next session acknowledges without regrant", function()
	local w = world()
	local p = w.join(1)
	w.saveOk = false
	ReceiptProcessor.new(w.deps):process(receipt("A"))
	w.leave(p, true)
	w.saveOk = true
	local p2 = w.join(1)
	eq(ReceiptProcessor.new(w.deps):process(receipt("A")), "Granted", "decision")
	eq(w.data[p2].Cash, 500, "granted exactly once")
end)

test("save fails and leave-save fails too: grant is lost with its record, then re-granted once", function()
	local w = world()
	local p = w.join(1)
	w.saveOk = false
	ReceiptProcessor.new(w.deps):process(receipt("A"))
	w.leave(p, false)
	w.saveOk = true
	local p2 = w.join(1)
	eq(ReceiptProcessor.new(w.deps):process(receipt("A")), "Granted", "decision")
	eq(w.data[p2].Cash, 500, "player still receives the purchase")
end)

test("player leaves mid-purchase (profile released): pending, granted once next session", function()
	local w = world()
	local p = w.join(1)
	local deps = table.clone(w.deps)
	deps.getData = function(player)
		local data = w.data[player]
		w.leave(player, true) -- leaves while the receipt is being handled
		return data
	end
	eq(ReceiptProcessor.new(deps):process(receipt("A")), "NotProcessedYet", "during leave")
	eq(w.data[p].Cash, 0, "nothing granted to the released profile")
	local p2 = w.join(1)
	eq(ReceiptProcessor.new(w.deps):process(receipt("A")), "Granted", "next session")
	eq(w.data[p2].Cash, 500, "granted once")
end)

test("concurrent delivery of the same receipt grants once", function()
	local w = world()
	local p = w.join(1)
	local deps = table.clone(w.deps)
	deps.saveNow = function(player)
		coroutine.yield() -- simulate a slow DataStore write
		return w.deps.saveNow(player)
	end
	local rp = ReceiptProcessor.new(deps)
	local first = coroutine.create(function()
		return rp:process(receipt("A"))
	end)
	coroutine.resume(first) -- suspended inside saveNow
	eq(rp:process(receipt("A")), "NotProcessedYet", "second concurrent call")
	local _, decision = coroutine.resume(first)
	eq(decision, "Granted", "first call completes")
	eq(w.data[p].Cash, 500, "granted once")
end)

test("concurrent different receipts for one player both grant", function()
	local w = world()
	local p = w.join(1)
	local rp = ReceiptProcessor.new(w.deps)
	eq(rp:process(receipt("A")), "Granted", "A")
	eq(rp:process(receipt("B")), "Granted", "B")
	eq(w.data[p].Cash, 1000, "both granted")
end)

test("test-mode ledger is separate from real receipts", function()
	local w = world("TestReceipts")
	local p = w.join(1)
	eq(ReceiptProcessor.new(w.deps):process(receipt("TEST-1")), "Granted", "decision")
	eq(count(w.data[p].TestReceipts), 1, "test ledger")
	eq(count(w.data[p].ProcessedReceipts), 0, "real ledger untouched")
	eq(w.data[p].PurchaseHistory[1].Test, true, "history marks test")
end)

test("failed grant records nothing", function()
	local w = world()
	local p = w.join(1)
	local deps = table.clone(w.deps)
	deps.grant = function()
		return false
	end
	eq(ReceiptProcessor.new(deps):process(receipt("A")), "NotProcessedYet", "decision")
	eq(count(w.data[p].ProcessedReceipts), 0, "ledger empty")
end)

test("errors are contained and do not leave the receipt locked", function()
	local w = world()
	local p = w.join(1)
	local deps = table.clone(w.deps)
	local explode = true
	deps.findProduct = function(r)
		if explode then
			error("boom")
		end
		return w.products[r.ProductId]
	end
	local rp = ReceiptProcessor.new(deps)
	eq(rp:process(receipt("A")), "NotProcessedYet", "errored call")
	explode = false
	eq(rp:process(receipt("A")), "Granted", "next attempt works")
	eq(w.data[p].Cash, 500, "cash")
end)

test("invalid purchase ids are rejected", function()
	local w = world()
	w.join(1)
	eq(ReceiptProcessor.new(w.deps):process(receipt("")), "NotProcessedYet", "empty id")
end)

test("ledger pruning drops only old ids beyond the cap", function()
	local w = world()
	local p = w.join(1)
	local ledger = w.data[p].ProcessedReceipts
	for i = 1, 300 do
		ledger["old" .. i] = w.clock - 90 * 86400
	end
	ledger.recent = w.clock - 86400
	eq(ReceiptProcessor.new(w.deps):process(receipt("A")), "Granted", "decision")
	eq(ledger.old1, nil, "old pruned")
	eq(ledger.recent ~= nil, true, "recent kept")
	eq(ledger.A ~= nil, true, "new kept")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
