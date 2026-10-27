-- Premium detail pass for the atrium (visual benchmark slice). Adds the layers that make
-- the space read as designed rather than blocked out: floor tiling, fluted columns with
-- night uplights, brass railing posts, fountain jets, seating islands, kiosk carts, the
-- directory, the hero neon sign, hanging wayfinding, sun shafts and ambient particles.
-- Every addition avoids the customer route (see Layout.CustomerRoute) and nav points.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local AssetRegistry = require(script.Parent.AssetRegistry)
local Builder = require(script.Parent.Builder)
local Layout = require(script.Parent.Layout)
local Props = require(script.Parent.Props)

local LobbyDetail = {}

local A = Layout.Atrium
local FONT_TITLE = Font.new("rbxasset://fonts/families/Creepster.json")
local FONT_HEADING = Font.new("rbxasset://fonts/families/FredokaOne.json")

local function ringPoint(radius: number, angle: number, y: number): Vector3
	return Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
end

local function nearEscalatorTop(p: Vector3, distance: number): boolean
	for _, escalator in Layout.Escalators do
		local top = escalator.Top
		if Vector3.new(p.X - top.X, 0, p.Z - top.Z).Magnitude < distance then
			return true
		end
	end
	return false
end

local function floorDetail(parent: Instance)
	local floor = parent:FindFirstChild("AtriumFloor", true)
	if floor then
		Builder.tag(floor, "ReflectiveFloor")
	end
	-- large-format tile grout (sits below the compass-rose inlays)
	local grout = Color3.fromRGB(198, 186, 168)
	for v = -60, 60, 10 do
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(0.16, 0.012, A.Half * 2),
			CFrame = CFrame.new(v, 0.006, 0),
			Color = grout,
		})
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(A.Half * 2, 0.012, 0.16),
			CFrame = CFrame.new(0, 0.006, v),
			Color = grout,
		})
	end
	-- dark promenade ring under the balcony edge
	local count = 48
	local step = math.pi * 2 / count
	for i = 0, count - 1 do
		local p = ringPoint(40.6, i * step, 0.012)
		Builder.decor({
			Parent = parent,
			Size = Vector3.new(2 * 41.2 * math.tan(step / 2) + 0.05, 0.02, 1.2),
			CFrame = CFrame.lookAt(p, Vector3.new(0, p.Y, 0)),
			Color = Palette.MarbleDark,
			Material = Enum.Material.Marble,
		})
	end
end

local function columnDetail(parent: Instance)
	for i = 0, 7 do
		local angle = (i + 0.5) * math.pi / 4
		local base = ringPoint(A.ColumnRadius, angle, 0)
		if not AssetRegistry.has("Column") then
			for k = 0, 7 do
				local a = k * math.pi / 4
				Builder.decor({
					Parent = parent,
					Size = Vector3.new(0.24, A.Height - 2, 0.3),
					CFrame = CFrame.new(base + Vector3.new(math.cos(a) * 1.5, A.Height / 2, math.sin(a) * 1.5))
						* CFrame.Angles(0, -a, 0),
					Color = Palette.MarbleWarm,
					Material = Enum.Material.Marble,
				})
			end
		end
		-- night uplight on the atrium side of each column
		local inward = -Vector3.new(math.cos(angle), 0, math.sin(angle))
		Props.uplight(base + inward * 2.6, if i % 2 == 0 then Palette.NeonPurple else Palette.NeonCyan, parent, 3)
	end
end

local function balconyDetail(parent: Instance)
	local count = 32
	local step = math.pi * 2 / count
	for i = 0, count - 1 do
		local p = ringPoint(A.BalconyInner + 0.5, i * step, A.BalconyY)
		if not nearEscalatorTop(p, 5.5) then
			Builder.decor({
				Parent = parent,
				Size = Vector3.new(0.3, 3.5, 0.3),
				CFrame = CFrame.new(p + Vector3.new(0, 1.75, 0)),
				Color = Palette.Gold,
				Material = Enum.Material.Metal,
			})
		end
	end
end

local function fountainJets(parent: Instance)
	local anchor = Builder.decor({
		Name = "FountainJets",
		Parent = parent,
		Size = Vector3.one,
		CFrame = CFrame.new(0, 2, 0),
		Transparency = 1,
	})
	for i = 0, 7 do
		local angle = i * math.pi / 4 + math.pi / 8
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local nozzle = outward * 10.5 + Vector3.new(0, 2.15, 0)
		Builder.decor({
			Parent = parent,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.5,
			CFrame = CFrame.new(nozzle),
			Color = Palette.Gold,
			Material = Enum.Material.Metal,
		})
		local up = (-outward * 0.55 + Vector3.new(0, 0.85, 0)).Unit
		local tangent = Vector3.new(-outward.Z, 0, outward.X)
		local attachment = Instance.new("Attachment")
		attachment.Parent = anchor
		attachment.WorldCFrame = CFrame.fromMatrix(nozzle, tangent, up)
		local jet = Instance.new("ParticleEmitter")
		jet.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		jet.Color = ColorSequence.new(Color3.fromRGB(225, 250, 255), Color3.fromRGB(130, 215, 245))
		jet.LightEmission = 0.35
		jet.Transparency = NumberSequence.new(0.2, 0.9)
		jet.Size = NumberSequence.new(0.35, 0.18)
		jet.Speed = NumberRange.new(9, 10)
		jet.SpreadAngle = Vector2.new(3, 3)
		jet.Acceleration = Vector3.new(0, -34, 0)
		jet.Lifetime = NumberRange.new(0.55, 0.65)
		jet.Rate = 22
		jet.EmissionDirection = Enum.NormalId.Top
		jet.Parent = attachment
	end
end

local function seating(parent: Instance)
	if AssetRegistry.has("PlanterBench") then
		return -- the authored planter already includes its bench
	end
	for i = 0, 5 do
		Props.ringBench(ringPoint(22, math.rad(30 + i * 60), 0), 3.2, 4.3, parent)
	end
end

local function retail(parent: Instance)
	Props.kioskCart(
		CFrame.lookAt(Vector3.new(-46, 0, -6), Vector3.new(0, 0, -6)),
		"Moonbeam Coffee",
		Palette.NeonPink,
		parent
	)
	Props.kioskCart(
		CFrame.lookAt(Vector3.new(-20, 0, -44), Vector3.new(0, 0, -30)),
		"Cosmo Candy",
		Palette.NeonCyan,
		parent
	)
	local spawn = Layout.PlayerSpawn.Position
	Props.directoryTotem(CFrame.lookAt(Vector3.new(14, 0, -44), Vector3.new(spawn.X, 0, spawn.Z)), {
		"MALL DIRECTORY",
		"› East Wing — 6 shops for lease",
		"› Upper Level — escalators",
		"› Food Court — coming soon",
		"🛍️ Claim a shop for free!",
	}, parent)
end

-- The hero sign: big enough to read from spawn, echoing the key-art logo.
local function heroSign(parent: Instance)
	local center = Vector3.new(0, 43, A.Half - 0.4)
	local cf = CFrame.lookAt(center, center + Vector3.new(0, 0, -1))
	local board = Builder.decor({
		Name = "HeroSign",
		Parent = parent,
		Size = Vector3.new(36, 7, 0.5),
		CFrame = cf,
		Color = Color3.fromRGB(14, 10, 26),
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 2.4
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.74)
	title.Text = "NIGHT SHIFT"
	title.TextScaled = true
	title.FontFace = FONT_TITLE
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 248, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(235, 248, 255)),
		ColorSequenceKeypoint.new(0.52, Palette.NeonPink),
		ColorSequenceKeypoint.new(1, Palette.NeonPink),
	})
	gradient.Parent = title
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.NeonPurple
	stroke.Thickness = 5
	stroke.Parent = title
	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromScale(0.2, 0.74)
	subtitle.Size = UDim2.fromScale(0.6, 0.22)
	subtitle.Text = "— M A L L —"
	subtitle.TextScaled = true
	subtitle.FontFace = FONT_HEADING
	subtitle.TextColor3 = Color3.fromRGB(255, 220, 250)
	subtitle.Parent = gui
	gui.Parent = board

	for _, data in
		{
			{ Vector3.new(36.6, 0.3, 0.3), Vector3.new(0, 3.65, -0.3), Palette.NeonPink },
			{ Vector3.new(36.6, 0.3, 0.3), Vector3.new(0, -3.65, -0.3), Palette.NeonPink },
			{ Vector3.new(0.3, 7.6, 0.3), Vector3.new(-18.3, 0, -0.3), Palette.NeonCyan },
			{ Vector3.new(0.3, 7.6, 0.3), Vector3.new(18.3, 0, -0.3), Palette.NeonCyan },
		}
	do
		Builder.decor({
			Parent = parent,
			Size = data[1],
			CFrame = cf * CFrame.new(data[2]),
			Color = data[3],
			Material = Enum.Material.Neon,
			Tags = { "NightNeon" },
		})
	end
	Builder.light("PointLight", board, { Range = 22, Brightness = 1.2, Color = Palette.NeonPink }, { "FxLight" })
end

local function wayfinding(parent: Instance)
	local y = A.BalconyY - 1.5
	Props.hangingSign(
		CFrame.lookAt(Vector3.new(52, 17.6, -14), Vector3.new(52, 17.6, -30)),
		11,
		2.6,
		"SHOPS  ›  EAST WING",
		Palette.NeonCyan,
		y,
		parent
	)
	Props.hangingSign(
		CFrame.lookAt(Vector3.new(-50, 17.6, -24), Vector3.new(-50, 17.6, -40)),
		11,
		2.6,
		"↑ UPPER LEVEL",
		Palette.NeonPink,
		y,
		parent
	)
end

local function atmosphere(parent: Instance)
	local sun = Lighting:GetSunDirection()
	if sun.Y > 0.2 then
		local anchor = Builder.decor({
			Name = "ShaftAnchor",
			Parent = parent,
			Size = Vector3.one,
			CFrame = CFrame.new(0, 1, 0),
			Transparency = 1,
		})
		local flatSun = Vector3.new(sun.X, 0, sun.Z)
		local reach = (A.Height + 1.5) / sun.Y -- distance along the ray to the dome opening
		for _, offset in
			{
				Vector3.new(0, 0, 0),
				Vector3.new(14, 0, 6),
				Vector3.new(-12, 0, 10),
				Vector3.new(8, 0, -16),
				Vector3.new(-16, 0, -8),
			}
		do
			-- shift into the sunlit patch and keep only points whose ray clears the opening
			local floor = offset - flatSun / math.max(flatSun.Magnitude, 0.01) * 6
			local through = floor + sun * reach
			if Vector3.new(through.X, 0, through.Z).Magnitude < A.DomeRadius - 6 then
				Props.sunShaft(anchor, floor, sun, reach + 30, 9)
			end
		end
	end
	Props.ambientVolume(CFrame.new(0, 18, 0), Vector3.new(84, 34, 84), 16, parent)
end

function LobbyDetail.build(parent: Instance)
	local model = Builder.model("AtriumDetail", parent)
	floorDetail(parent)
	columnDetail(model)
	balconyDetail(model)
	fountainJets(model)
	seating(model)
	retail(model)
	heroSign(model)
	wayfinding(model)
	atmosphere(model)
	return model
end

return LobbyDetail
