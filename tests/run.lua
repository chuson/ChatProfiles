-- Runs every test file. Run from the repository root with Lua 5.1 or later: lua tests/run.lua

local TEST_FILES = { "tests/ExportString.lua", "tests/ChatSettings.lua" }

local failures = 0
for _, file in ipairs(TEST_FILES) do
	local fileFailures = dofile(file)
	print(file .. ": " .. (fileFailures == 0 and "passed" or (fileFailures .. " failed")))
	failures = failures + fileFailures
end

if failures > 0 then
	print(failures .. " check(s) failed.")
	os.exit(1)
end
print("All tests passed.")
