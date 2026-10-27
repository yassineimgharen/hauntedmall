--!strict
-- Display formatting helpers.

local Format = {}

function Format.number(n: number): string
	local whole = tostring(math.floor(math.abs(n)))
	local grouped = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if grouped:sub(1, 1) == "," then
		grouped = grouped:sub(2)
	end
	return if n < 0 then "-" .. grouped else grouped
end

function Format.cash(n: number): string
	return "$" .. Format.number(n)
end

function Format.time(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return Format
