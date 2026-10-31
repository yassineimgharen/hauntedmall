-- A small test runner for the simulation specs: named tests, assertions, a summary, and a
-- machine-readable result file (build/qa/<suite>.json) that scripts/qa-report.luau turns into
-- the per-level reports. Each result carries the verification level it reached.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Check = {}

local suite = "suite"
local level = "Integration-tested"
local results: { any } = {}
local notes: { [string]: any } = {}
local started = os.clock()
local filter = process.env.QA_FILTER

function Check.suite(name: string, verification: string)
	suite = name
	level = verification
	started = os.clock()
	print(string.format("%s  [%s]", name, verification))
end

-- `name` starts with "L05 Night:" or "L05 Day:" to count towards that level's report.
function Check.test(name: string, fn: () -> ())
	if filter and not name:find(filter, 1, true) then
		return
	end
	local t0 = os.clock()
	local ok, err = xpcall(fn, function(e)
		return tostring(e)
	end)
	table.insert(
		results,
		{ Name = name, Ok = ok, Error = if ok then nil else err, Level = level, Seconds = os.clock() - t0 }
	)
	if ok then
		print("  ✓ " .. name)
	else
		print("  ✗ " .. name .. "\n      " .. tostring(err):gsub("\n", "\n      "))
	end
end

-- A measured fact for the report (never an assertion): e.g. how long a day took to clear.
function Check.note(key: string, value: any)
	notes[key] = value
	print(string.format("    · %s = %s", key, tostring(value)))
end

function Check.skip(name: string, why: string)
	table.insert(results, { Name = name, Skipped = true, Error = why, Level = level, Seconds = 0 })
	print("  - " .. name .. " (skipped: " .. why .. ")")
end

function Check.eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
	end
end

function Check.truthy(value: any, label: string?)
	if not value then
		error((label or "value") .. ": expected true, got " .. tostring(value), 2)
	end
end

function Check.falsy(value: any, label: string?)
	if value then
		error((label or "value") .. ": expected false, got " .. tostring(value), 2)
	end
end

function Check.near(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(
			string.format(
				"%s: expected %s ± %s, got %s",
				label or "value",
				tostring(expected),
				tostring(tolerance),
				tostring(actual)
			),
			2
		)
	end
end

-- Fails if the server logged any error during the run.
function Check.noServerErrors(world: any)
	if #world.Errors > 0 then
		local first = world.Errors[1]
		error(string.format("%d server error(s), first at t=%.1f: %s", #world.Errors, first.At, first.Message), 2)
	end
end

-- Ends the suite: prints the summary, writes the result file, and fails the process on failure.
function Check.finish()
	local passed, failed, skipped = 0, 0, 0
	for _, result in results do
		if result.Skipped then
			skipped += 1
		elseif result.Ok then
			passed += 1
		else
			failed += 1
		end
	end
	local seconds = os.clock() - started
	print(string.format("%s: %d passed, %d failed, %d skipped (%.1f s)", suite, passed, failed, skipped, seconds))
	if not filter then
		pcall(function()
			fs.writeDir("build/qa")
			fs.writeFile(
				"build/qa/" .. suite .. ".json",
				serde.encode(
					"json",
					{ Suite = suite, Level = level, Seconds = seconds, Results = results, Notes = notes },
					true
				)
			)
		end)
	end
	if failed > 0 then
		process.exit(1)
	end
end

return Check
