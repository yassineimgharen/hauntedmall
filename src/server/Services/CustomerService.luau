-- NPC shoppers during the day. They walk in from the plaza, browse a shelf, queue at the
-- register and pay the owner. Owners who serve in person earn a tip. At dusk every
-- customer fades into the dark.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local CollisionGroups = require(script.Parent.Parent.Util.CollisionGroups)
local Notify = require(script.Parent.Parent.Util.Notify)
local Layout = require(script.Parent.Parent.World.Layout)
local GameStateService = require(script.Parent.GameStateService)
local ProgressionService = require(script.Parent.ProgressionService)
local ShopService = require(script.Parent.ShopService)

type Customer = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Shop: ShopService.Shop,
	State: "Walking" | "Waiting" | "Paid" | "Leaving",
	Abort: boolean,
	Bubble: TextLabel,
}

local CustomerService = {}

local CFG = EconomyConfig.Customers
local ANIMATIONS = {
	Walk = "rbxassetid://507777826", -- Roblox default R15 walk
	Idle = "rbxassetid://507766388", -- Roblox default R15 idle
}
local SKIN = {
	Color3.fromRGB(255, 220, 177),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(198, 134, 98),
	Color3.fromRGB(141, 85, 54),
	Color3.fromRGB(94, 60, 40),
}
local SHIRTS = {
	Color3.fromRGB(240, 92, 120),
	Color3.fromRGB(80, 160, 240),
	Color3.fromRGB(250, 200, 70),
	Color3.fromRGB(120, 210, 140),
	Color3.fromRGB(170, 120, 230),
	Color3.fromRGB(245, 245, 245),
	Color3.fromRGB(40, 40, 52),
}
local PANTS = {
	Color3.fromRGB(46, 58, 92),
	Color3.fromRGB(30, 30, 36),
	Color3.fromRGB(120, 96, 72),
	Color3.fromRGB(200, 196, 186),
}

local templates: { Model } = {}
local customers: { Customer } = {}
local nextSpawn: { [any]: number } = {}
local lastWaitNotice: { [any]: number } = {}
local WAIT_NOTICE_COOLDOWN = 20
local folder: Folder
local rng = Random.new()

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function buildTemplates()
	for _, height in { 0.92, 1, 1.06 } do
		local ok, result = pcall(function()
			local description = Instance.new("HumanoidDescription")
			description.HeightScale = height
			description.BodyTypeScale = 0
			description.ProportionScale = 0
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		if ok and result then
			local model = result :: Model
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BaseScript") or descendant:IsA("BodyColors") then
					descendant:Destroy()
				end
			end
			table.insert(templates, model)
		else
			warn("[CustomerService] could not create customer rig: " .. tostring(result))
		end
	end
end

local function paint(model: Model)
	local skin, shirt, pants = pick(SKIN), pick(SHIRTS), pick(PANTS)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local name = part.Name
			if name == "UpperTorso" or name == "LowerTorso" or name:find("UpperArm") then
				part.Color = shirt
			elseif name:find("Leg") then
				part.Color = pants
			elseif name:find("Foot") then
				part.Color = Color3.fromRGB(36, 34, 40)
			elseif name ~= "HumanoidRootPart" then
				part.Color = skin
			end
		end
	end
end

local function makeBubble(model: Model): TextLabel
	local head = model:FindFirstChild("Head") :: BasePart
	local gui = Instance.new("BillboardGui")
	gui.Name = "Bubble"
	gui.Size = UDim2.fromOffset(44, 44)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0.1
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.8, 0.8)
	label.Position = UDim2.fromScale(0.1, 0.1)
	label.TextScaled = true
	label.Text = ""
	label.Parent = frame
	gui.Enabled = false
	gui.Parent = head
	return label
end

local function setBubble(customer: Customer, text: string?)
	local gui = customer.Bubble.Parent and customer.Bubble.Parent.Parent :: BillboardGui
	if text then
		customer.Bubble.Text = text
		gui.Enabled = true
	else
		gui.Enabled = false
	end
end

local function updateWaiting(shop: ShopService.Shop)
	local waiting = 0
	for _, customer in customers do
		if customer.Shop == shop and customer.State == "Waiting" then
			waiting += 1
		end
	end
	shop.Model:SetAttribute("CustomersWaiting", waiting)
end

local function despawn(customer: Customer, fade: boolean)
	customer.Abort = true
	local index = table.find(customers, customer)
	if index then
		table.remove(customers, index)
	end
	updateWaiting(customer.Shop)
	if fade and customer.Model.Parent then
		customer.Humanoid.WalkSpeed = 0
		for _, part in customer.Model:GetDescendants() do
			if (part:IsA("BasePart") and part.Name ~= "HumanoidRootPart") or part:IsA("Decal") then
				TweenService:Create(part, TweenInfo.new(1.2), { Transparency = 1 }):Play()
			end
		end
		task.delay(1.3, function()
			customer.Model:Destroy()
		end)
	else
		customer.Model:Destroy()
	end
end

-- Walks to a floor point. Returns false if the customer was aborted.
local function walkTo(customer: Customer, point: Vector3): boolean
	local deadline = os.clock() + 12
	local reissueAt = 0
	while true do
		if customer.Abort or not customer.Model.Parent then
			return false
		end
		local offset = point - customer.Root.Position
		if Vector3.new(offset.X, 0, offset.Z).Magnitude < 1.8 then
			return true
		end
		if os.clock() > deadline then
			customer.Model:PivotTo(CFrame.new(point + Vector3.new(0, 3, 0))) -- unstick
			return true
		end
		if os.clock() >= reissueAt then
			customer.Humanoid:MoveTo(point)
			reissueAt = os.clock() + 2
		end
		task.wait(0.15)
	end
end

local function walkRoute(customer: Customer, route: { Vector3 }): boolean
	for _, point in route do
		if not walkTo(customer, point) then
			return false
		end
	end
	return true
end

local function face(customer: Customer, direction: Vector3)
	local root = customer.Root
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude > 0.01 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	end
end

local function giveBag(customer: Customer)
	local hand = customer.Model:FindFirstChild("RightHand") :: BasePart?
	if not hand then
		return
	end
	local bag = Instance.new("Part")
	bag.Name = "ShoppingBag"
	bag.Size = Vector3.new(1.1, 1.3, 0.5)
	bag.Color = customer.Shop.Model:GetAttribute("Accent") :: Color3
	bag.Material = Enum.Material.SmoothPlastic
	bag.CanCollide = false
	bag.CanQuery = false
	bag.CanTouch = false
	bag.Massless = true
	bag.CFrame = hand.CFrame * CFrame.new(0, -0.9, 0)
	bag.CollisionGroup = CollisionGroups.NPCs
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = bag
	weld.Parent = bag
	bag.Parent = customer.Model
end

local function checkout(customer: Customer, served: boolean)
	if customer.State ~= "Waiting" then
		return
	end
	customer.State = "Paid"
	updateWaiting(customer.Shop)
	local earned = ShopService.Sell(customer.Shop, served)
	if earned > 0 then
		setBubble(customer, if served then "😍" else "😊")
		giveBag(customer)
	else
		setBubble(customer, "😞")
	end
end

local function run(customer: Customer)
	local model = customer.Shop.Model
	local function p(name: string): Vector3
		return model:GetAttribute("P_" .. name) :: Vector3
	end
	local lane = p("Lane")
	local mouth = Vector3.new(Layout.Corridor.StartX + 2, 0, lane.Z)

	local inbound = table.clone(Layout.CustomerRoute)
	for _, point in { mouth, lane, p("Door"), p("Entry"), p("Aisle") } do
		table.insert(inbound, point)
	end
	if not walkRoute(customer, inbound) then
		return
	end

	setBubble(customer, "🛍️")
	if not walkTo(customer, p("Browse" .. rng:NextInteger(1, 3))) then
		return
	end
	face(customer, model:GetAttribute("CounterFacing") :: Vector3)
	task.wait(rng:NextNumber(2, 3.5))

	local leaveRoute = { p("Entry"), p("Door"), lane, mouth }
	for i = #Layout.CustomerRoute, 1, -1 do
		table.insert(leaveRoute, Layout.CustomerRoute[i])
	end
	table.insert(leaveRoute, Layout.CustomerSpawn)

	if ShopService.GetStock(customer.Shop) <= 0 then
		setBubble(customer, "😞")
		if walkRoute(customer, { p("Aisle") }) and walkRoute(customer, leaveRoute) then
			despawn(customer, false)
		end
		return
	end

	if not walkRoute(customer, { p("Aisle"), p("CounterApproach"), p("Counter") }) then
		return
	end
	face(customer, model:GetAttribute("CounterFacing") :: Vector3)
	customer.State = "Waiting"
	setBubble(customer, "💬")
	updateWaiting(customer.Shop)
	local owner = customer.Shop.Owner
	if owner and os.clock() - (lastWaitNotice[customer.Shop] or 0) > WAIT_NOTICE_COOLDOWN then
		lastWaitNotice[customer.Shop] = os.clock()
		Notify.player(owner, "💬 A customer is waiting at your register — serve them for a tip!", "info")
	end

	local deadline = os.clock() + EconomyConfig.AutoCheckoutDelay
	while customer.State == "Waiting" and os.clock() < deadline do
		if customer.Abort then
			return
		end
		task.wait(0.1)
	end
	checkout(customer, false) -- self-checkout if nobody served them (no-op if already paid)

	customer.State = "Leaving"
	if walkRoute(customer, { p("CounterApproach") }) and walkRoute(customer, leaveRoute) then
		despawn(customer, false)
	end
end

export type Npc = { Model: Model, Humanoid: Humanoid, Root: BasePart, Bubble: TextLabel }

-- A painted, animated shopper rig placed at `cf` under `parent` (also used by level
-- mechanics for night shoppers). Nil until the rig templates have loaded.
function CustomerService.CreateNpc(name: string, cf: CFrame, parent: Instance): Npc?
	if #templates == 0 then
		return nil
	end
	local model = pick(templates):Clone()
	model.Name = name
	paint(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.WalkSpeed = CFG.WalkSpeed * rng:NextNumber(0.9, 1.1)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	CollisionGroups.assign(model, CollisionGroups.NPCs)
	local bubble = makeBubble(model)

	model:PivotTo(cf)
	model.Parent = parent
	root:SetNetworkOwner(nil)

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local tracks = {}
	for name, id in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		tracks[name] = animator:LoadAnimation(animation)
	end
	tracks.Idle:Play()
	humanoid.Running:Connect(function(speed)
		if speed > 0.5 then
			if not tracks.Walk.IsPlaying then
				tracks.Walk:Play(0.2)
			end
		elseif tracks.Walk.IsPlaying then
			tracks.Walk:Stop(0.2)
		end
	end)
	return { Model = model, Humanoid = humanoid, Root = root, Bubble = bubble }
end

local function spawnCustomer(shop: ShopService.Shop)
	local npc = CustomerService.CreateNpc(
		"Customer",
		CFrame.new(Layout.CustomerSpawn + Vector3.new(rng:NextNumber(-6, 6), 0, 0)),
		folder
	)
	if not npc then
		return
	end
	local customer: Customer = {
		Model = npc.Model,
		Humanoid = npc.Humanoid,
		Root = npc.Root,
		Shop = shop,
		State = "Walking",
		Abort = false,
		Bubble = npc.Bubble,
	}
	table.insert(customers, customer)

	task.spawn(function()
		local ok, err = pcall(run, customer)
		if not ok then
			warn("[CustomerService] customer error: " .. tostring(err))
			despawn(customer, false)
		end
	end)
end

local function countFor(shop: ShopService.Shop): number
	local n = 0
	for _, customer in customers do
		if customer.Shop == shop then
			n += 1
		end
	end
	return n
end

function CustomerService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Customers"
	folder.Parent = workspace
end

function CustomerService.Start()
	task.spawn(buildTemplates)

	ShopService.ShopClaimed:Connect(function(shop)
		nextSpawn[shop] = os.clock() + EconomyConfig.Customers.FirstCustomerDelay
	end)
	ShopService.ShopReleased:Connect(function(shop)
		for _, customer in table.clone(customers) do
			if customer.Shop == shop then
				despawn(customer, true)
			end
		end
	end)

	GameStateService.PhaseChanged:Connect(function(phase)
		if phase == "Dusk" then
			for _, customer in table.clone(customers) do
				despawn(customer, true)
			end
		elseif phase == "Day" then
			for shop in nextSpawn do
				nextSpawn[shop] = os.clock() + rng:NextNumber(1, 4)
			end
		end
	end)

	-- serving: only the owner, only a customer waiting at this shop's register
	for _, shop in ShopService.GetAllShops() do
		local prompt = shop.Model:FindFirstChild("ServePrompt", true) :: ProximityPrompt
		prompt.Triggered:Connect(function(player)
			if shop.Owner ~= player then
				Notify.player(player, "Only the owner can work this register.", "warning")
				return
			end
			for _, customer in customers do
				if customer.Shop == shop and customer.State == "Waiting" then
					checkout(customer, true)
					return
				end
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(0.5)
			if GameStateService.GetPhase() == "Day" then
				local now = os.clock()
				for _, shop in ShopService.GetOwnedShops() do
					local owner = shop.Owner :: Player
					local due = nextSpawn[shop]
					if
						due
						and now >= due
						and #customers < CFG.MaxTotal
						and countFor(shop) < CFG.MaxPerShop
						and ShopService.GetStock(shop) > 0
					then
						local traffic = 1 + ProgressionService.UpgradeBonus(owner, "Appeal")
						nextSpawn[shop] = now + CFG.BaseInterval / traffic * rng:NextNumber(0.8, 1.2)
						spawnCustomer(shop)
					end
				end
			end
		end
	end)
end

return CustomerService
