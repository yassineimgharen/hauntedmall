-- Meatball (Level 14 boss minion): a rolling, sauce-dripping ball with teeth. Uses the
-- standard chase-and-bite AI; the client rolls it (BodyJoint) as it moves.

local Palette = require(game:GetService("ReplicatedStorage").Shared.Config.Palette)
local Rig = require(script.Parent.Rig)

local Meatball = {}

function Meatball.Build(): Model
	local model = Instance.new("Model")
	model.Name = "Meatball"
	local hip = 1.4
	local root = Rig.root(model, Vector3.new(2.4, 2, 2.4), hip)
	local body = Rig.ball(model, Vector3.new(3.2, 3.2, 3.2), CFrame.new(), Color3.fromRGB(120, 62, 40), {
		Name = "Body",
		Material = Enum.Material.Slate,
	})
	Rig.motor("BodyJoint", root, body, CFrame.new(0, -0.8, 0))
	for i = 0, 5 do
		local blob = Rig.ball(
			model,
			Vector3.new(0.9, 0.5, 0.9),
			body.CFrame * CFrame.Angles(i * 1.1, i * 0.7, 0) * CFrame.new(0, 1.5, 0),
			Color3.fromRGB(200, 30, 30),
			{ Material = Enum.Material.Glass, Transparency = 0.2 }
		)
		Rig.weld(body, blob)
	end
	for _, x in { -0.5, 0.5 } do
		Rig.eye(
			model,
			body,
			body.CFrame * CFrame.new(x, 0.5, -1.5),
			Vector3.new(0.4, 0.3, 0.1),
			Palette.NeonGold,
			x > 0
		)
	end
	for i = -2, 2 do
		local tooth = Rig.part(model, {
			Size = Vector3.new(0.2, 0.3, 0.1),
			CFrame = body.CFrame * CFrame.new(i * 0.28, -0.3, -1.55),
			Color = Color3.fromRGB(250, 240, 220),
		})
		Rig.weld(body, tooth)
	end
	Rig.humanoid(model, hip, 12.5)
	return model
end

return Meatball
