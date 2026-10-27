--!strict
-- Pure campaign rules (no Roblox services), shared by server and client and unit-tested
-- outside Studio (tests/Campaign.spec.luau, via Lune).
--
--   * Objective tracking for one stage (a level's Day or its Night)
--   * Which level a player may play / gets credit for
--   * Which level the server plays next (votes)
--   * What a finished attempt is worth

local CampaignLogic = {}

export type Objective = {
	Id: string,
	Text: string,
	Kind: ("Count" | "Avoid" | "Survive")?, -- default Count
	Event: string?, -- Count: progresses on this event; Avoid: fails on it
	Target: number?, -- Count only (default 1)
	Scope: ("Player" | "Team")?, -- default Player
	Optional: boolean?,
	Hint: string?,
	Marker: { [string]: string }?,
}

export type Row = {
	Id: string,
	Text: string,
	Progress: number,
	Target: number,
	Done: boolean,
	Failed: boolean,
	Optional: boolean,
	Team: boolean,
	Hint: string?,
	Marker: { [string]: string }?,
}

export type Tracker = {
	Objectives: { Objective },
	Team: { [string]: number },
	Players: { [any]: { [string]: number } },
	Failed: { [any]: { [string]: boolean } },
}

-- ── objective tracking ──────────────────────────────────────────────────────

function CampaignLogic.newTracker(objectives: { Objective }): Tracker
	return { Objectives = objectives, Team = {}, Players = {}, Failed = {} }
end

local function kind(objective: Objective): string
	return objective.Kind or "Count"
end

local function target(objective: Objective): number
	return if kind(objective) == "Count" then objective.Target or 1 else 1
end

local function playerCounts(tracker: Tracker, key: any): { [string]: number }
	local counts = tracker.Players[key]
	if not counts then
		counts = {}
		tracker.Players[key] = counts
	end
	return counts
end

function CampaignLogic.value(tracker: Tracker, key: any, objective: Objective): number
	if objective.Scope == "Team" then
		return tracker.Team[objective.Id] or 0
	end
	local counts = tracker.Players[key]
	return if counts then counts[objective.Id] or 0 else 0
end

function CampaignLogic.isFailed(tracker: Tracker, key: any, objective: Objective): boolean
	local failed = tracker.Failed[key]
	return failed ~= nil and failed[objective.Id] == true
end

-- final = the stage has ended (Survive objectives only complete then).
function CampaignLogic.isDone(tracker: Tracker, key: any, objective: Objective, final: boolean?): boolean
	local k = kind(objective)
	if k == "Avoid" then
		return final == true and not CampaignLogic.isFailed(tracker, key, objective)
	elseif k == "Survive" then
		return final == true
	end
	return CampaignLogic.value(tracker, key, objective) >= target(objective)
end

-- Applies an event. key identifies the player (nil for team-wide events with no player).
-- Returns true if any objective changed.
function CampaignLogic.record(tracker: Tracker, key: any, event: string, amount: number?): boolean
	local changed = false
	local step = amount or 1
	for _, objective in tracker.Objectives do
		if objective.Event ~= event then
			continue
		end
		local k = kind(objective)
		if k == "Avoid" then
			if key ~= nil and not CampaignLogic.isFailed(tracker, key, objective) then
				local failed = tracker.Failed[key] or {}
				tracker.Failed[key] = failed
				failed[objective.Id] = true
				changed = true
			end
		elseif k == "Count" then
			local goal = target(objective)
			if objective.Scope == "Team" then
				local current = tracker.Team[objective.Id] or 0
				if current < goal then
					tracker.Team[objective.Id] = math.min(current + step, goal)
					changed = true
				end
			elseif key ~= nil then
				local counts = playerCounts(tracker, key)
				local current = counts[objective.Id] or 0
				if current < goal then
					counts[objective.Id] = math.min(current + step, goal)
					changed = true
				end
			end
		end
	end
	return changed
end

-- Completes every required Count objective (Studio test helper).
function CampaignLogic.completeRequired(tracker: Tracker, keys: { any })
	for _, objective in tracker.Objectives do
		if kind(objective) == "Count" and not objective.Optional then
			if objective.Scope == "Team" then
				tracker.Team[objective.Id] = target(objective)
			else
				for _, key in keys do
					playerCounts(tracker, key)[objective.Id] = target(objective)
				end
			end
		end
	end
end

function CampaignLogic.requiredComplete(tracker: Tracker, key: any, final: boolean?): boolean
	for _, objective in tracker.Objectives do
		if not objective.Optional and not CampaignLogic.isDone(tracker, key, objective, final) then
			return false
		end
	end
	return true
end

-- Optional objectives this player finished (evaluated at stage end).
function CampaignLogic.optionalDone(tracker: Tracker, key: any): { string }
	local done = {}
	for _, objective in tracker.Objectives do
		if objective.Optional and CampaignLogic.isDone(tracker, key, objective, true) then
			table.insert(done, objective.Id)
		end
	end
	return done
end

function CampaignLogic.rows(tracker: Tracker, key: any, final: boolean?): { Row }
	local rows = {}
	for _, objective in tracker.Objectives do
		local k = kind(objective)
		local failed = k == "Avoid" and CampaignLogic.isFailed(tracker, key, objective)
		table.insert(rows, {
			Id = objective.Id,
			Text = objective.Text,
			Progress = CampaignLogic.value(tracker, key, objective),
			Target = target(objective),
			Done = CampaignLogic.isDone(tracker, key, objective, final),
			Failed = failed,
			Optional = objective.Optional == true,
			Team = objective.Scope == "Team",
			Hint = objective.Hint,
			Marker = objective.Marker,
		})
	end
	return rows
end

-- ── campaign progress ───────────────────────────────────────────────────────

-- The first implemented level not yet completed; nil when every available level is done.
function CampaignLogic.nextLevel(levels: { any }, completed: { [string]: any }): any?
	for _, level in levels do
		if not level.Implemented then
			return nil
		end
		if completed[level.Id] == nil then
			return level
		end
	end
	return nil
end

function CampaignLogic.isUnlocked(levels: { any }, completed: { [string]: any }, levelId: string): boolean
	if completed[levelId] ~= nil then
		return true
	end
	local nextLevel = CampaignLogic.nextLevel(levels, completed)
	return nextLevel ~= nil and nextLevel.Id == levelId
end

-- Plurality vote; ties go to the earliest level so the least-progressed players are never
-- skipped ahead. "FREE" (Free Shift) loses every tie. Returns nil for no votes.
function CampaignLogic.pickLevel(votes: { string }, indexOf: { [string]: number }): string?
	local counts: { [string]: number } = {}
	for _, vote in votes do
		counts[vote] = (counts[vote] or 0) + 1
	end
	local best, bestCount, bestIndex = nil, 0, math.huge
	for vote, count in counts do
		local index = if vote == "FREE" then math.huge else indexOf[vote] or math.huge
		if count > bestCount or (count == bestCount and index < bestIndex) then
			best, bestCount, bestIndex = vote, count, index
		end
	end
	return best
end

export type Outcome = "FirstClear" | "Replay" | "Guest" | "DayMissing" | "NightFailed" | "LateJoin"

-- What a player's attempt at the active level earns at dawn.
function CampaignLogic.outcome(
	info: {
		Eligible: boolean, -- level unlocked for this player
		InRoster: boolean, -- present when the night began
		DayCleared: boolean, -- this level's day cleared now or on an earlier attempt
		NightSuccess: boolean,
		AlreadyCompleted: boolean,
	}
): Outcome
	if not info.Eligible then
		return "Guest"
	elseif not info.InRoster then
		return "LateJoin"
	elseif not info.NightSuccess then
		return "NightFailed"
	elseif not info.DayCleared then
		return "DayMissing"
	end
	return if info.AlreadyCompleted then "Replay" else "FirstClear"
end

-- Cash/XP for a cleared level: full on the first clear, a fraction on replays.
function CampaignLogic.reward(rewards: { Cash: number, XP: number }, firstClear: boolean, replayFraction: number)
	local scale = if firstClear then 1 else replayFraction
	return { Cash = math.floor(rewards.Cash * scale), XP = math.floor(rewards.XP * scale) }
end

return CampaignLogic
