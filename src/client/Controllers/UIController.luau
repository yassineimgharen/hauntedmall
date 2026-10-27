-- Mounts every screen, routes server messages to them, and owns modal/window state.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local LocalEvents = require(script.Parent.Parent.LocalEvents)
local AudioController = require(script.Parent.AudioController)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)
local DevStorePanel = require(script.Parent.Parent.UI.Screens.DevStorePanel)
local Hud = require(script.Parent.Parent.UI.Screens.Hud)
local MainMenu = require(script.Parent.Parent.UI.Screens.MainMenu)
local Notifications = require(script.Parent.Parent.UI.Screens.Notifications)
local ResultsPanel = require(script.Parent.Parent.UI.Screens.ResultsPanel)
local SettingsPanel = require(script.Parent.Parent.UI.Screens.SettingsPanel)
local ShopPanel = require(script.Parent.Parent.UI.Screens.ShopPanel)

local UIController = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local windows: { [string]: any } = {}
local openWindow: string? = nil

local function setWindow(name: string?)
	if openWindow and windows[openWindow] then
		windows[openWindow]:SetVisible(false)
	end
	openWindow = name
	if name and windows[name] then
		windows[name]:SetVisible(true)
		if UserInputService.GamepadEnabled then
			local first = windows[name].Modal:FindFirstChildWhichIsA("TextButton", true)
			GuiService.SelectedObject = first
		end
	else
		GuiService.SelectedObject = nil
	end
end

local function toggleWindow(name: string)
	setWindow(if openWindow == name then nil else name)
end

-- Keeps offset-sized UI legible from phones to 4K by scaling a root frame.
local function makeScaledRoot(gui: ScreenGui): Frame
	local root = Create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local scale = Create("UIScale", { Parent = root })
	local function update()
		local viewport = camera.ViewportSize
		local s = math.clamp(math.min(viewport.X / 1280, viewport.Y / 760), 0.55, 1.3)
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
	return root
end

function UIController.Start()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	local gui = Create("ScreenGui", {
		Name = "NightShiftUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local root = makeScaledRoot(gui)

	local hud
	hud = Hud.new(root, {
		OpenShop = function()
			toggleWindow("Shop")
		end,
		OpenSettings = function()
			toggleWindow("Settings")
		end,
	})
	local notifications = Notifications.new(root)
	local close = function()
		setWindow(nil)
	end
	windows.Shop = ShopPanel.new(root, close)
	windows.Settings = SettingsPanel.new(root, close)
	windows.Results = ResultsPanel.new(root, close)
	DevStorePanel.mount(root) -- Studio test mode only; no-op in live servers

	MainMenu.new(root, function()
		hud:SetVisible(true)
		notifications:Push("Welcome to the night shift! Claim an empty shop in the East Wing.", "info")
	end)

	Net.get("Notify").OnClientEvent:Connect(function(text: string, kind: string)
		notifications:Push(text, kind)
	end)
	LocalEvents.Notify:Connect(function(text: string, kind: string)
		notifications:Push(text, kind)
	end)

	Net.get("NightResults").OnClientEvent:Connect(function(data)
		task.delay(2.5, function()
			setWindow(nil)
			openWindow = "Results"
			windows.Results:Show(data)
		end)
	end)

	Net.get("Effect").OnClientEvent:Connect(function(kind: string, payload)
		if kind == "Hit" then
			hud:FlashDamage()
			hud:Popup("-" .. tostring(payload.Damage or 0), Theme.Colors.Red, UDim2.fromScale(0.5, 0.55))
			AudioController.Play("PlayerHurt")
			-- knock the player away from the bite so they can break free (client owns its character)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and typeof(payload.Direction) == "Vector3" then
				local push = payload.Direction * EnemyConfig.Combat.Knockback + Vector3.new(0, 14, 0)
				root:ApplyImpulse(push * root.AssemblyMass)
			end
		elseif kind == "Danger" then
			hud:FlashWarning()
			AudioController.Play("Warning")
		elseif kind == "Sale" then
			if typeof(payload.Position) == "Vector3" then
				local text = "+"
					.. Format.cash(payload.Amount or 0)
					.. (if payload.Tip and payload.Tip > 0 then " ★" else "")
				hud:WorldPopup(payload.Position, text, Theme.Colors.Green)
			end
			AudioController.Play("Purchase")
		elseif kind == "Kill" then
			hud:Popup("+" .. Format.cash(payload.Amount or 0), Theme.Colors.Gold, UDim2.fromScale(0.5, 0.42))
			AudioController.Play("MonsterHit")
		elseif kind == "Purchase" then
			AudioController.Play("Purchase")
		elseif kind == "PowerRestored" then
			hud:ShowBanner("POWER RESTORED", "The shadows are stunned — strike now!", Theme.Colors.Cyan)
			AudioController.Play("PowerUp")
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.B or input.KeyCode == Enum.KeyCode.ButtonY then
			toggleWindow("Shop")
		elseif input.KeyCode == Enum.KeyCode.ButtonB and openWindow then
			setWindow(nil)
		end
	end)
end

return UIController
