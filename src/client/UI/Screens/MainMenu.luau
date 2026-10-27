-- Title screen over a slow orbit of the atrium. PLAY unlocks once the save has loaded.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Components = require(script.Parent.Parent.Components)
local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local MainMenu = {}
MainMenu.__index = MainMenu

function MainMenu.new(root: Frame, onPlay: () -> ())
	local self = setmetatable({}, MainMenu)
	self.OnPlay = onPlay
	self.Root = Create("Frame", {
		Name = "MainMenu",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Backdrop,
		BackgroundTransparency = 0.25,
		ZIndex = 30,
		Parent = root,
	}, {
		Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.45, 0.85),
				NumberSequenceKeypoint.new(1, 0.1),
			}),
		}),
	})

	local logo = Create("Frame", {
		Size = UDim2.new(0.9, 0, 0, 190),
		Position = UDim2.fromScale(0.5, 0.2),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 31,
		Parent = self.Root,
	})
	local function word(text: string, color: Color3, glow: Color3, x: number)
		local label = Create.text({
			Size = UDim2.new(0.5, 0, 0, 130),
			Position = UDim2.fromScale(x, 0),
			AnchorPoint = Vector2.new(if x < 0.5 then 1 else 0, 0),
			Text = text,
			TextColor3 = color,
			FontFace = Theme.Fonts.Title,
			TextXAlignment = if x < 0.5 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
			ZIndex = 31,
			Parent = logo,
		})
		Create("UIStroke", { Color = glow, Thickness = 5, Transparency = 0.2, Parent = label })
		return label
	end
	word("NIGHT", Color3.fromRGB(235, 245, 255), C.Cyan, 0.49)
	word("SHIFT", C.Pink, C.Purple, 0.51)
	Create.text({
		Size = UDim2.new(0.6, 0, 0, 36),
		Position = UDim2.new(0.5, 0, 0, 136),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "—  H A U N T E D   M A L L  —",
		TextColor3 = Color3.fromRGB(255, 220, 250),
		FontFace = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 31,
		Parent = logo,
	})

	Create.text({
		Size = UDim2.new(0.7, 0, 0, 26),
		Position = UDim2.fromScale(0.5, 0.56),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "Run a shop by day.  Survive the mall by night.",
		TextColor3 = C.TextDim,
		FontFace = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 31,
		Parent = self.Root,
	})

	self.PlayButton = Components.button({
		Text = "LOADING YOUR SHIFT…",
		Color = C.PanelLighter,
		Size = UDim2.fromOffset(300, 64),
		Position = UDim2.fromScale(0.5, 0.66),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = self.Root,
		OnClick = function()
			self:_play()
		end,
	})
	self.PlayButton.ZIndex = 32
	Components.setButtonEnabled(self.PlayButton, false)

	self.Fade = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = root,
	})

	self:_startOrbit()
	local function onLoaded()
		if player:GetAttribute("DataLoaded") then
			(self.PlayButton:FindFirstChild("Label") :: TextLabel).Text = "▶  PLAY"
			Components.setButtonEnabled(self.PlayButton, true, C.Pink)
		end
	end
	player:GetAttributeChangedSignal("DataLoaded"):Connect(onLoaded)
	onLoaded()
	return self
end

function MainMenu:_startOrbit()
	camera.CameraType = Enum.CameraType.Scriptable
	local angle = 0
	self.OrbitConnection = RunService.RenderStepped:Connect(function(dt)
		angle += dt * 0.06
		local position = Vector3.new(math.cos(angle) * 52, 20 + math.sin(angle * 0.7) * 4, math.sin(angle) * 52)
		camera.CFrame = CFrame.lookAt(position, Vector3.new(0, 12, 0))
	end)
end

function MainMenu:_play()
	if self.Playing then
		return
	end
	self.Playing = true
	TweenService:Create(self.Fade, TweenInfo.new(0.4), { BackgroundTransparency = 0 }):Play()
	task.wait(0.45)
	self.OrbitConnection:Disconnect()
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	self.Root.Visible = false
	self.OnPlay()
	TweenService:Create(self.Fade, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
end

return MainMenu
