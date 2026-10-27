-- Music, ambience and UI sound. Tracks with empty ids in AudioConfig are skipped, so the
-- game runs silently until licensed audio is chosen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)

local AudioController = {}

local player = Players.LocalPlayer
local musicGroup: SoundGroup
local sfxGroup: SoundGroup
local tracks: { [string]: Sound } = {}

local function makeSound(id: string, group: SoundGroup, looped: boolean, volume: number): Sound?
	if id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = looped
	sound.Volume = volume
	sound.SoundGroup = group
	sound.Parent = group
	return sound
end

local function applyVolumes()
	musicGroup.Volume = player:GetAttribute("Set_Music") or 0.6
	sfxGroup.Volume = player:GetAttribute("Set_Sfx") or 0.8
end

local function crossfade(toNight: boolean)
	local wanted = if toNight then { "NightMusic", "NightAmbience" } else { "DayMusic", "DayAmbience" }
	for name, sound in tracks do
		local on = table.find(wanted, name) ~= nil
		local target = if on then sound:GetAttribute("BaseVolume") :: number else 0
		if on and not sound.IsPlaying then
			sound.Volume = 0
			sound:Play()
		end
		TweenService:Create(sound, TweenInfo.new(3), { Volume = target }):Play()
	end
end

function AudioController.Play(name: string)
	local id = AudioConfig.Sfx[name]
	if not id or id == "" or not sfxGroup then
		return
	end
	local sound = makeSound(id, sfxGroup, false, AudioConfig.Volumes.Sfx)
	if sound then
		sound:Play()
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end
end

function AudioController.Start()
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "NS_Music"
	musicGroup.Parent = SoundService
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "NS_Sfx"
	sfxGroup.Parent = SoundService

	local volumes = AudioConfig.Volumes
	for name, data in
		{
			DayMusic = { AudioConfig.Music.Day, volumes.Music },
			NightMusic = { AudioConfig.Music.Night, volumes.Music },
			DayAmbience = { AudioConfig.Ambience.MallDay, volumes.Ambience },
			NightAmbience = { AudioConfig.Ambience.MallNight, volumes.Ambience },
		}
	do
		local sound = makeSound(data[1], musicGroup, true, 0)
		if sound then
			sound:SetAttribute("BaseVolume", data[2])
			tracks[name] = sound
		end
	end

	applyVolumes()
	player:GetAttributeChangedSignal("Set_Music"):Connect(applyVolumes)
	player:GetAttributeChangedSignal("Set_Sfx"):Connect(applyVolumes)

	local function onPhase()
		local phase = ReplicatedStorage:GetAttribute("Phase")
		crossfade(phase == "Dusk" or phase == "Night")
		if phase == "Dusk" then
			AudioController.Play("PowerDown")
		elseif phase == "Dawn" then
			AudioController.Play("PowerUp")
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(onPhase)
	onPhase()
end

return AudioController
