-- Boss health bar (top centre) while ReplicatedStorage.BossActive is set. Everything here
-- mirrors server attributes (BossHP/MaxHP/Phase, BossShield = Shielded | Down | Returning |
-- Defeated, BossShieldUntil, BossDarkness/BossDarkUntil, BossCannonsReady), so the text
-- always matches what the server will actually allow.
-- BossKind = "Chef" (Level 14): BossShield = Greased | Sick | Ravenous | Defeated, plus
-- BossHungerAt (next ORDER UP) and BossPass (Empty | Dish | Laced).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Components = require(script.Parent.Parent.Components)
local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors

local BossBar = {}

local PHASE_MARKS = { 0.66, 0.33 }

local function attr(name: string): any
	return ReplicatedStorage:GetAttribute(name)
end

local function secondsLeft(name: string): number
	return math.max(0, math.ceil((attr(name) or 0) - workspace:GetServerTimeNow()))
end

-- The Gorging Chef's status lines: what he is, and what the team should do right now.
function BossBar.chefStatus(state: string, hp: number): (string, Color3, string)
	if hp <= 0 or state == "Defeated" then
		return "👨‍🍳 DEFEATED!", C.Gold, "Dawn is coming: Chapter 2 complete!"
	elseif state == "Sick" then
		return string.format("🤢 SICK! BURN HIM NOW! (%ds)", secondsLeft("BossShieldUntil")),
			C.Green,
			"Hold your flashlight on his glowing belly!"
	elseif state == "Ravenous" then
		return string.format("😡 RAVENOUS! RUN! (%ds)", secondsLeft("BossShieldUntil")),
			C.Red,
			"Keep away, then get a LACED dish ready for the next order."
	end
	local pass = attr("BossPass")
	local passText = if pass == "Laced"
		then "Pass: 🧪 LACED DISH READY ✓"
		elseif pass == "Dish" then "Pass: ⚠️ PLAIN DISH (it will heal him!)"
		else "Pass: EMPTY. Cook 🍳 → lace 🧪 → serve 🍽️"
	return string.format("🧈 GREASED · ORDER UP IN %ds", secondsLeft("BossHungerAt")), C.Gold, passText
end

function BossBar.mount(root: Frame)
	local panel = Components.panel({
		Name = "BossBar",
		Size = UDim2.fromOffset(620, 112),
		Position = UDim2.new(0.5, 0, 0, 100),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = root,
	})
	local stroke = Create.stroke(C.Purple, 2.5, 0.1)
	stroke.Parent = panel
	local name = Create.text({
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.fromOffset(12, 6),
		Text = "",
		FontFace = Theme.Fonts.Title,
		TextColor3 = C.Purple,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})
	local bar, setHealth = Components.bar({
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 34),
		Parent = panel,
	}, C.Pink)
	local fill = bar:FindFirstChild("Fill") :: Frame
	for _, mark in PHASE_MARKS do
		Create("Frame", {
			Size = UDim2.new(0, 2, 1, 6),
			Position = UDim2.fromScale(mark, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = C.Text,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = bar,
		})
	end
	local hpText = Create.text({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextScaled = false,
		TextSize = 15,
		FontFace = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		ZIndex = 4,
		Parent = bar,
	})
	local status = Create.text({
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.fromOffset(12, 60),
		Text = "",
		TextScaled = false,
		TextSize = 22,
		FontFace = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		Parent = panel,
	})
	local hint = Create.text({
		Size = UDim2.new(1, -24, 0, 18),
		Position = UDim2.fromOffset(12, 88),
		Text = "",
		TextScaled = false,
		TextSize = 15,
		FontFace = Theme.Fonts.Bold,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})

	local lastHp: number? = nil
	local flashUntil = 0
	local function render()
		local active = attr("BossActive") == true
		panel.Visible = active
		if not active then
			lastHp = nil
			return
		end
		local hp = attr("BossHP") or 0
		local maxHp = math.max(attr("BossMaxHP") or 1, 1)
		local state = attr("BossShield") or (if attr("BossShielded") then "Shielded" else "Down")
		local dark = attr("BossDarkness") == true
		local ready = attr("BossCannonsReady") or 0
		name.Text = string.format("%s  ·  PHASE %d/3", attr("BossName") or "BOSS", attr("BossPhase") or 1)
		setHealth(hp / maxHp, false)
		hpText.Text = string.format("%d / %d", hp, maxHp)
		local barColor = if state == "Shielded" then C.Purple else C.Pink
		if attr("BossKind") == "Chef" then
			barColor = if state == "Sick" then C.Green else C.Gold
		end
		if lastHp and hp < lastHp then
			-- the bar blinks white on every hit so damage is impossible to miss
			fill.BackgroundColor3 = Color3.new(1, 1, 1)
			TweenService:Create(fill, TweenInfo.new(0.25), { BackgroundColor3 = barColor }):Play()
			flashUntil = os.clock() + 0.25
		elseif os.clock() > flashUntil then
			fill.BackgroundColor3 = barColor
		end
		lastHp = hp

		local text, color, hintText
		if attr("BossKind") == "Chef" then
			text, color, hintText = BossBar.chefStatus(state, hp)
		elseif hp <= 0 or state == "Defeated" then
			text, color, hintText = "👑 DEFEATED!", C.Gold, "Dawn is coming: Chapter 1 complete!"
		elseif state == "Down" then
			text = string.format("⚡ ATTACK NOW! SHIELD DOWN! (%ds)", secondsLeft("BossShieldUntil"))
			color, hintText = C.Green, "Hold your flashlight on her body: every hit shows a number."
		elseif state == "Returning" then
			text = string.format("⚠️ SHIELD RETURNING! (%ds)", secondsLeft("BossShieldUntil"))
			color, hintText = C.Gold, "Last chance to burn her, then get to a charged cannon."
		else
			text, color = "🛡️ SHIELDED: FIRE A LIGHT CANNON!", C.Purple
			hintText = if dark
				then string.format(
					"🌑 DARKNESS: cannons can't fire for %ds. Dodge and wait!",
					secondsLeft("BossDarkUntil")
				)
				elseif ready > 0 then string.format(
					"Your light can't hurt her yet. %d cannon%s ready: hold E at a gold 🔆 ring.",
					ready,
					if ready == 1 then "" else "s"
				)
				else "Cannons recharging: stand in a ring to charge it faster."
		end
		status.Text = text
		status.TextColor3 = color
		hint.Text = hintText
		stroke.Color = color
	end
	for _, attribute in
		{
			"BossActive",
			"BossHP",
			"BossMaxHP",
			"BossShield",
			"BossShielded",
			"BossPhase",
			"BossName",
			"BossDarkness",
			"BossCannonsReady",
			"BossKind",
			"BossHungerAt",
			"BossPass",
		}
	do
		ReplicatedStorage:GetAttributeChangedSignal(attribute):Connect(render)
	end
	-- countdowns tick even when nothing replicates
	task.spawn(function()
		while true do
			task.wait(0.25)
			if panel.Visible then
				render()
			end
		end
	end)
	render()
end

return BossBar
