-- One carried item per player for level mechanics (fuses, lamps, crates, planks).
-- The item is a glowing prop welded to the chest and mirrored as the player attribute
-- "Carrying" (clients use it to show the right prompts and markers).
--
-- An item with an onLost callback is unique (e.g. a stolen crate): if the carrier dies,
-- leaves, swaps it or the stage ends, the callback runs so the level can put it back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Builder = require(script.Parent.Parent.World.Builder)

local Carry = {}

local LOOKS: { [string]: { Size: Vector3, Color: Color3, Material: Enum.Material } } = {
	Fuse = { Size = Vector3.new(0.7, 1.3, 0.7), Color = Palette.NeonGold, Material = Enum.Material.Neon },
	Lamp = { Size = Vector3.new(1.1, 1.6, 1.1), Color = Palette.WarmLight, Material = Enum.Material.Neon },
	Crate = {
		Size = Vector3.new(1.8, 1.6, 1.4),
		Color = Color3.fromRGB(198, 152, 100),
		Material = Enum.Material.Cardboard,
	},
	Planks = { Size = Vector3.new(0.6, 0.5, 2.6), Color = Palette.Wood, Material = Enum.Material.WoodPlanks },
	Extinguisher = {
		Size = Vector3.new(0.9, 1.8, 0.9),
		Color = Color3.fromRGB(230, 40, 40),
		Material = Enum.Material.SmoothPlastic,
	},
	Mop = { Size = Vector3.new(0.35, 3.4, 0.35), Color = Color3.fromRGB(240, 196, 40), Material = Enum.Material.Fabric },
	Floodlight = {
		Size = Vector3.new(1.4, 1.2, 1.4),
		Color = Color3.fromRGB(235, 240, 255),
		Material = Enum.Material.Neon,
	},
}

type Carried = { Item: string, Visual: BasePart, OnLost: (() -> ())? }

local carrying: { [Player]: Carried } = {}

function Carry.item(player: Player): string?
	local carried = carrying[player]
	return carried and carried.Item
end

local function release(player: Player): Carried?
	local carried = carrying[player]
	if carried then
		carrying[player] = nil
		carried.Visual:Destroy()
	end
	if player.Parent then
		player:SetAttribute("Carrying", nil)
	end
	return carried
end

-- Drops (loses) whatever the player carries; unique items report back via onLost.
function Carry.drop(player: Player)
	local carried = release(player)
	if carried and carried.OnLost then
		task.spawn(carried.OnLost)
	end
end

function Carry.pickUp(player: Player, item: string, onLost: (() -> ())?): boolean
	local character = player.Character
	local torso = character
		and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	local look = LOOKS[item]
	if not torso or not look then
		return false
	end
	Carry.drop(player)
	local visual = Builder.decor({
		Name = "Carried" .. item,
		Size = look.Size,
		CFrame = torso.CFrame * CFrame.new(0, 0.2, -1.2),
		Color = look.Color,
		Material = look.Material,
		Anchored = false,
		Massless = true,
	})
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = visual
	weld.Parent = visual
	visual.Parent = character
	carrying[player] = { Item = item, Visual = visual, OnLost = onLost }
	player:SetAttribute("Carrying", item)
	return true
end

-- Uses up the carried item if it is `item`. Returns whether it was.
function Carry.consume(player: Player, item: string): boolean
	local carried = carrying[player]
	if not carried or carried.Item ~= item then
		return false
	end
	release(player)
	return true
end

-- Stage over: everyone drops everything.
function Carry.clearAll()
	for player in table.clone(carrying) do
		Carry.drop(player)
	end
end

local function watch(player: Player)
	player.CharacterRemoving:Connect(function()
		Carry.drop(player)
	end)
end
Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end
Players.PlayerRemoving:Connect(Carry.drop)

return Carry
