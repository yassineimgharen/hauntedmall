-- Physics collision groups. Players, NPC customers and enemies pass through each other
-- (no body-blocking or griefing) but all collide with the world.

local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {
	Players = "Players",
	NPCs = "NPCs",
	Enemies = "Enemies",
}

function CollisionGroups.setup()
	for _, name in { "Players", "NPCs", "Enemies" } do
		PhysicsService:RegisterCollisionGroup(name)
	end
	local pairsOff = {
		{ "Players", "NPCs" },
		{ "Players", "Enemies" },
		{ "NPCs", "NPCs" },
		{ "NPCs", "Enemies" },
		{ "Enemies", "Enemies" },
		{ "Players", "Players" },
	}
	for _, pair in pairsOff do
		PhysicsService:CollisionGroupSetCollidable(pair[1], pair[2], false)
	end
end

function CollisionGroups.assign(model: Instance, group: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

-- World-only line of sight: these params ignore characters, NPCs and enemies, and
-- non-colliding decoration.
function CollisionGroups.worldRaycastParams(): RaycastParams
	local params = RaycastParams.new()
	params.CollisionGroup = "Enemies"
	params.RespectCanCollide = true
	return params
end

return CollisionGroups
