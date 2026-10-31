-- What a player learns from the level's on-screen hints, for objectives the generic
-- marker-following can't do alone (puzzles, bosses, escorts). Strategies use only things a
-- client can see: prompts, tags, replicated attributes, toasts, part colours.

local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Vector3 = roblox.Vector3
local Color3 = roblox.Color3

local Strategies: { [string]: any } = {}

local function byTag(bot: any, tag: string, keep: ((any) -> boolean)?): { any }
	local list = {}
	for _, part in bot.World.CollectionService:GetTagged(tag) do
		if not keep or keep(part) then
			table.insert(list, part)
		end
	end
	return list
end

local function nearestOf(bot: any, parts: { any }): any
	local best, bestDistance = nil, math.huge
	local p = bot:position()
	for _, part in parts do
		local d = (part.Position - p).Magnitude
		if d < bestDistance then
			best, bestDistance = part, d
		end
	end
	return best
end

local function huntOrWait(bot: any)
	if not bot:hunt() then
		bot:wait(0.5)
	end
end

-- ── Chapter 1 ───────────────────────────────────────────────────────────────

Strategies.L01 = {
	Day = {
		upgrade = function(bot: any)
			-- Press B and buy the cheapest upgrade you can afford; keep the shop running meanwhile.
			bot.World:clientFire(bot.Player, "PurchaseUpgrade", "Shelves")
			bot:wait(0.4)
			local target = bot:shopTarget()
			if target then
				bot:useTarget(target, "SHOP")
			else
				bot:wait(1)
			end
		end,
	},
	Night = {
		equip = function(bot: any)
			bot:equip()
			bot:wait(0.5)
		end,
		burn = huntOrWait,
	},
}

Strategies.L02 = {
	Night = {
		Reflex = function(_bot: any)
			return false
		end,
	},
}

local function shopperModels(bot: any): { any }
	local list = {}
	local folder = bot.World.Workspace:FindFirstChild("ImpostorsNight")
		or bot.World.Workspace:FindFirstChild("NightShoppers")
	for _, child in (folder and folder:GetChildren()) or {} do
		if child:IsA("Model") and child:FindFirstChild("HumanoidRootPart") then
			table.insert(list, child)
		end
	end
	return list
end

Strategies.L03 = {
	Night = {
		phantoms = function(bot: any)
			-- Burn unmasked phantoms; otherwise shine on the shopper you've suspected least.
			if bot:hunt() then
				return
			end
			bot.Lit = bot.Lit or {}
			local best, bestAt = nil, math.huge
			for _, model in shopperModels(bot) do
				local at = bot.Lit[model] or 0
				if at < bestAt then
					best, bestAt = model, at
				end
			end
			if not best then
				bot:wait(1)
				return
			end
			bot.Lit[best] = bot.World.Now
			local root = best:FindFirstChild("HumanoidRootPart")
			if
				not bot:walkTo(root.Position, 12, nil, function()
					return not best.Parent or ((root.Position - bot:position()).Magnitude < 24 and bot:sees(root))
				end)
			then
				return
			end
			local stop = bot.World.Now + 1.8
			bot:shine(function()
				return if best.Parent and root.Parent then root.Position else nil
			end, function()
				return bot.World.Now >= stop or not best.Parent
			end, 2)
		end,
	},
}

-- Night: every player goes where the attackers are, spreading out over the strike groups.
local function defendTerminals(bot: any)
	local list = {}
	for _, enemy in bot:enemies() do
		if not enemy.Dead then
			table.insert(list, enemy)
		end
	end
	if #list == 0 then
		bot:wait(0.5)
		return
	end
	table.sort(list, function(a, b)
		return a.Root.Position.X < b.Root.Position.X
	end)
	local enemy = list[(bot.Index - 1) % #list + 1]
	if (enemy.Root.Position - bot:position()).Magnitude > 16 or not bot:sees(enemy.Root) then
		bot:walkTo(enemy.Root.Position, 10, nil, function()
			return enemy.Dead or ((enemy.Root.Position - bot:position()).Magnitude < 24 and bot:sees(enemy.Root))
		end)
	end
	bot:fight(30)
end

Strategies.L04 = { Night = { Idle = defendTerminals } }

local function vaultCode(bot: any): string?
	local rs = bot.World.ReplicatedStorage
	local cards = rs:GetAttribute("VaultCards")
	local order = rs:GetAttribute("VaultOrder")
	if not cards or not order then
		return nil
	end
	local map = serde.decode("json", cards)
	local code = ""
	for color in string.gmatch(order, "[^,]+") do
		if map[color] == nil then
			return nil
		end
		code ..= tostring(map[color])
	end
	return code
end

Strategies.L05 = {
	Day = {
		code = function(bot: any)
			local target = nearestOf(bot, byTag(bot, "VaultKeypad"))
			if not target then
				bot:wait(1)
				return
			end
			for _, prompt in bot:promptsFor(target) do
				if bot:usable(prompt) then
					bot:hold(prompt)
					break
				end
			end
			local code = vaultCode(bot)
			if code then
				bot.World:clientFire(bot.Player, "SubmitCode", code)
			end
			bot:wait(1.2)
		end,
	},
	Night = {
		Reflex = function(bot: any)
			bot.SpeedCap = 7 -- sneak (the client's sneak toggle): the Stalker tracks sound
			return false
		end,
	},
}

Strategies.L06 = {
	Night = (function()
		local EVAC = Vector3.new(0, 0, -62)
		local function nextShopper(bot: any): any
			local folder = bot.World.Workspace:FindFirstChild("RescueNight")
			local prompts = {}
			for _, d in (folder and folder:GetDescendants()) or {} do
				if d:IsA("ProximityPrompt") and d.Enabled and d.Name == "RescuePrompt" then
					table.insert(prompts, d)
				end
			end
			local best, bestD = nil, math.huge
			for _, prompt in prompts do
				local d = (prompt.Parent.Position - bot:position()).Magnitude
				if d < bestD then
					best, bestD = prompt, d
				end
			end
			return best
		end
		local function waitAtEvac(bot: any)
			bot.SpeedCap = nil
			if bot.Player:GetAttribute("EvacMustWalk") then
				-- just respawned beside the ring: the van wants you to have come back to it
				bot:walkTo(EVAC + Vector3.new(0, 0, 34), 3)
				return
			end
			if (bot:position() - EVAC).Magnitude > 8 then
				bot:walkTo(EVAC, 3)
			end
			if not bot:fight(10) then -- defend the ring, but don't leave it: the van won't wait
				bot:wait(0.5)
			end
		end
		return {
			rescue = function(bot: any)
				local before = bot:row("rescue") and bot:row("rescue").Progress or 0
				local prompt = nextShopper(bot)
				if not prompt then
					waitAtEvac(bot)
					return
				end
				if not bot:hold(prompt) then
					return
				end
				-- lead them back at a pace they can follow (they walk at 15)
				bot.SpeedCap = 13.5
				local npc = prompt.Parent
				bot:walkTo(EVAC, 3, nil, function()
					-- wait for a shopper who fell behind
					return npc.Parent ~= nil and (npc.Position - bot:position()).Magnitude > 22
				end)
				local stop = bot.World.Now + 25
				while bot.World.Now < stop and bot:root() and npc.Parent do
					local row = bot:row("rescue")
					if row and row.Progress > before then
						break
					end
					if (npc.Position - bot:position()).Magnitude > 16 then
						bot:wait(0.5)
					else
						bot:walkTo(EVAC, 3)
						bot:fight(14)
						bot:wait(0.3)
					end
				end
				bot.SpeedCap = nil
			end,
			escape = waitAtEvac,
			Idle = waitAtEvac,
		}
	end)(),
}

Strategies.L07 = {
	Day = {
		cannons = function(bot: any)
			-- "Stand inside a cannon's ring until it's fully charged."
			local ring = nearestOf(
				bot,
				byTag(bot, "LightCannon", function(part)
					return not part:GetAttribute("Done")
				end)
			)
			if not ring then
				bot:wait(1)
				return
			end
			bot:walkTo(ring.Position, 4.5) -- anywhere inside the 6-stud ring, beside the cannon
			local stop = bot.World.Now + 25
			while bot.World.Now < stop and bot:root() and not ring:GetAttribute("Done") do
				bot:wait(0.5)
			end
		end,
		mirrors = function(bot: any)
			-- One player works a puzzle, as a team would (the concurrent case has its own test).
			if bot.Index ~= 1 and not bot.Scramble then
				bot:wait(1)
				return
			end
			-- Turn mirrors and watch the beam, trying each combination in turn (Gray code).
			bot.MirrorStep = (bot.MirrorStep or 0) + 1
			local mirrors = byTag(bot, "Mirror")
			if #mirrors == 0 then
				bot:wait(1)
				return
			end
			local step, index = bot.MirrorStep, 1
			while step % 2 == 0 and index < #mirrors do
				step //= 2
				index += 1
			end
			local prompt = bot:promptsFor(mirrors[index])[1]
			if prompt and bot:usable(prompt) then
				bot:hold(prompt)
			end
		end,
	},
	Night = {
		queen = function(bot: any)
			local world = bot.World
			local state = world.ReplicatedStorage:GetAttribute("BossShield")
			local arena = world.Workspace:FindFirstChild("QueenArena")
			local queen = arena and arena:FindFirstChild("ShadowQueen")
			if not queen then
				bot:wait(0.5)
				return
			end
			if state == "Down" or state == "Returning" then
				local part = queen:FindFirstChild("WeakpointThorax") or queen:FindFirstChild("WeakpointHead", true)
				if not part then
					bot:wait(0.5)
					return
				end
				if (part.Position - bot:position()).Magnitude > 30 then
					bot:walkTo(part.Position, 22)
				end
				bot:shine(function()
					return part.Position
				end, function()
					local s = world.ReplicatedStorage:GetAttribute("BossShield")
					return s ~= "Down" and s ~= "Returning"
				end, 4)
				return
			end
			-- shielded: the arrow leads to a ready cannon
			local target = bot:markerTarget(bot:focusRow())
			if target then
				local fired = false
				for _, prompt in bot:promptsFor(target) do
					if prompt.Name == "FirePrompt" and bot:usable(prompt) then
						bot:hold(prompt)
						fired = true
						break
					end
				end
				if not fired then
					if not bot:fight(25) then
						bot:wait(0.5)
					end
				end
			else
				if not bot:fight(25) then
					bot:wait(0.5)
				end
			end
		end,
	},
}

-- ── Chapter 2 ───────────────────────────────────────────────────────────────

local function parcelCall(bot: any, parcel: any, wrong: boolean?): boolean
	-- Inspect, shine, read the label, decide (`wrong` makes the wrong call on purpose).
	local inspect, deliver, quarantine = nil, nil, nil
	for _, prompt in bot:promptsFor(parcel) do
		if prompt.ActionText == "Inspect" then
			inspect = prompt
		elseif prompt.ActionText == "Deliver" then
			deliver = prompt
		elseif prompt.ActionText == "Quarantine" then
			quarantine = prompt
		end
	end
	if inspect and bot:usable(inspect) then
		if not bot:hold(inspect) then
			return false
		end
	end
	local gui = parcel:FindFirstChildOfClass("BillboardGui")
	local text = gui and gui:FindFirstChild("TextLabel", true)
	local function label(): string
		return if text then text.Text else ""
	end
	if label():find("Shine your flashlight", 1, true) then
		bot:shine(function()
			return parcel.Position
		end, function()
			return not label():find("Shine your flashlight", 1, true)
		end, 4)
	end
	local infected = label():find("HANDPRINT", 1, true) ~= nil
	local choose = if infected ~= (wrong == true) then quarantine else deliver
	local stop = bot.World.Now + 4
	while bot.World.Now < stop and choose and not bot:usable(choose) do
		bot:wait(0.2)
	end
	if choose and bot:usable(choose) then
		return bot:hold(choose)
	end
	return false
end
Strategies.parcelCall = parcelCall

Strategies.L10 = {
	Day = {
		sort = function(bot: any)
			local target = bot:markerTarget(bot:focusRow())
			if target then
				parcelCall(bot, target)
			else
				bot:wait(0.5)
			end
		end,
	},
}

local function warmUp(bot: any): boolean
	local cold = bot.Player:GetAttribute("Meter_Cold")
	if type(cold) == "number" and (cold > 0.7 or (bot.Warming and cold > 0.15)) then
		bot.Warming = true
		local lamp = nearestOf(bot, byTag(bot, "HeatLamp"))
		if lamp then
			bot:walkTo(lamp.Position, 5)
			bot:wait(0.5)
			return true
		end
	end
	bot.Warming = false
	return false
end

Strategies.L11 = {
	Day = {
		Reflex = warmUp,
		open = function(bot: any)
			local target = nearestOf(
				bot,
				byTag(bot, "FrozenLever", function(part)
					return not part:GetAttribute("Done")
				end)
			)
			if not target then
				bot:wait(1)
				return
			end
			local ice = target.Parent:FindFirstChild("Ice")
			if ice then
				-- "melt the ice off the lever with your flashlight"
				bot:walkTo(ice.Position, nil, 14)
				bot:shine(function()
					return if ice.Parent then ice.Position else nil
				end, function()
					return ice.Parent == nil
				end, 9)
				return
			end
			for _, prompt in bot:promptsFor(target) do
				if bot:usable(prompt) then
					bot:hold(prompt)
				end
			end
		end,
	},
	Night = {
		Reflex = warmUp,
	},
}

Strategies.L12 = {
	Day = {
		anomalies = function(bot: any)
			-- The 📡 meter leads a player here; the bot knows the spots and walks there.
			local spot = nearestOf(
				bot,
				byTag(bot, "Anomaly", function(part)
					return not part:GetAttribute("Done")
				end)
			)
			if not spot then
				bot:wait(1)
				return
			end
			if not bot:walkTo(spot.Position, nil, 6) then
				if bot:root() then
					bot:fail("can't reach anomaly at " .. tostring(spot.Position))
				end
				bot:wait(2)
				return
			end
			bot:wait(0.5)
			for _, prompt in bot:promptsFor(spot) do
				if bot:usable(prompt) then
					bot:hold(prompt)
				end
			end
		end,
	},
}

Strategies.L13 = {
	Day = {
		airflow = function(bot: any)
			if bot.Index ~= 1 and not bot.Scramble then
				bot:wait(1)
				return
			end
			-- Read the five gauges (green = open), work out the flips, pull the levers.
			local world = bot.World
			local rules = world:require("Levels.FoodCourtRules")
			local panel = world.Workspace:FindFirstChild("AirflowPanel", true)
			if not panel then
				bot:wait(1)
				return
			end
			local gauges, handles = {}, {}
			for _, part in panel:GetChildren() do
				if part:IsA("BasePart") and part.Size == Vector3.new(2.2, 1.6, 0.1) then
					table.insert(gauges, part)
				elseif part.Name == "Damper" then
					table.insert(handles, part)
				end
			end
			-- the panel's own left-to-right order: index = (x - offset), same as the code builds
			local origin = panel:FindFirstChild("Board").Position
			local function along(part: any): number
				return (part.Position - origin).X
			end
			table.sort(gauges, function(a, b)
				return along(a) > along(b)
			end)
			table.sort(handles, function(a, b)
				return along(a) > along(b)
			end)
			local green = Color3.fromRGB(84, 255, 164)
			local vents = {}
			for i, gauge in gauges do
				vents[i] = gauge.Color == green
			end
			local presses = rules.solveAirflow(vents)
			if not presses or #presses == 0 then
				bot:wait(1)
				return
			end
			local handle = handles[presses[1]]
			local prompt = bot:promptsFor(handle)[1]
			if prompt and bot:usable(prompt) then
				bot:hold(prompt)
			else
				bot:walkNear(handle, 5)
				bot:wait(0.5)
			end
		end,
	},
	Night = {
		Reflex = function(bot: any): boolean
			local gas = bot.Player:GetAttribute("Meter_Gas")
			if type(gas) == "number" and gas > 0.6 and bot.World.Now >= (bot.NextBreath or 0) then
				local tank = nearestOf(bot, byTag(bot, "OxygenStation"))
				local prompt = tank and bot:promptsFor(tank)[1]
				if prompt then
					bot:hold(prompt)
					bot.NextBreath = bot.World.Now + 7
					return true
				end
			end
			return false
		end,
	},
}

Strategies.L14 = {
	Night = {
		chef = function(bot: any)
			local world = bot.World
			local rs = world.ReplicatedStorage
			local state = rs:GetAttribute("BossShield")
			local arena = world.Workspace:FindFirstChild("ChefArena")
			local chef = arena and arena:FindFirstChild("GorgingChef")
			if not chef then
				bot:wait(0.5)
				return
			end
			if state == "Sick" then
				local belly = chef:FindFirstChild("WeakpointBelly")
				if (belly.Position - bot:position()).Magnitude > 28 then
					bot:walkTo(belly.Position, 20, nil, function()
						return rs:GetAttribute("BossShield") ~= "Sick"
					end)
				end
				bot:shine(function()
					return belly.Position
				end, function()
					return rs:GetAttribute("BossShield") ~= "Sick"
				end, 4)
				return
			end
			local carrying = bot.Player:GetAttribute("Carrying")
			if rs:GetAttribute("BossPass") ~= "Empty" and carrying ~= "LacedDish" then
				if not bot:fight(25) then
					bot:wait(0.5) -- the laced dish is out: wait for ORDER UP
				end
				return
			end
			local target, label = bot:markerTarget(bot:focusRow())
			if target then
				bot:useTarget(target, label)
			else
				bot:wait(0.5)
			end
		end,
	},
}

return Strategies
