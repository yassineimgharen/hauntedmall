-- QA ONLY, with NightShiftQA.server.luau; the shipped game doesn't include it (see qa.project.json).
-- Tells the harness what only the client knows: when it finished loading, whether the escalators'
-- belt speed reached it (a player's physics runs here), and whether Roblox considers it idle, since
-- an idle client can be disconnected after 20 minutes. It also tries to stay un-idle while a run goes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local started = os.clock()
local report = ReplicatedStorage:WaitForChild("QA_ClientReport", 120) :: RemoteEvent?
if not report then
	return
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local ramps = {}
for _, escalator in CollectionService:GetTagged("Escalator") do
	local ramp = escalator:WaitForChild("Ramp", 30) :: BasePart?
	if ramp then
		ramps[escalator.Name] = ramp.AssemblyLinearVelocity.Magnitude
	end
end
report:FireServer("Ready", { Ramps = ramps, Text = string.format("loaded after %.0f s", os.clock() - started) })

local idleSeconds = 0
Players.LocalPlayer.Idled:Connect(function(seconds)
	idleSeconds = seconds
	local ok, err = pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.zero)
	end)
	report:FireServer("Idled", {
		IdleSeconds = seconds,
		Text = string.format(
			"Roblox says idle for %.0f s; staying awake %s",
			seconds,
			if ok then "attempted" else "failed: " .. tostring(err)
		),
	})
end)

-- a heartbeat: silence before a disconnect means this client froze or ran out of memory
while true do
	task.wait(30)
	report:FireServer("Alive", { IdleSeconds = idleSeconds })
end
