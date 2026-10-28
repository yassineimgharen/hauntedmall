-- Stealth nights (ReplicatedStorage StealthNight, Level 5): sneak toggle, noise meter and
-- the Stalker heartbeat. Sneaking only slows your own character; the server measures your
-- real movement to decide how loud you are (player attributes Noise, StalkerNear, Hidden).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Components = require(script.Parent.Parent.UI.Components)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)

local StealthController = {}

local C = Theme.Colors
local SNEAK_SPEED = 7
local NORMAL_SPEED = 16

local player = Players.LocalPlayer
local sneaking = false

local function humanoid(): Humanoid?
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

local function active(): boolean
	return ReplicatedStorage:GetAttribute("StealthNight") == true
end

local function applySpeed()
	local h = humanoid()
	if h then
		h.WalkSpeed = if active() and sneaking then SNEAK_SPEED else NORMAL_SPEED
	end
end

function StealthController.Start()
	local gui = Create("ScreenGui", {
		Name = "Stealth",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local pulse = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Red,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local meter = Components.panel({
		Size = UDim2.fromOffset(240, 58),
		Position = UDim2.new(0.5, 0, 1, -110),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = gui,
	})
	local label = Create.text({
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.fromOffset(10, 6),
		Text = "",
		FontFace = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = meter,
	})
	local _, setBar = Components.bar({
		Size = UDim2.new(1, -20, 0, 12),
		Position = UDim2.fromOffset(10, 36),
		Parent = meter,
	}, C.Green)
	local button = Components.button({
		Text = "🤫 SNEAK",
		Color = C.Purple,
		Size = UDim2.fromOffset(120, 48),
		Position = UDim2.new(0.5, 130, 1, -110),
		AnchorPoint = Vector2.new(0, 1),
		Parent = gui,
		OnClick = function()
			sneaking = not sneaking
			applySpeed()
		end,
	})

	local function render()
		local noise = player:GetAttribute("Noise") or 0
		label.Text = if player:GetAttribute("Hidden")
			then "🚪 HIDDEN"
			elseif noise >= 0.6 then "🔊 LOUD: it can hear you!"
			elseif noise > 0 then "🔉 quiet steps"
			else "🤫 silent"
		setBar(noise, false)
		local fill = meter:FindFirstChild("Fill", true) :: Frame?
		if fill then
			fill.BackgroundColor3 = if noise >= 0.6 then C.Red elseif noise > 0 then C.Gold else C.Green
		end
		local caption = button:FindFirstChild("Label") :: TextLabel?
		if caption then
			caption.Text = if sneaking then "🤫 SNEAKING" else "🤫 SNEAK [C]"
		end
	end

	local function onActive()
		gui.Enabled = active()
		if not active() then
			sneaking = false
		end
		applySpeed()
		render()
	end
	ReplicatedStorage:GetAttributeChangedSignal("StealthNight"):Connect(onActive)
	player:GetAttributeChangedSignal("Noise"):Connect(render)
	player:GetAttributeChangedSignal("Hidden"):Connect(render)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid", 10)
		applySpeed()
	end)
	onActive()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not active() then
			return
		end
		if
			input.KeyCode == Enum.KeyCode.C
			or input.KeyCode == Enum.KeyCode.LeftControl
			or input.KeyCode == Enum.KeyCode.ButtonL3
		then
			sneaking = not sneaking
			applySpeed()
			render()
		end
	end)

	-- heartbeat: a red edge pulse while the Stalker is close
	task.spawn(function()
		while true do
			if active() and player:GetAttribute("StalkerNear") then
				pulse.BackgroundTransparency = 0.82
				TweenService:Create(pulse, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
				task.wait(0.8)
			else
				task.wait(0.3)
			end
		end
	end)
end

return StealthController
