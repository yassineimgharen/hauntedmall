-- Unit tests for the Shadow Queen fight (Level 7 night), run outside Roblox with Lune:
--   .tools/bin/lune run tests/ShadowQueen.spec.luau     (also part of scripts/check.sh)
-- They cover the pure rules (QueenLogic), the flashlight cone (LightCone), the one-time
-- chapter reward (CampaignLogic) and that the level records the events its objectives need.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local CampaignConfig = require("../src/shared/Campaign/CampaignConfig")
local CampaignLogic = require("../src/shared/Campaign/CampaignLogic")
local EnemyConfig = require("../src/shared/Config/EnemyConfig")
local LightCone = require("../src/shared/Util/LightCone")
local Q = require("../src/server/Levels/QueenLogic")

local T = Q.Tuning
local FL = EnemyConfig.Flashlight
local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ✓ " .. name)
	else
		failed += 1
		print("  ✗ " .. name .. "\n      " .. tostring(err))
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
	end
end

local function near(actual: number, expected: number, label: string?)
	if math.abs(actual - expected) > 1e-6 then
		error(string.format("%s: expected %.4f, got %.4f", label or "value", expected, actual), 2)
	end
end

-- tiny vector helpers (Lune has no Vector3 global)
local function sub(a, b)
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function len(a)
	return math.sqrt(a[1] ^ 2 + a[2] ^ 2 + a[3] ^ 2)
end
local function unit(a)
	local l = len(a)
	return { a[1] / l, a[2] / l, a[3] / l }
end
local function dot(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

-- Does a beam from `eye` aimed at `aimAt` light a sphere (centre, radius)?
local function lit(eye, aimAt, center, radius): boolean
	local aim = unit(sub(aimAt, eye))
	local offset = sub(center, eye)
	local distance = len(offset)
	return LightCone.hits(dot(aim, unit(offset)), distance, radius, math.rad(FL.ConeHalfAngle), FL.Range)
end

-- Queen facing the player (-Z toward them) with her root at `root`: body sphere centres.
local function bodyCentres(root)
	local out = {}
	for _, spot in Q.Body do
		-- she faces +Z here (toward a player south of her), so local -Z maps to world +Z
		out[spot.Name] = { root[1] + spot.Offset[1], root[2] + spot.Offset[2], root[3] - spot.Offset[3] }
	end
	return out
end

local function vulnerableFight(players: number?)
	local fight = Q.new(players or 1)
	local cannon = { Charged = true, Progress = 1, Fired = false }
	assert(Q.fire(fight, cannon, 100), "fire")
	return fight
end

print("Shadow Queen: flashlight targeting")

test("root cause: the old single hit point missed when aiming at her face", function()
	-- old model: one point 2 studs under the root of a 3.2x crawler; its skull sat
	-- (0, 0.85, -2.0) x 3.2 from the root, i.e. 6.4 ahead of and 4.7 above that point
	local eye = { 0, 4.5, 15 }
	local root = { 0, 8, 0 }
	local oldPoint = { 0, 6, 0 }
	local skull = { 0, 10.72, 6.4 }
	eq(lit(eye, skull, oldPoint, 0), false, "face aim vs old point")
	eq(lit(eye, root, oldPoint, 0), true, "body aim vs old point")
end)

test("aiming at any visible part of her (eyes, crown, tail, flank) lights a body sphere", function()
	local root = { 0, 11, 0 }
	local body = bodyCentres(root)
	-- visible extremities from ShadowQueen.buildQueen, in her local space (-Z forward)
	local visible = {
		Eye = { 1.2, 4.1, -6.95 },
		CrownTip = { 0, 9.6, -4.5 },
		Mandible = { 1.1, 2.1, -7 },
		Flank = { 3.5, 1.5, 0 },
		TailEnd = { 0, 0.5, 11.5 },
		Belly = { 0, -3, 6 },
	}
	for _, eye in { { 0, 4.5, 15 }, { 0, 4.5, 25 }, { 12, 4.5, 28 }, { 0, 4.5, 38 } } do
		for name, l in visible do
			local aimAt = { root[1] + l[1], root[2] + l[2], root[3] - l[3] }
			local any = false
			for _, spot in Q.Body do
				any = any or lit(eye, aimAt, body[spot.Name], spot.Radius)
			end
			eq(any, true, string.format("aim at %s from (%d, %d)", name, eye[1], eye[3]))
		end
	end
end)

test("aiming well away from her, or out of range, does not count", function()
	local body = bodyCentres({ 0, 11, 0 })
	local away = { 30, 4.5, 15 } -- 90° to the side
	for _, spot in Q.Body do
		eq(lit({ 0, 4.5, 15 }, away, body[spot.Name], spot.Radius), false, spot.Name .. " side aim")
		eq(lit({ 0, 4.5, 60 }, body[spot.Name], body[spot.Name], spot.Radius), false, spot.Name .. " far")
	end
end)

test("point targets (crawlers) keep the old cone exactly", function()
	local half = math.rad(FL.ConeHalfAngle)
	eq(LightCone.hits(math.cos(half - 0.01), 20, 0, half, FL.Range), true, "just inside")
	eq(LightCone.hits(math.cos(half + 0.01), 20, 0, half, FL.Range), false, "just outside")
	eq(LightCone.hits(math.cos(math.rad(45)), 6, 0, half, FL.Range), true, "close range is wider")
	eq(LightCone.hits(1, FL.Range + 0.5, 0, half, FL.Range), false, "range")
end)

print("Shadow Queen: cannons and shield")

test("a charged cannon drops the shield for exactly ShieldDown seconds", function()
	local fight = Q.new(1)
	local cannon = { Charged = true, Progress = 1, Fired = false }
	eq(Q.shieldState(fight, 50), "Shielded", "before")
	local ok = Q.fire(fight, cannon, 50)
	eq(ok, true, "fired")
	eq(cannon.Charged, false, "charge consumed")
	eq(cannon.Progress, 0, "progress reset")
	eq(Q.shieldState(fight, 50), "Down", "just fired")
	eq(Q.shieldState(fight, 50 + T.ShieldDown - T.Returning - 0.01), "Down", "still down")
	eq(Q.shieldState(fight, 50 + T.ShieldDown - T.Returning + 0.01), "Returning", "warning")
	eq(Q.shieldState(fight, 50 + T.ShieldDown), "Shielded", "back up")
end)

test("uncharged, darkened or already-open cannons are refused", function()
	local fight = Q.new(1)
	local empty = { Charged = false, Progress = 0.5, Fired = true }
	local _, reason = Q.fire(fight, empty, 10)
	eq(reason, "NotCharged", "uncharged")
	fight.DarkUntil = 20
	local charged = { Charged = true, Progress = 1, Fired = false }
	_, reason = Q.fire(fight, charged, 15)
	eq(reason, "Dark", "darkness")
	eq(charged.Charged, true, "charge kept when refused")
	assert(Q.fire(fight, charged, 25), "fires after the darkness")
end)

test("two players firing at the same moment: only one cannon is spent", function()
	local fight = Q.new(2)
	local a = { Charged = true, Progress = 1, Fired = false }
	local b = { Charged = true, Progress = 1, Fired = false }
	local okA = Q.fire(fight, a, 30)
	local okB, reason = Q.fire(fight, b, 30)
	eq(okA, true, "first")
	eq(okB, false, "second")
	eq(reason, "ShieldDown", "reason")
	eq(b.Charged, true, "second cannon keeps its charge")
	local again = Q.fire(fight, a, 30)
	eq(again, false, "same cannon twice")
end)

test("night recharge: automatic, faster with people in the ring, capped at 3", function()
	near(Q.nightChargeRate(0), 1 / T.Recharge, "alone")
	near(Q.nightChargeRate(1), 2 / T.Recharge, "one helper")
	near(Q.nightChargeRate(9), 4 / T.Recharge, "cap")
end)

print("Shadow Queen: damage, phases, victory")

test("light while shielded is blocked and does nothing", function()
	local fight = Q.new(1)
	local result = Q.applyLight(fight, 5, 30)
	eq(result.Blocked, true, "blocked")
	eq(result.Dealt, 0, "dealt")
	eq(fight.Hp, fight.MaxHp, "hp")
end)

test("light while the shield is down reduces her health", function()
	local fight = vulnerableFight()
	local result = Q.applyLight(fight, 101, 30)
	eq(result.Blocked, false, "not blocked")
	eq(result.Dealt, 30, "dealt")
	eq(fight.Hp, fight.MaxHp - 30, "hp")
	-- after the window, blocked again
	eq(Q.applyLight(fight, 100 + T.ShieldDown, 30).Blocked, true, "window over")
end)

test("flashlight damage: lens upgrades and the Prism Lens multiply", function()
	near(Q.lightDamage(30, 0.1, 0, false), 3, "base")
	near(Q.lightDamage(30, 0.1, 0.5, false), 4.5, "lens +50%")
	near(Q.lightDamage(30, 0.1, 0, true), 3 * (1 + T.PrismBonus), "prism")
end)

test("phases change at 66% and 33% and never go back", function()
	eq(Q.phaseFor(1), 1, "full")
	eq(Q.phaseFor(0.661), 1, "above 66%")
	eq(Q.phaseFor(0.66), 2, "at 66%")
	eq(Q.phaseFor(0.331), 2, "above 33%")
	eq(Q.phaseFor(0.33), 3, "at 33%")
	local fight = vulnerableFight()
	local toPhase2 = fight.MaxHp - math.floor(fight.MaxHp * T.PhaseAt[1])
	local result = Q.applyLight(fight, 101, toPhase2)
	eq(result.PhaseChanged, 2, "enters phase 2")
	eq(Q.applyLight(fight, 101, 1).PhaseChanged, nil, "no repeat")
	result = Q.applyLight(fight, 101, fight.Hp - math.floor(fight.MaxHp * T.PhaseAt[2]))
	eq(result.PhaseChanged, 3, "enters phase 3")
	eq(fight.Phase, 3, "phase")
end)

test("victory is reported exactly once and stops everything", function()
	local fight = vulnerableFight()
	local result = Q.applyLight(fight, 101, fight.MaxHp + 500)
	eq(result.Defeated, true, "defeated")
	eq(result.Dealt, fight.MaxHp, "overkill not counted")
	eq(fight.Hp, 0, "hp")
	eq(Q.shieldState(fight, 101), "Defeated", "state")
	local again = Q.applyLight(fight, 101, 50)
	eq(again.Defeated, false, "only once")
	eq(again.Dealt, 0, "no damage after")
	local _, reason = Q.fire(fight, { Charged = true, Progress = 1, Fired = false }, 200)
	eq(reason, "Defeated", "no cannon after")
end)

print("Shadow Queen: solo and team difficulty")

test("health scales with players", function()
	eq(Q.maxHp(1), T.BaseHP + T.HPPerPlayer, "solo")
	eq(Q.maxHp(0), Q.maxHp(1), "never below solo")
	eq(Q.maxHp(4), T.BaseHP + T.HPPerPlayer * 4, "four")
end)

test("brood: small solo, larger for teams, never above the alive cap", function()
	eq(Q.broodSize(1, 1), 1, "solo phase 1")
	eq(Q.maxBrood(1, 1), 2, "solo phase 1 cap")
	eq(Q.maxBrood(3, 1), 4, "solo phase 3 cap")
	assert(Q.broodSize(2, 4) > Q.broodSize(2, 1), "teams get more")
	assert(Q.maxBrood(3, 4) > Q.maxBrood(3, 1), "teams allow more")
	for phase = 1, 3 do
		for players = 1, 8 do
			eq(Q.maxBrood(phase, players) <= T.MaxAliveCap, true, "cap")
			for alive = 0, 12 do
				local n = Q.broodToSpawn(phase, players, alive)
				eq(n >= 0, true, "non-negative")
				eq(alive + n <= math.max(alive, Q.maxBrood(phase, players)), true, "within cap")
			end
		end
	end
	eq(Q.broodToSpawn(1, 1, 2), 0, "solo at cap: none")
end)

test("brood crawlers are always slower than players (16)", function()
	for _, tier in T.BroodTier do
		local speed = EnemyConfig.Scaled("ShadowCrawler", tier).WalkSpeed
		eq(speed < 15, true, "tier " .. tier .. " speed " .. speed)
	end
end)

test("brood never spawns next to a player or a cannon", function()
	local candidates = { { 0, 0 }, { 30, 0 }, { 60, 0 }, { 14, 26 } }
	local players = { { 5, 0 } }
	local cannons = { { 14.5, 25.1 } }
	local index = Q.pickSpawn(candidates, players, cannons)
	eq(index, 2, "nearest safe spot") -- {0,0}: player; {14,26}: cannon; {30,0} beats {60,0}
	eq(Q.pickSpawn({ { 0, 0 }, { 10, 0 } }, { { 3, 0 } }, {}), nil, "no safe spot: none")
end)

-- Solo, no Prism Lens, hitting 70% of the time: can she be beaten well inside the night?
local function simulateKill(players: number, accuracy: number): number
	local fight = Q.new(players)
	local cannons = {}
	for i = 1, 3 do
		cannons[i] = { Charged = true, Progress = 1, Fired = false }
	end
	local t, dt = 6 + T.FirstAttackDelay, 0.1
	local nextTry = t
	while t < 600 do
		for _, cannon in cannons do
			if not cannon.Charged then
				cannon.Progress = math.min(1, cannon.Progress + Q.nightChargeRate(0) * dt)
				cannon.Charged = cannon.Progress >= 1
			end
		end
		if t >= nextTry and Q.shieldState(fight, t) == "Shielded" then
			for _, cannon in cannons do
				if Q.fire(fight, cannon, t) then
					break
				end
			end
			nextTry = t + T.ShieldDown + 6 -- walking to the next cannon
		end
		local amount = Q.lightDamage(FL.DPS, dt, 0, false) * accuracy * players
		if Q.applyLight(fight, t, amount).Defeated then
			return t
		end
		t += dt
	end
	return math.huge
end

test("a solo player can win well before dawn; a team of 4 too", function()
	local night = CampaignConfig.ById.L07.Night.Duration
	local solo = simulateKill(1, 0.7)
	local team = simulateKill(4, 0.7)
	eq(solo < night * 0.75, true, string.format("solo kill at %.0fs of %ds", solo, night))
	eq(team < night * 0.75, true, string.format("team kill at %.0fs of %ds", team, night))
	eq(solo > 45, true, "solo is not trivial (needs several cannon cycles)")
end)

print("Shadow Queen: rewards and progression")

test("Chapter 1 reward is granted once and the mark persists", function()
	local L07 = CampaignConfig.ById.L07
	local campaign = { Completed = {}, DayCleared = {}, OptionalDone = {}, Chapters = {} }
	local reward = CampaignLogic.claimChapter(campaign, L07, 1700000000)
	assert(reward, "first clear pays the chapter reward")
	eq(reward.Title, "Queen Slayer", "title")
	eq(CampaignLogic.claimChapter(campaign, L07, 1700000100), nil, "second time: nothing")
	-- what DataStore keeps (JSON) still says the chapter is done
	local stored = serde.decode("json", serde.encode("json", campaign))
	eq(CampaignLogic.claimChapter(stored, L07, 1700000200), nil, "after save/load: nothing")
	eq(CampaignLogic.claimChapter(campaign, CampaignConfig.ById.L06, 1), nil, "levels without a finale")
end)

test("replaying Level 7 is a replay (no first-clear rewards again)", function()
	local outcome = CampaignLogic.outcome({
		Eligible = true,
		InRoster = true,
		DayCleared = true,
		NightSuccess = true,
		AlreadyCompleted = true,
	})
	eq(outcome, "Replay", "outcome")
end)

test("the level records every event its objectives need", function()
	local source = fs.readFile("src/server/Levels/ShadowQueen.luau")
	local L07 = CampaignConfig.ById.L07
	for _, stage in { L07.Day, L07.Night } do
		for _, objective in stage.Objectives do
			if objective.Event and objective.Event ~= "Downed" then
				assert(source:find('"' .. objective.Event .. '"', 1, true), objective.Event .. " is never recorded")
			end
		end
	end
	assert(source:find('MissionEvents.record(nil, "QueenDefeated")', 1, true), "victory is a team event")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
