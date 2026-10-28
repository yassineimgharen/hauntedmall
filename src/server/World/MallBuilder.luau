-- Builds the whole mall once at server start, plus global lighting objects.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LightingPresets = require(ReplicatedStorage.Shared.Config.LightingPresets)
local Corridor = require(script.Parent.Corridor)
local FoodCourt = require(script.Parent.FoodCourt)
local Lobby = require(script.Parent.Lobby)

local MallBuilder = {}

local function ensure(className: string, name: string): any
	local existing = Lighting:FindFirstChild(name)
	if existing then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance
end

local function apply(target: Instance, props: { [string]: any })
	for key, value in props do
		(target :: any)[key] = value
	end
end

local function setupLighting()
	local day = LightingPresets.Day
	apply(Lighting, day.Lighting)
	Lighting.GeographicLatitude = 28
	Lighting.ShadowSoftness = 0.25

	local sky = ensure("Sky", "NS_Sky")
	sky.StarCount = 3000
	sky.MoonAngularSize = 18
	sky.SunAngularSize = 14
	sky.CelestialBodiesShown = true

	apply(ensure("Atmosphere", "NS_Atmosphere"), day.Atmosphere)
	apply(ensure("ColorCorrectionEffect", "NS_ColorCorrection"), day.ColorCorrection)
	apply(ensure("BloomEffect", "NS_Bloom"), day.Bloom)
	apply(ensure("SunRaysEffect", "NS_SunRays"), day.SunRays)
end

function MallBuilder.build(): Model
	local started = os.clock()
	setupLighting()

	local mall = Instance.new("Model")
	mall.Name = "Mall"
	Lobby.build(mall)
	Corridor.build(mall)
	FoodCourt.build(mall)
	mall.Parent = workspace

	local parts = 0
	for _, descendant in mall:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[MallBuilder] built %d parts in %.2fs", parts, os.clock() - started))
	return mall
end

return MallBuilder
