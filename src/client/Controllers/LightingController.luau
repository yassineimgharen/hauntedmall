-- Day/night look. Tweens Lighting and post effects between presets, switches tagged
-- lights, and runs the dramatic dusk power-down. All local: zero network cost.
--
-- Tags used by the world builder:
--   DayLight  (Light)  on during the day, off at night
--   DayNeon   (Part)   warm neon that goes dark at night
--   NightNeon (Part)   pastel by day, saturated + flickering at night
--   NightLight(Light)  off by day, on at night
--
-- Blackout nights (ReplicatedStorage Blackout = true) use the Blackout preset and keep
-- NightLight/NightNeon dark except in zones listed in PoweredZones ("Atrium,Balcony,
-- Corridor": the breaker ids). PowerFlicker = true makes day lights stutter (Day 2).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LightingPresets = require(ReplicatedStorage.Shared.Config.LightingPresets)

local LightingController = {}

local player = Players.LocalPlayer
local rng = Random.new()
local effects: { [string]: Instance } = {}
local baseBrightness: { [Light]: number } = {}
local nightLightBrightness: { [Light]: number } = {}
local baseColor: { [BasePart]: Color3 } = {}
local isNight = false
local sequence = 0
local zoneCache: { [Instance]: string } = {}

-- Which breaker powers this light: East Wing (corridor + shops), upper level, or atrium.
local function zoneOf(instance: Instance): string
	local cached = zoneCache[instance]
	if cached then
		return cached
	end
	local holder = if instance:IsA("Light") then instance.Parent else instance
	local position = if holder and holder:IsA("BasePart")
		then holder.Position
		elseif holder and holder:IsA("Attachment") then holder.WorldPosition
		else Vector3.zero
	local zone = if position.X >= 70 then "Corridor" elseif position.Y >= 18 then "Balcony" else "Atrium"
	zoneCache[instance] = zone
	return zone
end

-- nil = every zone powered (normal night); otherwise the set of re-powered zones.
local function poweredZones(): { [string]: boolean }?
	if ReplicatedStorage:GetAttribute("Blackout") ~= true then
		return nil
	end
	local zones = {}
	for zone in string.gmatch(ReplicatedStorage:GetAttribute("PoweredZones") or "", "[^,]+") do
		zones[zone] = true
	end
	return zones
end

local function nightPreset(): string
	return if ReplicatedStorage:GetAttribute("Blackout") == true then "Blackout" else "Night"
end

local function reducedEffects(): boolean
	return player:GetAttribute("Set_ReducedEffects") == true
end

local function tweenProps(target: Instance, props: { [string]: any }, duration: number)
	if duration <= 0 then
		for key, value in props do
			(target :: any)[key] = value
		end
		return
	end
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(target, info, props):Play()
end

local function applyPreset(name: string, duration: number)
	local preset = LightingPresets[name]
	tweenProps(Lighting, preset.Lighting, duration)
	for key, effect in effects do
		tweenProps(effect, (preset :: any)[key], duration)
	end
end

local function neonColor(part: BasePart): Color3
	local attribute = part:GetAttribute("BaseColor")
	if typeof(attribute) == "Color3" then
		return attribute
	end
	local color = baseColor[part]
	if not color then
		color = part.Color
		baseColor[part] = color
	end
	return color
end

-- Lights faded to zero are disabled afterwards so they cost nothing to render. FxLights
-- (optional extras) stay off when the player picked Reduced Effects.
local fadeTokens: { [Light]: number } = {}
local function fadeLight(light: Light, on: boolean, brightness: number, duration: number)
	local token = (fadeTokens[light] or 0) + 1
	fadeTokens[light] = token
	if on then
		light.Enabled = not (reducedEffects() and CollectionService:HasTag(light, "FxLight"))
		tweenProps(light, { Brightness = brightness }, duration)
	else
		tweenProps(light, { Brightness = 0 }, duration)
		task.delay(duration, function()
			if fadeTokens[light] == token then
				light.Enabled = false
			end
		end)
	end
end

local function setDayLights(on: boolean, duration: number)
	for _, light in CollectionService:GetTagged("DayLight") do
		local base = baseBrightness[light]
		if base == nil then
			base = light.Brightness
			baseBrightness[light] = base
		end
		fadeLight(light, on, base, duration)
	end
	for _, part in CollectionService:GetTagged("DayNeon") do
		local base = neonColor(part)
		tweenProps(part, { Color = if on then base else base:Lerp(Color3.new(0, 0, 0), 0.85) }, duration)
	end
end

local function setNightMode(on: boolean, duration: number)
	local zones = if on then poweredZones() else nil
	for _, part in CollectionService:GetTagged("NightNeon") do
		local base = neonColor(part)
		local color = if not on
			then base:Lerp(Color3.new(1, 1, 1), 0.4)
			elseif zones and not zones[zoneOf(part)] then base:Lerp(Color3.new(0, 0, 0), 0.9)
			else base
		tweenProps(part, { Color = color }, duration)
	end
	for _, light in CollectionService:GetTagged("NightLight") do
		local base = nightLightBrightness[light]
		if base == nil then
			base = (light:GetAttribute("NightBrightness") :: number?) or math.max(light.Brightness, 1.4)
			nightLightBrightness[light] = base
		end
		fadeLight(light, on and (zones == nil or zones[zoneOf(light)] == true), base, duration)
	end
end

local function powerDown(token: number, duration: number)
	-- stutter, fail, then the night creeps in
	if not reducedEffects() then
		for i = 1, 7 do
			if sequence ~= token then
				return
			end
			setDayLights(i % 2 == 0, 0)
			task.wait(rng:NextNumber(0.06, 0.22))
		end
	end
	setDayLights(false, 0.4)
	applyPreset(nightPreset(), math.max(duration - 2, 1))
	task.wait(1.2)
	if sequence == token then
		setNightMode(true, 2)
	end
end

local function onPhase(instant: boolean)
	local phase = ReplicatedStorage:GetAttribute("Phase")
	sequence += 1
	local token = sequence
	local duration = ReplicatedStorage:GetAttribute("PhaseDuration") or 8

	if phase == "Dusk" or phase == "Night" then
		isNight = true
		if instant or phase == "Night" then
			applyPreset(nightPreset(), if instant then 0 else 2)
			setDayLights(false, if instant then 0 else 1)
			setNightMode(true, if instant then 0 else 1)
		else
			task.spawn(powerDown, token, duration)
		end
	else
		isNight = false
		local fade = if instant then 0 elseif phase == "Dawn" then math.min(duration, 8) else 2
		applyPreset("Day", fade)
		setDayLights(true, fade)
		setNightMode(false, fade)
	end
end

-- Blackout started, a zone came back, or power fully returned.
local function onPowerChanged()
	if not isNight then
		return
	end
	local blackoutStarting = ReplicatedStorage:GetAttribute("Blackout") == true
		and (ReplicatedStorage:GetAttribute("PoweredZones") or "") == ""
	if blackoutStarting and not reducedEffects() then
		for i = 1, 6 do -- the lights stutter and die
			setNightMode(i % 2 == 0, 0)
			task.wait(rng:NextNumber(0.05, 0.18))
		end
	end
	applyPreset(nightPreset(), if blackoutStarting then 1 else 3)
	setNightMode(true, 1.2)
end

-- Random neon stutter at night (and failing day lights during a power fault); skipped
-- with Reduced Effects.
local function flickerLoop()
	while true do
		task.wait(rng:NextNumber(0.15, 0.5))
		if not isNight and ReplicatedStorage:GetAttribute("PowerFlicker") == true and not reducedEffects() then
			local lights = CollectionService:GetTagged("DayLight")
			if #lights > 0 and rng:NextNumber() < 0.6 then
				local light = lights[rng:NextInteger(1, #lights)] :: Light
				if light.Enabled then
					light.Enabled = false
					task.delay(rng:NextNumber(0.08, 0.3), function()
						light.Enabled = true
					end)
				end
			end
		end
		if isNight and not reducedEffects() then
			local neon = CollectionService:GetTagged("NightNeon")
			if #neon > 0 then
				local part = neon[rng:NextInteger(1, #neon)]
				local original = part.Transparency
				part.Transparency = 0.85
				task.delay(rng:NextNumber(0.05, 0.15), function()
					part.Transparency = original
				end)
			end
		end
	end
end

function LightingController.Start()
	effects.Atmosphere = Lighting:WaitForChild("NS_Atmosphere")
	effects.ColorCorrection = Lighting:WaitForChild("NS_ColorCorrection")
	effects.Bloom = Lighting:WaitForChild("NS_Bloom")
	effects.SunRays = Lighting:WaitForChild("NS_SunRays")
	workspace:WaitForChild("Mall")

	-- trim colours change when shops are claimed; re-tint on the fly
	for _, tag in { "NightNeon", "DayNeon" } do
		local function watch(part: Instance)
			part:GetAttributeChangedSignal("BaseColor"):Connect(function()
				local base = neonColor(part :: BasePart)
				local p = part :: BasePart
				p.Color = if isNight or tag == "DayNeon" then base else base:Lerp(Color3.new(1, 1, 1), 0.4)
			end)
		end
		for _, part in CollectionService:GetTagged(tag) do
			watch(part)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(watch)
	end

	onPhase(true)
	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(function()
		onPhase(false)
	end)
	player:GetAttributeChangedSignal("Set_ReducedEffects"):Connect(function()
		onPhase(true)
	end)
	ReplicatedStorage:GetAttributeChangedSignal("Blackout"):Connect(function()
		task.spawn(onPowerChanged)
	end)
	ReplicatedStorage:GetAttributeChangedSignal("PoweredZones"):Connect(function()
		task.spawn(onPowerChanged)
	end)
	task.spawn(flickerLoop)
end

function LightingController.IsNight(): boolean
	return isNight
end

return LightingController
