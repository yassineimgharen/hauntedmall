-- In-game HUD. Everything is derived from replicated attributes (phase, cash, XP,
-- battery...) so it never drifts from server state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local MissionClient = require(script.Parent.Parent.Parent.MissionClient)
local Components = require(script.Parent.Parent.Components)
local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer

local Hud = {}
Hud.__index = Hud

local PHASES = {
	Intermission = {
		Icon = "🛍️",
		Color = C.Day,
		Title = function()
			return "MALL OPENING"
		end,
	},
	Day = {
		Icon = "☀️",
		Color = C.Day,
		Title = function(n)
			return "DAY " .. (n + 1)
		end,
	},
	Dusk = {
		Icon = "🌆",
		Color = C.Pink,
		Title = function()
			return "CLOSING TIME"
		end,
	},
	Night = {
		Icon = "🌙",
		Color = C.Night,
		Title = function(n)
			return "NIGHT " .. n
		end,
	},
	Dawn = {
		Icon = "🌅",
		Color = C.Gold,
		Title = function()
			return "DAWN"
		end,
	},
}

local BANNERS = {
	Day = { "OPEN FOR BUSINESS", "Serve customers, stock up, upgrade." },
	Dusk = { "THE MALL IS CLOSED", "Grab your flashlight..." },
	Night = { "NIGHT %d", "Repair the fuses. Protect your shop. Survive." },
	Dawn = { "YOU SURVIVED", "The shadows retreat... for now." },
}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

function Hud.new(root: Frame, callbacks: { OpenShop: () -> (), OpenSettings: () -> (), OpenCampaign: () -> () })
	local self = setmetatable({}, Hud)
	self.Root = Create("Frame", {
		Name = "HUD",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	self.Callbacks = callbacks
	self.LastCash = player:GetAttribute("Cash")
	self:_buildPhase()
	self:_buildStats()
	self:_buildGoals()
	self:_buildVitals()
	self:_buildButtons()
	self:_buildOverlays()
	self:_bind()
	return self
end

function Hud:_buildPhase()
	local pill = Components.panel({
		Name = "Phase",
		Size = UDim2.fromOffset(300, 70),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = self.Root,
	})
	self.PhaseStroke = pill:FindFirstChildOfClass("UIStroke")
	self.PhaseIcon = Create.text({
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromOffset(12, 8),
		Text = "☀️",
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = pill,
	})
	self.PhaseTitle = Create.text({
		Size = UDim2.new(1, -150, 0, 30),
		Position = UDim2.fromOffset(64, 10),
		Text = "DAY 1",
		FontFace = Theme.Fonts.Heading,
		Parent = pill,
	})
	self.PhaseTimer = Create.text({
		Size = UDim2.fromOffset(78, 30),
		Position = UDim2.new(1, -14, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		Text = "0:00",
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = pill,
	})
	local bar, set = Components.bar({
		Size = UDim2.new(1, -28, 0, 8),
		Position = UDim2.new(0, 14, 1, -16),
		Parent = pill,
	}, C.Day)
	self.PhaseBar = bar
	self.SetPhaseProgress = set
	self.NightInfo = Create.text({
		Size = UDim2.fromOffset(360, 22),
		Position = UDim2.new(0.5, 0, 0, 88),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Text,
		TextStrokeTransparency = 0.4,
		Parent = self.Root,
	})
end

function Hud:_buildStats()
	local cash = Components.panel({
		Name = "Cash",
		Size = UDim2.fromOffset(220, 50),
		Position = UDim2.fromOffset(16, 12),
		Parent = self.Root,
	})
	Create.text({ Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(10, 8), Text = "💰", Parent = cash })
	self.CashLabel = Create.text({
		Size = UDim2.new(1, -60, 0, 30),
		Position = UDim2.fromOffset(50, 10),
		Text = "$0",
		TextColor3 = C.Gold,
		FontFace = Theme.Fonts.Heading,
		Parent = cash,
	})
	self.CashPanel = cash

	local level = Components.panel({
		Name = "Level",
		Size = UDim2.fromOffset(220, 46),
		Position = UDim2.fromOffset(16, 70),
		Parent = self.Root,
	})
	local badge = Create("Frame", {
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.fromOffset(8, 6),
		BackgroundColor3 = C.Purple,
		Parent = level,
	}, { Create.round(), Create.gradient(C.Pink, C.Purple, 45) })
	self.LevelLabel = Create.text({
		Size = UDim2.fromScale(0.8, 0.6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "1",
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Heading,
		Parent = badge,
	})
	self.XPLabel = Create.text({
		Size = UDim2.new(1, -60, 0, 16),
		Position = UDim2.fromOffset(50, 6),
		Text = "0 / 100 XP",
		TextColor3 = C.TextDim,
		Parent = level,
	})
	local _, setXP = Components.bar({
		Size = UDim2.new(1, -62, 0, 10),
		Position = UDim2.fromOffset(50, 27),
		Parent = level,
	}, C.Cyan)
	self.SetXP = setXP
end

function Hud:_buildGoals()
	local panel = Components.panel({
		Name = "Goals",
		Size = UDim2.fromOffset(290, 214),
		Position = UDim2.fromOffset(16, 126),
		BackgroundTransparency = 0.2,
		Parent = self.Root,
	})
	self.GoalsTitle = Create.text({
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 10),
		Text = "SHIFT GOALS",
		FontFace = Theme.Fonts.Heading,
		TextColor3 = C.Cyan,
		Parent = panel,
	})
	local list = Create("Frame", {
		Size = UDim2.new(1, -24, 1, -44),
		Position = UDim2.fromOffset(12, 38),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { Create.list(nil, 6) })
	self.GoalsPanel = panel
	self.GoalRows = {}
	for i = 1, 6 do
		self.GoalRows[i] = Create.text({
			Size = UDim2.new(1, 0, 0, 26),
			Text = "",
			TextScaled = false,
			TextSize = 15,
			TextWrapped = true,
			FontFace = Theme.Fonts.Body,
			LayoutOrder = i,
			Parent = list,
		})
	end
	self.GoalHint = Create.text({
		Size = UDim2.new(1, -24, 0, 34),
		Position = UDim2.new(0, 12, 1, -42),
		Text = "",
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = C.Gold,
		FontFace = Theme.Fonts.Bold,
		Parent = panel,
	})
end

function Hud:_buildVitals()
	local holder = Create("Frame", {
		Size = UDim2.fromOffset(320, 52),
		Position = UDim2.new(0.5, 0, 1, -100),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = self.Root,
	}, { Create.list(nil, 6, Enum.HorizontalAlignment.Center) })
	local function row(icon: string, color: Color3, order: number)
		local frame = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = holder,
		})
		Create.text({
			Size = UDim2.fromOffset(22, 22),
			Text = icon,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = frame,
		})
		local bar, set = Components.bar({
			Size = UDim2.new(1, -30, 0, 14),
			Position = UDim2.fromOffset(30, 4),
			Parent = frame,
		}, color)
		return frame, bar, set
	end
	local _, _, setHealth = row("❤️", C.Red, 1)
	self.SetHealth = setHealth
	local batteryRow, _, setBattery = row("🔋", C.Gold, 2)
	self.BatteryRow = batteryRow
	self.SetBattery = setBattery
end

function Hud:_buildButtons()
	local column = Create("Frame", {
		Size = UDim2.fromOffset(72, 260),
		Position = UDim2.new(1, -16, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Parent = self.Root,
	}, { Create.list(nil, 12, Enum.HorizontalAlignment.Center) })
	local function sideButton(icon: string, caption: string, color: Color3, order: number, onClick: () -> ())
		local button = Components.button({
			Text = icon,
			Color = color,
			Size = UDim2.fromOffset(64, 64),
			LayoutOrder = order,
			Parent = column,
			OnClick = onClick,
		})
		Create.text({
			Size = UDim2.new(1, 8, 0, 16),
			Position = UDim2.new(0.5, 0, 1, 2),
			AnchorPoint = Vector2.new(0.5, 0),
			Text = caption,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.3,
			Parent = button,
		})
	end
	sideButton("🏪", "SHOP [B]", C.Pink, 1, self.Callbacks.OpenShop)
	sideButton("🗺️", "CAMPAIGN [M]", C.Purple, 2, self.Callbacks.OpenCampaign)
	sideButton("⚙️", "SETTINGS", C.PanelLighter, 3, self.Callbacks.OpenSettings)
end

function Hud:_buildOverlays()
	-- red edge vignette for damage (four gradient strips; no image assets needed)
	self.Vignette = {}
	for _, data in
		{
			{ UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0), 90 },
			{ UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0.75), -90 },
			{ UDim2.fromScale(0.18, 1), UDim2.fromScale(0, 0), 0 },
			{ UDim2.fromScale(0.18, 1), UDim2.fromScale(0.82, 0), 180 },
		}
	do
		local frame = Create("Frame", {
			Size = data[1],
			Position = data[2],
			BackgroundColor3 = C.Red,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = self.Root,
		})
		Create("UIGradient", {
			Rotation = data[3],
			Transparency = NumberSequence.new(0, 1),
			Parent = frame,
		})
		table.insert(self.Vignette, frame)
	end

	self.Banner = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 150),
		Position = UDim2.fromScale(0.5, 0.32),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = self.Root,
	})
	self.BannerTitle = Create.text({
		Size = UDim2.new(0.9, 0, 0, 92),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		FontFace = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = self.Banner,
	})
	Create("UIStroke", { Color = C.Purple, Thickness = 4, Parent = self.BannerTitle })
	self.BannerSub = Create.text({
		Size = UDim2.new(0.7, 0, 0, 30),
		Position = UDim2.new(0.5, 0, 0, 100),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		FontFace = Theme.Fonts.Heading,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		Parent = self.Banner,
	})

	self.MockWarning = Create.text({
		Size = UDim2.fromOffset(420, 18),
		Position = UDim2.new(0, 16, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		Text = "ℹ️ Studio test mode: saving is off, progress lasts this session only",
		TextColor3 = C.Gold,
		TextStrokeTransparency = 0.4,
		Visible = false,
		Parent = self.Root,
	})
end

function Hud:ShowBanner(title: string, subtitle: string, color: Color3?)
	self.Banner.Visible = true
	self.BannerTitle.Text = title
	self.BannerTitle.TextColor3 = color or C.Text
	self.BannerSub.Text = subtitle
	self.BannerTitle.TextTransparency = 1
	self.BannerSub.TextTransparency = 1
	TweenService:Create(self.BannerTitle, Theme.TweenSlow, { TextTransparency = 0 }):Play()
	TweenService:Create(self.BannerSub, Theme.TweenSlow, { TextTransparency = 0 }):Play()
	local token = {}
	self.BannerToken = token
	task.delay(3.2, function()
		if self.BannerToken ~= token then
			return
		end
		TweenService:Create(self.BannerTitle, Theme.TweenSlow, { TextTransparency = 1 }):Play()
		TweenService:Create(self.BannerSub, Theme.TweenSlow, { TextTransparency = 1 }):Play()
		task.wait(0.5)
		if self.BannerToken == token then
			self.Banner.Visible = false
		end
	end)
end

-- Short orange edge pulse + "!" when a monster starts winding up an attack on you.
function Hud:FlashWarning()
	for _, frame in self.Vignette do
		frame.BackgroundColor3 = C.Gold
		frame.BackgroundTransparency = 0.55
		TweenService:Create(frame, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	end
	self:Popup("⚠ DODGE!", C.Gold, UDim2.fromScale(0.5, 0.6))
end

function Hud:FlashDamage()
	for _, frame in self.Vignette do
		frame.BackgroundColor3 = C.Red
		frame.BackgroundTransparency = 0.35
		TweenService:Create(frame, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		task.spawn(function()
			for _ = 1, 6 do
				humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 0.5
				task.wait(0.03)
			end
			humanoid.CameraOffset = Vector3.zero
		end)
	end
end

-- Floating "+$12" near a screen anchor.
function Hud:Popup(text: string, color: Color3, position: UDim2)
	local label = Create.text({
		Size = UDim2.fromOffset(160, 30),
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = text,
		TextColor3 = color,
		FontFace = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Parent = self.Root,
	})
	TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad), {
		Position = position - UDim2.fromOffset(0, 40),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.2, function()
		label:Destroy()
	end)
end

-- Floating "+$12" above a point in the world (e.g. the register).
function Hud:WorldPopup(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 6, 0))
	anchor.Parent = workspace
	local gui = Create("BillboardGui", {
		Size = UDim2.fromOffset(160, 40),
		AlwaysOnTop = true,
		Adornee = anchor,
		Parent = anchor,
	})
	local label = Create.text({
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = color,
		FontFace = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.2,
		Parent = gui,
	})
	TweenService:Create(gui, TweenInfo.new(1.2), { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.3, function()
		anchor:Destroy()
	end)
end

-- Tutorial steps are persisted server-side (Tut_* attributes), so they never un-tick.
local DAY_STEPS = {
	{
		Flag = "Claimed",
		Text = "Claim a shop in the East Wing",
		Hint = "Follow the marker to a FOR LEASE stand and press E.",
	},
	{
		Flag = "Stocked",
		Text = "Order stock at your 📦 crates",
		Hint = "The crates are in your shop's back corner. Press E.",
	},
	{
		Flag = "Served",
		Text = "Serve a customer at the register",
		Hint = "When a 💬 customer waits at your till, press E for a tip.",
	},
	{ Flag = "Upgraded", Text = "Buy an upgrade", Hint = "Press B (or 🏪) and pick an upgrade you can afford." },
}

-- Campaign objectives from MissionService. Returns false when no level is running.
function Hud:_missionGoals(): (boolean, { { Text: string, State: string } }, string)
	local snapshot = MissionClient.Snapshot
	if not snapshot or not snapshot.Rows then
		return false, {}, ""
	end
	self.GoalsTitle.Text = snapshot.Title or "MISSION"
	local rows = {}
	local nextFound = false
	for _, row in snapshot.Rows do
		local text = row.Text
		local avoid = row.Kind == "Avoid"
		if avoid and row.Target > 0 then
			text ..= string.format(" (%d/%d max)", row.Progress, row.Target)
		elseif not avoid and row.Target > 1 then
			text ..= string.format(" (%d/%d)", row.Progress, row.Target)
		end
		if row.Team then
			text = "👥 " .. text
		end
		local state = "todo"
		if row.Failed then
			state = "failed"
		elseif row.Done then
			state = "done"
		elseif row.Optional then
			state = "optional"
		elseif avoid then
			state = "guard" -- holds unless it fails; nothing to "do"
		elseif row.Kind == "Survive" then
			state = "info"
		elseif not nextFound and not snapshot.Final then
			nextFound = true
			state = "next"
		end
		table.insert(rows, { Text = text, State = state })
	end
	local hint = snapshot.Hint or ""
	if snapshot.Guest then
		hint = "Guest: this level isn't unlocked for you yet, so no level credit (cash & XP still count)."
	elseif snapshot.LateJoin then
		hint = "You joined mid-night: help out! Level credit starts with the next full night."
	elseif snapshot.Final then
		hint = if snapshot.Stage == "Day" then "Day over. Night is coming…" else "Night over. Results incoming…"
	elseif snapshot.Stage == "Day" and snapshot.DayCleared then
		hint = if hint ~= "" then hint else "Day already cleared on an earlier try. Tonight is what counts."
	elseif snapshot.Stage == "Night" then
		-- say plainly what tonight can and can't do for the level
		local requiredLeft = false
		for _, row in snapshot.Rows do
			if not row.Optional and not row.Done and row.Kind == "Count" then
				requiredLeft = true
			end
		end
		if not snapshot.DayCleared then
			hint = "⚠️ This level's DAY isn't cleared, so tonight can't complete it. " .. hint
		elseif not requiredLeft then
			hint = "✅ Night objectives done: the level completes at dawn. Stay safe!"
		end
	end
	return true, rows, hint
end

function Hud:_updateGoals()
	local phase = ReplicatedStorage:GetAttribute("Phase")
	local rows: { { Text: string, State: string } } = {}
	local hint = ""

	local mission, missionRows, missionHint = self:_missionGoals()
	if mission then
		rows, hint = missionRows, missionHint
	elseif phase == "Night" or phase == "Dusk" then
		local repaired = ReplicatedStorage:GetAttribute("FusesRepaired") or 0
		local total = ReplicatedStorage:GetAttribute("FusesTotal") or 3
		local equipped = player.Character ~= nil and player.Character:FindFirstChild("Flashlight") ~= nil
		self.GoalsTitle.Text = "NIGHT SHIFT"
		rows = {
			{ Text = "Equip your flashlight [1]", State = if equipped then "done" else "next" },
			{
				Text = string.format("Repair fuse boxes (%d/%d)", repaired, total),
				State = if repaired >= total then "done" elseif equipped then "next" else "todo",
			},
			{ Text = "Defend your shop's stock", State = "info" },
			{ Text = "Survive until dawn", State = "info" },
		}
		hint = if equipped
			then "Hold click / 🔦 to burn shadows. Follow the ⚡ marker to a fuse box."
			else "Press 1 (or tap the flashlight in your hotbar)."
	elseif player:GetAttribute("Tut_Completed") then
		local remaining = (ReplicatedStorage:GetAttribute("PhaseStartedAt") or 0)
			+ (ReplicatedStorage:GetAttribute("PhaseDuration") or 0)
			- workspace:GetServerTimeNow()
		local stock = player:GetAttribute("ShopStock") or 0
		self.GoalsTitle.Text = "DAILY ROUTINE"
		rows = {
			{
				Text = string.format("Keep shelves stocked (%d/%d)", stock, player:GetAttribute("ShopMaxStock") or 0),
				State = if stock > 0 then "done" else "next",
			},
			{ Text = "Serve customers for +50% tips", State = "info" },
			{ Text = "Upgrade 🔦 Lens & 🔋 Battery", State = "info" },
			{
				Text = if phase == "Day"
					then "Night falls in " .. Format.time(remaining)
					else "Get ready for the night",
				State = "info",
			},
		}
		hint = if stock > 0 then "" else "Your shelves are empty. Order stock at your crates."
	else
		self.GoalsTitle.Text = "SHIFT GOALS"
		local nextFound = false
		for _, step in DAY_STEPS do
			local done = player:GetAttribute("Tut_" .. step.Flag) == true
			if step.Flag == "Claimed" and player:GetAttribute("ShopId") ~= nil then
				done = true
			end
			local state: "done" | "next" | "todo" = "todo"
			if done then
				state = "done"
			elseif not nextFound then
				nextFound = true
				state = "next"
				hint = step.Hint
				if step.Flag ~= "Claimed" and player:GetAttribute("ShopId") == nil then
					hint = "Claim a shop again first (shops reset when you leave a server)."
				end
			end
			table.insert(rows, { Text = step.Text, State = state })
		end
	end

	local styles = {
		done = { "✅ ", C.Green },
		next = { "▶ ", C.Gold },
		todo = { "⬜ ", C.TextDim },
		info = { "• ", C.Text },
		optional = { "★ ", C.Cyan },
		failed = { "❌ ", C.Red },
		guard = { "🛡 ", C.Gold },
	}
	for i, label in self.GoalRows do
		local row = rows[i]
		label.Visible = row ~= nil
		if row then
			local style = styles[row.State] or styles.info
			label.Text = style[1] .. row.Text
			label.TextColor3 = style[2]
		end
	end
	local count = math.min(#rows, #self.GoalRows)
	self.GoalsPanel.Size = UDim2.fromOffset(290, 38 + count * 32 + (if hint ~= "" then 48 else 8))
	self.GoalHint.Text = hint
end

function Hud:_updatePhase()
	local phase = ReplicatedStorage:GetAttribute("Phase") or "Intermission"
	local info = PHASES[phase] or PHASES.Intermission
	local night = ReplicatedStorage:GetAttribute("NightNumber") or 0
	local level = ReplicatedStorage:GetAttribute("LevelIndex") or 0
	self.PhaseIcon.Text = info.Icon
	if level > 0 and (phase == "Day" or phase == "Night") then
		self.PhaseTitle.Text = string.upper(phase) .. " " .. level
	else
		self.PhaseTitle.Text = info.Title(night)
	end
	self.PhaseTitle.TextColor3 = info.Color
	if self.PhaseStroke then
		self.PhaseStroke.Color = info.Color
	end
	self.PhaseBar.Fill.BackgroundColor3 = info.Color
end

function Hud:_tick()
	local started = ReplicatedStorage:GetAttribute("PhaseStartedAt") or serverNow()
	local duration = ReplicatedStorage:GetAttribute("PhaseDuration") or 1
	local remaining = started + duration - serverNow()
	self.PhaseTimer.Text = Format.time(remaining)
	self.SetPhaseProgress(1 - remaining / duration, true)

	local phase = ReplicatedStorage:GetAttribute("Phase")
	if phase == "Night" then
		local total = ReplicatedStorage:GetAttribute("FusesTotal") or 0
		local fuses = if total > 0
			then string.format("⚡ Breakers %d/%d   ", ReplicatedStorage:GetAttribute("FusesRepaired") or 0, total)
			else ""
		self.NightInfo.Text = string.format(
			"%s%s👁️ Wave %d   👾 %d shadows",
			if ReplicatedStorage:GetAttribute("Blackout") then "🌑 BLACKOUT   " else "",
			fuses,
			ReplicatedStorage:GetAttribute("Wave") or 0,
			workspace:GetAttribute("EnemiesAlive") or 0
		)
	elseif phase == "Day" and player:GetAttribute("ShopId") then
		self.NightInfo.Text = string.format(
			"📦 Stock %d/%d",
			player:GetAttribute("ShopStock") or 0,
			player:GetAttribute("ShopMaxStock") or 0
		)
	else
		self.NightInfo.Text = ""
	end

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self.SetHealth(humanoid.Health / math.max(humanoid.MaxHealth, 1))
	end
	local equipped = player.Character ~= nil and player.Character:FindFirstChild("Flashlight") ~= nil
	self.BatteryRow.Visible = equipped or phase == "Night"
	self.SetBattery(player:GetAttribute("Battery") or 1)
end

function Hud:_bind()
	local function onCash()
		local cash = player:GetAttribute("Cash") or 0
		self.CashLabel.Text = Format.cash(cash)
		if self.LastCash and cash ~= self.LastCash and self.Root.Visible then
			local delta = cash - self.LastCash
			self:Popup(
				(if delta > 0 then "+" else "-") .. Format.cash(math.abs(delta)),
				if delta > 0 then C.Green else C.Red,
				UDim2.fromOffset(130, 74)
			)
		end
		self.LastCash = cash
	end
	local function onLevel()
		local xp = player:GetAttribute("XP") or 0
		local needed = player:GetAttribute("XPNeeded") or 100
		self.LevelLabel.Text = tostring(player:GetAttribute("Level") or 1)
		self.XPLabel.Text = string.format("%s / %s XP", Format.number(xp), Format.number(needed))
		self.SetXP(xp / math.max(needed, 1))
	end
	player:GetAttributeChangedSignal("Cash"):Connect(onCash)
	player:GetAttributeChangedSignal("XP"):Connect(onLevel)
	player:GetAttributeChangedSignal("Level"):Connect(onLevel)
	player:GetAttributeChangedSignal("DataMock"):Connect(function()
		self.MockWarning.Visible = player:GetAttribute("DataMock") == true
	end)
	self.MockWarning.Visible = player:GetAttribute("DataMock") == true
	onCash()
	onLevel()

	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(function()
		self:_updatePhase()
		local phase = ReplicatedStorage:GetAttribute("Phase")
		local banner = BANNERS[phase]
		if banner and self.Root.Visible then
			local title = string.format(banner[1], ReplicatedStorage:GetAttribute("NightNumber") or 1)
			local subtitle = banner[2]
			local level = CampaignConfig.ById[ReplicatedStorage:GetAttribute("LevelId") or ""]
			if level and (phase == "Day" or phase == "Night") then
				title = string.format("%s %d: %s", string.upper(phase), level.Index, string.upper(level[phase].Name))
				subtitle = level[phase].Teaser
			elseif level and phase == "Dawn" then
				subtitle = "The shadows retreat. Checking your level results…"
			end
			local info = PHASES[phase]
			self:ShowBanner(title, subtitle, info and info.Color)
		end
	end)
	self:_updatePhase()

	RunService.RenderStepped:Connect(function()
		if self.Root.Visible then
			self:_tick()
		end
	end)
	task.spawn(function()
		while true do
			if self.Root.Visible then
				self:_updateGoals()
			end
			task.wait(0.5)
		end
	end)
end

function Hud:SetVisible(visible: boolean)
	self.Root.Visible = visible
	if visible then
		self.LastCash = player:GetAttribute("Cash")
		self:_updateGoals()
	end
end

return Hud
