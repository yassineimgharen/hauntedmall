-- Client entry point. Waits for the world, then starts controllers in order.

if not game:IsLoaded() then
	game.Loaded:Wait()
end
workspace:WaitForChild("Mall")

local CONTROLLER_ORDER = {
	"AudioController",
	"LightingController",
	"AtmosphereController",
	"WorldFxController",
	"EnemyVisualController",
	"PromptController",
	"FlashlightController",
	"GuideController",
	"UIController",
}

for _, name in CONTROLLER_ORDER do
	local controller = require(script.Controllers[name])
	task.spawn(function()
		local ok, err = pcall(controller.Start)
		if not ok then
			warn(string.format("[NightShift] %s failed to start: %s", name, tostring(err)))
		end
	end)
end
