-- QA ONLY, with NightShiftQA.server.luau; the shipped game doesn't include it (see qa.project.json).
-- Tells the harness what only the client knows: when it finished loading, whether the escalators'
-- belt speed reached it (a player's physics runs here), and how healthy it is, so a disconnect leaves
-- evidence. It prints the same lines locally: if the server says this client went silent while
-- these keep printing, the fault is between them; if these stop too, the client itself froze.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local REPORT_EVERY = 15
local started = os.clock()

-- Whatever message Roblox shows when the connection goes: the only place the real reason appears.
GuiService.ErrorMessageChanged:Connect(function(message)
	if message ~= "" then
		warn(string.format("[QA] CLIENT-ERROR after %.0f s: %s", os.clock() - started, message))
	end
end)

-- A frame that took this long is a freeze, however short the whole session looks.
local frames, longestFrame, lastFrame = 0, 0, os.clock()
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local gap = now - lastFrame
	lastFrame = now
	frames += 1
	longestFrame = math.max(longestFrame, gap)
	if gap > 2 then
		warn(string.format("[QA] CLIENT-LOCAL froze for %.1f s, at %.0f s", gap, now - started))
	end
end)

local report = ReplicatedStorage:WaitForChild("QA_ClientReport", 120) :: RemoteEvent?
if not report then
	warn("[QA] CLIENT-LOCAL the harness's remote never appeared")
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
	report:FireServer("Idled", { IdleSeconds = seconds, Text = string.format("Roblox says idle for %.0f s", seconds) })
end)

local count = 0
while true do
	task.wait(REPORT_EVERY)
	count += 1
	local line = string.format(
		"alive at %.0f s: %.0f frames/s, longest frame %.2f s, client memory %.0f MB",
		os.clock() - started,
		frames / REPORT_EVERY,
		longestFrame,
		Stats:GetTotalMemoryUsageMb()
	)
	frames, longestFrame = 0, 0
	if count % 4 == 0 then
		print("[QA] CLIENT-LOCAL " .. line)
		report:FireServer("Health", { IdleSeconds = idleSeconds, Text = line })
	else
		report:FireServer("Alive", { IdleSeconds = idleSeconds })
	end
end
