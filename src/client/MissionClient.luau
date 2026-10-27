-- Client view of the campaign: the latest objective snapshot from MissionService and the
-- player's own campaign progress (CampaignState attribute). Read-only; votes go through
-- the VoteLevel remote.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local player = Players.LocalPlayer

local MissionClient = {}
MissionClient.Snapshot = nil :: { [string]: any }?
MissionClient.Changed = Signal.new()

export type Campaign =
	{ Completed: { [string]: boolean }, DayCleared: { [string]: boolean }, Next: string, Vote: string }

local function decode(text: any): any
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, text)
	return if ok then value else nil
end

local function toSet(list: any): { [string]: boolean }
	local set = {}
	if type(list) == "table" then
		for _, id in list do
			set[id] = true
		end
	end
	return set
end

function MissionClient.campaign(): Campaign
	local raw = decode(player:GetAttribute("CampaignState")) or {}
	return {
		Completed = toSet(raw.Completed),
		DayCleared = toSet(raw.DayCleared),
		Next = raw.Next or "L01",
		Vote = raw.Vote or raw.Next or "L01",
	}
end

function MissionClient.votes(): { [string]: number }
	return decode(ReplicatedStorage:GetAttribute("LevelVotes")) or {}
end

-- The first required objective still open, preferring one that uses what you carry.
function MissionClient.focusRow(): { [string]: any }?
	local snapshot = MissionClient.Snapshot
	if not snapshot or not snapshot.Rows or snapshot.Final then
		return nil
	end
	local carrying = player:GetAttribute("Carrying")
	local first = nil
	for _, row in snapshot.Rows do
		if not row.Done and not row.Optional then
			if carrying and row.Marker and row.Marker.Carry == carrying then
				return row
			end
			first = first or row
		end
	end
	return first
end

Net.get("MissionState").OnClientEvent:Connect(function(snapshot)
	MissionClient.Snapshot = snapshot
	MissionClient.Changed:Fire(snapshot)
end)

return MissionClient
