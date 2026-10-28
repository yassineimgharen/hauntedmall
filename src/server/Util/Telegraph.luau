-- Floor warnings for attacks, so everyone sees exactly where and when a hit lands:
--   disc(center, radius, seconds)      outline + a fill that grows until impact
--   lane(from, to, width, seconds)     a strip that fills from `from` to `to`
--   burst(center, radius, color)       the impact ring (after the hit)
-- Parts live in workspace.Telegraphs and remove themselves; clear() wipes them all.
-- No service dependencies, so enemy types and levels can both use it.

local TweenService = game:GetService("TweenService")

local CollisionGroups = require(script.Parent.CollisionGroups)

local Telegraph = {}

local DANGER = Color3.fromRGB(255, 60, 70)
local rayParams = CollisionGroups.worldRaycastParams()

local function folder(): Folder
	local existing = workspace:FindFirstChild("Telegraphs")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "Telegraphs"
	created.Parent = workspace
	return created
end

local function flat(name: string, size: Vector3, cf: CFrame, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cf
	part.Parent = folder()
	return part
end

-- The floor under a point (a character's root, an enemy), or the point itself.
function Telegraph.floorBelow(position: Vector3): Vector3
	local hit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), rayParams)
	return if hit then hit.Position else position
end

function Telegraph.disc(center: Vector3, radius: number, seconds: number, color: Color3?): Model
	local tint = color or DANGER
	local model = Instance.new("Model")
	model.Name = "DiscWarning"
	local flatten = CFrame.Angles(0, 0, math.rad(90))
	local base = CFrame.new(center + Vector3.new(0, 0.08, 0)) * flatten
	local outline = flat("Outline", Vector3.new(0.06, radius * 2, radius * 2), base, tint, 0.55)
	outline.Shape = Enum.PartType.Cylinder
	outline.Parent = model
	local fill = flat("Fill", Vector3.new(0.08, 0.4, 0.4), base * CFrame.new(0.02, 0, 0), tint, 0.25)
	fill.Shape = Enum.PartType.Cylinder
	fill.Parent = model
	model.Parent = folder()
	TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.08, radius * 2, radius * 2),
	}):Play()
	task.delay(seconds + 0.1, function()
		model:Destroy()
	end)
	return model
end

function Telegraph.lane(from: Vector3, to: Vector3, width: number, seconds: number, color: Color3?): Model
	local tint = color or DANGER
	local a = Vector3.new(from.X, from.Y + 0.08, from.Z)
	local b = Vector3.new(to.X, from.Y + 0.08, to.Z)
	local length = (b - a).Magnitude
	local model = Instance.new("Model")
	model.Name = "LaneWarning"
	if length < 0.5 then
		model.Parent = folder()
		task.delay(seconds, function()
			model:Destroy()
		end)
		return model
	end
	local frame = CFrame.lookAt(a, b)
	local outline = flat("Outline", Vector3.new(width, 0.06, length), frame * CFrame.new(0, 0, -length / 2), tint, 0.6)
	outline.Parent = model
	local fill = flat("Fill", Vector3.new(width * 0.9, 0.08, 0.2), frame * CFrame.new(0, 0.01, -0.1), tint, 0.25)
	fill.Parent = model
	model.Parent = folder()
	TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
		Size = Vector3.new(width * 0.9, 0.08, length),
		CFrame = frame * CFrame.new(0, 0.01, -length / 2),
	}):Play()
	task.delay(seconds + 0.1, function()
		model:Destroy()
	end)
	return model
end

function Telegraph.burst(center: Vector3, radius: number, color: Color3?)
	local ring = flat(
		"Burst",
		Vector3.new(0.1, 1, 1),
		CFrame.new(center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color or DANGER,
		0.2
	)
	ring.Shape = Enum.PartType.Cylinder
	TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
		Size = Vector3.new(0.1, radius * 2.2, radius * 2.2),
		Transparency = 1,
	}):Play()
	task.delay(0.45, function()
		ring:Destroy()
	end)
end

-- Players whose character stands inside the circle (flat distance, roughly same level).
function Telegraph.playersInCircle(players: { Player }, center: Vector3, radius: number): { Player }
	local inside = {}
	for _, player in players do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and humanoid.Health > 0 and root then
			local offset = root.Position - center
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) < 8 then
				table.insert(inside, player)
			end
		end
	end
	return inside
end

-- Players inside the strip from `from` to `to` of the given width.
function Telegraph.playersInLane(players: { Player }, from: Vector3, to: Vector3, width: number): { Player }
	local inside = {}
	local axis = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = axis.Magnitude
	if length < 0.01 then
		return inside
	end
	axis /= length
	for _, player in players do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and humanoid.Health > 0 and root then
			local offset = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
			local along = offset:Dot(axis)
			local across = (offset - axis * along).Magnitude
			if
				along >= -1
				and along <= length + 1
				and across <= width / 2 + 1
				and math.abs(root.Position.Y - from.Y) < 8
			then
				table.insert(inside, player)
			end
		end
	end
	return inside
end

function Telegraph.clear()
	local existing = workspace:FindFirstChild("Telegraphs")
	if existing then
		existing:ClearAllChildren()
	end
end

return Telegraph
