-- One player-ownable store. Local space: origin at the doorway on the floor,
-- +Z runs into the shop, -Z faces the corridor. Width 30, depth 34.
--
-- Contract used by ShopService / CustomerService / GuideController (do not rename):
--   children  Sign (SurfaceGui Gui.Title), Trim (neon parts), Products (slot models with
--             Order), LeaseStand.Board.ClaimPrompt, Crates.Crate.RestockPrompt,
--             Counter.Top.ServePrompt
--   attributes ShopId, Category, Accent, and world-space nav points P_* (Vector3)
--
-- Floor plan (local, top view; customers walk the "+" path):
--
--   z=34 ┌──────────────── feature wall + logo ─────────────────┐
--        │  [shelf]        [shelf]        [shelf]                │
--   z=28 │   B1 +           B2 +           B3 +                  │
--   z=24 │ crates           + aisle          ┌gondola┐ poster    │
--        │ (stock)          +                │display│           │
--   z=14 │  [feature table] +                └───────┘ cabinet   │
--        │ plant            +          ┌──counter──┐             │
--   z=7  │                  + ─ ─ ─ ─ ─+ approach  + till        │
--   z=2  │ [window plinth]  + entry     [window plinth]          │
--   z=0  └─glass───────────door──────────glass────────── blade ──┘

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Builder = require(script.Parent.Builder)
local Props = require(script.Parent.Props)

local ShopUnit = {}

local FONT_TITLE = Font.new("rbxasset://fonts/families/FredokaOne.json")
local FONT_BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
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

-- Stock-visualising merchandise (one per shelf slot; hidden until stocked).
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

-- Category hero pieces: window displays and the in-store feature fixture. These are
-- always visible (they are the shop's identity), unlike the stock slots.
local function heroPlush(parent: Instance, cf: CFrame, color: Color3, scale: number)
	local function ball(size: number, offset: Vector3, c: Color3, material: Enum.Material?)
		Builder.decor({
			Parent = parent,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size * scale,
			CFrame = cf * CFrame.new(offset * scale),
			Color = c,
			Material = material or Enum.Material.Fabric,
			CastShadow = true,
		})
	end
	ball(2.6, Vector3.new(0, 1.3, 0), color)
	ball(1.9, Vector3.new(0, 3.1, 0), Builder.shade(color, 0.1))
	ball(0.75, Vector3.new(-0.75, 3.95, 0), color)
	ball(0.75, Vector3.new(0.75, 3.95, 0), color)
	ball(0.8, Vector3.new(0, 2.9, -0.8), Color3.fromRGB(255, 246, 236))
	ball(0.2, Vector3.new(-0.35, 3.3, -0.85), Color3.fromRGB(30, 26, 40), Enum.Material.SmoothPlastic)
	ball(0.2, Vector3.new(0.35, 3.3, -0.85), Color3.fromRGB(30, 26, 40), Enum.Material.SmoothPlastic)
	ball(0.8, Vector3.new(-1.2, 1.6, -0.4), Builder.shade(color, 0.1))
	ball(0.8, Vector3.new(1.2, 1.6, -0.4), Builder.shade(color, 0.1))
end

local function heroMannequin(parent: Instance, cf: CFrame, shirt: Color3)
	local function part(size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?, material: Enum.Material?)
		Builder.decor({
			Parent = parent,
			Shape = shape,
			Size = size,
			CFrame = cf * offset,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			CastShadow = true,
		})
	end
	local skin = Color3.fromRGB(240, 238, 244)
	part(
		Vector3.new(0.3, 1.6, 1.6),
		CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Palette.Gold,
		Enum.PartType.Cylinder,
		Enum.Material.Metal
	)
	part(Vector3.new(0.18, 3.2, 0.18), CFrame.new(0, 1.8, 0), Palette.Gold, nil, Enum.Material.Metal)
	part(Vector3.new(1.7, 0.7, 1), CFrame.new(0, 3.45, 0), Color3.fromRGB(46, 44, 60))
	part(Vector3.new(2.1, 2.2, 1.1), CFrame.new(0, 4.9, 0), shirt, nil, Enum.Material.Fabric)
	part(Vector3.new(2.5, 0.5, 1.15), CFrame.new(0, 5.85, 0), Builder.shade(shirt, -0.15), nil, Enum.Material.Fabric)
	part(Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 6.3, 0), skin, Enum.PartType.Cylinder)
	part(Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, 7, 0), skin, Enum.PartType.Ball)
end

local function heroGadget(parent: Instance, cf: CFrame, accent: Color3)
	Builder.decor({
		Parent = parent,
		Size = Vector3.new(1.2, 2.2, 1.2),
		CFrame = cf * CFrame.new(0, 1.1, 0),
		Color = Color3.fromRGB(30, 28, 42),
		CastShadow = true,
	})
	local screen = Builder.decor({
		Parent = parent,
		Size = Vector3.new(4.2, 2.6, 0.25),
		CFrame = cf * CFrame.new(0, 3.6, 0) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = Color3.fromRGB(18, 16, 28),
		CastShadow = true,
	})
	Builder.decor({
		Parent = parent,
		Size = Vector3.new(3.9, 2.3, 0.05),
		CFrame = cf * CFrame.new(0, 3.6, 0) * CFrame.Angles(math.rad(-12), 0, 0) * CFrame.new(0, 0, -0.14),
		Color = Builder.shade(accent, -0.25),
		Material = Enum.Material.Neon,
	})
	Builder.label(
		screen,
		Enum.NormalId.Front,
		"NEW!\nPLAY ME",
		{ Color = Color3.new(1, 1, 1), Font = FONT_TITLE, GuiName = "Demo" }
	)
	Builder.decor({
		Parent = parent,
		Size = Vector3.new(1.6, 0.25, 0.9),
		CFrame = cf * CFrame.new(0, 2.3, -0.9) * CFrame.Angles(math.rad(10), 0, 0),
		Color = Color3.fromRGB(240, 240, 248),
	})
end

local function featureFixture(parent: Instance, category: string, cf: CFrame, accent: Color3, rng: Random)
	-- cf: centre of a 3 x 8 footprint, long axis = local Z
	Builder.part({
		Parent = parent,
		Size = Vector3.new(3, 0.6, 8),
		CFrame = cf * CFrame.new(0, 0.3, 0),
		Color = Palette.WoodDark,
		Material = Enum.Material.Wood,
	})
	Builder.decor({
		Parent = parent,
		Size = Vector3.new(3.05, 0.1, 8.05),
		CFrame = cf * CFrame.new(0, 0.12, 0),
		Color = accent,
		Material = Enum.Material.Neon,
		Tags = { "DayNeon" },
	})
	if category == "Toys" then
		for i, z in { -2.6, 0, 2.6 } do
			-- +90° turns the plush's front (-Z) toward the shop centre (-X)
			heroPlush(
				parent,
				cf * CFrame.new(0, 0.6, z) * CFrame.Angles(0, math.rad(90 + (i - 2) * 15), 0),
				PASTELS[rng:NextInteger(1, #PASTELS)],
				0.55
			)
		end
	elseif category == "Apparel" then
		for _, x in { -1.1, 1.1 } do
			Builder.decor({
				Parent = parent,
				Size = Vector3.new(0.15, 5, 0.15),
				CFrame = cf * CFrame.new(0, 3.1, x * 3.2),
				Color = Palette.Gold,
				Material = Enum.Material.Metal,
			})
		end
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(0.12, 0.12, 7.2),
			CFrame = cf * CFrame.new(0, 5.5, 0),
			Color = Palette.Gold,
			Material = Enum.Material.Metal,
		})
		for i = 0, 6 do
			local z = -3 + i
			local tee = PASTELS[rng:NextInteger(1, #PASTELS)]
			Builder.decor({
				Parent = parent,
				Size = Vector3.new(1.6, 2, 0.12),
				CFrame = cf * CFrame.new(0, 4.35, z) * CFrame.Angles(0, math.rad(90 + rng:NextNumber(-8, 8)), 0),
				Color = tee,
				Material = Enum.Material.Fabric,
				CastShadow = true,
			})
			Builder.decor({
				Parent = parent,
				Size = Vector3.new(2.2, 0.5, 0.13),
				CFrame = cf * CFrame.new(0, 5.15, z) * CFrame.Angles(0, math.rad(90), 0),
				Color = tee,
				Material = Enum.Material.Fabric,
			})
		end
	else
		Builder.part({
			Parent = parent,
			Size = Vector3.new(2.8, 2.4, 7.6),
			CFrame = cf * CFrame.new(0, 1.8, 0),
			Color = Color3.fromRGB(34, 30, 48),
		})
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(3, 0.25, 7.8),
			CFrame = cf * CFrame.new(0, 3.1, 0),
			Color = Palette.MarbleLight,
			Material = Enum.Material.Marble,
		})
		for _, z in { -2.4, 0, 2.4 } do
			Builder.decor({
				Parent = parent,
				Size = Vector3.new(1.4, 1, 0.12),
				CFrame = cf
					* CFrame.new(0, 3.75, z)
					* CFrame.Angles(0, math.rad(-90), 0)
					* CFrame.Angles(math.rad(-20), 0, 0),
				Color = Color3.fromRGB(20, 18, 30),
			})
			Builder.decor({
				Parent = parent,
				Size = Vector3.new(1.2, 0.8, 0.05),
				CFrame = cf
					* CFrame.new(-0.08, 3.77, z)
					* CFrame.Angles(0, math.rad(-90), 0)
					* CFrame.Angles(math.rad(-20), 0, 0),
				Color = accent,
				Material = Enum.Material.Neon,
			})
		end
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
	local wallColor = Palette.Wall:Lerp(accent, 0.08)
	local accentDark = Builder.shade(accent, -0.55)

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

	-- ── shell ───────────────────────────────────────────────────────────────
	solid("Floor", Vector3.new(30, 1, 34), at(0, -0.5, 17), Palette.Wood, Enum.Material.WoodPlanks)
	-- polished showroom tile inlaid in the wood floor
	decor(Vector3.new(18, 0.04, 20), at(0, 0.02, 19), Palette.MarbleLight, Enum.Material.Marble)
	decor(Vector3.new(18.6, 0.03, 20.6), at(0, 0.015, 19), Palette.Gold, Enum.Material.Metal)
	decor(Vector3.new(12, 0.06, 8), at(-1, 0.06, 19.5), accentDark, Enum.Material.Fabric)
	decor(Vector3.new(8, 0.06, 2.8), at(0, 0.04, 2.4), Color3.fromRGB(34, 30, 44), Enum.Material.Fabric)

	solid(nil, Vector3.new(1, 20, 34), at(-14.5, 10, 17), wallColor)
	solid(nil, Vector3.new(1, 20, 34), at(14.5, 10, 17), wallColor)
	solid(nil, Vector3.new(30, 20, 1), at(0, 10, 33.5), wallColor)
	solid(nil, Vector3.new(30, 1, 34), at(0, 20.5, 17), Palette.Wall)

	-- wainscot panelling, brass cap rail, crown moulding on three walls
	for _, data in
		{
			{ Vector3.new(0.2, 4, 33), Vector3.new(-13.9, 0, 17), 0 },
			{ Vector3.new(0.2, 4, 33), Vector3.new(13.9, 0, 17), 0 },
			{ Vector3.new(28, 4, 0.2), Vector3.new(0, 0, 32.9), 1 },
		}
	do
		local size, p = data[1], data[2]
		decor(size, at(p.X, 2, p.Z), Builder.shade(accent, -0.45), Enum.Material.Wood)
		local railSize = if data[3] == 1 then Vector3.new(size.X, 0.15, 0.35) else Vector3.new(0.35, 0.15, size.Z)
		decor(railSize, at(p.X, 4.05, p.Z), Palette.Gold, Enum.Material.Metal)
		local crownSize = if data[3] == 1 then Vector3.new(size.X, 0.5, 0.45) else Vector3.new(0.45, 0.5, size.Z)
		decor(crownSize, at(p.X, 19.7, p.Z), Palette.MarbleLight, Enum.Material.Marble)
		local lineSize = if data[3] == 1 then Vector3.new(size.X, 0.1, 0.5) else Vector3.new(0.5, 0.1, size.Z)
		decor(lineSize, at(p.X, 19.4, p.Z), Palette.Gold, Enum.Material.Metal)
	end

	-- ceiling light troughs
	for _, x in { -6, 6 } do
		decor(Vector3.new(1.4, 0.2, 24), at(x, 19.92, 19), Palette.WallTrim, nil)
		decor(
			Vector3.new(0.5, 0.1, 23),
			at(x, 19.8, 19),
			Palette.WarmLight,
			Enum.Material.Neon,
			{ Tags = { "DayNeon" } }
		)
	end

	-- feature wall: deep accent panel behind the shelving, logo band, neon line
	decor(Vector3.new(27.6, 9.6, 0.1), at(0, 5.2, 32.95), accentDark, nil)
	decor(Vector3.new(27, 0.25, 0.15), at(0, 12.5, 32.85), accent, Enum.Material.Neon, { Tags = { "NightNeon" } })
	local logo = decor(Vector3.new(24, 3.4, 0.1), at(0, 15.2, 32.9), wallColor, nil)
	Builder.label(logo, Enum.NormalId.Front, category.Icon .. "  " .. string.upper(category.Name), {
		Color = Builder.shade(accent, -0.2),
		Font = FONT_TITLE,
		Lit = true,
		GuiName = "Logo",
	})

	-- ── storefront ──────────────────────────────────────────────────────────
	for _, x in { -10, 10 } do
		solid(nil, Vector3.new(10, 1.2, 0.7), at(x, 0.6, 0), Palette.DarkMetal, Enum.Material.Metal)
		decor(Vector3.new(10, 0.12, 0.8), at(x, 1.26, 0), Palette.Gold, Enum.Material.Metal)
		Builder.part({
			Parent = model,
			Size = Vector3.new(10, 9.8, 0.25),
			CFrame = at(x, 6.2, 0),
			Color = Palette.Glass,
			Material = Enum.Material.Glass,
			Transparency = 0.65,
			CastShadow = false,
		})
		decor(Vector3.new(10, 0.5, 0.8), at(x, 11.35, 0), Palette.DarkMetal, Enum.Material.Metal)
	end
	for _, x in { -15, -5, 5, 15 } do
		solid(nil, Vector3.new(0.7, 12, 0.9), at(x, 6, 0), Palette.DarkMetal, Enum.Material.Metal)
	end
	for _, x in { -4.62, 4.62 } do
		decor(Vector3.new(0.08, 12, 0.92), at(x, 6, 0), Palette.Gold, Enum.Material.Metal)
	end
	decor(Vector3.new(10, 0.05, 1.2), at(0, 0.025, 0), Palette.Gold, Enum.Material.Metal)

	-- fascia with marble cap and brass line
	solid(nil, Vector3.new(31, 8, 1), at(0, 16, 0), Palette.DarkMetal, Enum.Material.Metal)
	decor(Vector3.new(31.2, 0.6, 1.3), at(0, 19.7, 0), Palette.MarbleWarm, Enum.Material.Marble)
	decor(Vector3.new(31.2, 0.15, 1.15), at(0, 12.12, 0), Palette.Gold, Enum.Material.Metal)
	decor(Vector3.new(19.2, 5.4, 0.1), at(0, 16, -0.53), Color3.fromRGB(8, 6, 14), nil)

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

	-- projecting blade sign: readable from far down the corridor
	decor(Vector3.new(0.2, 0.2, 3.4), at(13.2, 16.4, -1.7), Palette.Gold, Enum.Material.Metal)
	local blade = decor(Vector3.new(0.4, 3.2, 2.8), at(13.2, 14.6, -2.1), Color3.fromRGB(16, 12, 26), nil)
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		Builder.label(blade, face, category.Icon .. "\n" .. category.Name, {
			Color = Color3.new(1, 1, 1),
			Font = FONT_TITLE,
			Stroke = accent,
			StrokeThickness = 2,
			GuiName = "Blade" .. face.Name,
		})
	end
	decor(Vector3.new(0.45, 0.15, 2.9), at(13.2, 12.95, -2.1), accent, Enum.Material.Neon, { Tags = { "NightNeon" } })

	-- display windows: marble plinths, a spot-lit hero piece behind each pane
	for _, x in { -10, 10 } do
		solid(nil, Vector3.new(8.6, 1.4, 3), at(x, 0.7, 2), Palette.MarbleLight, Enum.Material.Marble)
		decor(Vector3.new(8.7, 0.1, 3.1), at(x, 1.42, 2), Palette.Gold, Enum.Material.Metal)
		-- local -Z faces the corridor, so heroes face out through the glass, angled to the door
		local heroCF = at(x, 1.45, 2) * CFrame.Angles(0, if x < 0 then 0.35 else -0.35, 0)
		if category.Id == "Toys" then
			heroPlush(model, heroCF, PASTELS[rng:NextInteger(1, #PASTELS)], 0.9)
		elseif category.Id == "Apparel" then
			heroMannequin(model, heroCF, if x < 0 then accent else PASTELS[rng:NextInteger(1, #PASTELS)])
		else
			heroGadget(model, heroCF, accent)
		end
		local fixture = decor(Vector3.new(1, 0.3, 1), at(x, 11, 2), Palette.DarkMetal, Enum.Material.Metal)
		Builder.light("SpotLight", fixture, {
			Face = Enum.NormalId.Bottom,
			Angle = 70,
			Range = 14,
			Brightness = 2.4,
			Color = Palette.WarmLight,
		}, { "DayLight" })
	end

	-- ── shelving along the back wall (stock slots) ──────────────────────────
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
				decor(Vector3.new(7.6, 0.16, 0.06), at(unitX, boardY - 0.2, 30.48), Color3.fromRGB(248, 246, 240), nil)
				for _, dx in { -2.6, 0, 2.6 } do
					order += 1
					addProductSlot(products, order, at(unitX + dx, boardY, 31.5), category.Id, accent, rng, 1)
				end
			end
		end
		decor(Vector3.new(8.5, 0.5, 2.6), at(unitX, 10.1, 31.6), accentDark, Enum.Material.Wood)
		decor(Vector3.new(7.6, 0.12, 0.12), at(unitX, 9.4, 30.5), accent, Enum.Material.Neon, { Tags = { "DayNeon" } })
	end

	-- featured display table (stock slots on top)
	decor(Vector3.new(6, 0.35, 4), at(-7, 3, 14), Palette.MarbleLight, Enum.Material.Marble, { CanCollide = true })
	solid(nil, Vector3.new(4.6, 2.8, 2.6), at(-7, 1.4, 14), Palette.WoodDark, Enum.Material.Wood)
	decor(Vector3.new(6.05, 0.12, 4.05), at(-7, 2.78, 14), accent, Enum.Material.Neon, { Tags = { "DayNeon" } })
	local card = decor(
		Vector3.new(1.6, 0.9, 0.08),
		at(-7, 3.7, 12.15) * CFrame.Angles(math.rad(-15), 0, 0),
		Color3.fromRGB(250, 248, 240),
		nil
	)
	Builder.label(
		card,
		Enum.NormalId.Front,
		"FEATURED",
		{ Color = Builder.shade(accent, -0.3), Font = FONT_BODY, Lit = true }
	)
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

	-- category feature fixture (right side, clear of the customer path)
	featureFixture(model, category.Id, at(10, 0, 19), accent, rng)

	-- ── counter & register ──────────────────────────────────────────────────
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
	local front =
		decor(Vector3.new(6, 2.3, 0.1), at(9.5, 1.95, 8.76), Builder.shade(accent, -0.3), nil, { Parent = counter })
	Builder.label(
		front,
		Enum.NormalId.Front,
		category.Icon,
		{ Color = Color3.new(1, 1, 1), Font = FONT_TITLE, GuiName = "Badge" }
	)
	decor(
		Vector3.new(7, 0.2, 0.1),
		at(9.5, 0.5, 8.75),
		accent,
		Enum.Material.Neon,
		{ Parent = counter, Tags = { "NightNeon" } }
	)
	decor(Vector3.new(7.2, 0.12, 0.12), at(9.5, 3.55, 8.72), Palette.Gold, Enum.Material.Metal, { Parent = counter })
	decor(Vector3.new(0.4, 0.6, 0.4), at(10.8, 4.2, 10.3), Palette.DarkMetal, Enum.Material.Metal, { Parent = counter })
	local screen =
		decor(Vector3.new(1.9, 1.2, 0.15), at(10.8, 5.05, 10.3), Color3.fromRGB(20, 20, 30), nil, { Parent = counter })
	Builder.label(screen, Enum.NormalId.Front, "$", { Color = Palette.NeonGreen, Font = FONT_TITLE })
	decor(Vector3.new(1.6, 0.2, 1), at(8, 4, 10), Color3.fromRGB(40, 40, 50), nil, { Parent = counter })
	decor(Vector3.new(0.45, 0.6, 0.3), at(7.1, 4.2, 9.6), Color3.fromRGB(30, 30, 38), nil, { Parent = counter })
	for i, color in { accent, Builder.shade(accent, 0.3) } do
		decor(
			Vector3.new(1, 1.3, 0.5),
			at(12.3, 4.55, 10.4 + i * 0.25),
			color,
			Enum.Material.SmoothPlastic,
			{ Parent = counter }
		)
	end
	Builder.prompt(counterTop, {
		Name = "ServePrompt",
		ActionText = "Serve Customer",
		ObjectText = "Register",
		MaxActivationDistance = 9,
	}):SetAttribute("PromptKind", "Serve")

	-- back cabinet behind the register
	solid(nil, Vector3.new(1.2, 6, 5), at(13.4, 3, 13), Palette.WoodDark, Enum.Material.Wood)
	for _, y in { 2.2, 4.2 } do
		for i = 0, 3 do
			decor(
				Vector3.new(0.6, 1, 0.9),
				at(12.6, y + 0.5, 11 + i * 1.3),
				PASTELS[(i + y) % #PASTELS + 1],
				Enum.Material.SmoothPlastic
			)
		end
	end

	-- ── stock crates on a pallet ────────────────────────────────────────────
	local crates = Builder.model("Crates", model)
	Builder.decor({
		Parent = crates,
		Size = Vector3.new(3, 0.3, 5),
		CFrame = at(-12, 0.15, 23.2),
		Color = Palette.Wood,
		Material = Enum.Material.WoodPlanks,
	})
	local crate = Builder.part({
		Name = "Crate",
		Parent = crates,
		Size = Vector3.new(2.2, 2.2, 2.2),
		CFrame = at(-12, 1.4, 22),
		Color = CARDBOARD,
		Material = Enum.Material.Cardboard,
	})
	Builder.part({
		Parent = crates,
		Size = Vector3.new(2, 2, 2),
		CFrame = at(-12, 1.3, 24.4) * CFrame.Angles(0, 0.3, 0),
		Color = Builder.shade(CARDBOARD, -0.1),
		Material = Enum.Material.Cardboard,
	})
	Builder.decor({
		Parent = crates,
		Size = Vector3.new(1.7, 1.7, 1.7),
		CFrame = at(-12, 3.35, 23) * CFrame.Angles(0, -0.25, 0),
		Color = Builder.shade(CARDBOARD, 0.08),
		Material = Enum.Material.Cardboard,
	})
	Builder.prompt(crate, {
		Name = "RestockPrompt",
		ActionText = "Order Stock",
		ObjectText = "Stock Crates",
		MaxActivationDistance = 9,
	}):SetAttribute("PromptKind", "Restock")
	local stockSign = decor(
		Vector3.new(4, 1.4, 0.1),
		at(-13.85, 6.8, 23) * CFrame.Angles(0, -math.pi / 2, 0),
		Color3.fromRGB(20, 16, 30),
		nil
	)
	Builder.label(stockSign, Enum.NormalId.Front, "📦 STOCK", { Color = Palette.NeonGold, Font = FONT_TITLE })

	-- ── lease stand outside the door ────────────────────────────────────────
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

	-- ── dressing ────────────────────────────────────────────────────────────
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
	Props.pottedPlant((origin * CFrame.new(-13, 0, 6.5)).Position, model, rng)
	for _, data in
		{
			{ at(-13.85, 9, 12) * CFrame.Angles(0, -math.pi / 2, 0), category.Icon .. "\nNEW!" },
			{ at(13.85, 9, 22) * CFrame.Angles(0, math.pi / 2, 0), "SALE\n%" },
		}
	do
		decor(Vector3.new(4.6, 5.8, 0.08), data[1] * CFrame.new(0, 0, 0.03), Palette.Gold, Enum.Material.Metal)
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
