-- One player-ownable store. Local space: origin at the doorway on the floor,
-- +Z runs into the shop, -Z faces the corridor. Width 30, depth 34.
--
-- The model exposes, for ShopService/CustomerService:
--   children  Sign (SurfaceGui Gui.Title), Trim (neon parts), Products (slot models),
--             LeaseStand.Board.ClaimPrompt, Crates.Crate.RestockPrompt, Counter.Top.ServePrompt
--   attributes ShopId, Category, Accent, and world-space nav points P_* (Vector3)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Builder = require(script.Parent.Builder)
local Props = require(script.Parent.Props)

local ShopUnit = {}

local FONT_TITLE = Font.new("rbxasset://fonts/families/FredokaOne.json")
local CARDBOARD = Color3.fromRGB(198, 152, 100)
local PASTELS = {
	Color3.fromRGB(255, 182, 214),
	Color3.fromRGB(178, 226, 255),
	Color3.fromRGB(255, 226, 150),
	Color3.fromRGB(196, 176, 255),
	Color3.fromRGB(170, 240, 200),
	Color3.fromRGB(255, 196, 160),
}

type ProductBuilder = (cf: CFrame, parent: Instance, accent: Color3, rng: Random, scale: number) -> ()

local PRODUCT_BUILDERS: { [string]: ProductBuilder } = {
	Toys = function(cf, parent, _accent, rng, scale)
		local color = PASTELS[rng:NextInteger(1, #PASTELS)]
		Builder.decor({
			Parent = parent,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.3 * scale,
			CFrame = cf * CFrame.new(0, 0.65 * scale, 0),
			Color = color,
			Material = Enum.Material.Fabric,
		})
		Builder.decor({
			Parent = parent,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.95 * scale,
			CFrame = cf * CFrame.new(0, 1.55 * scale, 0),
			Color = Builder.shade(color, 0.15),
			Material = Enum.Material.Fabric,
		})
	end,
	Apparel = function(cf, parent, _accent, rng, scale)
		for i = 0, 2 do
			Builder.decor({
				Parent = parent,
				Size = Vector3.new(1.9, 0.38, 1.3) * scale,
				CFrame = cf
					* CFrame.new(0, (0.19 + i * 0.4) * scale, 0)
					* CFrame.Angles(0, rng:NextNumber(-0.08, 0.08), 0),
				Color = PASTELS[rng:NextInteger(1, #PASTELS)],
				Material = Enum.Material.Fabric,
			})
		end
	end,
	Gadgets = function(cf, parent, accent, _rng, scale)
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(1.3, 1.7, 0.8) * scale,
			CFrame = cf * CFrame.new(0, 0.85 * scale, 0),
			Color = Color3.fromRGB(32, 30, 44),
		})
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(1, 0.7, 0.05) * scale,
			CFrame = cf * CFrame.new(0, 1.1 * scale, -0.42 * scale),
			Color = accent,
			Material = Enum.Material.Neon,
		})
	end,
}

local function addProductSlot(
	products: Folder,
	order: number,
	cf: CFrame,
	category: string,
	accent: Color3,
	rng: Random,
	scale: number
)
	local slot = Builder.model("Slot" .. order, products)
	slot:SetAttribute("Order", order)
	PRODUCT_BUILDERS[category](cf, slot, accent, rng, scale)
	for _, part in slot:GetChildren() do
		(part :: BasePart).Transparency = 1 -- hidden until stocked
	end
end

function ShopUnit.build(
	parent: Instance,
	id: string,
	origin: CFrame,
	accent: Color3,
	category: { Id: string, Name: string, Icon: string }
): Model
	local model = Builder.model("Shop_" .. id, parent)
	model:SetAttribute("ShopId", id)
	model:SetAttribute("Category", category.Id)
	model:SetAttribute("CategoryName", category.Name)
	model:SetAttribute("Accent", accent)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("Stock", 0)
	model:SetAttribute("MaxStock", 0)
	model:SetAttribute("CustomersWaiting", 0)

	local rng = Random.new(#id * 97 + string.byte(id, -1))
	local wallColor = Palette.Wall:Lerp(accent, 0.1)

	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	local function solid(name: string?, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
		return Builder.part({
			Name = name or "Part",
			Parent = model,
			Size = size,
			CFrame = cf,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
		})
	end
	local function decor(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?)
		local props = {
			Parent = model,
			Size = size,
			CFrame = cf,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
		}
		if extra then
			for k, v in extra do
				props[k] = v
			end
		end
		return Builder.decor(props)
	end

	-- shell
	solid("Floor", Vector3.new(30, 1, 34), at(0, -0.5, 17), Palette.Wood, Enum.Material.WoodPlanks)
	decor(Vector3.new(12, 0.06, 9), at(-1, 0.03, 19), Builder.shade(accent, -0.55), Enum.Material.Fabric)
	solid(nil, Vector3.new(1, 20, 34), at(-14.5, 10, 17), wallColor)
	solid(nil, Vector3.new(1, 20, 34), at(14.5, 10, 17), wallColor)
	solid(nil, Vector3.new(30, 20, 1), at(0, 10, 33.5), wallColor)
	solid(nil, Vector3.new(30, 1, 34), at(0, 20.5, 17), Palette.Wall)
	for _, data in
		{
			{ Vector3.new(0.2, 4, 33), at(-13.9, 2, 17) },
			{ Vector3.new(0.2, 4, 33), at(13.9, 2, 17) },
			{ Vector3.new(28, 4, 0.2), at(0, 2, 32.9) },
		}
	do
		decor(data[1], data[2], Builder.shade(accent, -0.35), Enum.Material.Wood)
	end
	decor(Vector3.new(27, 0.25, 0.15), at(0, 12.5, 32.85), accent, Enum.Material.Neon, { Tags = { "NightNeon" } })

	-- storefront
	for _, x in { -10, 10 } do
		solid(nil, Vector3.new(10, 1.2, 0.6), at(x, 0.6, 0), Palette.DarkMetal, Enum.Material.Metal)
		Builder.part({
			Parent = model,
			Size = Vector3.new(10, 10.8, 0.3),
			CFrame = at(x, 6.6, 0),
			Color = Palette.Glass,
			Material = Enum.Material.Glass,
			Transparency = 0.6,
			CastShadow = false,
		})
	end
	for _, x in { -15, -5, 5, 15 } do
		solid(nil, Vector3.new(0.7, 12, 0.8), at(x, 6, 0), Palette.DarkMetal, Enum.Material.Metal)
	end
	solid(nil, Vector3.new(31, 8, 1), at(0, 16, 0), Palette.DarkMetal, Enum.Material.Metal)

	local sign = Builder.part({
		Name = "Sign",
		Parent = model,
		Size = Vector3.new(18, 4.4, 0.3),
		CFrame = at(0, 16, -0.65),
		Color = Color3.fromRGB(16, 12, 26),
	})
	Builder.label(sign, Enum.NormalId.Front, "FOR LEASE", { Color = Color3.fromRGB(200, 200, 210), Font = FONT_TITLE })

	local trim = Builder.folder("Trim", model)
	for _, data in
		{
			{ Vector3.new(18.6, 0.25, 0.25), at(0, 18.35, -0.85) },
			{ Vector3.new(18.6, 0.25, 0.25), at(0, 13.65, -0.85) },
			{ Vector3.new(0.25, 4.95, 0.25), at(-9.3, 16, -0.85) },
			{ Vector3.new(0.25, 4.95, 0.25), at(9.3, 16, -0.85) },
		}
	do
		decor(data[1], data[2], Color3.fromRGB(80, 80, 92), Enum.Material.Neon, {
			Parent = trim,
			Tags = { "NightNeon" },
		})
	end

	-- shelving along the back wall
	local products = Builder.folder("Products", model)
	local order = 0
	for _, unitX in { -9, 0, 9 } do
		decor(Vector3.new(8, 10, 0.3), at(unitX, 5, 32.65), Builder.shade(Palette.Wood, -0.2), Enum.Material.Wood)
		for _, side in { -4, 4 } do
			decor(Vector3.new(0.3, 10, 2.2), at(unitX + side, 5, 31.6), Palette.WoodDark, Enum.Material.Wood)
		end
		for level, boardY in { 0.6, 3.6, 6.6, 9.6 } do
			decor(Vector3.new(8, 0.25, 2.2), at(unitX, boardY - 0.125, 31.6), Palette.Wood, Enum.Material.Wood)
			if level <= 3 then
				for _, dx in { -2.6, 0, 2.6 } do
					order += 1
					addProductSlot(products, order, at(unitX + dx, boardY, 31.5), category.Id, accent, rng, 1)
				end
			end
		end
		decor(Vector3.new(7.6, 0.12, 0.12), at(unitX, 9.4, 30.5), accent, Enum.Material.Neon, { Tags = { "DayNeon" } })
	end

	-- featured display table
	decor(Vector3.new(6, 0.35, 4), at(-7, 3, 14), Palette.MarbleLight, Enum.Material.Marble, { CanCollide = true })
	solid(nil, Vector3.new(4.6, 2.8, 2.6), at(-7, 1.4, 14), Palette.WoodDark, Enum.Material.Wood)
	decor(Vector3.new(6.05, 0.12, 4.05), at(-7, 2.78, 14), accent, Enum.Material.Neon, { Tags = { "DayNeon" } })
	for _, dx in { -1.8, 0, 1.8 } do
		order += 1
		addProductSlot(
			products,
			order,
			at(-7 + dx, 3.18, 14) * CFrame.Angles(0, math.pi, 0),
			category.Id,
			accent,
			rng,
			1.15
		)
	end

	-- counter & register
	local counter = Builder.model("Counter", model)
	Builder.part({
		Parent = counter,
		Size = Vector3.new(7, 3.6, 2.4),
		CFrame = at(9.5, 1.8, 10),
		Color = Palette.WoodDark,
		Material = Enum.Material.Wood,
	})
	local counterTop = Builder.part({
		Name = "Top",
		Parent = counter,
		Size = Vector3.new(7.6, 0.3, 3),
		CFrame = at(9.5, 3.75, 10),
		Color = Palette.MarbleLight,
		Material = Enum.Material.Marble,
	})
	decor(
		Vector3.new(7, 0.2, 0.1),
		at(9.5, 0.5, 8.75),
		accent,
		Enum.Material.Neon,
		{ Parent = counter, Tags = { "NightNeon" } }
	)
	decor(Vector3.new(0.4, 0.6, 0.4), at(10.8, 4.2, 10.3), Palette.DarkMetal, Enum.Material.Metal, { Parent = counter })
	local screen =
		decor(Vector3.new(1.9, 1.2, 0.15), at(10.8, 5.05, 10.3), Color3.fromRGB(20, 20, 30), nil, { Parent = counter })
	Builder.label(screen, Enum.NormalId.Front, "$", { Color = Palette.NeonGreen, Font = FONT_TITLE })
	decor(Vector3.new(1.6, 0.2, 1), at(8, 4, 10), Color3.fromRGB(40, 40, 50), nil, { Parent = counter })
	Builder.prompt(counterTop, {
		Name = "ServePrompt",
		ActionText = "Serve Customer",
		ObjectText = "Register",
		MaxActivationDistance = 9,
	}):SetAttribute("PromptKind", "Serve")

	-- stock crates
	local crates = Builder.model("Crates", model)
	local crate = Builder.part({
		Name = "Crate",
		Parent = crates,
		Size = Vector3.new(2.2, 2.2, 2.2),
		CFrame = at(-12, 1.1, 22),
		Color = CARDBOARD,
		Material = Enum.Material.Cardboard,
	})
	Builder.part({
		Parent = crates,
		Size = Vector3.new(2, 2, 2),
		CFrame = at(-12, 1, 24.4) * CFrame.Angles(0, 0.3, 0),
		Color = Builder.shade(CARDBOARD, -0.1),
		Material = Enum.Material.Cardboard,
	})
	Builder.decor({
		Parent = crates,
		Size = Vector3.new(1.7, 1.7, 1.7),
		CFrame = at(-12, 3.05, 23) * CFrame.Angles(0, -0.25, 0),
		Color = Builder.shade(CARDBOARD, 0.08),
		Material = Enum.Material.Cardboard,
	})
	Builder.prompt(crate, {
		Name = "RestockPrompt",
		ActionText = "Order Stock",
		ObjectText = "Stock Crates",
		MaxActivationDistance = 9,
	}):SetAttribute("PromptKind", "Restock")

	-- lease stand outside the door
	local stand = Builder.model("LeaseStand", model)
	Builder.decor({
		Parent = stand,
		Size = Vector3.new(0.35, 3.2, 0.35),
		CFrame = at(-8, 1.6, -3),
		Color = Palette.Gold,
		Material = Enum.Material.Metal,
	})
	local board = Builder.part({
		Name = "Board",
		Parent = stand,
		Size = Vector3.new(3, 1.8, 0.2),
		CFrame = at(-8, 3.9, -3),
		Color = Color3.fromRGB(20, 16, 30),
		CanCollide = false, -- stays clickable but never blocks the doorway once hidden
	})
	Builder.label(board, Enum.NormalId.Front, "FOR LEASE\nClaim free!", {
		Color = Palette.NeonGold,
		Font = FONT_TITLE,
	})
	Builder.prompt(board, {
		Name = "ClaimPrompt",
		ActionText = "Claim Shop",
		ObjectText = category.Name,
		MaxActivationDistance = 10,
	}):SetAttribute("PromptKind", "Claim")

	-- dressing
	for _, data in
		{
			{ Vector3.new(-6, 17, 24), false },
			{ Vector3.new(6, 17, 24), false },
			{ Vector3.new(0, 16, 12), true },
		}
	do
		local p = (origin * CFrame.new(data[1])).Position
		Props.pendantLamp(p, origin.Position.Y + 20, model, data[2])
	end
	Props.pottedPlant((origin * CFrame.new(-12.5, 0, 2.5)).Position, model, rng)
	Props.pottedPlant((origin * CFrame.new(12.5, 0, 3)).Position, model, rng)
	for _, data in
		{
			{ at(-13.85, 9, 12) * CFrame.Angles(0, -math.pi / 2, 0), category.Icon .. "\nNEW!" },
			{ at(13.85, 9, 22) * CFrame.Angles(0, math.pi / 2, 0), "SALE\n%" },
		}
	do
		local poster = decor(Vector3.new(4.2, 5.4, 0.1), data[1], Builder.shade(accent, -0.4))
		Builder.label(
			poster,
			Enum.NormalId.Front,
			data[2],
			{ Color = Color3.new(1, 1, 1), Font = FONT_TITLE, Lit = true }
		)
	end
	Props.lurkerEyes(at(12.6, 15.5, 32.85) * CFrame.Angles(0, math.pi, 0), model, 1.1)

	-- navigation points (world space)
	local points = {
		Lane = Vector3.new(0, 0, -10),
		Door = Vector3.new(0, 0, -3),
		Entry = Vector3.new(0, 0, 4),
		Aisle = Vector3.new(0, 0, 24),
		Browse1 = Vector3.new(-8, 0, 28),
		Browse2 = Vector3.new(0, 0, 28),
		Browse3 = Vector3.new(8, 0, 28),
		CounterApproach = Vector3.new(4, 0, 6.5),
		Counter = Vector3.new(9.5, 0, 7.2),
		Stock = Vector3.new(0, 0, 20),
	}
	for name, localPoint in points do
		model:SetAttribute("P_" .. name, (origin * CFrame.new(localPoint)).Position)
	end
	model:SetAttribute("CounterFacing", origin:VectorToWorldSpace(Vector3.new(0, 0, 1)))

	Builder.tag(model, "Shop")
	return model
end

return ShopUnit
