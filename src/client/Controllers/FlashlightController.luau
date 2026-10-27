-- Flashlight input. Works with mouse (hold click), touch (hold the on-screen button or
-- tap-hold the screen), and gamepad (R2) via the Tool's Activated/Deactivated events.
-- The client only sends on/off + aim direction; the server does all damage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local Net = require(ReplicatedStorage.Shared.Net)

local FlashlightController = {}

local AIM_SEND_INTERVAL = 0.1

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()
local setBeamRemote = Net.get("SetBeam")
local aimRemote = Net.get("AimUpdate")

local beaming = false
local lastAimSent = 0
local touchButton: TextButton? = nil

local function character()
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = char and char:FindFirstChild("Head") :: BasePart?
	return char, humanoid, root, head
end

local function aimDirection(): Vector3
	local _, _, _, head = character()
	local direction
	if head and UserInputService.MouseEnabled then
		local target = mouse.Hit.Position
		direction = target - head.Position
	else
		direction = camera.CFrame.LookVector
	end
	if direction.Magnitude < 0.01 then
		direction = camera.CFrame.LookVector
	end
	direction = direction.Unit
	local pitch =
		math.clamp(direction.Y, -EnemyConfig.Flashlight.MaxAimPitch + 0.05, EnemyConfig.Flashlight.MaxAimPitch - 0.05)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	end
	return (flat.Unit * math.sqrt(1 - pitch * pitch) + Vector3.new(0, pitch, 0)).Unit
end

local function predictVisual(on: boolean)
	local _, _, root = character()
	local beam = root and root:FindFirstChild("FlashlightBeam") :: Beam?
	if beam then
		beam.Enabled = on
	end
end

local function setBeaming(on: boolean)
	if on == beaming then
		return
	end
	local _, humanoid = character()
	if on and ((player:GetAttribute("Battery") or 1) <= 0 or not humanoid or humanoid.Health <= 0) then
		return
	end
	beaming = on
	if humanoid then
		humanoid.AutoRotate = not on
	end
	predictVisual(on)
	setBeamRemote:FireServer(on, aimDirection())
end

local function equippedTool(): Tool?
	local char = player.Character
	return char and char:FindFirstChild("Flashlight") :: Tool?
end

local function bindTool(tool: Tool)
	tool.Activated:Connect(function()
		setBeaming(true)
	end)
	tool.Deactivated:Connect(function()
		setBeaming(false)
	end)
	tool.Unequipped:Connect(function()
		setBeaming(false)
	end)
end

-- Backpacks are replaced on respawn, so rescan instead of tracking instances.
local function watchBackpack()
	local function scan(container: Instance?)
		local tool = container and container:FindFirstChild("Flashlight")
		if tool and tool:IsA("Tool") and not tool:GetAttribute("Bound") then
			tool:SetAttribute("Bound", true)
			bindTool(tool)
		end
	end
	player.CharacterAdded:Connect(function()
		beaming = false
	end)
	while true do
		scan(player:FindFirstChild("Backpack"))
		scan(player.Character)
		task.wait(0.5)
	end
end

-- Large hold-to-shine button for touch screens, visible while the flashlight is out.
local function buildTouchButton()
	if not UserInputService.TouchEnabled then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "FlashlightTouch"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(86, 86)
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -24, 1, -170)
	button.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
	button.BackgroundTransparency = 0.15
	button.Text = "🔦"
	button.TextScaled = true
	button.Visible = false
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			setBeaming(true)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			setBeaming(false)
		end
	end)
	touchButton = button
end

function FlashlightController.EquipFlashlight()
	local _, humanoid = character()
	local backpack = player:FindFirstChild("Backpack")
	local tool = backpack and backpack:FindFirstChild("Flashlight")
	if humanoid and tool and tool:IsA("Tool") then
		humanoid:EquipTool(tool)
	end
end

function FlashlightController.Start()
	buildTouchButton()
	task.spawn(watchBackpack)

	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(function()
		if ReplicatedStorage:GetAttribute("Phase") == "Dusk" then
			FlashlightController.EquipFlashlight()
		end
	end)

	player:GetAttributeChangedSignal("Battery"):Connect(function()
		if beaming and (player:GetAttribute("Battery") or 0) <= 0 then
			setBeaming(false)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if touchButton then
			touchButton.Visible = equippedTool() ~= nil
		end
		if not beaming then
			return
		end
		local _, humanoid, root = character()
		if not root or not humanoid or humanoid.Health <= 0 or not equippedTool() then
			setBeaming(false)
			return
		end
		local aim = aimDirection()
		local flat = Vector3.new(aim.X, 0, aim.Z)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		local now = os.clock()
		if now - lastAimSent >= AIM_SEND_INTERVAL then
			lastAimSent = now
			aimRemote:FireServer(aim)
		end
	end)
end

return FlashlightController
