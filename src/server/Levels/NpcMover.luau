-- Path-following for level NPCs (night shoppers, rescued shoppers, the Stalker).
-- Call :steer(goal) every tick: it re-plans when the goal moves or the plan is stale and
-- walks the waypoints, falling back to a straight MoveTo when no path is found.

local PathfindingService = game:GetService("PathfindingService")

local NpcMover = {}
NpcMover.__index = NpcMover

export type Mover = {
	Humanoid: Humanoid,
	Root: BasePart,
	Path: Path,
	Goal: Vector3?,
	Waypoints: { Vector3 }?,
	Index: number,
	RepathAt: number,
	steer: (self: Mover, goal: Vector3) -> (),
	reset: (self: Mover) -> (),
}

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function NpcMover.new(humanoid: Humanoid, root: BasePart, agentRadius: number?, agentHeight: number?): Mover
	local self = setmetatable({
		Humanoid = humanoid,
		Root = root,
		Path = PathfindingService:CreatePath({
			AgentRadius = agentRadius or 2,
			AgentHeight = agentHeight or 5,
			AgentCanJump = false,
		}),
		Goal = nil,
		Waypoints = nil,
		Index = 1,
		RepathAt = 0,
	}, NpcMover)
	return (self :: any) :: Mover
end

-- Forget the current plan (next steer re-plans).
function NpcMover.reset(self: Mover)
	self.Goal = nil
	self.Waypoints = nil
end

-- May yield while planning; call it from the NPC's own loop.
function NpcMover.steer(self: Mover, goal: Vector3)
	local now = os.clock()
	if not self.Goal or (self.Goal - goal).Magnitude > 4 or now > self.RepathAt then
		self.Goal = goal
		self.RepathAt = now + 3
		self.Index = 1
		self.Waypoints = nil
		local path = self.Path
		local ok = pcall(function()
			path:ComputeAsync(self.Root.Position, goal)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local points = {}
			for i, waypoint in path:GetWaypoints() do
				if i > 1 then
					table.insert(points, waypoint.Position)
				end
			end
			self.Waypoints = points
		end
	end
	local waypoints = self.Waypoints
	if waypoints then
		local waypoint = waypoints[self.Index]
		if waypoint and flatDistance(self.Root.Position, waypoint) < 2.5 then
			self.Index += 1
			waypoint = waypoints[self.Index]
		end
		self.Humanoid:MoveTo(waypoint or goal)
	else
		self.Humanoid:MoveTo(goal)
	end
end

return NpcMover
