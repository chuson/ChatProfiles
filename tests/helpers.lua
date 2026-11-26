-- Shared by the test files. Each file loads its own copy, runs its checks, and returns
-- helpers.Failures() to run.lua.

local helpers = {}
local failures = 0

function helpers.Fail(message)
	failures = failures + 1
	print("FAIL: " .. message)
end

function helpers.Check(ok, message)
	if not ok then
		helpers.Fail(message)
	end
end

local function DeepEqual(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in pairs(a) do
		if not DeepEqual(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- Writes a value out with sorted keys, so a failed comparison shows both sides readably.
local function Describe(value)
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) ~= "table" then
		return tostring(value)
	end
	local keys = {}
	for key in pairs(value) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, key in ipairs(keys) do
		local prefix = type(key) == "number" and "" or (tostring(key) .. " = ")
		table.insert(parts, prefix .. Describe(value[key]))
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- Compares by content, so two tables with the same fields are equal.
function helpers.Equal(actual, expected, message)
	if not DeepEqual(actual, expected) then
		helpers.Fail(message .. "\n  expected " .. Describe(expected) .. "\n  got      " .. Describe(actual))
	end
end

function helpers.DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value) do
		copy[key] = helpers.DeepCopy(item)
	end
	return copy
end

-- unpack is a global in Lua 5.1 but table.unpack in 5.2 and later, and CI runs 5.1.
function helpers.Unpack(list, first, last)
	first, last = first or 1, last or #list
	if first <= last then
		return list[first], helpers.Unpack(list, first + 1, last)
	end
end

-- Runs an addon file the way the client does: with the addon's name and a shared namespace.
function helpers.LoadAddonFile(path, ns)
	assert(loadfile(path))("ChatProfiles", ns)
end

-- The client turns ChatTypeInfo into an empty proxy once chat loads, so the stand-in is one too.
function helpers.ChatTypeInfoProxy(entries)
	return setmetatable({}, { __index = entries })
end

function helpers.Failures()
	return failures
end

return helpers
