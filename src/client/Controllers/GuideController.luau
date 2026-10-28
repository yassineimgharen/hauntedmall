-- Objective marker: one floating arrow over whatever the player should do next. Campaign
-- objectives with a Marker (e.g. "carry a fuse to a panel") come first; otherwise the
-- classic shop loop (claim, stock, serve) and broken fuse boxes at night.
-- Purely client-side guidance; it reads replicated attributes and never sends anything.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MissionClient = require(script.Parent.Parent.MissionClient)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)

local GuideController = {}

local HIDE_WITHIN = 7 -- studs; the ProximityPrompt takes over up close

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function rootPosition(): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

local function nearest(parts: { BasePart }, from: Vector3): BasePart?
	local best, bestDistance = nil, math.huge
	for _, part in parts do
		local distance = (part.Position - from).Magnitude
		if distance < bestDistance then
			best, bestDistance = part, distance
		end
	end
	return best
end

-- Unfinished parts with `tag`. Own = "Shop": only ones at your shop. Prefer = attribute:
-- if any part has it (e.g. the cage the clues pointed to), only those.
local function openTagged(tag: string, own: string?, prefer: string?): { BasePart }
	local parts, preferred = {}, {}
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") and not instance:GetAttribute("Done") then
			if own ~= "Shop" or instance:GetAttribute("ShopId") == player:GetAttribute("ShopId") then
				table.insert(parts, instance)
				if prefer and instance:GetAttribute(prefer) then
					table.insert(preferred, instance)
				end
			end
		end
	end
	return if #preferred > 0 then preferred else parts
end

local function missionTarget(from: Vector3): (BasePart?, string?, Color3?)
	local row = MissionClient.focusRow()
	local marker = row and row.Marker
	if not marker or (marker.Own == "Shop" and player:GetAttribute("ShopId") == nil) then
		return nil -- e.g. "barricade your shop" without a shop: the claim marker takes over
	end
	local steps = (marker :: any).Steps
	if type(steps) == "table" then
		-- a chain (cook → lace → serve): the step matching what you carry ("None" = nothing)
		local carrying = player:GetAttribute("Carrying") or "None"
		for _, step in steps do
			if step.Carry == carrying then
				return nearest(openTagged(step.Tag), from), step.Label, Theme.Colors.Cyan
			end
		end
		return nil
	end
	if marker.Carry and player:GetAttribute("Carrying") ~= marker.Carry then
		return nearest(openTagged(marker.Pickup), from), marker.PickupLabel, Theme.Colors.Gold
	end
	return nearest(openTagged(marker.Tag, marker.Own, marker.Prefer), from), marker.Label, Theme.Colors.Cyan
end

-- Returns the part to point at and the label, or nil when nothing needs doing.
local function currentTarget(from: Vector3): (BasePart?, string?, Color3?)
	local phase = ReplicatedStorage:GetAttribute("Phase")
	local missionPart, missionText, missionColor = missionTarget(from)
	if missionPart then
		return missionPart, missionText, missionColor
	end
	if phase == "Night" then
		local broken = {}
		for _, fuse in CollectionService:GetTagged("FuseBox") do
			local box = fuse:FindFirstChild("Box") :: BasePart?
			if box and fuse:GetAttribute("Broken") then
				table.insert(broken, box)
			end
		end
		local fuse = nearest(broken, from)
		if fuse then
			return fuse, "⚡ REPAIR FUSE", Theme.Colors.Gold
		end
		return nil
	end

	local myShopId = player:GetAttribute("ShopId")
	if myShopId == nil then
		if phase == "Dusk" then
			return nil
		end
		local stands = {}
		for _, shop in CollectionService:GetTagged("Shop") do
			if shop:GetAttribute("OwnerUserId") == 0 then
				local board = shop:FindFirstChild("Board", true) :: BasePart?
				if board then
					table.insert(stands, board)
				end
			end
		end
		local stand = nearest(stands, from)
		return stand, if stand then "🛍️ CLAIM A SHOP" else nil, Theme.Colors.Pink
	end

	for _, shop in CollectionService:GetTagged("Shop") do
		if shop:GetAttribute("ShopId") == myShopId then
			if (shop:GetAttribute("CustomersWaiting") or 0) > 0 then
				local counter = shop:FindFirstChild("Counter")
				return counter and counter:FindFirstChild("Top") :: BasePart?, "💬 SERVE CUSTOMER", Theme.Colors.Green
			end
			if (player:GetAttribute("ShopStock") or 0) == 0 then
				local crates = shop:FindFirstChild("Crates")
				return crates and crates:FindFirstChild("Crate") :: BasePart?, "📦 ORDER STOCK", Theme.Colors.Cyan
			end
		end
	end
	return nil
end

function GuideController.Start()
	local gui = Create("BillboardGui", {
		Name = "ObjectiveMarker",
		Size = UDim2.fromOffset(190, 84),
		StudsOffset = Vector3.new(0, 4.5, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local pill = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.1,
		Parent = gui,
	}, { Create.round(), Create.stroke(Theme.Colors.Pink, 2) })
	local label = Create.text({
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 6),
		Text = "",
		FontFace = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = pill,
	})
	local distance = Create.text({
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 36),
		Text = "",
		TextColor3 = Theme.Colors.Text,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gui,
	})
	local arrow = Create.text({
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 54),
		Text = "▼",
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gui,
	})
	local stroke = pill:FindFirstChildOfClass("UIStroke") :: UIStroke

	-- target selection at 4 Hz; bobbing every frame
	task.spawn(function()
		while true do
			local from = rootPosition()
			local inMenu = camera.CameraType == Enum.CameraType.Scriptable
			local target, text, color = nil, nil, nil
			if from and not inMenu then
				target, text, color = currentTarget(from)
			end
			local far = target ~= nil and from ~= nil and (target.Position - from).Magnitude > HIDE_WITHIN
			gui.Enabled = far
			if far and target and from and text then
				gui.Adornee = target
				label.Text = text
				stroke.Color = color or Theme.Colors.Pink
				arrow.TextColor3 = color or Theme.Colors.Pink
				distance.Text = string.format("%d studs", math.floor((target.Position - from).Magnitude))
			end
			task.wait(0.25)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if gui.Enabled then
			arrow.Position = UDim2.fromOffset(0, 54 + math.sin(os.clock() * 5) * 4)
		end
	end)
end

return GuideController
