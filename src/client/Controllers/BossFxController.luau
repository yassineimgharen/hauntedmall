-- Boss feedback in the world (client-only, purely visual):
--   BossHit      floating damage numbers where your light hit her
--   BossBlocked  "🛡️ BLOCKED" where your light hit her shield
--   BossHitAt    (ReplicatedStorage attribute) a brief white flash on her, seen by everyone
--   Shake        camera shake from slams, phase roars and her fall, scaled by distance
--   ShieldBreak  shake and flash when a cannon breaks her shield

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Parent.UI.Theme)

local BossFxController = {}

local player = Players.LocalPlayer
local rng = Random.new()
local highlight: Highlight? = nil
local flashToken = 0

local function queenModel(): Model?
	local arena = workspace:FindFirstChild("QueenArena")
	return arena and arena:FindFirstChild("ShadowQueen") :: Model?
end

local function hitFlash(strength: number)
	local model = queenModel()
	if not model then
		return
	end
	local h = highlight
	if not h or h.Adornee ~= model or not h.Parent then
		if h then
			h:Destroy()
		end
		h = Instance.new("Highlight")
		h.FillColor = Color3.new(1, 1, 1)
		h.OutlineColor = Color3.fromRGB(255, 240, 200)
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = model
		h.Parent = model
		highlight = h
	end
	local active = h :: Highlight
	flashToken += 1
	local token = flashToken
	active.Enabled = true
	active.FillTransparency = 1 - 0.55 * strength
	active.OutlineTransparency = 0.2
	task.delay(0.12, function()
		if flashToken == token and active.Parent then
			active.Enabled = false
		end
	end)
end

local function floatingText(position: Vector3, text: string, color: Color3, size: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame =
		CFrame.new(position + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(1, 3), rng:NextNumber(-2, 2)))
	anchor.Parent = workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size * 5, size * 1.4)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.FontFace = Theme.Fonts.Heading
	label.TextStrokeTransparency = 0.1
	label.Parent = gui
	TweenService:Create(gui, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { StudsOffset = Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1, function()
		anchor:Destroy()
	end)
end

local function shake(origin: Vector3?, strength: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	local falloff = if origin then math.clamp(1 - (root.Position - origin).Magnitude / 60, 0, 1) else 1
	local amount = strength * falloff
	if amount < 0.05 then
		return
	end
	task.spawn(function()
		for i = 1, 10 do
			local k = amount * (1 - i / 10) * 0.8
			humanoid.CameraOffset = Vector3.new(rng:NextNumber(-k, k), rng:NextNumber(-k, k), 0)
			task.wait(0.03)
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

function BossFxController.Start()
	Net.get("Effect").OnClientEvent:Connect(function(kind: string, payload)
		if kind == "BossHit" and typeof(payload.Position) == "Vector3" then
			local amount = tonumber(payload.Amount) or 0
			if amount > 0 then
				floatingText(payload.Position, "-" .. amount, Theme.Colors.Gold, if amount >= 15 then 30 else 24)
			end
		elseif kind == "BossBlocked" and typeof(payload.Position) == "Vector3" then
			floatingText(payload.Position, "🛡️ BLOCKED", Theme.Colors.Purple, 22)
		elseif kind == "Shake" then
			shake(
				if typeof(payload.Position) == "Vector3" then payload.Position else nil,
				tonumber(payload.Strength) or 1
			)
		elseif kind == "ShieldBreak" then
			hitFlash(1)
			shake(if typeof(payload.Position) == "Vector3" then payload.Position else nil, 1.2)
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal("BossHitAt"):Connect(function()
		hitFlash(0.7)
	end)
end

return BossFxController
