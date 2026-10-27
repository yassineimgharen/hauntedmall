-- Swaps procedural placeholders for authored models.
--
-- Put a Model named e.g. "PalmTree" in ServerStorage.Assets (the assets/ folder via Rojo).
-- Every place that prop appears then uses it; delete it to fall back to the procedural one.
--
-- Conventions that make imports zero-effort (see docs/ASSETS.md):
--   * Placement: the model's bounding-box bottom centre is put on the target point, so the
--     importer's pivot doesn't matter. Set attribute UsePivot = true on the template to use
--     its own pivot instead.
--   * Materials: parts named "<Material>_<anything>" (e.g. "Marble_Basin", "Leaf_Fronds")
--     get the palette material/colour below. Set attribute KeepLook = true on a part to keep
--     what the artist authored (e.g. SurfaceAppearance textures).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)

local AssetRegistry = {}

type Look = { Material: Enum.Material, Color: Color3, Transparency: number?, Reflectance: number?, Solid: boolean? }

local LOOKS: { [string]: Look } = {
	Marble = { Material = Enum.Material.Marble, Color = Palette.MarbleLight, Solid = true },
	MarbleWarm = { Material = Enum.Material.Marble, Color = Palette.MarbleWarm, Solid = true },
	MarbleDark = { Material = Enum.Material.Marble, Color = Palette.MarbleDark, Solid = true },
	Gold = { Material = Enum.Material.Metal, Color = Palette.Gold, Reflectance = 0.08 },
	Metal = { Material = Enum.Material.Metal, Color = Palette.DarkMetal, Solid = true },
	Wood = { Material = Enum.Material.Wood, Color = Palette.Wood, Solid = true },
	Bark = { Material = Enum.Material.Wood, Color = Palette.Trunk, Solid = true },
	Leaf = { Material = Enum.Material.SmoothPlastic, Color = Palette.Leaf },
	LeafDark = { Material = Enum.Material.SmoothPlastic, Color = Palette.LeafDark },
	Soil = { Material = Enum.Material.Ground, Color = Palette.Soil },
	Water = { Material = Enum.Material.Glass, Color = Palette.Water, Transparency = 0.25, Reflectance = 0.15 },
	Glass = { Material = Enum.Material.Glass, Color = Palette.Glass, Transparency = 0.55 },
}

local assetsFolder = ServerStorage:FindFirstChild("Assets")

local function applyLooks(model: Instance)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanTouch = false
			local prefix = part.Name:match("^(%a+)_")
			local look = prefix and LOOKS[prefix]
			if look and not part:GetAttribute("KeepLook") then
				part.Material = look.Material
				part.Color = look.Color
				part.Transparency = look.Transparency or 0
				part.Reflectance = look.Reflectance or 0
				part.CanCollide = look.Solid == true
				part.CastShadow = look.Transparency == nil
			end
		end
	end
end

function AssetRegistry.has(name: string): boolean
	return assetsFolder ~= nil and assetsFolder:FindFirstChild(name) ~= nil
end

-- Places an anchored clone so its base sits on `target`. Returns nil if none authored.
function AssetRegistry.place(name: string, target: CFrame, parent: Instance, scale: number?): Model?
	if not assetsFolder then
		return nil
	end
	local template = assetsFolder:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil
	end
	local clone = template:Clone()
	applyLooks(clone)
	if scale and scale ~= 1 then
		clone:ScaleTo(scale)
	end
	if not template:GetAttribute("UsePivot") then
		local box, size = clone:GetBoundingBox()
		clone.WorldPivot = CFrame.new((box * CFrame.new(0, -size.Y / 2, 0)).Position) * clone:GetPivot().Rotation
	end
	clone:PivotTo(target)
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
