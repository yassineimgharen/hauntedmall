-- Security camera viewer (Level 4 nights). Opened by the server after "View Cameras" at a
-- terminal with the repaired cameras' views. Purely local: the camera moves, the world
-- doesn't. Moving, getting hurt, X or ✕ closes it, so it can't be used to hide safely.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Components = require(script.Parent.Parent.Components)
local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local CameraFeed = {}
CameraFeed.__index = CameraFeed

export type Feed = { Name: string, CFrame: CFrame }

function CameraFeed.new(root: Frame)
	local self = setmetatable({}, CameraFeed)
	self.Feeds = {} :: { Feed }
	self.Index = 1
	self.Connections = {} :: { RBXScriptConnection }

	local overlay = Create("Frame", {
		Name = "CameraFeed",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 60, 40),
		BackgroundTransparency = 0.86,
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	self.Overlay = overlay
	self.Title = Create.text({
		Size = UDim2.fromOffset(520, 34),
		Position = UDim2.fromOffset(28, 24),
		Text = "",
		FontFace = Theme.Fonts.Heading,
		TextColor3 = Color3.fromRGB(220, 255, 230),
		TextStrokeTransparency = 0.4,
		ZIndex = 21,
		Parent = overlay,
	})
	self.Info = Create.text({
		Size = UDim2.fromOffset(360, 24),
		Position = UDim2.new(1, -28, 0, 28),
		AnchorPoint = Vector2.new(1, 0),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Gold,
		TextStrokeTransparency = 0.4,
		ZIndex = 21,
		Parent = overlay,
	})
	local bar = Create("Frame", {
		Size = UDim2.fromOffset(470, 56),
		Position = UDim2.new(0.5, 0, 1, -24),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = overlay,
	}, { Create.list(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center) })
	for i, data in
		{
			{ "◀ CAM [Q]", -1 },
			{ "✕ EXIT [X]", 0 },
			{ "CAM [E] ▶", 1 },
		}
	do
		Components.button({
			Text = data[1],
			Color = if data[2] == 0 then C.Red else C.PanelLighter,
			Size = UDim2.fromOffset(140, 50),
			LayoutOrder = i,
			Parent = bar,
			OnClick = function()
				if data[2] == 0 then
					self:Close()
				else
					self:Step(data[2])
				end
			end,
		})
	end
	return self
end

function CameraFeed:_show()
	local feed = self.Feeds[self.Index]
	if feed then
		camera.CFrame = feed.CFrame
		self.Title.Text = string.format("● REC   %s   (%d/%d)", feed.Name, self.Index, #self.Feeds)
	end
end

function CameraFeed:Step(delta: number)
	if #self.Feeds == 0 then
		return
	end
	self.Index = (self.Index - 1 + delta) % #self.Feeds + 1
	self:_show()
end

function CameraFeed:IsOpen(): boolean
	return self.Overlay.Visible
end

function CameraFeed:Open(feeds: { Feed })
	if #feeds == 0 then
		return
	end
	self:Close()
	self.Feeds = feeds
	self.Index = 1
	camera.CameraType = Enum.CameraType.Scriptable
	self.Overlay.Visible = true
	-- E/Q switch cameras, so the terminal's own E prompt must not fire meanwhile
	ProximityPromptService.Enabled = false
	self:_show()

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local openedAt = os.clock()
	local health = humanoid and humanoid.Health or 0
	table.insert(
		self.Connections,
		RunService.RenderStepped:Connect(function()
			camera.CameraType = Enum.CameraType.Scriptable
			self:_show()
			self.Info.Text = string.format("👾 %d shadows on site", workspace:GetAttribute("EnemiesAlive") or 0)
			self.Overlay.BackgroundTransparency = if math.random() < 0.03 then 0.7 else 0.86 -- static
			if humanoid then
				local moving = humanoid.MoveDirection.Magnitude > 0.1 and os.clock() - openedAt > 0.5
				if moving or humanoid.Health < health or humanoid.Health <= 0 then
					self:Close()
				end
			end
		end)
	)
	table.insert(
		self.Connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.DPadLeft then
				self:Step(-1)
			elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.DPadRight then
				self:Step(1)
			elseif input.KeyCode == Enum.KeyCode.X or input.KeyCode == Enum.KeyCode.ButtonB then
				self:Close()
			end
		end)
	)
end

function CameraFeed:Close()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	if self.Overlay.Visible then
		self.Overlay.Visible = false
		ProximityPromptService.Enabled = true
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

return CameraFeed
