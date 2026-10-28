-- Boss health bar (top centre) while ReplicatedStorage.BossActive is set: name, HP,
-- phase and whether the shield is up (the cue to fire a light cannon).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Parent.Components)
local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors

local BossBar = {}

function BossBar.mount(root: Frame)
	local panel = Components.panel({
		Name = "BossBar",
		Size = UDim2.fromOffset(560, 74),
		Position = UDim2.new(0.5, 0, 0, 104),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = root,
	})
	local name = Create.text({
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.fromOffset(12, 6),
		Text = "",
		FontFace = Theme.Fonts.Title,
		TextColor3 = C.Purple,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})
	local _, setHealth = Components.bar({
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.fromOffset(12, 34),
		Parent = panel,
	}, C.Pink)
	local status = Create.text({
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.fromOffset(12, 54),
		Text = "",
		TextScaled = false,
		TextSize = 14,
		FontFace = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})

	local function render()
		local active = ReplicatedStorage:GetAttribute("BossActive") == true
		panel.Visible = active
		if not active then
			return
		end
		local hp = ReplicatedStorage:GetAttribute("BossHP") or 0
		local maxHp = math.max(ReplicatedStorage:GetAttribute("BossMaxHP") or 1, 1)
		local shielded = ReplicatedStorage:GetAttribute("BossShielded") == true
		name.Text = string.format(
			"%s  ·  PHASE %d",
			ReplicatedStorage:GetAttribute("BossName") or "BOSS",
			ReplicatedStorage:GetAttribute("BossPhase") or 1
		)
		setHealth(hp / maxHp, false)
		status.Text = if hp <= 0
			then "DEFEATED"
			elseif shielded then "🛡️ SHIELDED: fire a light cannon!"
			else "⚡ SHIELD DOWN: burn her with your flashlight!"
		status.TextColor3 = if shielded then C.Gold else C.Green
	end
	for _, attribute in { "BossActive", "BossHP", "BossMaxHP", "BossShielded", "BossPhase", "BossName" } do
		ReplicatedStorage:GetAttributeChangedSignal(attribute):Connect(render)
	end
	render()
end

return BossBar
