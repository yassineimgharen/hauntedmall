-- Level 5 day, "Restricted Access": timing hazards and a code puzzle.
--
--   * 3 glass booths, each with 3 laser gates blinking on staggered timers. A lit laser
--     zaps (damage + knock-back out of the booth). An access card waits at the back.
--   * Each card (red / green / blue) shows one random digit when taken.
--   * The vault keypad wants the digits in the colour order printed on it (random each
--     day); the client keypad UI submits through the validated SubmitCode remote.
--   * Inside the opened vault, the security records set up tonight's Stalker.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Net = require(ReplicatedStorage.Shared.Net)
local GameStateService = require(script.Parent.Parent.Services.GameStateService)
local MissionEvents = require(script.Parent.Parent.Util.MissionEvents)
local Notify = require(script.Parent.Parent.Util.Notify)
local Builder = require(script.Parent.Parent.World.Builder)

local RestrictedAccess = {}

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local LASER_DAMAGE = 15
local LASER_PERIOD = 2.4
local LASER_ON = 1.3
local LOCKOUT = 3

local BOOTHS = {
	{ Entrance = Vector3.new(50, 0, 50), Color = "Red" },
	{ Entrance = Vector3.new(-46, 0, -46), Color = "Green" },
	{ Entrance = Vector3.new(156, 0, 0), Color = "Blue" },
}
local CARD_COLORS = {
	Red = Color3.fromRGB(255, 70, 80),
	Green = Color3.fromRGB(90, 232, 150),
	Blue = Color3.fromRGB(70, 150, 255),
}
local CARD_ICONS = { Red = "🟥", Green = "🟩", Blue = "🟦" }

local VAULT = CFrame.lookAt(Vector3.new(-55, 0, 52), Vector3.new(0, 0, 52)) -- door wall faces east

type Laser = { Parts: { BasePart }, Offset: number, LocalZ: number }
type Booth = { CFrame: CFrame, Lasers: { Laser } }

local folder: Folder? = nil
local token: {}? = nil
local booths: { Booth } = {}
local digits: { [string]: number } = {}
local found: { [string]: number } = {}
local order: { string } = {}
local opened = false
local keypadPart: BasePart? = nil
local openDoor: (() -> ())? = nil
local lockedUntil: { [Player]: number } = {}
local zappedAt: { [Player]: number } = {}
local rng = Random.new()

local function isDay(): boolean
	return token ~= nil and GameStateService.GetPhase() == "Day"
end

local function publish()
	ReplicatedStorage:SetAttribute("VaultCards", HttpService:JSONEncode(found))
	ReplicatedStorage:SetAttribute("VaultOrder", table.concat(order, ","))
end

-- ── laser booths ────────────────────────────────────────────────────────────

local function buildBooth(parent: Instance, info: { Entrance: Vector3, Color: string }, index: number)
	-- the entrance faces the atrium centre; the tunnel runs away from it (local +Z)
	local cf = CFrame.lookAt(info.Entrance, Vector3.new(0, info.Entrance.Y, 0))
	local model = Builder.model("LaserBooth" .. index, parent)
	local glass = { Parent = model, Color = Palette.Glass, Material = Enum.Material.Glass, Transparency = 0.6 }
	local function piece(size: Vector3, offset: Vector3, props: { [string]: any })
		local data = table.clone(props)
		data.Size = size
		data.CFrame = cf * CFrame.new(offset)
		return Builder.part(data)
	end
	piece(
		Vector3.new(6.4, 0.3, 11),
		Vector3.new(0, 0.15, 5.5),
		{ Parent = model, Color = Palette.DarkMetal, Material = Enum.Material.DiamondPlate }
	)
	for _, x in { -3.2, 3.2 } do
		piece(Vector3.new(0.3, 7, 11), Vector3.new(x, 3.5, 5.5), glass)
	end
	piece(Vector3.new(6.4, 7, 0.3), Vector3.new(0, 3.5, 11), glass)
	piece(
		Vector3.new(6.4, 0.3, 11),
		Vector3.new(0, 7.1, 5.5),
		{ Parent = model, Color = Palette.DarkMetal, Material = Enum.Material.Metal }
	)
	local sign = Builder.decor({
		Parent = model,
		Size = Vector3.new(5, 1.2, 0.2),
		CFrame = cf * CFrame.new(0, 7.9, 0),
		Color = Color3.fromRGB(20, 16, 30),
	})
	Builder.label(sign, Enum.NormalId.Front, "⚠ RESTRICTED · " .. string.upper(info.Color), {
		Color = CARD_COLORS[info.Color],
		Font = FONT,
	})

	local booth: Booth = { CFrame = cf, Lasers = {} }
	for i, z in { 2.5, 5, 7.5 } do
		local parts = {}
		for _, y in { 1.1, 3.4 } do
			for _, x in { -3.05, 3.05 } do -- emitters on both walls
				Builder.decor({
					Parent = model,
					Size = Vector3.new(0.3, 0.5, 0.5),
					CFrame = cf * CFrame.new(x, y, z),
					Color = Palette.DarkMetal,
					Material = Enum.Material.Metal,
				})
			end
			table.insert(
				parts,
				Builder.decor({
					Name = "Laser",
					Parent = model,
					Size = Vector3.new(6, 0.15, 0.15),
					CFrame = cf * CFrame.new(0, y, z),
					Color = Palette.NeonRed,
					Material = Enum.Material.Neon,
				})
			)
		end
		table.insert(booth.Lasers, { Parts = parts, Offset = (i - 1) * 0.8, LocalZ = z })
	end
	table.insert(booths, booth)

	-- the card on a pedestal at the back
	Builder.part({
		Parent = model,
		Size = Vector3.new(1.6, 3, 1.6),
		CFrame = cf * CFrame.new(0, 1.5, 9.4),
		Color = Palette.MarbleDark,
		Material = Enum.Material.Marble,
	})
	local card = Builder.decor({
		Name = "AccessCard",
		Parent = model,
		Size = Vector3.new(1.2, 0.1, 0.8),
		CFrame = cf * CFrame.new(0, 3.15, 9.4) * CFrame.Angles(0, 0.3, 0),
		Color = CARD_COLORS[info.Color],
		Material = Enum.Material.Neon,
	})
	Builder.light("PointLight", card, { Range = 8, Brightness = 1.5, Color = CARD_COLORS[info.Color] })
	Builder.tag(card, "AccessCard")
	local prompt = Builder.prompt(card, {
		Name = "TakePrompt",
		ActionText = "Take Access Card",
		ObjectText = info.Color .. " Card",
		MaxActivationDistance = 6,
	})
	prompt.Triggered:Connect(function(player)
		if not isDay() or card:GetAttribute("Done") then
			return
		end
		card:SetAttribute("Done", true)
		prompt.Enabled = false
		card.Transparency = 1
		found[info.Color] = digits[info.Color]
		publish()
		MissionEvents.record(player, "CardFound")
		Notify.all(
			string.format(
				"💳 %s took the %s %s card. It reads: %d",
				player.DisplayName,
				CARD_ICONS[info.Color],
				string.upper(info.Color),
				digits[info.Color]
			),
			"success"
		)
	end)
end

local function laserOn(laser: Laser, now: number): boolean
	return (now + laser.Offset) % LASER_PERIOD < LASER_ON
end

local function runLasers(myToken: {})
	while token == myToken do
		local now = os.clock()
		for _, booth in booths do
			for _, laser in booth.Lasers do
				local on = laserOn(laser, now)
				for _, part in laser.Parts do
					part.Transparency = if on then 0 else 0.92
				end
				if on then
					for _, player in Players:GetPlayers() do
						local character = player.Character
						local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
						local humanoid = character and character:FindFirstChildOfClass("Humanoid")
						if root and humanoid and humanoid.Health > 0 then
							local p = booth.CFrame:PointToObjectSpace(root.Position)
							local inside = math.abs(p.X) < 3.2 and math.abs(p.Z - laser.LocalZ) < 1 and p.Y < 6.5
							if inside and now - (zappedAt[player] or 0) > 1 then
								zappedAt[player] = now
								humanoid:TakeDamage(LASER_DAMAGE)
								Notify.effect(
									player,
									"Hit",
									{ Damage = LASER_DAMAGE, Direction = booth.CFrame.LookVector }
								)
								MissionEvents.record(player, "LaserTripped")
							end
						end
					end
				end
			end
		end
		task.wait(0.08)
	end
end

-- ── vault ───────────────────────────────────────────────────────────────────

local function buildVault(parent: Instance)
	local model = Builder.model("SecurityVault", parent)
	local metal = { Parent = model, Color = Color3.fromRGB(70, 74, 88), Material = Enum.Material.DiamondPlate }
	local function wall(size: Vector3, offset: Vector3)
		local data = table.clone(metal)
		data.Size = size
		data.CFrame = VAULT * CFrame.new(offset)
		return Builder.part(data)
	end
	-- local -Z faces east (the door side); the room spans local z -7..7, x -7..7
	wall(Vector3.new(14, 0.4, 14), Vector3.new(0, 0.2, 0))
	wall(Vector3.new(14, 10, 1), Vector3.new(0, 5, 7))
	wall(Vector3.new(1, 10, 14), Vector3.new(-7, 5, 0))
	wall(Vector3.new(1, 10, 14), Vector3.new(7, 5, 0))
	wall(Vector3.new(5, 10, 1), Vector3.new(-4.5, 5, -7))
	wall(Vector3.new(5, 10, 1), Vector3.new(4.5, 5, -7))
	wall(Vector3.new(4, 3, 1), Vector3.new(0, 8.5, -7))
	wall(Vector3.new(14, 0.5, 14), Vector3.new(0, 10.25, 0))
	for i = -3, 3 do
		Builder.decor({
			Parent = model,
			Size = Vector3.new(1.4, 0.6, 0.1),
			CFrame = VAULT * CFrame.new(i * 2, 9.6, -7.55) * CFrame.Angles(0, 0, math.rad(35)),
			Color = if i % 2 == 0 then Color3.fromRGB(240, 196, 40) else Color3.fromRGB(30, 30, 30),
		})
	end
	local sign = Builder.decor({
		Parent = model,
		Size = Vector3.new(6, 1.4, 0.2),
		CFrame = VAULT * CFrame.new(0, 11.4, -7.3),
		Color = Color3.fromRGB(20, 16, 30),
	})
	Builder.label(sign, Enum.NormalId.Front, "SECURITY VAULT", { Color = Palette.NeonRed, Font = FONT })
	local door = Builder.part({
		Name = "VaultDoor",
		Parent = model,
		Size = Vector3.new(4, 7, 0.6),
		CFrame = VAULT * CFrame.new(0, 3.5, -7),
		Color = Color3.fromRGB(110, 114, 128),
		Material = Enum.Material.Metal,
	})
	local lamp = Builder.decor({
		Parent = model,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.7,
		CFrame = VAULT * CFrame.new(0, 7.6, -7.7),
		Color = Palette.NeonRed,
		Material = Enum.Material.Neon,
	})

	local keypad = Builder.part({
		Name = "Keypad",
		Parent = model,
		Size = Vector3.new(1.4, 2, 0.4),
		CFrame = VAULT * CFrame.new(3.2, 4, -7.7),
		Color = Color3.fromRGB(26, 28, 36),
		Material = Enum.Material.Metal,
	})
	Builder.label(keypad, Enum.NormalId.Front, "🔢", { Color = Palette.NeonCyan })
	keypad:SetAttribute("Done", false)
	Builder.tag(keypad, "VaultKeypad")
	keypadPart = keypad
	local keypadPrompt = Builder.prompt(keypad, {
		Name = "KeypadPrompt",
		ActionText = "Enter Code",
		ObjectText = "Vault Keypad",
		MaxActivationDistance = 8,
	})
	keypadPrompt.Triggered:Connect(function(player)
		if isDay() and not opened then
			Notify.effect(player, "Keypad", { Order = order })
		end
	end)

	-- inside: the records desk
	Builder.part({
		Parent = model,
		Size = Vector3.new(5, 3, 2.4),
		CFrame = VAULT * CFrame.new(0, 1.5, 4.5),
		Color = Palette.WoodDark,
		Material = Enum.Material.Wood,
	})
	local records = Builder.part({
		Name = "Records",
		Parent = model,
		Size = Vector3.new(1.6, 0.4, 1.2),
		CFrame = VAULT * CFrame.new(0, 3.2, 4.5),
		Color = Color3.fromRGB(230, 220, 190),
	})
	Builder.light("PointLight", records, { Range = 10, Brightness = 1.2, Color = Palette.WarmLight })
	records:SetAttribute("Done", false)
	Builder.tag(records, "VaultRecords")
	local recordsPrompt = Builder.prompt(records, {
		Name = "ReadPrompt",
		ActionText = "Read Records",
		ObjectText = "Security Records",
		HoldDuration = 2,
		MaxActivationDistance = 7,
		Enabled = false,
	})
	recordsPrompt.Triggered:Connect(function(player)
		if not isDay() or records:GetAttribute("Done") then
			return
		end
		records:SetAttribute("Done", true)
		recordsPrompt.Enabled = false
		MissionEvents.record(player, "RecordsFound")
		Notify.all(
			'📁 RECORDS: "Subject S escaped containment. Blind. Hunts by SOUND. Steel lockers block it out. It hates the music boxes... until it finds who\'s near them."',
			"warning"
		)
	end)

	openDoor = function()
		opened = true
		door.CanCollide = false
		door.Transparency = 1
		lamp.Color = Palette.NeonGreen
		keypad:SetAttribute("Done", true)
		keypadPrompt.Enabled = false
		recordsPrompt.Enabled = true
	end
end

local function submitCode(player: Player, code: any)
	if not isDay() or opened or type(code) ~= "string" or not code:match("^%d%d%d$") then
		return
	end
	local keypad = keypadPart
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not keypad or not root or (root.Position - keypad.Position).Magnitude > 12 then
		return
	end
	local now = os.clock()
	if now < (lockedUntil[player] or 0) then
		Notify.player(player, "🔒 Keypad locked, try again in a moment.", "warning")
		return
	end
	local expected = ""
	for _, color in order do
		expected ..= tostring(digits[color])
	end
	if code ~= expected then
		lockedUntil[player] = now + LOCKOUT
		Notify.player(player, "❌ ACCESS DENIED. Check the colour order on the keypad.", "warning")
		return
	end
	if openDoor then
		openDoor()
	end
	MissionEvents.record(player, "CodeEntered")
	Notify.all(string.format("🔓 %s cracked the vault! The door slides open.", player.DisplayName), "success")
end

Net.handle("SubmitCode", 1, 3, submitCode)
Players.PlayerRemoving:Connect(function(player)
	lockedUntil[player] = nil
	zappedAt[player] = nil
end)

-- ── level hooks ─────────────────────────────────────────────────────────────

local function clear()
	token = nil
	opened = false
	openDoor = nil
	keypadPart = nil
	table.clear(booths)
	table.clear(found)
	table.clear(order)
	ReplicatedStorage:SetAttribute("VaultCards", nil)
	ReplicatedStorage:SetAttribute("VaultOrder", nil)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function RestrictedAccess.StartDay()
	clear()
	local myToken = {}
	token = myToken
	local newFolder = Instance.new("Folder")
	newFolder.Name = "RestrictedAccess"
	newFolder.Parent = workspace
	folder = newFolder

	order = { "Red", "Green", "Blue" }
	for i = #order, 2, -1 do -- shuffle the colour order
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for _, color in order do
		digits[color] = rng:NextInteger(0, 9)
	end
	publish()

	for index, info in BOOTHS do
		buildBooth(newFolder, info, index)
	end
	buildVault(newFolder)
	task.spawn(runLasers, myToken)
end

function RestrictedAccess.EndDay()
	clear()
end

return RestrictedAccess
