-- Runs every test file. Run from the repository root with Lua 5.1 or later: lua tests/run.lua
--
-- Each file runs in its own Lua process, so stand-ins one file sets up for the game can't leak
-- into the next, and an error in one file doesn't stop the others.

local TEST_FILES = {
	"tests/ExportString.lua",
	"tests/ChatSettings.lua",
	"tests/Profiles.lua",
	"tests/PanelText.lua",
	"tests/Apply.lua",
	"tests/WholePath.lua",
}

-- Given a file, run just that one and exit with its result.
if arg[1] then
	local ok, failures = pcall(dofile, arg[1])
	if not ok then
		print("ERROR: " .. tostring(failures))
		os.exit(1)
	end
	print(arg[1] .. ": " .. (failures == 0 and "passed" or (failures .. " failed")))
	os.exit(failures == 0 and 0 or 1)
end

-- os.execute returns the exit status in Lua 5.1, and true or nil in 5.2 and later.
local function Succeeded(result)
	return result == true or result == 0
end

-- Negative indexes in arg hold the interpreter and its options, such as -lluacov for coverage.
-- Each file is run the same way.
local first = -1
while arg[first - 1] do
	first = first - 1
end
-- Only parts with spaces are quoted: given more than two quotes, Windows' cmd.exe strips the
-- outer ones.
local interpreter = {}
for i = first, -1 do
	table.insert(interpreter, arg[i]:find(" ") and ('"' .. arg[i] .. '"') or arg[i])
end
local lua = #interpreter > 0 and table.concat(interpreter, " ") or "lua"

local failedFiles = {}
for _, file in ipairs(TEST_FILES) do
	if not Succeeded(os.execute(lua .. " tests/run.lua " .. file)) then
		table.insert(failedFiles, file)
	end
end

if #failedFiles > 0 then
	print("Failed: " .. table.concat(failedFiles, ", "))
	os.exit(1)
end
print("All tests passed.")
