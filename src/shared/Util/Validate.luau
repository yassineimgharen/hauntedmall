--!strict
-- Type guards for values arriving from clients. Treat every remote argument as hostile.

local Validate = {}

function Validate.finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.unitVector(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	if not (Validate.finite(value.X) and Validate.finite(value.Y) and Validate.finite(value.Z)) then
		return false
	end
	local magnitude = value.Magnitude
	return magnitude > 0.95 and magnitude < 1.05
end

function Validate.shortString(value: any, maxLength: number): boolean
	return type(value) == "string" and #value > 0 and #value <= maxLength
end

function Validate.fraction(value: any): boolean
	return Validate.finite(value) and value >= 0 and value <= 1
end

return Validate
