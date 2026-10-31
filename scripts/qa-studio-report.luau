-- Merges saved Studio harness sessions into one report:
--   .tools/bin/lune run scripts/qa-studio-report.luau           reads qa-results/*.txt
-- Save each session's Output as a text file in qa-results/. Writes docs/qa/STUDIO_RESULTS.md. Files
-- are read in name order, and a later file's result for a check replaces an earlier one's.

local fs = require("@lune/fs")
local process = require("@lune/process")

local StudioLog = require("../tests/harness/StudioLog")

local folder = "qa-results"
if not fs.isDir(folder) then
	print("no " .. folder .. " folder: nothing to merge")
	process.exit(0)
end
local names = {}
for _, name in fs.readDir(folder) do
	if name:match("%.txt$") then
		table.insert(names, name)
	end
end
table.sort(names)

local merged = StudioLog.new()
for _, name in names do
	-- Output copied on Windows may be UTF-16; the [QA] lines themselves are all this needs
	StudioLog.add(merged, name, (fs.readFile(folder .. "/" .. name):gsub("%z", "")))
end
local levels = {}
for i = 1, 14 do
	table.insert(levels, string.format("L%02d", i))
end
fs.writeFile("docs/qa/STUDIO_RESULTS.md", StudioLog.render(merged, levels))
print(string.format("merged %d sessions into docs/qa/STUDIO_RESULTS.md", #names))
