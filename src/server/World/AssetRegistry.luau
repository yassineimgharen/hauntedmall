-- Swaps procedural placeholders for authored models.
-- Put a Model named e.g. "PalmTree" in ServerStorage.Assets (assets/ folder via Rojo).
-- Its PrimaryPart (or pivot) should sit at the base centre, facing -Z. The builder will use
-- it everywhere that prop appears; delete it to fall back to the procedural version.

local ServerStorage = game:GetService("ServerStorage")

local AssetRegistry = {}

local assetsFolder = ServerStorage:FindFirstChild("Assets")

function AssetRegistry.has(name: string): boolean
	return assetsFolder ~= nil and assetsFolder:FindFirstChild(name) ~= nil
end

-- Returns the placed clone, or nil if no authored asset exists.
function AssetRegistry.place(name: string, pivot: CFrame, parent: Instance): Model?
	if not assetsFolder then
		return nil
	end
	local template = assetsFolder:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil
	end
	local clone = template:Clone()
	clone:PivotTo(pivot)
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	clone.Parent = parent
	return clone
end

-- Unanchored clone for animated/physics assets (enemies, NPCs). Nil if none authored.
function AssetRegistry.clone(name: string): Model?
	local template = assetsFolder and assetsFolder:FindFirstChild(name)
	if template and template:IsA("Model") then
		return template:Clone()
	end
	return nil
end

return AssetRegistry
