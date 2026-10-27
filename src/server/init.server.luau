-- Server entry point. Builds the world, then initialises and starts services in
-- dependency order. Init must not yield or depend on other services; Start may.

local CollisionGroups = require(script.Util.CollisionGroups)
local MallBuilder = require(script.World.MallBuilder)

local SERVICE_ORDER = {
	"DataService",
	"ProgressionService",
	"GameStateService",
	"ShopService",
	"CustomerService",
	"EnemyService",
	"CombatService",
	"NightService",
}

CollisionGroups.setup()
MallBuilder.build()

local services = {}
for _, name in SERVICE_ORDER do
	services[name] = require(script.Services[name])
end
for _, name in SERVICE_ORDER do
	services[name].Init()
end
for _, name in SERVICE_ORDER do
	services[name].Start()
end

print("[NightShift] server ready")
