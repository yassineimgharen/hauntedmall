-- Objective event bus. Game systems report what happened ("Served", "PanelRepaired", ...);
-- MissionService decides whether it counts. Keeps services free of circular requires.
-- Event names are listed in CampaignConfig.Events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local MissionEvents = {}
MissionEvents.Recorded = Signal.new() -- (player: Player?, event: string, amount: number)

-- player may be nil for team-wide events (e.g. "PowerRestored").
function MissionEvents.record(player: Player?, event: string, amount: number?)
	MissionEvents.Recorded:Fire(player, event, amount or 1)
end

return MissionEvents
