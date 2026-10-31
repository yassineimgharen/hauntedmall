-- Scenario helpers on top of Engine and Bot: boot a world on a level, add bots, play it through
-- the server's real day/night clock, and collect what happened.

local Bot = require("./Bot")
local Engine = require("./Engine")

local Sim = {}

export type Run = {
	World: any,
	Bots: { any },
	Level: string,
}

-- Boots a world forced onto `level` (MissionTest_Level) with `count` players.
function Sim.start(level: string, count: number?, options: { [string]: any }?): any
	local opts = options or {}
	local attributes = opts.Attributes or {}
	attributes.MissionTest_Level = level
	local world = Engine.new({ Seed = opts.Seed or 1, DataStore = opts.DataStore, Attributes = attributes })
	world:boot()
	local bots = {}
	for i = 1, count or 1 do
		local player = world:addPlayer("Bot" .. i, opts.UserIds and opts.UserIds[i] or nil)
		local profile = if type(opts.Profile) == "table" and opts.Profile.Name then opts.Profile else nil
		local bot = Bot.new(world, player, profile)
		bot.Index = i
		table.insert(bots, bot)
	end
	world:run(1)
	return { World = world, Bots = bots, Level = level }
end

-- Runs one bot-driven stage to the end of its phase. strategies = per-objective overrides.
function Sim.playStage(run: any, stage: string, strategies: { [string]: any }?, per: ((any, number) -> ())?)
	local world = run.World
	if not world:waitForPhase(stage, 400) then
		error("phase " .. stage .. " never started; stuck at " .. tostring(world:phase()))
	end
	for i, bot in run.Bots do
		bot.Strategies = strategies or {}
		if per then
			per(bot, i)
		end
		world.task.spawn(function()
			bot:playStage(stage)
		end)
	end
	while world:phase() == stage do
		world:step()
		if run.OnStep then
			run.OnStep(world)
		end
	end
	run.StageEnd = run.StageEnd or {}
	run.StageEnd[stage] = {}
	for i, bot in run.Bots do
		run.StageEnd[stage][i] = Sim.rows(bot)
	end
end

-- Nobody does anything for a whole stage (the clock must still move on).
function Sim.idleStage(run: any, stage: string)
	local world = run.World
	if not world:waitForPhase(stage, 400) then
		error("phase " .. stage .. " never started; stuck at " .. tostring(world:phase()))
	end
	while world:phase() == stage do
		world:step()
		if run.OnStep then
			run.OnStep(world)
		end
	end
	run.StageEnd = run.StageEnd or {}
	run.StageEnd[stage] = {}
	for i, bot in run.Bots do
		run.StageEnd[stage][i] = Sim.rows(bot)
	end
end

-- Waits for the results of the night that just ended.
function Sim.toDawn(run: any)
	run.World:waitForPhase("Dawn", 60)
	run.World:run(4)
end

-- Records every spawn with how close the nearest living player was, and the fastest a monster
-- was ever set to walk (outside a telegraphed charge), for the fairness checks.
function Sim.watchEnemies(run: any)
	local world = run.World
	local EnemyService = world:require("Services.EnemyService")
	local watch = { Spawns = {}, TopSpeed = 0, TopSpeedType = nil }
	local spawn = EnemyService.Spawn
	EnemyService.Spawn = function(kind: string, position: any, ...)
		local nearest = math.huge
		for _, bot in run.Bots do
			local root = bot:root()
			if root then
				nearest = math.min(nearest, (root.Position - position).Magnitude)
			end
		end
		table.insert(watch.Spawns, { Type = kind, Nearest = nearest, At = world.Now })
		return spawn(kind, position, ...)
	end
	local previous = run.OnStep
	run.OnStep = function(w: any)
		if previous then
			previous(w)
		end
		for _, enemy in EnemyService.GetAll() do
			-- the configured chase speed: carts and mimics also have telegraphed dashes
			local speed = enemy.Config.WalkSpeed or 0
			if speed > watch.TopSpeed then
				watch.TopSpeed = speed
				watch.TopSpeedType = enemy.Type
			end
		end
	end
	return watch
end

-- Day → Night → Dawn with the same strategies, returning when dawn's results are out.
function Sim.playLevel(run: any, dayStrategies: any?, nightStrategies: any?, per: any?)
	Sim.playStage(run, "Day", dayStrategies, per)
	Sim.playStage(run, "Night", nightStrategies, per)
	run.World:waitForPhase("Dawn", 60)
	run.World:run(4)
end

function Sim.rows(bot: any): { [string]: any }
	local map = {}
	local snapshot = bot:snapshot()
	for _, row in (snapshot and snapshot.Rows) or {} do
		map[row.Id] = row
	end
	return map
end

function Sim.campaign(world: any, player: any): any
	local data = world:require("Services.DataService").Get(player)
	return data and data.Campaign
end

-- Everything the server logged as an error, formatted.
function Sim.errors(world: any): { string }
	local out = {}
	for _, e in world.Errors do
		table.insert(out, string.format("t=%.1f %s", e.At, (e.Message:gsub("\n.*", ""))))
	end
	return out
end

return Sim
