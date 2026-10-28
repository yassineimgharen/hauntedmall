--!strict
-- Pure flashlight-cone geometry (no Roblox APIs, so it is unit-tested with Lune).
--
-- A target is a sphere: it is lit when any part of it pokes into the cone, not only its
-- centre. Small enemies use radius 0 (a point); big bosses pass the radius of each body
-- part, so aiming at the Queen's head or abdomen counts, not just one hidden point.

local LightCone = {}

-- Within this distance the cone is treated as much wider (point-blank flailing still hits).
LightCone.CloseRange = 7
LightCone.CloseHalfAngle = math.rad(50)

-- alignment = dot(aim, unit offset to the target centre); distance = to the centre.
function LightCone.hits(alignment: number, distance: number, radius: number, halfAngle: number, range: number): boolean
	if distance - radius > range then
		return false
	end
	if distance <= radius or distance <= 0.1 then
		return true -- the lens is inside the target
	end
	local cone = if distance < LightCone.CloseRange then math.max(halfAngle, LightCone.CloseHalfAngle) else halfAngle
	local angle = math.acos(math.clamp(alignment, -1, 1))
	return angle <= cone + math.asin(math.min(1, radius / distance))
end

return LightCone
