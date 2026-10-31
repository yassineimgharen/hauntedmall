--!strict
-- Keeps a boss's health in line with who's actually there. Pure rules (no Roblox APIs), run by
-- ShadowQueen and GorgingChef and tested in tests/ShadowQueen.spec.luau.
--
-- Rescaling keeps the health FRACTION: damage already dealt stays dealt, phases never change, and
-- leaving then rejoining gains nothing. More players always finish a boss faster (each one brings
-- more damage than HP), so nobody can profit by sending teammates away.
--   * Someone joins: applied at once.
--   * Someone leaves: applied after LeaveDelay, if they haven't come back by then.

local BossScaling = {}

BossScaling.Tuning = { LeaveDelay = 10 }

export type Tracker = { Applied: number, LowerSince: number? }

function BossScaling.new(players: number): Tracker
	return { Applied = math.max(players, 1), LowerSince = nil }
end

-- The player count to scale to now, or nil to leave the boss alone.
function BossScaling.decide(tracker: Tracker, players: number, now: number): number?
	local count = math.max(players, 1)
	if count > tracker.Applied then
		tracker.Applied = count
		tracker.LowerSince = nil
		return count
	elseif count == tracker.Applied then
		tracker.LowerSince = nil
		return nil
	end
	local since = tracker.LowerSince or now
	tracker.LowerSince = since
	if now - since >= BossScaling.Tuning.LeaveDelay then
		tracker.Applied = count
		tracker.LowerSince = nil
		return count
	end
	return nil
end

-- Sets a new maximum, keeping the fraction of health left. Returns whether anything changed.
function BossScaling.rescale(fight: { Hp: number, MaxHp: number, Defeated: boolean }, maxHp: number): boolean
	if fight.Defeated or fight.MaxHp == maxHp or fight.MaxHp <= 0 then
		return false
	end
	fight.Hp = fight.Hp / fight.MaxHp * maxHp
	fight.MaxHp = maxHp
	return true
end

return BossScaling
