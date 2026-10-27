-- Cheap local ambience: moving escalator treads and the eyes that watch from the dark.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WorldFxController = {}

local ESCALATOR_SPEED = 0.035 -- loop fraction per second
local EYE_HIDE_DISTANCE = 16

type Escalator = { Bottom: Vector3, Top: Vector3, Flat: Vector3, Count: number, Steps: { BasePart } }
type Eyes = { Model: Model, Parts: { BasePart }, Center: Vector3, NextBlink: number }

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local escalators: { Escalator } = {}
local eyes: { Eyes } = {}
local rng = Random.new()

local function registerEscalator(model: Instance)
	local bottom = model:GetAttribute("Bottom") :: Vector3
	local top = model:GetAttribute("Top") :: Vector3
	local steps = {}
	for _, child in model:GetChildren() do
		if child.Name == "Step" and child:IsA("BasePart") then
			steps[child:GetAttribute("Index") :: number] = child
		end
	end
	local dir = top - bottom
	table.insert(escalators, {
		Bottom = bottom,
		Top = top,
		Flat = Vector3.new(dir.X, 0, dir.Z),
		Count = model:GetAttribute("StepCount") :: number,
		Steps = steps,
	})
end

local function registerEyes(model: Instance)
	local parts = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	if #parts == 0 then
		return
	end
	table.insert(eyes, {
		Model = model :: Model,
		Parts = parts,
		Center = parts[1].Position,
		NextBlink = os.clock() + rng:NextNumber(1, 5),
	})
end

local function nightTime(): boolean
	local phase = ReplicatedStorage:GetAttribute("Phase")
	return phase == "Night" or phase == "Dusk"
end

function WorldFxController.Start()
	workspace:WaitForChild("Mall")
	for _, model in CollectionService:GetTagged("Escalator") do
		registerEscalator(model)
	end
	for _, model in CollectionService:GetTagged("LurkerEyes") do
		registerEyes(model)
	end

	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local cameraPosition = camera.CFrame.Position

		for _, escalator in escalators do
			if (escalator.Bottom - cameraPosition).Magnitude < 160 then
				local offset = clock * ESCALATOR_SPEED
				for index, step in escalator.Steps do
					local f = ((index - 1) / escalator.Count + offset) % 1
					local position = escalator.Bottom:Lerp(escalator.Top, f) - Vector3.new(0, 0.5, 0)
					step.CFrame = CFrame.lookAt(position, position + escalator.Flat)
				end
			end
		end
	end)

	-- eyes update at a relaxed rate
	task.spawn(function()
		while true do
			task.wait(0.1)
			local night = nightTime()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local now = os.clock()
			for _, eye in eyes do
				local visible = night
				if visible and root and (root.Position - eye.Center).Magnitude < EYE_HIDE_DISTANCE then
					visible = false -- they retreat when you get close
				end
				if visible and now >= eye.NextBlink then
					eye.NextBlink = now + rng:NextNumber(2, 6)
					visible = false
				elseif visible and now >= eye.NextBlink - 0.15 then
					visible = false
				end
				local transparency = if visible then 0 else 1
				for _, part in eye.Parts do
					part.Transparency = transparency
				end
			end
		end
	end)
end

return WorldFxController
