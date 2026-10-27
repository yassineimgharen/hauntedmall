-- Campaign map: 6 chapters × 7 levels, your progress, what this server is playing, and
-- votes for the next level. Voting only *asks*: the server validates the unlock and picks
-- the plurality at sunrise (CampaignLogic.pickLevel).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local MissionClient = require(script.Parent.Parent.Parent.MissionClient)
local Components = require(script.Parent.Parent.Components)
local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer

local CampaignPanel = {}
CampaignPanel.__index = CampaignPanel

type Status = "Cleared" | "Next" | "DayCleared" | "Locked" | "Soon"

local STATUS = {
	Cleared = { "✅ CLEARED", C.Green },
	Next = { "▶ NEXT UP", C.Gold },
	DayCleared = { "◐ DAY CLEARED", C.Cyan },
	Locked = { "🔒 LOCKED", C.TextDim },
	Soon = { "🚧 COMING SOON", C.TextDim },
}

local function statusOf(level: any, campaign: MissionClient.Campaign): Status
	if not level.Implemented then
		return "Soon"
	elseif campaign.Completed[level.Id] then
		return "Cleared"
	elseif campaign.Next == level.Id then
		return if campaign.DayCleared[level.Id] then "DayCleared" else "Next"
	end
	return "Locked"
end

function CampaignPanel.new(root: Frame, onClose: () -> ())
	local self = setmetatable({}, CampaignPanel)
	local modal, body = Components.modal(root, "🗺️  CAMPAIGN", UDim2.fromOffset(860, 560), onClose)
	self.Modal = modal
	self.Chapter = 1

	self.NowPlaying = Create.text({
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		FontFace = Theme.Fonts.Heading,
		TextColor3 = C.Gold,
		Parent = body,
	})
	self.Progress = Create.text({
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 26),
		Text = "",
		TextScaled = false,
		TextSize = 15,
		TextColor3 = C.TextDim,
		FontFace = Theme.Fonts.Body,
		Parent = body,
	})

	local tabs = Create("Frame", {
		Size = UDim2.new(0, 200, 1, -60),
		Position = UDim2.fromOffset(0, 56),
		BackgroundTransparency = 1,
		Parent = body,
	}, { Create.list(nil, 8) })
	self.Tabs = {}
	for _, chapter in CampaignConfig.Chapters do
		local button = Components.button({
			Text = "",
			Color = C.PanelLighter,
			Size = UDim2.new(1, 0, 0, 52),
			LayoutOrder = chapter.Index,
			Parent = tabs,
			OnClick = function()
				self.Chapter = chapter.Index
				self:Refresh()
			end,
		})
		local label = button:FindFirstChild("Label") :: TextLabel
		label.TextScaled = false
		label.TextSize = 15
		label.TextWrapped = true
		label.Size = UDim2.fromScale(0.92, 0.85)
		self.Tabs[chapter.Index] = button
	end
	Components.button({
		Text = "🌙 Vote Free Shift",
		Color = C.Purple,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 99,
		Parent = tabs,
		OnClick = function()
			Net.get("VoteLevel"):FireServer("FREE")
		end,
	})

	self.ChapterInfo = Create.text({
		Size = UDim2.new(1, -216, 0, 22),
		Position = UDim2.fromOffset(216, 56),
		Text = "",
		TextScaled = false,
		TextSize = 15,
		TextColor3 = C.Cyan,
		FontFace = Theme.Fonts.Bold,
		Parent = body,
	})
	self.List = Create("ScrollingFrame", {
		Size = UDim2.new(1, -216, 1, -88),
		Position = UDim2.fromOffset(216, 84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Purple,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, { Create.list(nil, 8), Create.padding(2, 2) })

	local function refreshIfOpen()
		if modal.Visible then
			self:Refresh()
		end
	end
	player:GetAttributeChangedSignal("CampaignState"):Connect(refreshIfOpen)
	ReplicatedStorage:GetAttributeChangedSignal("LevelVotes"):Connect(refreshIfOpen)
	ReplicatedStorage:GetAttributeChangedSignal("LevelId"):Connect(refreshIfOpen)
	return self
end

function CampaignPanel:_card(level: any, campaign: MissionClient.Campaign, votes: { [string]: number }, order: number)
	local status = statusOf(level, campaign)
	local style = STATUS[status]
	local playing = ReplicatedStorage:GetAttribute("LevelId") == level.Id
	local card = Components.panel({
		Size = UDim2.new(1, -10, 0, 104),
		BackgroundColor3 = if playing then C.PanelLighter else C.PanelLight,
		LayoutOrder = order,
		Parent = self.List,
	})
	Create.text({
		Size = UDim2.fromOffset(64, 40),
		Position = UDim2.fromOffset(12, 14),
		Text = tostring(level.Index),
		FontFace = Theme.Fonts.Title,
		TextColor3 = style[2],
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = card,
	})
	Create.text({
		Size = UDim2.fromOffset(70, 30),
		Position = UDim2.fromOffset(9, 58),
		Text = style[1],
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = style[2],
		FontFace = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = card,
	})
	for i, stage in { "Day", "Night" } do
		local info = level[stage]
		Create.text({
			Size = UDim2.new(1, -250, 0, 42),
			Position = UDim2.fromOffset(88, 8 + (i - 1) * 46),
			Text = string.format(
				'<font color="#%s"><b>%s %s</b></font>\n<font color="#B0A6D2">%s</font>',
				(if stage == "Day" then C.Day else C.Night):ToHex(),
				if stage == "Day" then "☀️" else "🌙",
				string.upper(info.Name),
				info.Teaser
			),
			RichText = true,
			TextScaled = false,
			TextSize = 14,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			FontFace = Theme.Fonts.Body,
			Parent = card,
		})
	end
	local rewards = if level.Rewards
		then string.format("%s · %d XP", Format.cash(level.Rewards.Cash), level.Rewards.XP)
		else ""
	local voteCount = votes[level.Id] or 0
	Create.text({
		Size = UDim2.fromOffset(150, 34),
		Position = UDim2.new(1, -160, 0, 6),
		Text = rewards .. (if voteCount > 0
			then string.format("\n🗳️ %d vote%s", voteCount, if voteCount == 1 then "" else "s")
			else ""),
		TextScaled = false,
		TextSize = 13,
		TextColor3 = C.Gold,
		FontFace = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	local playable = status == "Cleared" or status == "Next" or status == "DayCleared"
	local voted = campaign.Vote == level.Id
	local button = Components.button({
		Text = if voted
			then "VOTED ✓"
			elseif playable then (if status == "Cleared" then "REPLAY" else "VOTE")
			else if status == "Soon" then "SOON" else "🔒",
		Color = if voted then C.Green elseif playable then C.Pink else C.PanelLighter,
		Size = UDim2.fromOffset(130, 42),
		Position = UDim2.new(1, -14, 1, -12),
		AnchorPoint = Vector2.new(1, 1),
		Parent = card,
		OnClick = function()
			if playable and not voted then
				Net.get("VoteLevel"):FireServer(level.Id)
			end
		end,
	})
	if voted then
		button:SetAttribute("Disabled", true) -- stays green: your current vote
	elseif not playable then
		Components.setButtonEnabled(button, false)
	end
	if playing then
		Create.text({
			Size = UDim2.fromOffset(140, 18),
			Position = UDim2.new(1, -160, 0, 42),
			Text = "● PLAYING NOW",
			TextScaled = false,
			TextSize = 13,
			TextColor3 = C.Green,
			FontFace = Theme.Fonts.Bold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
	end
end

function CampaignPanel:Refresh()
	local campaign = MissionClient.campaign()
	local votes = MissionClient.votes()

	local cleared = 0
	for _ in campaign.Completed do
		cleared += 1
	end
	local nextLevel = CampaignConfig.ById[campaign.Next]
	self.Progress.Text = string.format(
		"Your progress: %d / %d levels cleared  ·  %s  ·  Your vote: %s",
		cleared,
		#CampaignConfig.Levels,
		if nextLevel
			then string.format("Next: Level %d, %s", nextLevel.Index, nextLevel.Day.Name)
			else "All available levels cleared!",
		if campaign.Vote == "FREE" then "Free Shift" else "Level " .. (CampaignConfig.IndexOf[campaign.Vote] or "?")
	)
	local playing = CampaignConfig.ById[ReplicatedStorage:GetAttribute("LevelId") or ""]
	self.NowPlaying.Text = if playing
		then string.format("NOW PLAYING: LEVEL %d · %s / %s", playing.Index, playing.Day.Name, playing.Night.Name)
		else "NOW PLAYING: FREE SHIFT (classic endless nights)"

	local nextIndex = if nextLevel then nextLevel.Index else math.huge
	for index, tab in self.Tabs do
		local chapter = CampaignConfig.Chapters[index]
		local firstLevel = CampaignConfig.Levels[(index - 1) * 7 + 1]
		local open = firstLevel.Implemented and (firstLevel.Index <= nextIndex or campaign.Completed[firstLevel.Id])
		local label = tab:FindFirstChild("Label") :: TextLabel
		label.Text = string.format("%s %d · %s", if open then "📖" else "🔒", index, chapter.Name)
		tab.BackgroundColor3 = if index == self.Chapter then C.Pink elseif open then C.PanelLighter else C.Panel
	end

	local chapter = CampaignConfig.Chapters[self.Chapter]
	self.ChapterInfo.Text = string.format(
		"CHAPTER %d: %s  ·  %s  ·  Boss: %s",
		chapter.Index,
		string.upper(chapter.Name),
		chapter.Theme,
		chapter.Boss
	)
	for _, child in self.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i = 1, 7 do
		self:_card(CampaignConfig.Levels[(self.Chapter - 1) * 7 + i], campaign, votes, i)
	end
end

function CampaignPanel:SetVisible(visible: boolean)
	if visible then
		local campaign = MissionClient.campaign()
		local nextLevel = CampaignConfig.ById[campaign.Next]
		self.Chapter = if nextLevel then nextLevel.Chapter else self.Chapter
		self:Refresh()
	end
	Components.show(self.Modal, visible)
end

return CampaignPanel
