-- Checks the import validator against good and malformed profiles.
-- Run from the repository root with Lua 5.1: lua tests/validate.lua

-- Stand-ins for the two game globals the validator reads.
Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
ChatTypeInfo = { SAY = {}, GUILD = {}, CHANNEL1 = {} }

local ns = {}
assert(loadfile("ChatCopy/Codec.lua"))("ChatCopy", ns)
local Validate = ns.Codec.Validate

local function GoodProfile()
	return {
		include = { tabs = true, contents = true, look = true, colors = true },
		windows = {
			{
				key = "id:1",
				name = "General",
				size = 0,
				r = 0,
				g = 0,
				b = 0,
				a = 0.25,
				locked = true,
				groups = { "SAY", "SYSTEM_NOMENU", "GUILD" },
				channels = { { name = "Trade", zoneID = 2 }, { name = "MyChannel", zoneID = 0 } },
			},
			{ key = "id:2", name = "Combat Log", size = 14 },
			{ key = "name:trade", name = "trade", groups = {}, channels = {} },
		},
		colors = { SAY = { r = 1, g = 1, b = 1 }, GUILD = { r = 0.25, g = 1, b = 0.25, classColor = true } },
	}
end

local failures = 0

local function Expect(description, shouldPass, change)
	local data = GoodProfile()
	if change then
		data = change(data) or data
	end
	local result, reason = Validate(data)
	if (result ~= nil) ~= shouldPass then
		failures = failures + 1
		print("FAIL: " .. description .. (reason and (" (" .. reason .. ")") or ""))
	end
	return result
end

local function Accepts(description, change)
	return Expect(description, true, change)
end

local function Rejects(description, change)
	Expect(description, false, change)
end

-- Accepted, and cleaned where needed
Accepts("a complete profile")
Accepts("a profile without colors", function(p)
	p.colors = nil
end)
Accepts("a tab with only a key and name", function(p)
	p.windows = { { key = "name:x", name = "x" } }
end)
local cleaned = Accepts("names containing |", function(p)
	p.windows[3].name = "tr|cffff0000ade"
	p.windows[3].key = "name:anything"
end)
if cleaned and (cleaned.windows[3].name ~= "trcffff0000ade" or cleaned.windows[3].key ~= "name:trcffff0000ade") then
	failures = failures + 1
	print("FAIL: | not stripped, or the key not rebuilt from the cleaned name")
end

-- Rejected
Rejects("not a table", function()
	return "ChatCopy"
end)
Rejects("an unknown top-level field", function(p)
	p.extra = true
end)
Rejects("missing categories", function(p)
	p.include = nil
end)
Rejects("an unknown category", function(p)
	p.include.bogus = true
end)
Rejects("a category that is not a boolean", function(p)
	p.include.tabs = 1
end)
Rejects("missing tabs", function(p)
	p.windows = nil
end)
Rejects("tabs that are not a list", function(p)
	p.windows = { first = p.windows[1] }
end)
Rejects("a hole in the tab list", function(p)
	p.windows[2] = nil
end)
Rejects("too many tabs", function(p)
	for i = 4, 11 do
		p.windows[i] = { key = "name:t" .. i, name = "t" .. i }
	end
end)
Rejects("two tabs with the same name", function(p)
	p.windows[4] = { key = "name:trade", name = "trade" }
end)
Rejects("an unknown tab field", function(p)
	p.windows[1].script = "print(1)"
end)
Rejects("a bad key", function(p)
	p.windows[1].key = "id:3"
end)
Rejects("a name that is only |", function(p)
	p.windows[3].name = "||"
end)
Rejects("a name that is too long", function(p)
	p.windows[3].name = string.rep("a", 51)
end)
Rejects("a fractional font size", function(p)
	p.windows[1].size = 12.5
end)
Rejects("a huge font size", function(p)
	p.windows[1].size = 400
end)
Rejects("a color above 1", function(p)
	p.windows[1].r = 1.5
end)
Rejects("a negative opacity", function(p)
	p.windows[1].a = -0.1
end)
Rejects("a color given as text", function(p)
	p.windows[1].g = "0"
end)
Rejects("only part of a color", function(p)
	p.windows[2].r = 0.5
end)
Rejects("a lock that is not a boolean", function(p)
	p.windows[1].locked = 1
end)
Rejects("a lowercase message group", function(p)
	p.windows[1].groups[1] = "say"
end)
Rejects("a message group that is a number", function(p)
	p.windows[1].groups[1] = 5
end)
Rejects("too many message groups", function(p)
	for i = 1, 101 do
		p.windows[1].groups[i] = "SAY"
	end
end)
Rejects("a channel without an ID", function(p)
	p.windows[1].channels[1].zoneID = nil
end)
Rejects("a negative channel ID", function(p)
	p.windows[1].channels[1].zoneID = -1
end)
Rejects("an unknown channel field", function(p)
	p.windows[1].channels[1].password = "x"
end)
Rejects("an unknown chat type", function(p)
	p.colors.NOT_A_TYPE = { r = 1, g = 1, b = 1 }
end)
Rejects("a chat color missing blue", function(p)
	p.colors.SAY.b = nil
end)
Rejects("class-colored names that are not a boolean", function(p)
	p.colors.GUILD.classColor = "yes"
end)

if failures == 0 then
	print("All validator checks passed.")
else
	print(failures .. " validator check(s) failed.")
	os.exit(1)
end
