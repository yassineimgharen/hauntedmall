-- Shows each shop prompt only to the players it applies to (claim → players without a
-- shop, restock/serve → the owner). Purely cosmetic: the server re-checks everything.
-- Also answers "What's this?" info prompts (closed storefronts) locally, with no server call,
-- and shows mission "CarryPrompt"s only while you carry the item they need.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local EconomyConfig = require(game:GetService("ReplicatedStorage").Shared.Config.EconomyConfig)
local LocalEvents = require(script.Parent.Parent.LocalEvents)

local PromptController = {}

local player = Players.LocalPlayer

type Entry = { Prompt: ProximityPrompt, Shop: Instance, Kind: string }

local entries: { Entry } = {}

local function refresh()
	local myShop = player:GetAttribute("ShopId")
	for _, entry in entries do
		local owner = entry.Shop:GetAttribute("OwnerUserId")
		local mine = owner == player.UserId
		if entry.Kind == "Claim" then
			entry.Prompt.Enabled = owner == 0 and myShop == nil
		elseif entry.Kind == "Restock" then
			entry.Prompt.Enabled = mine
		elseif entry.Kind == "Serve" then
			entry.Prompt.Enabled = mine and (entry.Shop:GetAttribute("CustomersWaiting") or 0) > 0
		end
	end
end

local function bindInfo(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function()
			LocalEvents.Notify:Fire(prompt:GetAttribute("InfoText") or "Coming soon!", "info")
		end)
	end
end

local carryPrompts: { [ProximityPrompt]: boolean } = {}

local function refreshCarry()
	local carrying = player:GetAttribute("Carrying")
	local myShop = player:GetAttribute("ShopId")
	for prompt in carryPrompts do
		local shop = prompt:GetAttribute("RequiresShop") -- only the owner builds at their shop
		prompt.Enabled = carrying ~= nil
			and prompt:GetAttribute("RequiresCarry") == carrying
			and not prompt:GetAttribute("Done")
			and (shop == nil or shop == myShop)
	end
end

local function bindCarry(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		carryPrompts[prompt] = true
		prompt:GetAttributeChangedSignal("Done"):Connect(refreshCarry)
		refreshCarry()
	end
end

-- A locker someone else is hiding in shows no prompt to you.
local function bindLocker(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local function refreshLocker()
		local occupant = prompt:GetAttribute("Occupant") or 0
		prompt.Enabled = occupant == 0 or occupant == player.UserId
	end
	prompt:GetAttributeChangedSignal("Occupant"):Connect(refreshLocker)
	refreshLocker()
end

function PromptController.Start()
	for _, prompt in CollectionService:GetTagged("LockerPrompt") do
		bindLocker(prompt)
	end
	CollectionService:GetInstanceAddedSignal("LockerPrompt"):Connect(bindLocker)

	for _, prompt in CollectionService:GetTagged("CarryPrompt") do
		bindCarry(prompt)
	end
	CollectionService:GetInstanceAddedSignal("CarryPrompt"):Connect(bindCarry)
	CollectionService:GetInstanceRemovedSignal("CarryPrompt"):Connect(function(prompt)
		carryPrompts[prompt :: ProximityPrompt] = nil
	end)
	player:GetAttributeChangedSignal("Carrying"):Connect(refreshCarry)
	player:GetAttributeChangedSignal("ShopId"):Connect(refreshCarry)

	for _, prompt in CollectionService:GetTagged("InfoPrompt") do
		bindInfo(prompt)
	end
	CollectionService:GetInstanceAddedSignal("InfoPrompt"):Connect(bindInfo)

	local restock = EconomyConfig.Restock
	for _, shop in CollectionService:GetTagged("Shop") do
		for _, descendant in shop:GetDescendants() do
			if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("PromptKind") then
				local kind = descendant:GetAttribute("PromptKind") :: string
				if kind == "Restock" then
					descendant.ObjectText =
						string.format("$%d for %d", restock.Units * restock.CostPerUnit, restock.Units)
				end
				table.insert(entries, { Prompt = descendant, Shop = shop, Kind = kind })
			end
		end
		shop:GetAttributeChangedSignal("OwnerUserId"):Connect(refresh)
		shop:GetAttributeChangedSignal("CustomersWaiting"):Connect(refresh)
	end
	player:GetAttributeChangedSignal("ShopId"):Connect(refresh)
	refresh()
end

return PromptController
