-- Day/night state machine. Phase state is published as ReplicatedStorage attributes:
--   Phase, PhaseStartedAt (server time), PhaseDuration, NightNumber
-- Clients derive timers and visuals from those, so no per-second network traffic.
--
-- Studio helpers (set on Workspace in the server view):
--   FastPhases = true  → shortened durations (set before pressing Play)
--   SkipPhase  = true  → ends the current phase immediately (auto-resets)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

export type Phase = GameConfig.Phase

local GameStateService = {}
GameStateService.PhaseChanged = Signal.new() -- (phase, nightNumber)

local phase: Phase = "Intermission"
local nightNumber = 0

function GameStateService.GetPhase(): Phase
	return phase
end

function GameStateService.GetNight(): number
	return nightNumber
end

function GameStateService.IsNight(): boolean
	return phase == "Night"
end

local function durations()
	if RunService:IsStudio() and workspace:GetAttribute("FastPhases") == true then
		return GameConfig.FastPhases
	end
	return GameConfig.Phases
end

local function runPhase(newPhase: Phase)
	local duration = durations()[newPhase]
	phase = newPhase
	ReplicatedStorage:SetAttribute("Phase", phase)
	ReplicatedStorage:SetAttribute("PhaseStartedAt", workspace:GetServerTimeNow())
	ReplicatedStorage:SetAttribute("PhaseDuration", duration)
	ReplicatedStorage:SetAttribute("NightNumber", nightNumber)
	GameStateService.PhaseChanged:Fire(phase, nightNumber)

	local endsAt = os.clock() + duration
	while os.clock() < endsAt do
		if RunService:IsStudio() and workspace:GetAttribute("SkipPhase") == true then
			workspace:SetAttribute("SkipPhase", false)
			break
		end
		task.wait(0.25)
	end
end

function GameStateService.Init()
	ReplicatedStorage:SetAttribute("Phase", phase)
	ReplicatedStorage:SetAttribute("NightNumber", nightNumber)
end

function GameStateService.Start()
	task.spawn(function()
		runPhase("Intermission")
		while true do
			runPhase("Day")
			nightNumber += 1
			runPhase("Dusk")
			runPhase("Night")
			runPhase("Dawn")
		end
	end)
end

return GameStateService
