-- Turns a chat recording (ChatProfilesDB.capture in the SavedVariables file) into
-- tests/fixtures/ChatRecording.lua. CONTRIBUTING.md explains how to make the recording.
-- Run from the repository root:
--   lua tests/fixtures/convert.lua <path to WTF/Account/NAME/SavedVariables/ChatProfiles.lua>
local input, output = assert(arg[1], "pass the SavedVariables file"), "tests/fixtures/ChatRecording.lua"
dofile(input)
local capture = assert(ChatProfilesDB.capture, "no capture in " .. input)

local function Value(v)
	if type(v) == "string" then
		return string.format("%q", v)
	elseif type(v) == "number" then
		if v == math.floor(v) then
			return string.format("%d", v)
		end
		return string.format("%.16g", v)
	end
	return tostring(v)
end

-- Packs values into lines no longer than `width` after `indent`.
local function PackedList(values, indent, width)
	local lines, line = {}, ""
	for _, v in ipairs(values) do
		local item = Value(v) .. ","
		if #line > 0 and #indent + #line + 1 + #item > width then
			table.insert(lines, indent .. line)
			line = item
		else
			line = (#line > 0) and (line .. " " .. item) or item
		end
	end
	if #line > 0 then
		table.insert(lines, indent .. line)
	end
	return lines
end

local out = {}
local function Emit(s)
	table.insert(out, s)
end

Emit("-- Chat settings recorded from a WoW Forever character on " .. os.date("%Y-%m-%d") .. ". Made by")
Emit("-- tests/fixtures/convert.lua; CONTRIBUTING.md explains how to record a new one.")
Emit("--")
Emit("-- windows[n].info is what GetChatWindowInfo(n) returned: name, fontSize, r, g, b, a, shown,")
Emit("-- locked, docked, uninteractable. savedPosition and savedSize are what GetChatWindowSavedPosition")
Emit("-- and GetChatWindowSavedDimensions returned. colors[chatType] is that ChatTypeInfo entry's r, g, b")
Emit("-- and colorNameByClass.")
Emit("return {")
Emit("\treserved = " .. capture.reserved .. ",")
Emit("\twindows = {")
for n = 1, 10 do
	local w = capture[n]
	local info = {}
	for i = 1, 10 do
		info[i] = Value(w.i[i])
	end
	Emit("\t\t{")
	Emit("\t\t\tinfo = { " .. table.concat(info, ", ") .. " },")
	if #w.m == 0 then
		Emit("\t\t\tmessageGroups = {},")
	else
		Emit("\t\t\tmessageGroups = {")
		for _, line in ipairs(PackedList(w.m, "\t\t\t\t", 100)) do
			Emit(line)
		end
		Emit("\t\t\t},")
	end
	if #w.c == 0 then
		Emit("\t\t\tchannels = {},")
	else
		Emit("\t\t\tchannels = {")
		for i = 1, #w.c, 2 do
			Emit("\t\t\t\t" .. Value(w.c[i]) .. ", " .. Value(w.c[i + 1]) .. ",")
		end
		Emit("\t\t\t},")
	end
	-- Recordings made before position and size were captured have neither.
	if w.p and #w.p > 0 then
		Emit("\t\t\tsavedPosition = { " .. Value(w.p[1]) .. ", " .. Value(w.p[2]) .. ", " .. Value(w.p[3]) .. " },")
	end
	if w.s and #w.s > 0 then
		Emit("\t\t\tsavedSize = { " .. Value(w.s[1]) .. ", " .. Value(w.s[2]) .. " },")
	end
	Emit("\t\t},")
end
Emit("\t},")
Emit("\tcolors = {")
local chatTypes = {}
for chatType in pairs(capture.colors) do
	table.insert(chatTypes, chatType)
end
table.sort(chatTypes)
for _, chatType in ipairs(chatTypes) do
	local c = capture.colors[chatType]
	local parts = { Value(c[1]), Value(c[2]), Value(c[3]) }
	if c[4] ~= nil then
		table.insert(parts, Value(c[4]))
	end
	Emit("\t\t" .. chatType .. " = { " .. table.concat(parts, ", ") .. " },")
end
Emit("\t},")
Emit("}")

-- Binary mode, so Windows doesn't turn the line endings into CRLF.
local file = assert(io.open(output, "wb"))
file:write(table.concat(out, "\n"), "\n")
file:close()
print("wrote " .. output .. " with " .. #chatTypes .. " chat colors")
