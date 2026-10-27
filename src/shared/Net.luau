-- Remote registry. The server creates every remote at boot; clients wait for them.
-- All client→server handlers go through Net.handle, which rate-limits per player and
-- isolates handler errors so one bad request cannot break the service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RateLimiter = require(script.Parent.Util.RateLimiter)

local FOLDER_NAME = "Remotes"

local RELIABLE = {
	-- client → server
	"PurchaseUpgrade",
	"Restock",
	"SetBeam",
	"SaveSettings",
	"RequestPurchase",
	-- server → client
	"Notify",
	"NightResults",
	"Effect",
}

local UNRELIABLE = {
	"AimUpdate", -- client → server, high frequency, loss-tolerant
}

local Net = {}

local folder: Instance? = nil

local function getFolder(): Instance
	if folder then
		return folder
	end

	local result: Instance
	if RunService:IsServer() then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		for _, name in RELIABLE do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = created
		end
		for _, name in UNRELIABLE do
			local remote = Instance.new("UnreliableRemoteEvent")
			remote.Name = name
			remote.Parent = created
		end
		created.Parent = ReplicatedStorage
		result = created
	else
		result = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end

	folder = result
	return result
end

function Net.get(name: string): any
	local remotes = getFolder()
	local remote = if RunService:IsServer() then remotes:FindFirstChild(name) else remotes:WaitForChild(name)
	assert(remote, "Unknown remote: " .. name)
	return remote
end

-- Server only: connect a validated, rate-limited handler.
function Net.handle(name: string, ratePerSecond: number, burst: number, handler: (Player, ...any) -> ())
	assert(RunService:IsServer(), "Net.handle is server-only")
	local limiter = RateLimiter.new(ratePerSecond, burst)
	Net.get(name).OnServerEvent:Connect(function(player: Player, ...)
		if not limiter:allow(player) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Net] %s handler failed for %s: %s", name, player.Name, tostring(err)))
		end
	end)
end

return Net
