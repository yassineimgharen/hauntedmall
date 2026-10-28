-- Local ambience for the food court: ventilation fans spin while their model has
-- Spinning = true (Level 13 repairs them); possessed appliances (Level 8, tag
-- PossessedAppliance on the body) rattle in place. Only things near the camera animate;
-- the server's copy never moves.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local FoodCourtFxController = {}

type Fan = { Model: Instance, Blades: BasePart, Base: CFrame, Angle: number, Speed: number }

local camera = workspace.CurrentCamera
local fans: { Fan } = {}
local shaking: { [Model]: CFrame } = {}

local function register(model: Instance)
	local blades = model:FindFirstChild("Blades")
	if blades and blades:IsA("BasePart") then
		table.insert(fans, { Model = model, Blades = blades, Base = blades.CFrame, Angle = 0, Speed = 0 })
	end
end

function FoodCourtFxController.Start()
	for _, model in CollectionService:GetTagged("VentFan") do
		register(model)
	end
	CollectionService:GetInstanceAddedSignal("VentFan"):Connect(register)
	local function possessed(body: Instance)
		local model = body.Parent
		if model and model:IsA("Model") and not shaking[model] then
			shaking[model] = model:GetPivot()
		end
	end
	for _, body in CollectionService:GetTagged("PossessedAppliance") do
		possessed(body)
	end
	CollectionService:GetInstanceAddedSignal("PossessedAppliance"):Connect(possessed)
	CollectionService:GetInstanceRemovedSignal("PossessedAppliance"):Connect(function(body)
		local model = body.Parent
		local base = model and shaking[model :: Model]
		if model and base then
			shaking[model :: Model] = nil
			(model :: Model):PivotTo(base)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local eye = camera.CFrame.Position
		local t = os.clock()
		for model, base in shaking do
			if (base.Position - eye).Magnitude < 80 then
				model:PivotTo(
					base
						* CFrame.new(math.sin(t * 37) * 0.08, math.abs(math.sin(t * 23)) * 0.12, 0)
						* CFrame.Angles(0, math.sin(t * 29) * 0.03, math.sin(t * 41) * 0.03)
				)
			end
		end
		for _, fan in fans do
			local target = if fan.Model:GetAttribute("Spinning") == true then 9 else 0
			fan.Speed += (target - fan.Speed) * math.min(dt * 1.5, 1) -- spins up and down smoothly
			if fan.Speed > 0.01 and (fan.Base.Position - eye).Magnitude < 90 then
				fan.Angle = (fan.Angle + fan.Speed * dt) % (math.pi * 2)
				fan.Blades.CFrame = fan.Base * CFrame.Angles(0, 0, fan.Angle)
			end
		end
	end)
end

return FoodCourtFxController
