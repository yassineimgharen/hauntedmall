--!strict
-- Pure logic for the Level 7 light puzzle (no Roblox services: unit-tested with Lune in
-- tests/Campaign.spec.luau). A beam enters a 5×5 grid; mirrors are "/" or "\"; the
-- puzzle is solved when the beam leaves through the receiver edge.
--
-- Coordinates: cell {x, z}, x east, z north. "/" turns east↔north and west↔south,
-- "\" turns east↔south and west↔north. Solved exactly when the three mirrors on the
-- route are "/"; the other three are decoys (8 of 64 states solve it, none loop).

local MirrorGrid = {}

MirrorGrid.Size = 5
MirrorGrid.SourceCell = { 0, 1 }
MirrorGrid.SourceDir = { 1, 0 }
MirrorGrid.ReceiverCell = { 3, 4 }
MirrorGrid.ReceiverDir = { 0, 1 }
MirrorGrid.Mirrors = { { 2, 1 }, { 2, 3 }, { 3, 3 }, { 1, 3 }, { 3, 1 }, { 1, 4 } }

local function key(x: number, z: number): string
	return x .. "," .. z
end

-- states[i] is the state of MirrorGrid.Mirrors[i]. Returns the cells the beam visits, the
-- direction it leaves the last cell with, and whether it reached the receiver.
function MirrorGrid.trace(states: { string }): ({ { number } }, { number }, boolean)
	local mirrors: { [string]: string } = {}
	for i, cell in MirrorGrid.Mirrors do
		mirrors[key(cell[1], cell[2])] = states[i]
	end
	local x, z = MirrorGrid.SourceCell[1], MirrorGrid.SourceCell[2]
	local dx, dz = MirrorGrid.SourceDir[1], MirrorGrid.SourceDir[2]
	local cells = {}
	local seen: { [string]: boolean } = {}
	while x >= 0 and x < MirrorGrid.Size and z >= 0 and z < MirrorGrid.Size do
		local visit = key(x, z) .. ":" .. dx .. "," .. dz
		if seen[visit] then
			break -- a loop never reaches the receiver
		end
		seen[visit] = true
		table.insert(cells, { x, z })
		local mirror = mirrors[key(x, z)]
		if mirror == "/" then
			dx, dz = dz, dx
		elseif mirror == "\\" then
			dx, dz = -dz, -dx
		end
		if
			x == MirrorGrid.ReceiverCell[1]
			and z == MirrorGrid.ReceiverCell[2]
			and dx == MirrorGrid.ReceiverDir[1]
			and dz == MirrorGrid.ReceiverDir[2]
		then
			return cells, { dx, dz }, true
		end
		x += dx
		z += dz
	end
	return cells, { dx, dz }, false
end

function MirrorGrid.solved(states: { string }): boolean
	local _, _, hit = MirrorGrid.trace(states)
	return hit
end

return MirrorGrid
