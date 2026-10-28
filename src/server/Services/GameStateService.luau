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
local phaseStartedAt = 0 -- server time
local phaseEndsAt = 0 -- os.clock()
-- Called synchronously (must not yield) as each phase begins, before it is published.
-- Returns that phase's duration in normal-speed seconds, or nil for the default.
-- MissionService uses it to pick the level at dawn of each Day and to set level lengths.
local phaseHook: ((Phase) -> number?)? = nil

function GameStateService.GetPhase(): Phase
	return phase
end

function GameStateService.GetNight(): number
	return nightNumber
end

function GameStateService.IsNight(): boolean
	return phase == "Night"
end

function GameStateService.SetPhaseHook(hook: (Phase) -> number?)
	phaseHook = hook
end

local function phaseDuration(newPhase: Phase): number
	local override = if phaseHook then phaseHook(newPhase) else nil
	local normal = override or GameConfig.Phases[newPhase]
	if RunService:IsStudio() and workspace:GetAttribute("FastPhases") == true then
		-- keep a level's relative length when testing fast
		return normal * GameConfig.FastPhases[newPhase] / GameConfig.Phases[newPhase]
	end
	return normal
end

-- Ends the current phase within `seconds` (never lengthens it), e.g. dawn soon after a
-- boss falls. Clients re-read PhaseDuration, so their timers stay right.
function GameStateService.ShortenPhase(seconds: number)
	local now = os.clock()
	if now + seconds >= phaseEndsAt then
		return
	end
	phaseEndsAt = now + seconds
	ReplicatedStorage:SetAttribute("PhaseDuration", workspace:GetServerTimeNow() + seconds - phaseStartedAt)
end

local function runPhase(newPhase: Phase)
	local duration = phaseDuration(newPhase)
	phase = newPhase
	phaseStartedAt = workspace:GetServerTimeNow()
	phaseEndsAt = os.clock() + duration
	ReplicatedStorage:SetAttribute("Phase", phase)
	ReplicatedStorage:SetAttribute("PhaseStartedAt", phaseStartedAt)
	ReplicatedStorage:SetAttribute("PhaseDuration", duration)
	ReplicatedStorage:SetAttribute("NightNumber", nightNumber)
	GameStateService.PhaseChanged:Fire(phase, nightNumber)

	while os.clock() < phaseEndsAt do
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
