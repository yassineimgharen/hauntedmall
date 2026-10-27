--!strict
-- Idempotent developer-product receipt processing.
--
-- Free of Roblox services on purpose: every dependency is injected, so the exact logic that
-- runs in game is unit-tested outside Studio (tests/ReceiptProcessor.spec.luau, via Lune).
--
-- Guarantees:
--   1. A PurchaseId is granted at most once. The grant and the PurchaseId record are applied
--      to the same profile table in one non-yielding step, so they are saved together.
--   2. "Granted" is returned only after that profile write has reached the DataStore.
--      If the save fails, the receipt stays pending (NotProcessedYet) and Roblox retries;
--      the retry finds the id already recorded in memory and only re-attempts the save.
--   3. Concurrent calls for the same PurchaseId never both grant (in-flight guard).
--   4. Unknown products, absent players and unloaded profiles never grant: they stay pending
--      so nothing is lost (Roblox re-delivers when the player is back / the Id is configured).

export type Decision = "Granted" | "NotProcessedYet"

export type Receipt = {
	PurchaseId: string,
	PlayerId: number,
	ProductId: number,
	CurrencySpent: number?,
	ProductKey: string?, -- simulated (Studio test) receipts only
}

export type Product = { Key: string, Id: number, Grant: { [string]: any } }

export type Deps = {
	ledger: string, -- profile field holding processed ids: "ProcessedReceipts" | "TestReceipts"
	test: boolean,
	getPlayer: (userId: number) -> any?,
	getData: (player: any) -> { [string]: any }?, -- may yield while the profile loads
	isActive: (player: any, data: { [string]: any }) -> boolean,
	findProduct: (receipt: Receipt) -> Product?,
	grant: (player: any, data: { [string]: any }, product: Product) -> boolean, -- must not yield
	saveNow: (player: any) -> boolean,
	now: () -> number,
	log: (message: string) -> (),
	limits: { MaxReceipts: number, RetentionDays: number, MaxHistory: number },
}

export type Processor = {
	deps: Deps,
	inFlight: { [string]: boolean },
	unsaved: { [string]: boolean },
	process: (self: Processor, receipt: Receipt) -> (Decision, boolean),
}

local ReceiptProcessor = {}
ReceiptProcessor.__index = ReceiptProcessor

function ReceiptProcessor.new(deps: Deps): Processor
	local self = setmetatable({
		deps = deps,
		inFlight = {},
		unsaved = {},
	}, ReceiptProcessor)
	return (self :: any) :: Processor
end

local function prune(
	ledger: { [string]: number },
	keep: string,
	limits: { MaxReceipts: number, RetentionDays: number },
	now: number
)
	local count = 0
	for _ in ledger do
		count += 1
	end
	if count <= limits.MaxReceipts then
		return
	end
	local cutoff = now - limits.RetentionDays * 86400
	for id, at in ledger do
		if id ~= keep and type(at) == "number" and at < cutoff then
			ledger[id] = nil
		end
	end
end

local function recordHistory(data: { [string]: any }, product: Product, receipt: Receipt, deps: Deps)
	local history = data.PurchaseHistory
	if type(history) ~= "table" then
		history = {}
		data.PurchaseHistory = history
	end
	table.insert(history, {
		Key = product.Key,
		ProductId = receipt.ProductId,
		Robux = receipt.CurrencySpent or 0,
		At = deps.now(),
		Test = deps.test,
	})
	while #history > deps.limits.MaxHistory do
		table.remove(history, 1)
	end
end

-- Returns the decision and whether this call performed a fresh grant (for confirmations).
function ReceiptProcessor._process(self: Processor, receipt: Receipt): (Decision, boolean)
	local deps = self.deps
	local id = receipt.PurchaseId

	local player = deps.getPlayer(receipt.PlayerId)
	if not player then
		return "NotProcessedYet", false -- re-delivered when they next join
	end
	local data = deps.getData(player)
	if not data then
		return "NotProcessedYet", false
	end
	local ledger = data[deps.ledger]
	if type(ledger) ~= "table" then
		ledger = {}
		data[deps.ledger] = ledger
	end

	if ledger[id] ~= nil then
		if self.unsaved[id] then
			-- granted in memory earlier, but that save failed: only retry the save
			if deps.saveNow(player) then
				self.unsaved[id] = nil
				return "Granted", false
			end
			return "NotProcessedYet", false
		end
		return "Granted", false -- duplicate delivery of an already-persisted receipt
	end

	local product = deps.findProduct(receipt)
	if not product then
		deps.log(string.format("unknown product %s for receipt %s; left pending", tostring(receipt.ProductId), id))
		return "NotProcessedYet", false
	end
	if not deps.isActive(player, data) then
		return "NotProcessedYet", false -- profile released or session lost mid-purchase
	end

	-- Grant and record together: no yields between these lines.
	if not deps.grant(player, data, product) then
		deps.log("grant failed for " .. id .. "; left pending")
		return "NotProcessedYet", false
	end
	ledger[id] = deps.now()
	recordHistory(data, product, receipt, deps)
	prune(ledger, id, deps.limits, deps.now())

	if deps.saveNow(player) then
		return "Granted", true
	end
	self.unsaved[id] = true
	deps.log("save failed after granting " .. id .. "; pending until a save succeeds")
	return "NotProcessedYet", true
end

function ReceiptProcessor.process(self: Processor, receipt: Receipt): (Decision, boolean)
	local id = receipt.PurchaseId
	if type(id) ~= "string" or id == "" then
		return "NotProcessedYet", false
	end
	if self.inFlight[id] then
		return "NotProcessedYet", false -- same receipt already being handled; Roblox will retry
	end
	self.inFlight[id] = true
	local ok, decision, fresh = pcall(ReceiptProcessor._process, self, receipt)
	self.inFlight[id] = nil
	if not ok then
		self.deps.log("receipt " .. id .. " errored: " .. tostring(decision))
		return "NotProcessedYet", false
	end
	return decision :: Decision, fresh :: boolean
end

return ReceiptProcessor
