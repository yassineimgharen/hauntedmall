-- Short camera cutscenes (Effect "Cinematic"): letterbox bars, a scripted camera moving
-- through Shots { From, LookAt, Duration } and a title card, then control comes back.
-- Skippable (any key, click or tap). The server keeps threats idle while it plays, so
-- watching it never costs anything. Players with Reduced Effects see the title only.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)

local CinematicController = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local playing = 0

local function play(payload: { [string]: any }, gui: ScreenGui, bars: { Frame }, title: TextLabel, subtitle: TextLabel)
	playing += 1
	local token = playing
	local shots = if type(payload.Shots) == "table" then payload.Shots else {}
	local reduced = player:GetAttribute("Set_ReducedEffects") == true
	gui.Enabled = true
	title.Text = tostring(payload.Title or "")
	subtitle.Text = tostring(payload.Subtitle or "")
	title.TextTransparency, subtitle.TextTransparency = 1, 1
	for i, bar in bars do
		bar.Position = if i == 1 then UDim2.fromScale(0, -0.13) else UDim2.fromScale(0, 1)
		TweenService:Create(bar, Theme.TweenSlow, {
			Position = if i == 1 then UDim2.fromScale(0, 0) else UDim2.fromScale(0, 0.87),
		}):Play()
	end

	local skipped = false
	local connection = UserInputService.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Keyboard
			or input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.Gamepad1
		then
			skipped = true
		end
	end)
	local function wait(seconds: number)
		local t = 0
		while t < seconds and not skipped and playing == token do
			t += task.wait()
		end
	end

	local previousType = camera.CameraType
	if not reduced and #shots > 0 then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	for index, shot in shots do
		if skipped or playing ~= token then
			break
		end
		if typeof(shot.From) == "Vector3" and typeof(shot.LookAt) == "Vector3" and not reduced then
			local to = CFrame.lookAt(shot.From, shot.LookAt)
			local duration = tonumber(shot.Duration) or 2
			if index == 1 or shot.Cut then
				camera.CFrame = to
			else
				TweenService:Create(camera, TweenInfo.new(duration, Enum.EasingStyle.Sine), { CFrame = to }):Play()
			end
			if index == #shots then
				TweenService:Create(title, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
				TweenService:Create(subtitle, TweenInfo.new(0.9), { TextTransparency = 0 }):Play()
			end
			wait(duration)
		end
	end
	if reduced or #shots == 0 then
		title.TextTransparency, subtitle.TextTransparency = 0, 0
		wait(2.5)
	end
	wait(if skipped then 0 else 0.8)
	connection:Disconnect()
	if playing ~= token then
		return
	end
	camera.CameraType = if previousType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else previousType
	for i, bar in bars do
		TweenService:Create(bar, Theme.Tween, {
			Position = if i == 1 then UDim2.fromScale(0, -0.13) else UDim2.fromScale(0, 1),
		}):Play()
	end
	TweenService:Create(title, Theme.Tween, { TextTransparency = 1 }):Play()
	TweenService:Create(subtitle, Theme.Tween, { TextTransparency = 1 }):Play()
	task.delay(0.4, function()
		if playing == token then
			gui.Enabled = false
		end
	end)
end

function CinematicController.Start()
	local gui = Create("ScreenGui", {
		Name = "Cinematic",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local bars = {}
	for i = 1, 2 do
		bars[i] = Create("Frame", {
			Size = UDim2.fromScale(1, 0.13),
			Position = if i == 1 then UDim2.fromScale(0, -0.13) else UDim2.fromScale(0, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Parent = gui,
		})
	end
	local title = Create.text({
		Size = UDim2.new(1, -40, 0, 70),
		Position = UDim2.fromScale(0.5, 0.62),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		FontFace = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.2,
		Parent = gui,
	})
	local subtitle = Create.text({
		Size = UDim2.new(1, -40, 0, 30),
		Position = UDim2.new(0.5, 0, 0.62, 74),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		FontFace = Theme.Fonts.Heading,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Parent = gui,
	})
	Create.text({
		Size = UDim2.fromOffset(220, 22),
		Position = UDim2.new(1, -16, 1, -12),
		AnchorPoint = Vector2.new(1, 1),
		Text = "Press any key to skip ▶",
		FontFace = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 2,
		Parent = bars[2],
	})
	Net.get("Effect").OnClientEvent:Connect(function(kind: string, payload)
		if kind == "Cinematic" and type(payload) == "table" then
			task.spawn(play, payload, gui, bars, title, subtitle)
		end
	end)
end

return CinematicController
