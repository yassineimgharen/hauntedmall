-- Ambience layers that make the mall feel alive, driven by world tags:
--   SunShaft       (Beam)            light shafts, day only
--   DayParticles   (ParticleEmitter) drifting dust motes, day only
--   NightParticles (ParticleEmitter) glowing spores, night only
--   ReflectiveFloor(BasePart)        polished sheen at night (neon reads on the floor)
--   FxLight        (Light)           optional extra lights; off with Reduced Effects
-- Reduced Effects (Settings) turns every optional layer off for low-end devices.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AtmosphereController = {}

local DAY_REFLECTANCE = 0.06
local NIGHT_REFLECTANCE = 0.16

local player = Players.LocalPlayer

local function apply(instant: boolean)
	local phase = ReplicatedStorage:GetAttribute("Phase")
	local night = phase == "Night" or phase == "Dusk"
	local reduced = player:GetAttribute("Set_ReducedEffects") == true

	for _, beam in CollectionService:GetTagged("SunShaft") do
		(beam :: Beam).Enabled = not night and not reduced
	end
	for _, emitter in CollectionService:GetTagged("DayParticles") do
		(emitter :: ParticleEmitter).Enabled = not night and not reduced
	end
	for _, emitter in CollectionService:GetTagged("NightParticles") do
		(emitter :: ParticleEmitter).Enabled = night and not reduced
	end
	-- always-on extras (day/night lights are switched by LightingController)
	for _, light in CollectionService:GetTagged("FxLight") do
		if not CollectionService:HasTag(light, "NightLight") and not CollectionService:HasTag(light, "DayLight") then
			(light :: Light).Enabled = not reduced
		end
	end
	local reflectance = if night then NIGHT_REFLECTANCE else DAY_REFLECTANCE
	for _, floor in CollectionService:GetTagged("ReflectiveFloor") do
		if instant then
			(floor :: BasePart).Reflectance = reflectance
		else
			TweenService:Create(floor, TweenInfo.new(4), { Reflectance = reflectance }):Play()
		end
	end
end

function AtmosphereController.Start()
	workspace:WaitForChild("Mall")
	apply(true)
	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(function()
		apply(false)
	end)
	player:GetAttributeChangedSignal("Set_ReducedEffects"):Connect(function()
		apply(true)
	end)
end

return AtmosphereController
